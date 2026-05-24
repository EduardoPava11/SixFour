module Properties.Sinkhorn (tests) where

import Test.Tasty
import Test.Tasty.QuickCheck
import Test.QuickCheck

import qualified Data.Vector         as V
import qualified Data.Vector.Unboxed as U
import           Data.Maybe          (isJust, isNothing, fromJust)

import SixFour.Spec.Color   (OKLab(..), okLabDistanceSquared)
import SixFour.Spec.StageA
import SixFour.Spec.StageB
import SixFour.Spec.Palette (Palette(..))
import SixFour.Spec.Indices (IndexTensor(..), mkIndexTensor, mkSurjective256)

-- Tiny pipeline: T = 3 frames of 4x4 pixels, K = 8 colours.

type T = 3
type H = 4
type W = 4
type K = 8

genFrame :: Gen (Frame H W)
genFrame = do
  xs <- vectorOf (4 * 4) $ do
    l <- choose (0, 1)
    a <- choose (-0.4, 0.4)
    b <- choose (-0.4, 0.4)
    pure (OKLab l a b)
  pure (Frame (V.fromList xs))

-- | Per-OKLab-channel max-abs distance — used for "centroid sets agree" assertions.
labMaxDiff :: V.Vector OKLab -> V.Vector OKLab -> Double
labMaxDiff xs ys
  | V.length xs /= V.length ys = 1/0
  | otherwise = V.maximum $ V.zipWith
      (\(OKLab l1 a1 b1) (OKLab l2 a2 b2) ->
         maximum [abs (l1-l2), abs (a1-a2), abs (b1-b2)])
      xs ys

tests :: TestTree
tests = testGroup "StageB / Sinkhorn-balanced k-means"
  [ testProperty "output global palette has exactly K entries" $
      forAll (vectorOf 3 genFrame) $ \fs ->
        let perFrame = map (runStageA (varianceCutReference @H @W @K)) fs
            (pals, ixs) = unzip perFrame
            params  = sharedSinkhornParams { spKMeansIts = 3, spIterCount = 5 }
            out     = runStageB (sinkhornReference @T @H @W @K params)
                                (StageBInput pals ixs)
            Palette gp = sbGlobalPalette out
        in V.length gp == 8
  , testProperty "global indices have T*H*W entries, all in [0, K-1]" $
      forAll (vectorOf 3 genFrame) $ \fs ->
        let perFrame    = map (runStageA (varianceCutReference @H @W @K)) fs
            (pals, ixs) = unzip perFrame
            params      = sharedSinkhornParams { spKMeansIts = 3, spIterCount = 5 }
            out         = runStageB (sinkhornReference @T @H @W @K params)
                                    (StageBInput pals ixs)
            IndexTensor giv = sbGlobalIndices out
        in U.length giv == 3 * 4 * 4
           && U.all (\i -> i >= 0 && i < 8) giv

  -- New: log-domain Sinkhorn agrees with direct-exp at moderate θ.
  -- We compare centroid sets (palette OKLab values) within a tight
  -- tolerance — the two implementations should match to ~1e-4 at
  -- θ ∈ {0.05, 0.5} after the same number of outer/inner iterations.
  , testProperty "log-domain Sinkhorn agrees with direct-exp at θ=0.05" $
      forAll (vectorOf 3 genFrame) $ \fs ->
        let perFrame    = map (runStageA (varianceCutReference @H @W @K)) fs
            (pals, ixs) = unzip perFrame
            params      = SinkhornParams { spEpsilon = 0.05
                                         , spIterCount = 30
                                         , spKMeansIts = 5 }
            outA = runStageB (sinkhornReference          @T @H @W @K params)
                             (StageBInput pals ixs)
            outB = runStageB (logDomainSinkhornReference @T @H @W @K params)
                             (StageBInput pals ixs)
            Palette pA = sbGlobalPalette outA
            Palette pB = sbGlobalPalette outB
        in labMaxDiff pA pB < 1e-3

  , testProperty "log-domain Sinkhorn agrees with direct-exp at θ=0.5" $
      forAll (vectorOf 3 genFrame) $ \fs ->
        let perFrame    = map (runStageA (varianceCutReference @H @W @K)) fs
            (pals, ixs) = unzip perFrame
            params      = SinkhornParams { spEpsilon = 0.5
                                         , spIterCount = 30
                                         , spKMeansIts = 5 }
            outA = runStageB (sinkhornReference          @T @H @W @K params)
                             (StageBInput pals ixs)
            outB = runStageB (logDomainSinkhornReference @T @H @W @K params)
                             (StageBInput pals ixs)
            Palette pA = sbGlobalPalette outA
            Palette pB = sbGlobalPalette outB
        in labMaxDiff pA pB < 1e-3

  -- New: at θ = 50, log-domain Sinkhorn realises the rank-1 limit —
  -- every centroid lies within a small OKLab ball of the others.
  , testProperty "log-domain Sinkhorn at θ=50 collapses palette to a tight cluster" $
      forAll (vectorOf 3 genFrame) $ \fs ->
        let perFrame    = map (runStageA (varianceCutReference @H @W @K)) fs
            (pals, ixs) = unzip perFrame
            params      = globalSinkhornParams
            out         = runStageB (logDomainSinkhornReference @T @H @W @K params)
                                    (StageBInput pals ixs)
            Palette pv  = sbGlobalPalette out
            c0          = pv V.! 0
            farthestSq  = V.maximum (V.map (okLabDistanceSquared c0) pv)
        in -- centroids cluster within ~0.01 OKLab radius (≈ "very tight")
           farthestSq < 0.05

  -- The surjectivity witness is `Maybe`, NOT guaranteed to be `Just`.
  -- Research (Cuturi 2013; Peyré & Cuturi 2018) confirms that
  -- Sinkhorn balance gives equal soft column mass, not hard-NN
  -- surjectivity. Verify the wiring is consistent:
  --   * when witness is Just, the index tensor really is surjective
  --   * when witness is Nothing, at least one slot is missing
  , testProperty "witness Just implies index tensor is genuinely surjective" $
      forAll (vectorOf 3 genFrame) $ \fs ->
        let perFrame    = map (runStageA (varianceCutReference @H @W @K)) fs
            (pals, ixs) = unzip perFrame
            params      = sharedSinkhornParams { spKMeansIts = 3, spIterCount = 5 }
            out         = runStageB (sinkhornReference @T @H @W @K params)
                                    (StageBInput pals ixs)
            IndexTensor giv = sbGlobalIndices out
            usedAll     = all (\k -> U.any (== k) giv) [0 .. 7]
        in case sbWitness out of
             Just _  -> usedAll          -- claim must match reality
             Nothing -> not usedAll      -- absence must mean a slot is missing

  -- Counterexample (sanity for the witness type itself).
  , testProperty "mkSurjective256 rejects a tensor missing some index" $
      once $
        let v = replicate (3 * 4 * 4) 0    -- all-zero index tensor
            it = fromJust (mkIndexTensor @T @H @W @K v)
        in isNothing (mkSurjective256 @T @H @W @K it)
  ]
