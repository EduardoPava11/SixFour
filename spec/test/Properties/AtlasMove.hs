{- |
Module      : Properties.AtlasMove
Description : Property tests for 'SixFour.Spec.AtlasMove' (the curation Move ADT).

Exercises the EXPORTED laws on boards REACHABLE BY REPLAY (the toggle
involution is stated on {0,1} kill values, i.e. exactly the replay-reachable
boards) plus out-of-range bins (totality: identity).
-}
module Properties.AtlasMove (tests) where

import Test.Tasty
import Test.Tasty.QuickCheck
import Test.QuickCheck

import SixFour.Spec.AtlasBoard
import SixFour.Spec.AtlasMove
import SixFour.Spec.Color      (OKLab(..))

genOKLab :: Gen OKLab
genOKLab = OKLab <$> choose (0, 1) <*> choose (-0.4, 0.4) <*> choose (-0.4, 0.4)

genBinIn :: Gen BinIdx
genBinIn = fmap BinIdx ((,,) <$> choose (0, 15) <*> choose (0, 15) <*> choose (0, 15))

-- | In-range bins, plus the occasional out-of-range one (moves must be total).
genBinAny :: Gen BinIdx
genBinAny = frequency
  [ (4, genBinIn)
  , (1, fmap BinIdx ((,,) <$> choose (-3, 19) <*> choose (-3, 19) <*> choose (-3, 19)))
  ]

genQ88 :: Gen Q88
genQ88 = Q88 <$> arbitrary

genHash :: Gen GenomeHash
genHash = GenomeHash <$> arbitrary

genCuration :: Gen CurationMove
genCuration = oneof
  [ ToggleBin <$> genBinAny
  , WeightRegion <$> genBinAny <*> genQ88
  , PinAnchor <$> genBinAny <*> (okLabToQ16 <$> genOKLab)
  , Compare <$> genHash <*> genHash
  ]

-- | A replay-reachable board (base channels from capture, curation by fold).
genBoard :: Gen Board16
genBoard = do
  pals   <- resize 3 (listOf (resize 10 (listOf genOKLab)))
  pixels <- resize 16 (listOf genOKLab)
  cands  <- resize 16 (listOf genOKLab)
  moves  <- resize 12 (listOf genCuration)
  pure (boardFromLog (boardTensor pals pixels cands) moves)

tests :: TestTree
tests = testGroup "AtlasMove (curation plies on the 16^3 board)"
  [ testProperty "ToggleBin is involutive on replay-reachable boards" $
      forAll genBinAny $ \bi -> forAll genBoard $ \b -> lawToggleInvolutive bi b
  , testProperty "WeightRegion is additive + commutative (exact, Q8.8 dyadic)" $
      forAll genBinAny $ \bi -> forAll genQ88 $ \d1 ->
      forAll genBinAny $ \bj -> forAll genQ88 $ \d2 ->
      forAll genBoard  $ \b  -> lawWeightAdditiveCommutative bi d1 bj d2 b
  , testProperty "PinAnchor is idempotent" $
      forAll genBinAny $ \bi -> forAll (okLabToQ16 <$> genOKLab) $ \cq ->
      forAll genBoard  $ \b  -> lawPinIdempotent bi cq b
  , testProperty "Compare mutates nothing (pure BT signal)" $
      forAll genHash  $ \w -> forAll genHash $ \l ->
      forAll genBoard $ \b -> lawCompareIdentity w l b
  , testProperty "replay determinism: same log => identical board" $
      forAll genBoard $ \b -> forAll (resize 16 (listOf genCuration)) $ \lg ->
        lawReplayDeterminism b lg
  , testProperty "curation never edits base channels ch0-ch2" $
      forAll genBoard $ \b -> forAll (resize 16 (listOf genCuration)) $ \lg ->
        lawBaseChannelsUntouched b lg
  , testProperty "out-of-range bins act as the identity (totality)" $
      forAll genBoard $ \b -> forAll genQ88 $ \d ->
        let bi = BinIdx (16, 0, 0)
        in applyCuration (ToggleBin bi) b == b
             && applyCuration (WeightRegion bi d) b == b
             && applyCuration (PinAnchor bi (0, 0, 0)) b == b
  ]
