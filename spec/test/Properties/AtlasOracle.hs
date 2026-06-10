{- |
Module      : Properties.AtlasOracle
Description : Property tests for 'SixFour.Spec.AtlasOracle' — the day-1
              board-modulated oracle (every fix at the oracle seam).

Boards are replay-reachable (capture base + folded curation log) so kill
masks are {0,1} and anchors carry their pinned colours; states are depth-7
σ-pair genomes (design §4.0).
-}
module Properties.AtlasOracle (tests) where

import Test.Tasty
import Test.Tasty.QuickCheck
import Test.QuickCheck

import SixFour.Spec.AtlasBoard    (BinIdx(..), Board16(..), binOf, boardTensor,
                                   emptyBoard, okLabFromQ16, okLabToQ16)
import SixFour.Spec.AtlasMove     (CurationMove(..), GenomeHash(..), Q88(..),
                                   boardFromLog)
import SixFour.Spec.AtlasOracle
import SixFour.Spec.Color         (OKLab(..))
import SixFour.Spec.DeltaCodebook (moveVocab)
import SixFour.Spec.PairTree      (HaarPalette(..))
import SixFour.Spec.PaletteOracle (RewardWeights(..))
import SixFour.Spec.PaletteSearch (Move(..), SearchState)
import SixFour.Spec.SigmaPairHead (sigmaPairDepth)

genOKLab :: Gen OKLab
genOKLab = OKLab <$> choose (0, 1) <*> choose (-0.4, 0.4) <*> choose (-0.4, 0.4)

genSmallOKLab :: Gen OKLab
genSmallOKLab = OKLab <$> choose (-0.05, 0.05) <*> choose (-0.05, 0.05) <*> choose (-0.05, 0.05)

-- | A depth-7 σ-pair genome (the SearchState the Atlas search runs on).
genState7 :: Gen SearchState
genState7 = do
  rt   <- genOKLab
  lvls <- mapM (\i -> vectorOf (2 ^ i) genSmallOKLab) [0 .. sigmaPairDepth - 1]
  pure (HaarPalette rt lvls)

genBinIn :: Gen (Int, Int, Int)
genBinIn = (,,) <$> choose (0, 15) <*> choose (0, 15) <*> choose (0, 15)

genCuration :: Bool -> Gen CurationMove
genCuration withAnchors = oneof $
  [ ToggleBin . BinIdx <$> genBinIn
  , WeightRegion . BinIdx <$> genBinIn <*> (Q88 <$> choose (-512, 512))
  ] ++ [ genPin | withAnchors ]
  where
    -- CONSISTENT pins (the UI contract 'lawAnchorForcedMove' is stated for):
    -- the pin's bin IS the bin of its (Q16-rounded) colour.
    genPin = do
      c <- genOKLab
      let cq = okLabToQ16 c
      pure (PinAnchor (binOf (okLabFromQ16 cq)) cq)

genBoardWith :: Bool -> Gen Board16
genBoardWith withAnchors = do
  pals   <- resize 3 (listOf (resize 8 (listOf genOKLab)))
  pixels <- resize 12 (listOf genOKLab)
  cands  <- resize 12 (listOf genOKLab)
  moves  <- resize 8 (listOf (genCuration withAnchors))
  pure (boardFromLog (boardTensor pals pixels cands) moves)

genTheta :: Gen [Double]
genTheta = resize 16 (listOf (choose (-1, 1)))

genAtlasWeights :: Gen AtlasWeights
genAtlasWeights = AtlasWeights
  <$> (RewardWeights <$> choose (0.1, 1) <*> choose (0.1, 1))
  <*> genTheta
  <*> choose (0, 200)

genPolicyList :: Gen [(Move, Double)]
genPolicyList = resize 12 (listOf ((,) <$> elements moveVocab <*> choose (0.01, 1)))

tests :: TestTree
tests = testGroup "AtlasOracle (board-modulated reference policy + beta-blend value)"
  [ testProperty "priors sum to 1 (the childrenFromPolicy contract)" $
      forAll (genBoardWith True) $ \b -> forAll genState7 $ \s -> lawPriorsSumOne b s
  , testProperty "policy width <= 8" $
      forAll (genBoardWith True) $ \b -> forAll genState7 $ \s -> lawWidthLeqEight b s
  , testProperty "killed bins never proposed (anchor-free boards)" $
      forAll (genBoardWith False) $ \b -> forAll genState7 $ \s ->
        lawKilledNeverProposed b s
  , testProperty "unmet anchors force an anchor-satisfying move" $
      forAll (genBoardWith True) $ \b -> forAll genState7 $ \s ->
        lawAnchorForcedMove b s
  , testProperty "empty board + zero weights = the reference oracle exactly" $
      forAll genState7 lawZeroWeightsIsReference
  , testProperty "topKRenorm with k >= branching is pure renormalisation" $
      forAll genPolicyList lawTopKIdentityWhenWide
  , testProperty "oracle is deterministic (pure)" $
      forAll genAtlasWeights $ \w -> forAll (genBoardWith True) $ \b ->
      forAll genState7 $ \s -> lawOracleDeterministic w b s
  , testProperty "beta blend: 0 at n=0, monotone, < 1" $
      forAll (choose (0, 10000)) $ \n ->
        betaBlend 0 == 0
          && betaBlend n < 1
          && betaBlend (n + 1) >= betaBlend n
  , testProperty "no theta => value is the pure shaped reward (bottom tier)" $
      forAll (genBoardWith True) $ \b -> forAll genState7 $ \s ->
      forAll (choose (1, 500)) $ \n ->
        let w = zeroAtlasWeights { awCompares = n }   -- compares but NO theta
        in atlasValue w b s == atlasValue zeroAtlasWeights b s
  ]
