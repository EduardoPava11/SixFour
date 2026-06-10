{- |
Module      : Properties.AtlasBoard
Description : Property tests for 'SixFour.Spec.AtlasBoard' (the 16³ board state).

Exercises the EXPORTED laws: mass normalisation, binning agreement with
'Coverage.okLabBin', the σ-mirror off bin boundaries (generators avoid lattice
points by construction — continuous draws hit them with probability zero),
token σ-invariance, totality on empty capture, and the pinned Q16 rounding
golden vectors (design risk 7).
-}
module Properties.AtlasBoard (tests) where

import Test.Tasty
import Test.Tasty.QuickCheck
import Test.QuickCheck

import SixFour.Spec.AtlasBoard
import SixFour.Spec.AtlasMove  (CurationMove(..), GenomeHash(..), Q88(..),
                                boardFromLog)
import SixFour.Spec.Color      (OKLab(..))

genOKLab :: Gen OKLab
genOKLab = OKLab <$> choose (0, 1) <*> choose (-0.4, 0.4) <*> choose (-0.4, 0.4)

-- | Colours possibly OUTSIDE the working range (okLabBin clamps — the
-- binning-agreement law must hold there too).
genOKLabWide :: Gen OKLab
genOKLabWide = OKLab <$> choose (-0.3, 1.3) <*> choose (-0.7, 0.7) <*> choose (-0.7, 0.7)

genBin :: Gen BinIdx
genBin = fmap BinIdx ((,,) <$> choose (0, 15) <*> choose (0, 15) <*> choose (0, 15))

genCuration :: Gen CurationMove
genCuration = oneof
  [ ToggleBin <$> genBin
  , WeightRegion <$> genBin <*> (Q88 <$> arbitrary)
  , PinAnchor <$> genBin <*> (okLabToQ16 <$> genOKLab)
  , Compare <$> (GenomeHash <$> arbitrary) <*> (GenomeHash <$> arbitrary)
  ]

-- | A board reachable in the app: base channels from capture colours, then a
-- replayed curation log.
genBoard :: Gen Board16
genBoard = do
  pals   <- resize 4 (listOf (resize 12 (listOf genOKLab)))
  pixels <- resize 24 (listOf genOKLab)
  cands  <- resize 24 (listOf genOKLab)
  moves  <- resize 12 (listOf genCuration)
  pure (boardFromLog (boardTensor pals pixels cands) moves)

tests :: TestTree
tests = testGroup "AtlasBoard (the 16^3 curation board state)"
  [ testProperty "ch0 mass sums to 1 on any non-empty palettes" $
      forAll (resize 4 (listOf (resize 12 (listOf genOKLab)))) lawMassNormalized
  , testProperty "binning IS Coverage.okLabBin, pointwise (incl. clamped range)" $
      forAll genOKLabWide lawBinAgreesWithCoverage
  , testProperty "sigma-mirror off bin boundaries (continuous gens avoid lattice)" $
      forAll (resize 3 (listOf (resize 8 (listOf genOKLab)))) $ \pals ->
      forAll (resize 12 (listOf genOKLab)) $ \pixels ->
      forAll (resize 12 (listOf genOKLab)) $ \cands ->
        lawSigmaMirrorOffBoundary pals pixels cands
  , testProperty "boardSigma is an involution" $
      forAll genBoard $ \b -> boardSigma (boardSigma b) == b
  , testProperty "tokens map under sigma by negating cols 4-5 only" $
      forAll genBoard lawTokensSigmaInvariantCols
  , testProperty "every token has width 13" $
      forAll genBoard $ \b -> all ((== tokenWidth) . length) (boardTokens b)
  , testProperty "total on the empty capture" $
      property lawTotalOnEmpty
  , testProperty "mirrorBin is an involution on the lattice" $
      forAll genBin $ \bi -> mirrorBin (mirrorBin bi) == bi
  , testProperty "Q16 golden vectors (the ONE pinned rounding function)" $
      property $
        okLabToQ16 (OKLab 0 0 0) == (0, 0, 0)
          && okLabToQ16 (OKLab 1 0.5 (-0.5)) == (65536, 32768, -32768)
          && okLabToQ16 (OKLab 0.5 0.25 (-0.25)) == (32768, 16384, -16384)
          && okLabToQ16 (OKLab (1 / 131072) 0 0) == (1, 0, 0)   -- rounds half UP
  , testProperty "Q16 round trip is exact on Q16-representable colours" $
      forAll genOKLab $ \c ->
        let q = okLabToQ16 c in okLabToQ16 (okLabFromQ16 q) == q
  ]
