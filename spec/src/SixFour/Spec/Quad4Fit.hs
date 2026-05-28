{- |
Module      : SixFour.Spec.Quad4Fit
Description : Quad4 as an explicit linear map — design matrix, rank, residual.

Promotes 'SixFour.Spec.Quad4' from a constructive @reconstruct :: Quad4Palette
-> [OKLab]@ to an explicit linear operator @B ∈ ℝ^{768 × 513}@ on flat palette
vectors. From this we can compute:

  * The numerical rank of @B@ — the effective dimension of Quad4's image
    subspace in palette space. If @rank(B) < 513@, the genome has redundant
    parameters; if @rank(B) ≈ 384@, Quad4 spans the σ-pair palette subspace;
    if @rank(B) < 384@, Quad4 cannot even fit all σ-pair palettes.

  * 'quad4Residual' = the relative residual @‖P − Π_B P‖² / ‖P‖²@ where
    @Π_B@ is the orthogonal projection onto @im(B)@. This is the
    achievable-fidelity lower bound for ANY Quad4 representation of @P@,
    /before/ any learning.

  * The same operations on @im(B_achr)@ — Quad4 with the achromatic-root
    constraint (root.a = root.b = 0), which is the version
    'SixFour.Spec.Pipeline.Quad4ReconAchroma' uses. 511 columns, 2 fewer than
    the unconstrained version. ('quad4AchromaticIxs' is the index mapping
    from the 511-coefficient genome to the 513-coefficient full one.)

The orthonormal bases 'quad4Basis' and 'quad4AchromaticBasis' are CAFs:
computed once on first access (a few-second QR), reused for every residual
query (O(m·n) per query).

== What this replaces

The type-class compositional "proof" that Pipeline4 derives 'SigmaEquivariant'
(@option4Theorem@) certifies only that shapes commute. It does NOT say whether
Quad4 has the /representational capacity/ to fit a real target palette — that
question lives at the tensor level, and the answer is the value of
'quad4Residual' on the target.

Laws (see @Properties.Quad4Fit@):
  * @quad4Residual (Q4.reconstruct qp) ≈ 0@ for any @qp@ (the palette IS in
    @im(B)@).
  * @0 ≤ quad4Residual P ≤ 1@ for any palette.
  * @quad4ImageRank@ is reported empirically (no assertion — we want to /see/
    the value, not pretend we already know it).
-}
module SixFour.Spec.Quad4Fit
  ( -- * Quad4 in linear-algebra form
    quad4DesignMatrix
  , quad4DesignMatrixAchromatic
  , quad4AchromaticIxs
    -- * Palette ↔ vector
  , paletteToVec
  , vecToPalette
    -- * Orthonormal bases (CAFs, computed once)
  , quad4Basis
  , quad4AchromaticBasis
    -- * Empirical rank
  , quad4ImageRank
  , quad4AchromaticImageRank
    -- * Residuals
  , quad4Residual
  , quad4ResidualAchromatic
  ) where

import qualified Data.Vector.Unboxed as U
import           Data.Vector.Unboxed (Vector)

import SixFour.Spec.Color  (OKLab(..))
import SixFour.Spec.LinAlg
import SixFour.Spec.Quad4
  ( quad4DegreesOfFreedom
  , reconstructFromVector
  )

-- =============================================================================
-- Palette ↔ Vector (the linearisation that lets Quad4 become a matrix)
-- =============================================================================

-- | Flatten a 256-leaf palette to a 768-vector @(L₀, a₀, b₀, L₁, a₁, b₁, …)@.
paletteToVec :: [OKLab] -> Vector Double
paletteToVec leaves = U.fromList (concatMap okToList leaves)
  where okToList (OKLab l a b) = [l, a, b]

-- | Inverse: 768-vector back to 256 leaves.
vecToPalette :: Vector Double -> [OKLab]
vecToPalette v
  | U.length v == 768 =
      [ OKLab (v U.! i) (v U.! (i+1)) (v U.! (i+2)) | i <- [0, 3 .. 765] ]
  | otherwise = []

