{- |
Module      : SixFour.Spec.Diversity
Description : The VARIETY measures — Gaussian colour entropy and effective dim.

A faithful port of the Rust oracle @studio/analysis-core/src/cyclic.rs@
(@gaussian_color_entropy@) and @geometry.rs@ (@color_pca@ + @effective_dim@).
These quantify the *variety* (complexity) half of Birkhoff's Unity-in-Variety:
how much OKLab volume a colour set spans.

  * 'gaussianColorEntropy' — differential entropy of the Gaussian fit to the
    weighted palette, @½ ln((2πe)³ |Σ|)@ (LOOK_NN.md Def 32 is DPP-adjacent: a
    log-determinant of the colour spread).
  * 'effectiveDim' — participation ratio of the covariance eigenvalues
    @(Σλ)² / Σλ²@ ∈ [0,3]. Computed here via the trace identity
    @(tr Σ)² / tr(Σ²)@ (= @Σλ / Σλ²@) so no eigendecomposition is needed; this is
    mathematically identical and matches the Rust golden vector exactly.

The Rust functions remain the oracle (golden cross-checks in @Properties.Diversity@).
-}
module SixFour.Spec.Diversity
  ( Cov3
  , weightedCovariance
  , covDeterminant
  , covTrace
  , covFrobeniusSq
  , gaussianColorEntropy
  , effectiveDim
  ) where

import SixFour.Spec.Color (OKLab(..))

-- | A symmetric 3×3 OKLab covariance, stored as its six independent entries
-- @(s_LL, s_La, s_Lb, s_aa, s_ab, s_bb)@.
type Cov3 = (Double, Double, Double, Double, Double, Double)

-- | Weighted OKLab covariance @Σ pᵢ (xᵢ−μ)(xᵢ−μ)ᵀ@ with @pᵢ = wᵢ/Σw@. Returns the
-- all-zero covariance when total weight is non-positive (the @color_pca@ fallback).
weightedCovariance :: [(OKLab, Double)] -> Cov3
weightedCovariance cands =
  let wsum = sum (map snd cands)
  in if wsum <= 0
       then (0, 0, 0, 0, 0, 0)
       else
         let acc (al, aa, ab) (OKLab l a b, w) = (al + w * l, aa + w * a, ab + w * b)
             (ml0, ma0, mb0) = foldl acc (0, 0, 0) cands
             (ml, ma, mb)    = (ml0 / wsum, ma0 / wsum, mb0 / wsum)
             step (qll, qla, qlb, qaa, qab, qbb) (OKLab l a b, w) =
               let dl = l - ml; da = a - ma; db = b - mb
               in ( qll + w * dl * dl, qla + w * dl * da, qlb + w * dl * db
                  , qaa + w * da * da, qab + w * da * db, qbb + w * db * db )
             (sll, sla, slb, saa, sab, sbb) =
               foldl step (0, 0, 0, 0, 0, 0) cands
         in (sll / wsum, sla / wsum, slb / wsum, saa / wsum, sab / wsum, sbb / wsum)

-- | Determinant of the symmetric 3×3 covariance (same expansion as the oracle).
covDeterminant :: Cov3 -> Double
covDeterminant (sll, sla, slb, saa, sab, sbb) =
  sll * (saa * sbb - sab * sab)
    - sla * (sla * sbb - sab * slb)
    + slb * (sla * sab - saa * slb)

-- | Trace @tr Σ = Σλ@ (sum of variances).
covTrace :: Cov3 -> Double
covTrace (sll, _, _, saa, _, sbb) = sll + saa + sbb

-- | Frobenius² @tr(Σ²) = Σλ²@ for a symmetric matrix (diagonal² + 2·off-diagonal²).
covFrobeniusSq :: Cov3 -> Double
covFrobeniusSq (sll, sla, slb, saa, sab, sbb) =
  sll * sll + saa * saa + sbb * sbb + 2 * (sla * sla + slb * slb + sab * sab)

-- | Differential entropy of the Gaussian fit to a weighted palette,
-- @½ ln((2πe)³ |Σ|)@. Mirrors @cyclic::gaussian_color_entropy@ exactly, including
-- the uniform-weight fallback when @Σw ≤ 0@ and the @|Σ| ← max(|Σ|, 1e-12)@ floor.
gaussianColorEntropy :: [OKLab] -> [Double] -> Double
gaussianColorEntropy palette weights =
  let n     = length palette
      s     = sum weights
      ps    = if s <= 0
                then replicate n (1 / fromIntegral (max 1 n))
                else map (/ s) weights
      cands = zip palette ps           -- already-normalised "weights" sum to 1
      cov   = weightedCovarianceNorm cands
      det   = covDeterminant cov
      twoPiE = 2 * pi * exp 1
  in 0.5 * log (twoPiE ** 3 * max det 1e-12)

-- | Covariance for already-normalised probabilities (Σp = 1): @Σ pᵢ d d@ with no
-- re-division. Used by 'gaussianColorEntropy' so the uniform fallback matches the
-- oracle bit-for-bit.
weightedCovarianceNorm :: [(OKLab, Double)] -> Cov3
weightedCovarianceNorm cands =
  let acc (al, aa, ab) (OKLab l a b, p) = (al + p * l, aa + p * a, ab + p * b)
      (ml, ma, mb) = foldl acc (0, 0, 0) cands
      step (sll, sla, slb, saa, sab, sbb) (OKLab l a b, p) =
        let dl = l - ml; da = a - ma; db = b - mb
        in ( sll + p * dl * dl, sla + p * dl * da, slb + p * dl * db
           , saa + p * da * da, sab + p * da * db, sbb + p * db * db )
  in foldl step (0, 0, 0, 0, 0, 0) cands

-- | Participation-ratio effective dimensionality @(Σλ)² / Σλ²@ ∈ [0,3]. Computed
-- from covariance traces (identical to the eigenvalue form). Mirrors
-- @effective_dim(color_pca(..))@; returns 0 when the spread is degenerate.
effectiveDim :: [(OKLab, Double)] -> Double
effectiveDim cands =
  let cov = weightedCovariance cands
      s   = covTrace cov
      s2  = covFrobeniusSq cov
  in if s2 <= 0 then 0 else s * s / s2
