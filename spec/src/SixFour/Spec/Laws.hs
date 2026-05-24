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
    -- * Surjectivity laws
  , lawSurjectiveAfterStageB
    -- * Stage A law
  , lawWuShapesOut
    -- * Sinkhorn marginal law
  , lawSinkhornBalancedColumns
  ) where

import qualified Data.Vector         as V
import qualified Data.Vector.Unboxed as U
import           GHC.TypeLits        (KnownNat)

import SixFour.Spec.Color
import SixFour.Spec.Indices
import SixFour.Spec.Palette
import SixFour.Spec.Gauge
import SixFour.Spec.StageA   (StageA, Frame(..), runStageA)
import SixFour.Spec.StageB   (StageBOutput(..))
import SixFour.Spec.Shape    (kVal, pixelsPerFrame)

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

-- | Stage B output indices are surjective (witness exists by construction).
-- This law is trivially true at the type level; the test calls
-- 'mkSurjective256' on the raw tensor as an external sanity check.
lawSurjectiveAfterStageB
  :: forall t h w k. (KnownNat k)
  => StageBOutput t h w k -> Bool
lawSurjectiveAfterStageB out =
  let IndexTensor v = sbGlobalIndices out
      seen          = U.toList v
      uniq          = length (foldr (\x acc -> if x `elem` acc then acc else x:acc) [] seen)
  in uniq == kVal

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
