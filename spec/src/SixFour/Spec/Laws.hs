{- |
Module      : SixFour.Spec.Laws
Description : Algebraic laws that any conforming pipeline must satisfy.

These laws are *not* QuickCheck properties themselves — they are pure
predicates that the property test modules call. Keeping them here
documents the contract in one place and lets the codegen mention
each by name in the emitted Swift / Python doc-comments.
-}
module SixFour.Spec.Laws
  ( -- * Color laws
    lawOKLabRoundTrip
    -- * Gauge laws
  , lawGaugeIdentity
    -- * Stage A law
  , lawWuShapesOut
    -- * Transport marginal law (cyclic transition plan)
  , lawSinkhornBalancedColumns
    -- * Cyclic-environment laws (MATH.md §8)
  , lawCyclicClosedness
  , lawDescriptorGaugeInvariant
  , lawDescriptorCyclicShiftInvariant
  , lawPaletteEntropyBounds
  , lawSpectralEntropyBounds
  ) where

import qualified Data.Vector         as V
import qualified Data.Vector.Unboxed as U
import           GHC.TypeLits        (KnownNat)

import SixFour.Spec.Color
import SixFour.Spec.Indices
import SixFour.Spec.Palette
import SixFour.Spec.Gauge
import SixFour.Spec.StageA   (StageA, Frame(..), runStageA)
import SixFour.Spec.Shape    (kVal, pixelsPerFrame)
import SixFour.Spec.Cyclic
  ( Weights, SinkhornParams, CyclicStack(..), descriptor, alignedDelta
  , paletteEntropy, spectralEntropy )

-- | OKLab round-trip: @srgbToOKLab . okLabToSRGB@ should be identity
-- to within tolerance, for sRGB values in @[0,1]@.
lawOKLabRoundTrip :: Double -> SRGB -> Bool
lawOKLabRoundTrip tol s@(SRGB r g b)
  | r < 0 || g < 0 || b < 0 || r > 1 || g > 1 || b > 1 = True   -- ignore out-of-gamut
  | otherwise =
      let SRGB r' g' b' = okLabToSRGB (srgbToOKLab s)
      in abs (r - r') < tol && abs (g - g') < tol && abs (b - b') < tol

-- | Gauge: applying any permutation @σ@ to both palette and indices
-- leaves the decoded image (= 'gather' result) unchanged.
lawGaugeIdentity
  :: KnownNat k
  => Permutation k
  -> Palette k
  -> IndexTensor t h w k
  -> Bool
lawGaugeIdentity sigma p i =
  let (p', i') = gaugeAction sigma p i
      lhs      = gather p  i
      rhs      = gather p' i'
  in lhs == rhs

-- | After Stage A on a frame of size (H, W), the index tensor has
-- exactly @H*W@ entries and the palette has @K@ entries.
lawWuShapesOut
  :: forall h w k. (KnownNat h, KnownNat w, KnownNat k)
  => StageA h w k -> Frame h w -> Bool
lawWuShapesOut sA fr =
  let (Palette pv, IndexTensor iv) = runStageA sA fr
  in V.length pv == kVal && U.length iv == pixelsPerFrame

-- | Sinkhorn property: column marginals of the transport plan are
-- equal. We expose only the predicate; the property test constructs
-- the plan and feeds it here.
lawSinkhornBalancedColumns
  :: Double                      -- ^ tolerance
  -> V.Vector (V.Vector Double)  -- ^ plan @(N, K)@
  -> Bool
lawSinkhornBalancedColumns tol plan =
  let nC = V.length plan
      nK = if nC == 0 then 0 else V.length (plan V.! 0)
      colSum k = V.foldl' (\acc row -> acc + row V.! k) 0 plan
      sums     = [colSum k | k <- [0 .. nK - 1]]
      mu       = sum sums / fromIntegral (max 1 nK)
  in all (\s -> abs (s - mu) <= tol) sums

-- | Thm 4 (cyclic closedness). Under the identity correspondence the
-- per-colour cyclic deltas telescope to zero around the loop:
-- @Σ_t Δ[t,k] = 0@ for every colour @k@.
lawCyclicClosedness
  :: forall t k. (KnownNat t)
  => Double -> CyclicStack t k -> Bool
lawCyclicClosedness tol stk =
  let deltas = alignedDelta stk            -- T × K of OKLab
      nt     = V.length deltas
  in nt == 0 ||
     let nk = V.length (deltas V.! 0)
         sumK k = V.foldl'
           (\(aL, aA, aB) t -> let OKLab l a b = (deltas V.! t) V.! k
                               in (aL + l, aA + a, aB + b))
           (0, 0, 0) (V.enumFromN 0 nt)
     in all (\k -> let (l, a, b) = sumK k
                   in abs l <= tol && abs a <= tol && abs b <= tol)
            [0 .. nk - 1]

-- | Thm 5 (@S_K@ invariance). Permuting every frame's palette and weights
-- by the same σ (colour↔weight pairing preserved) leaves the descriptor
-- unchanged.
lawDescriptorGaugeInvariant
  :: forall t k. (KnownNat t, KnownNat k)
  => SinkhornParams -> Double -> Permutation k -> CyclicStack t k -> Bool
lawDescriptorGaugeInvariant params tol sigma stk@(CyclicStack frames) =
  let permuted :: CyclicStack t k
      permuted = CyclicStack $ V.map
        (\(Palette pv, w) -> (Palette (permuteVector sigma pv), permuteVector sigma w))
        frames
  in vecClose tol (descriptor params stk) (descriptor params permuted)

-- | Thm 5 (@Z_T@ invariance). Rotating the loop's start frame leaves the
-- descriptor unchanged.
lawDescriptorCyclicShiftInvariant
  :: forall t k. (KnownNat t, KnownNat k)
  => SinkhornParams -> Double -> CyclicStack t k -> Bool
lawDescriptorCyclicShiftInvariant params tol stk@(CyclicStack frames) =
  let nt = V.length frames
      rotated :: CyclicStack t k
      rotated = CyclicStack $ V.generate nt (\i -> frames V.! ((i + 1) `mod` nt))
  in vecClose tol (descriptor params stk) (descriptor params rotated)

-- | Def 15 bounds: @0 ≤ H(w) ≤ log K@. Palette size @K@ passed as a
-- plain 'Int' (the bound is the only place it appears).
lawPaletteEntropyBounds :: Int -> Weights -> Bool
lawPaletteEntropyBounds kSize w =
  let h  = paletteEntropy w
      hi = log (fromIntegral (max 1 kSize) :: Double)
  in h >= -1e-9 && h <= hi + 1e-9

-- | Def 18 bounds: @0 ≤ H_spec ≤ log(N-1)@ over the AC bins.
lawSpectralEntropyBounds :: [Double] -> Bool
lawSpectralEntropyBounds xs =
  let h  = spectralEntropy xs
      n  = length xs
      hi = if n <= 1 then 0 else log (fromIntegral (n - 1))
  in h >= -1e-9 && h <= hi + 1e-9

-- Internal: element-wise closeness of two descriptor vectors.
vecClose :: Double -> V.Vector Double -> V.Vector Double -> Bool
vecClose tol a b =
  V.length a == V.length b && V.and (V.zipWith (\x y -> abs (x - y) <= tol) a b)
