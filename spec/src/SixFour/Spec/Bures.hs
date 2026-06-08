{- |
Module      : SixFour.Spec.Bures
Description : Bures–Wasserstein (Gaussian W₂) distance + covariance backbone — a
              GAUSSIAN-SUMMARY approximation, NOT the discrete-palette collapse.

The per-frame palettes are DISCRETE empirical measures (≤256 weighted OKLab atoms).
The actual collapse to one palette is the maximin floor in "SixFour.Spec.Collapse"
('SixFour.Spec.Collapse.farthestPointCollapse' / 'SixFour.Spec.Collapse.globalCollapseQ16')
— gamut-closed, deterministic, golden-pinned. THIS module supplies only the
Gaussian-summary backbone: 'buresDistanceSq' (the spread-aware fidelity term the loss
uses) and 'buresBarycenterCov' (the covariance fixed point the Rust analysis oracle
cross-checks).

These are an APPROXIMATION with a real projection error, NOT the palette barycenter:
the closed-form Bures barycenter @Σ̄ = Σᵢ λᵢ (Σ̄^½ Σᵢ Σ̄^½)^½@ (Agueh–Carlier 2011;
Álvarez-Esteban et al. 2016) is proven ONLY for absolutely-continuous / Gaussian
measures — [arXiv:1511.05355] EXPLICITLY excludes discrete distributions, and the exact
discrete W₂ barycenter is NP-hard. So do NOT read a Gaussian Bures barycenter as "the
collapse"; it is a moment-matched spread prior. See docs/SIXFOUR-BURES-DISCRETE-CORRECTION.md
and docs/SIXFOUR-JEPA-VS-STATISTICAL-CELLGRID.md.

For Gaussians, @W₂((μ₁,Σ₁),(μ₂,Σ₂))² = ‖μ₁−μ₂‖² + tr(Σ₁ + Σ₂ − 2(Σ₁^½ Σ₂ Σ₁^½)^½)@
(the Bures metric on covariances). The matrix square root uses scaled Denman–Beavers
iteration (branch-free, ports identically to the Rust oracle). The bridge law
(@Properties.Bures@): as @Σ → 0@ the Bures distance reduces to plain Euclidean OKLab,
so the Gaussian summary degenerates to the discrete k-means/maximin floor. No
eigendecomposition, no metric weights: the metric is identity OKLab, the research
default — never the deleted hand-set @[4,2,1]@.
-}
module SixFour.Spec.Bures
  ( -- * 3×3 matrices
    Mat3(..)
  , fromCov3
  , toCov3
  , matId
  , matAdd
  , matScale
  , matMul
  , matTranspose
  , matTrace
  , det3
  , inverse3
    -- * Matrix square root (PSD)
  , sqrtPSD
    -- * Bures–Wasserstein (Gaussian-summary approximation — see module note)
  , buresDistanceSq
  , buresBarycenterCov
  ) where

