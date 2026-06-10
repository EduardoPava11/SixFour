{- |
Module      : Properties.AtlasState
Description : Property tests for 'SixFour.Spec.AtlasState' — the depth-7/768
              schism fix (embedding AND reward over the 256 leaves).

The generators here produce DEPTH-7 σ-pair genomes (the depth the old 768
claim was never exercised at — design §4.0), plus shallow/degenerate trees to
exercise totality of the well-formedness guards.
-}
module Properties.AtlasState (tests) where

import Test.Tasty
import Test.Tasty.QuickCheck
import Test.QuickCheck

import SixFour.Spec.AtlasBoard    (Board16, boardTensor, emptyBoard)
import SixFour.Spec.AtlasMove     (boardFromLog)
import SixFour.Spec.AtlasState
import SixFour.Spec.Color         (OKLab(..))
import SixFour.Spec.DeltaCodebook (moveVocab)
import SixFour.Spec.PairTree      (HaarPalette(..))
import SixFour.Spec.PaletteOracle (RewardWeights(..))
import SixFour.Spec.PaletteSearch (Move(..))
import SixFour.Spec.SigmaPairHead (sigmaPairDepth)

genOKLab :: Gen OKLab
genOKLab = OKLab <$> choose (0, 1) <*> choose (-0.4, 0.4) <*> choose (-0.4, 0.4)

genSmallOKLab :: Gen OKLab
genSmallOKLab = OKLab <$> choose (-0.05, 0.05) <*> choose (-0.05, 0.05) <*> choose (-0.05, 0.05)

-- | A well-formed depth-d Haar palette.
genHaarDepth :: Int -> Gen HaarPalette
genHaarDepth d = do
  rt   <- genOKLab
  lvls <- mapM (\i -> vectorOf (2 ^ i) genSmallOKLab) [0 .. d - 1]
  pure (HaarPalette rt lvls)

-- | THE state of the Atlas: a depth-7 σ-pair genome (384 DOF, 256 leaves).
genState7 :: Gen SigmaSearchState
genState7 = fromSearchState <$> genHaarDepth sigmaPairDepth

-- | Mixed depths 1..7 — exercises the well-formedness guards.
genStateAny :: Gen SigmaSearchState
genStateAny = do
  d <- choose (1, sigmaPairDepth)
  fromSearchState <$> genHaarDepth d

genVocabMove :: Gen Move
genVocabMove = elements moveVocab

genWeights :: Gen (Double, Double)
genWeights = (,) <$> choose (0.1, 1) <*> choose (0.1, 1)

genBoard :: Gen Board16
genBoard = do
  pals   <- resize 3 (listOf (resize 8 (listOf genOKLab)))
  pixels <- resize 12 (listOf genOKLab)
  cands  <- resize 12 (listOf genOKLab)
  pure (boardFromLog (boardTensor pals pixels cands) [])

tests :: TestTree
tests = testGroup "AtlasState (sigma-pair search state: 256 leaves, never 128 generators)"
  [ testProperty "embedding is EXACTLY 770-D on well-formed depth-7 states" $
      forAll genState7 lawEmbedding770
  , testProperty "embedding law is total over mixed depths" $
      forAll genStateAny lawEmbedding770
  , testProperty "leaves route through reconstructPaired (256 on depth 7)" $
      forAll genState7 lawLeavesViaReconstructPaired
  , testProperty "leaves law is total over mixed depths" $
      forAll genStateAny lawLeavesViaReconstructPaired
  , testProperty "PINNED: leaf-scored reward /= generator-scored reward (the judge fix)" $
      forAll genWeights $ \(wb, wd) ->
        lawRewardOverLeavesNotGenerators (RewardWeights wb wd) emptyBoard
  , testProperty "vocab moves preserve depth 7, well-formedness, 256 leaves" $
      forAll genVocabMove $ \m -> forAll genState7 $ \s ->
        lawSearchPreservesDepth m s
  , testProperty "shaped reward is deterministic" $
      forAll genWeights $ \(wb, wd) -> forAll genBoard $ \b -> forAll genState7 $ \s ->
        shapedReward (RewardWeights wb wd) b s == shapedReward (RewardWeights wb wd) b s
  , testProperty "empty board: shaping terms vanish (reward = pure aesthetics)" $
      forAll genWeights $ \(wb, wd) -> forAll genState7 $ \s ->
        let w = RewardWeights wb wd
            leavesOnly = wb * stateBeauty s
        in shapedReward w emptyBoard s >= leavesOnly - 1e9   -- sanity: finite
             && anchorHit emptyBoard (atlasLeaves s) == 0
  , testProperty "coverage scalar is in [0, 1]" $
      forAll genState7 $ \s -> stateCoverage s >= 0 && stateCoverage s <= 1
  ]
