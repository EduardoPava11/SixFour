{- |
Module      : SixFour.Spec.SigmaDecomp
Description : σ-eigenspace decomposition of the 16³ OKLab histogram (the 16³:16³ pair).

The chroma involution @σ(L,a,b) = (L,−a,−b)@ of 'SixFour.Spec.PairTree.sigmaReflect'
induces a permutation on the 4096 bin indices of 'SixFour.Spec.Bottleneck16':

    σ_bin (iL, ia, ib) = (iL, 15 − ia, 15 − ib)

It is an involution (@σ_bin ∘ σ_bin = id@). The histogram space ℝ⁴⁰⁹⁶ decomposes
orthogonally under σ into the ±1 eigenspaces:

    H        = H_sym + H_asym
    H_sym    = ½(H + σ·H)        (fixed by σ;  symmetric)
    H_asym   = ½(H − σ·H)        (negated by σ; antisymmetric)
    ⟨H_sym, H_asym⟩ = 0          (orthogonal)
    ‖H‖²     = ‖H_sym‖² + ‖H_asym‖²   (Parseval)

== Bin-orbit accounting (16 bins per axis is a clean case)

With 16 bins per chromatic axis, @σ_bin@ is @ia → 15−ia@. A fixed point would
require @ia = 7.5@ — no integer solution. So @σ_bin@ has **NO fixed bins** in
the chromatic plane, and all 4096 bins partition into 2048 σ-2-orbits:

    σ-fixed bins:   0
    σ-2-orbits:     2048 = 4096 / 2
    dim H_sym  :    2048   (one degree of freedom per orbit: the sum)
    dim H_asym :    2048   (one degree of freedom per orbit: the difference)
    total      :    4096  ✓

== The headline metric

'sigmaSymFraction' @H = ‖H_sym‖² / ‖H‖² ∈ [0, 1]@ is the **upper bound on
representational fidelity** of any σ-pair palette for a given capture, before any
look-NN training. A perfectly complement-symmetric scene has 1; a maximally
anti-symmetric scene has 0. It pairs with @gamutCoverageFraction@ to give two
orthogonal scene-affordance numbers: coverage = how much of the gamut you reach;
σ-symmetry = how much of the scene a σ-balanced palette can in principle fit.

== σ-symmetric palette ⇒ σ-symmetric histogram

For any palette whose 256 leaves form 128 σ-pairs @{c, σ(c)}@, the induced 4096-bin
histogram lies entirely in H_sym (the asymmetric part is exactly zero). This is the
algebraic statement that a σ-balanced palette cannot represent the σ-antisymmetric
component of a scene — the irreducible σ-asymmetry @‖H_asym‖@ is the floor on the
fidelity tax of σ-balance.

Laws: @σ_bin@ is an involution; the sym/asym parts are orthogonal; Parseval;
the uniform histogram has @H_asym = 0@ (it lies entirely in H_sym); a
σ-paired-OKLab list produces @sigmaSymFraction = 1@.
-}
module SixFour.Spec.SigmaDecomp
  ( -- * σ on bin indices
    sigmaBinPerm
    -- * Eigenspace projections
  , symPart
  , asymPart
  , symPartVector
    -- * The headline scene-affordance metrics
  , sigmaSymFraction
  , sigmaAsymNormSquared
    -- * Dimensional accounting (exact, exported for codegen)
  , sigmaFixedBinCount
  , sigmaOrbitCount
  , dimSigmaSym
  , dimSigmaAsym
    -- * Laws
  , lawSigmaBinInvolution
  , lawOrthogonalDecomp
  , lawParseval
  , lawSymPartMassOne
  , lawSymPartNonNeg
  , lawUniformIsSym
  , lawSigmaPairedListIsSym
  ) where

import qualified Data.Vector.Unboxed as U
import           Data.Vector.Unboxed (Vector)

import SixFour.Spec.Bottleneck16
  ( Histogram4096(..)
  , numBins
  , numBinsPerAxis
  , binIndex
  , binToCoords
  , histogramFromOKLabs
  )
import SixFour.Spec.Color    (OKLab(..))
import SixFour.Spec.PairTree (sigmaReflect)

-- | The σ-induced permutation on flat bin indices in [0, 4096).
-- @σ_bin (iL, ia, ib) = (iL, 15−ia, 15−ib)@.
sigmaBinPerm :: Int -> Int
sigmaBinPerm i =
  let (iL, ia, ib) = binToCoords i
      n           = numBinsPerAxis
  in binIndex (iL, n - 1 - ia, n - 1 - ib)

-- | Apply σ_bin to a histogram vector: @(σH)[i] = H[σ_bin i]@.
sigmaApply :: Vector Double -> Vector Double
sigmaApply v = U.generate (U.length v) (\i -> v U.! sigmaBinPerm i)