-- =============================================================================
-- The Quad4 design matrices (CAFs)
-- =============================================================================

-- | The full 768 × 513 Quad4 design matrix. Column @j@ is the palette obtained
-- by setting genome coordinate @j@ to 1 and all others to 0. Built by 513
-- calls to 'reconstructFromVector' on one-hot input vectors.
quad4DesignMatrix :: Matrix
quad4DesignMatrix =
  case fromColumns 768
         [ reconstructAtBasis j | j <- [0 .. quad4DegreesOfFreedom - 1] ] of
    Just m  -> m
    Nothing -> error "quad4DesignMatrix: column length mismatch (internal bug)"
  where
    reconstructAtBasis j =
      let zeros  = U.replicate quad4DegreesOfFreedom 0.0
          oneHot = zeros U.// [(j, 1.0)]
      in case reconstructFromVector oneHot of
           Just leaves -> paletteToVec leaves
           Nothing     -> U.replicate 768 0.0

-- | The genome indices retained under the achromatic-root constraint:
-- @[0, 3, 4, 5, …, 512]@ — we drop indices 1 and 2 (root.a and root.b).
quad4AchromaticIxs :: [Int]
quad4AchromaticIxs = 0 : [3 .. quad4DegreesOfFreedom - 1]

-- | The 768 × 511 achromatic-root Quad4 design matrix — 'quad4DesignMatrix'
-- with columns 1 and 2 dropped.
quad4DesignMatrixAchromatic :: Matrix
quad4DesignMatrixAchromatic =
  case fromColumns 768 [ matCol quad4DesignMatrix j | j <- quad4AchromaticIxs ] of
    Just m  -> m
    Nothing -> error "quad4DesignMatrixAchromatic: internal column count bug"

-- =============================================================================
-- Orthonormal bases of the column spaces (CAFs — built once via MGS)
-- =============================================================================

-- | Tolerance for rejecting linearly-dependent columns in Modified
-- Gram-Schmidt. Chosen well above floating-point epsilon to be robust to the
-- conditioning of the Quad4 basis but well below any meaningful residual.
mgsTol :: Double
mgsTol = 1e-9

-- | Orthonormal basis for @im(quad4DesignMatrix)@.
quad4Basis :: Matrix
quad4Basis = fst (modifiedGramSchmidt mgsTol quad4DesignMatrix)

-- | Orthonormal basis for @im(quad4DesignMatrixAchromatic)@.
quad4AchromaticBasis :: Matrix
quad4AchromaticBasis =
  fst (modifiedGramSchmidt mgsTol quad4DesignMatrixAchromatic)

-- =============================================================================
-- Empirical ranks (numbers we want to /see/, not assume)
-- =============================================================================

-- | Numerical rank of the full Quad4 design matrix.
quad4ImageRank :: Int
quad4ImageRank = matCols quad4Basis

-- | Numerical rank of the achromatic-root Quad4 design matrix.
quad4AchromaticImageRank :: Int
quad4AchromaticImageRank = matCols quad4AchromaticBasis

-- =============================================================================
-- Residuals (the headline numbers)
-- =============================================================================

-- | Relative residual @‖P − Π_B P‖² / ‖P‖²@ when projecting @P@ onto
-- @im(quad4DesignMatrix)@. Returns 0 for the zero vector.
quad4Residual :: [OKLab] -> Double
quad4Residual leaves = residualFraction quad4Basis (paletteToVec leaves)

-- | Relative residual when projecting @P@ onto the achromatic-root Quad4
-- image. ≥ 'quad4Residual' by inclusion of subspaces.
quad4ResidualAchromatic :: [OKLab] -> Double
quad4ResidualAchromatic leaves =
  residualFraction quad4AchromaticBasis (paletteToVec leaves)