import Data.List (foldl')

import SixFour.Spec.Color     (OKLab(..), okLabDistanceSquared)
import SixFour.Spec.Diversity (Cov3)
import SixFour.Spec.GMM       (Gaussian(..))

-- | A dense 3×3 matrix, row-major: @Mat3 m00 m01 m02 m10 m11 m12 m20 m21 m22@.
data Mat3 = Mat3 !Double !Double !Double !Double !Double !Double !Double !Double !Double
  deriving (Eq, Show)

-- | Expand a symmetric 'Cov3' into a full (symmetric) 'Mat3'.
fromCov3 :: Cov3 -> Mat3
fromCov3 (sll, sla, slb, saa, sab, sbb) =
  Mat3 sll sla slb
       sla saa sab
       slb sab sbb

-- | Read a (symmetric) 'Mat3' back as a 'Cov3' (upper triangle).
toCov3 :: Mat3 -> Cov3
toCov3 (Mat3 m00 m01 m02 _ m11 m12 _ _ m22) = (m00, m01, m02, m11, m12, m22)

-- | The 3×3 identity matrix.
matId :: Mat3
matId = Mat3 1 0 0 0 1 0 0 0 1

-- | Elementwise sum of two 3×3 matrices.
matAdd :: Mat3 -> Mat3 -> Mat3
matAdd (Mat3 a b c d e f g h i) (Mat3 a' b' c' d' e' f' g' h' i') =
  Mat3 (a+a') (b+b') (c+c') (d+d') (e+e') (f+f') (g+g') (h+h') (i+i')

-- | Scale every entry of a 3×3 matrix by a scalar.
matScale :: Double -> Mat3 -> Mat3
matScale s (Mat3 a b c d e f g h i) =
  Mat3 (s*a) (s*b) (s*c) (s*d) (s*e) (s*f) (s*g) (s*h) (s*i)

-- | Standard 3×3 matrix product.
matMul :: Mat3 -> Mat3 -> Mat3
matMul (Mat3 a b c d e f g h i) (Mat3 j k l m n o p q r) =
  Mat3 (a*j + b*m + c*p) (a*k + b*n + c*q) (a*l + b*o + c*r)
       (d*j + e*m + f*p) (d*k + e*n + f*q) (d*l + e*o + f*r)
       (g*j + h*m + i*p) (g*k + h*n + i*q) (g*l + h*o + i*r)

-- | Matrix transpose.
matTranspose :: Mat3 -> Mat3
matTranspose (Mat3 a b c d e f g h i) = Mat3 a d g b e h c f i

-- | Trace — the sum of the diagonal entries.
matTrace :: Mat3 -> Double
matTrace (Mat3 a _ _ _ e _ _ _ i) = a + e + i

-- | Determinant (cofactor expansion along the first row).
det3 :: Mat3 -> Double
det3 (Mat3 a b c d e f g h i) =
  a * (e*i - f*h) - b * (d*i - f*g) + c * (d*h - e*g)

-- | Inverse via the adjugate / determinant. Callers feed strictly-PD matrices
-- (the Denman–Beavers iterands and ridged covariances), so @det ≠ 0@.
inverse3 :: Mat3 -> Mat3
inverse3 mtx@(Mat3 a b c d e f g h i) =
  let dt   = det3 mtx
      invd = 1 / dt
      -- cofactors
      cA =  (e*i - f*h); cB = -(d*i - f*g); cC =  (d*h - e*g)
      cD = -(b*i - c*h); cE =  (a*i - c*g); cF = -(a*h - b*g)
      cG =  (b*f - c*e); cH = -(a*f - c*d); cI =  (a*e - b*d)
  -- inverse = adjugate / det = (cofactor matrix)ᵀ / det
  in matScale invd (Mat3 cA cD cG
                         cB cE cH
                         cC cF cI)

-- | Symmetric-PSD matrix square root via **scaled Denman–Beavers** iteration:
-- @Yₖ → A^½@, @Zₖ → A^{-½}@ with @Y₀ = A@, @Z₀ = I@ and the determinant scaling
-- @γ = (|det Z|/|det Y|)^{1/6}@ for 3×3 (accelerates + stabilises convergence). A
-- tiny ridge @A + εI@ keeps every iterand invertible (PSD with a zero eigenvalue is
-- still handled — the result is off by @O(ε)@, well inside test tolerance).
sqrtPSD :: Mat3 -> Mat3
sqrtPSD a0 =
  let ridge = 1e-9
      a     = matAdd a0 (matScale ridge matId)
      go :: Int -> Mat3 -> Mat3 -> Mat3
      go 0 y _ = y
      go n y z =
        let dy    = det3 y
            dz    = det3 z
            -- Higham determinantal scaling μ = |det Y · det Z|^{-1/(2n)}, n=3.
            gamma = max 1e-300 (abs (dy * dz)) ** (-1 / 6)
            iy    = inverse3 y
            iz    = inverse3 z
            y'    = matScale 0.5 (matAdd (matScale gamma y) (matScale (1/gamma) iz))
            z'    = matScale 0.5 (matAdd (matScale gamma z) (matScale (1/gamma) iy))
        in go (n - 1) y' z'
  in go (50 :: Int) a matId

-- | Squared Bures–Wasserstein (Gaussian W₂) distance. The mean term is the plain
-- OKLab Euclidean distance (identity metric); the covariance term is the Bures form.
-- When both covariances vanish this is exactly 'okLabDistanceSquared' (the reduction
-- law, @Properties.Bures@).
buresDistanceSq :: Gaussian -> Gaussian -> Double
buresDistanceSq (Gaussian m1 c1 _) (Gaussian m2 c2 _) =
  let dmu   = okLabDistanceSquared m1 m2
      s1    = sqrtPSD (fromCov3 c1)
      inner = sqrtPSD (matMul s1 (matMul (fromCov3 c2) s1))
      cross = matTrace inner
      t     = matTrace (fromCov3 c1) + matTrace (fromCov3 c2) - 2 * cross
  in dmu + max 0 t

-- | Bures–Wasserstein barycenter **covariance** of weighted Gaussian covariances: the
-- fixed point @Σ̄ = Σᵢ λᵢ (Σ̄^½ Σᵢ Σ̄^½)^½@, reached by direct iteration from the linear
-- average. Weights are renormalised to sum to 1. GAUSSIAN-ONLY (see module note): a
-- spread summary cross-checked by the Rust oracle, NOT the discrete-palette collapse
-- (that is 'SixFour.Spec.Collapse.farthestPointCollapse'; exact discrete barycenter is
-- NP-hard, [arXiv:1511.05355] excludes discrete measures).
buresBarycenterCov :: [(Double, Cov3)] -> Cov3
buresBarycenterCov wcs =
  let s   = sum (map fst wcs)
      ws  = if s <= 0 then wcs else [ (w / s, c) | (w, c) <- wcs ]
      zero = matScale 0 matId
      lin  = foldl' (\acc (w, c) -> matAdd acc (matScale w (fromCov3 c))) zero ws
      step sCur =
        let r = sqrtPSD sCur
            term (w, c) = matScale w (sqrtPSD (matMul r (matMul (fromCov3 c) r)))
        in foldl' (\acc wc -> matAdd acc (term wc)) zero ws
      iterateN :: Int -> Mat3 -> Mat3
      iterateN 0 x = x
      iterateN n x = iterateN (n - 1) (step x)
  in toCov3 (iterateN (30 :: Int) lin)