-- | Symmetric eigenspace projection: @H_sym = ½(H + σH)@.
-- Still a probability simplex: non-negativity and mass-1 are preserved.
symPart :: Histogram4096 -> Histogram4096
symPart (Histogram4096 v) =
  Histogram4096 (U.zipWith (\a b -> 0.5 * (a + b)) v (sigmaApply v))

-- | Anti-symmetric eigenspace projection: @H_asym = ½(H − σH)@.
-- Signed (no longer a probability), so the return type is a raw 'Vector Double'.
asymPart :: Histogram4096 -> Vector Double
asymPart (Histogram4096 v) =
  U.zipWith (\a b -> 0.5 * (a - b)) v (sigmaApply v)

-- | Convenience: the symmetric part as a raw vector (for norm computations).
symPartVector :: Histogram4096 -> Vector Double
symPartVector = unHistogram . symPart

-- | @sigmaSymFraction H = ‖H_sym‖² / ‖H‖²@. The upper bound on σ-pair palette
-- fidelity for the scene described by @H@. Maps a uniform histogram to 1.
sigmaSymFraction :: Histogram4096 -> Double
sigmaSymFraction h@(Histogram4096 v) =
  let s     = symPartVector h
      sN    = U.sum (U.map (\x -> x * x) s)
      hN    = U.sum (U.map (\x -> x * x) v)
  in if hN <= 1e-30 then 1.0 else sN / hN

-- | @‖H_asym‖²@ — the σ-antisymmetric "mass" the σ-pair palette cannot represent.
sigmaAsymNormSquared :: Histogram4096 -> Double
sigmaAsymNormSquared h =
  let a = asymPart h
  in U.sum (U.map (\x -> x * x) a)

-- * Dimensional accounting (compile-time integers, exposed for codegen)

-- | Number of σ-fixed bins: 0 (at 16 bins per axis, no @ia = 15 − ia@ integer fits).
sigmaFixedBinCount :: Int
sigmaFixedBinCount = 0

-- | Number of σ-2-orbits: @(numBins − sigmaFixedBinCount) / 2 = 2048@.
sigmaOrbitCount :: Int
sigmaOrbitCount = (numBins - sigmaFixedBinCount) `div` 2

-- | Dimension of the σ-symmetric eigenspace.
dimSigmaSym :: Int
dimSigmaSym = sigmaFixedBinCount + sigmaOrbitCount

-- | Dimension of the σ-antisymmetric eigenspace.
dimSigmaAsym :: Int
dimSigmaAsym = sigmaOrbitCount

-- * Laws

-- | @sigmaBinPerm@ is an involution on @[0, 4096)@.
lawSigmaBinInvolution :: Int -> Bool
lawSigmaBinInvolution i =
  not (i >= 0 && i < numBins) || sigmaBinPerm (sigmaBinPerm i) == i

-- | Orthogonal decomposition: @⟨H_sym, H_asym⟩ = 0@.
lawOrthogonalDecomp :: Double -> Histogram4096 -> Bool
lawOrthogonalDecomp tol h =
  let s = symPartVector h
      a = asymPart h
      ip = U.sum (U.zipWith (*) s a)
  in abs ip <= tol

-- | Parseval: @‖H‖² = ‖H_sym‖² + ‖H_asym‖²@.
lawParseval :: Double -> Histogram4096 -> Bool
lawParseval tol h@(Histogram4096 v) =
  let s = symPartVector h
      a = asymPart h
      nH = U.sum (U.map (\x -> x * x) v)
      nS = U.sum (U.map (\x -> x * x) s)
      nA = U.sum (U.map (\x -> x * x) a)
  in abs (nH - (nS + nA)) <= tol

-- | The symmetric part is still mass-1 (so the @Histogram4096@ brand on @symPart@
-- is correct).
lawSymPartMassOne :: Double -> Histogram4096 -> Bool
lawSymPartMassOne tol h =
  let Histogram4096 s = symPart h
  in abs (U.sum s - 1.0) <= tol

-- | The symmetric part is still non-negative.
lawSymPartNonNeg :: Histogram4096 -> Bool
lawSymPartNonNeg h =
  let Histogram4096 s = symPart h
  in U.all (>= 0) s

-- | The uniform histogram has @sigmaSymFraction = 1@ (no asymmetric mass).
lawUniformIsSym :: Double -> Bool
lawUniformIsSym tol =
  let h = Histogram4096 (U.replicate numBins (1.0 / fromIntegral numBins))
  in abs (sigmaSymFraction h - 1.0) <= tol

-- | An OKLab list closed under σ (every @c@ appears with its mirror @σ(c)@) yields
-- a histogram with @sigmaSymFraction = 1@ — the σ-pair palette achievability claim.
lawSigmaPairedListIsSym :: Double -> [OKLab] -> Bool
lawSigmaPairedListIsSym tol cs =
  let paired = cs ++ map sigmaReflect cs
      h      = histogramFromOKLabs paired
      f      = sigmaSymFraction h
  in abs (f - 1.0) <= tol
