module Properties.MaskedBandPrediction (tests) where

import Test.Tasty
import Test.Tasty.QuickCheck

import SixFour.Spec.OctreeCell (Detail)
import SixFour.Spec.MaskedBandPrediction

-- a Q16-ish detail band value
genBand :: Gen Int
genBand = choose (-32768, 32768)

genDetail :: Gen Detail
genDetail = (,,,,,,) <$> genBand <*> genBand <*> genBand <*> genBand
                     <*> genBand <*> genBand <*> genBand

-- a coarse Q16 value
genV :: Gen Int
genV = choose (0, 65536)

-- a masked band index (clamped inside the module, but keep it in-range here)
genM :: Gen Int
genM = choose (0, numBands - 1)

-- params padded/trimmed to paramCountB inside each law; generate a comfortable range
genParams :: Gen [Double]
genParams = vectorOf paramCountB (choose (-2.0, 2.0))

tests :: TestTree
tests = testGroup "MaskedBandPrediction (per-band I-JEPA, option B)"
  [ testProperty "zeroParams is the floor (by arithmetic), non-constant, step-decreases" $
      forAll genV $ \v -> forAll genDetail $ \det -> forAll genM $ \m ->
        lawMaskedZeroParamsIsFloor v det m
  , testProperty "analytic gradient matches central finite difference (63 params)" $
      forAll genParams $ \ps -> forAll genV $ \v -> forAll genDetail $ \det ->
        forAll genM $ \m -> lawMaskedGradientFiniteDiff ps v det m
  , testProperty "prediction excludes the masked band (no target peek)" $
      forAll genParams $ \ps -> forAll genV $ \v -> forAll genDetail $ \det ->
        forAll genM $ \m -> forAll genBand $ \nv ->
          lawMaskedContextExcludesTarget ps v det m nv
  , testProperty "sibling context STRICTLY beats any coarse-only predictor" $
      forAll (choose (0, 1000000)) lawSiblingContextStrictlyHelps
  , testProperty "prediction genuinely CONSUMES sibling context (coarse-only cannot)" $
      once lawMaskedConsumesSiblingContext
  , testProperty "one θ_B reuses on BOTH self-similar rungs (16³→64³ ≡ 64³→256³)" $
      once lawMaskedReusesOnBothRungs
  , testProperty "NUMERIC TRANSFER: DOWN-trained θ recovers the gap on the unseen UP range (self-similar)" $
      once lawTransferRecoversGapUnderSelfSimilarity
  , testProperty "transfer DEGRADES under a law-shift (reuse is similarity-proportional, not magic)" $
      once lawTransferDegradesUnderLawShift
  ]
