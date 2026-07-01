module Properties.V21Transport (tests) where

import Test.Tasty
import Test.Tasty.QuickCheck

import SixFour.Spec.V21Transport

-- A raw alphabet-size seed (the laws clamp it to a small level count) and raw int lists (the laws
-- coerce them into the value alphabet, so any Gen Int works). Equal mass is enforced INSIDE the laws
-- by truncating to a common sample length, exactly as the device produces box*w samples per bin.
genRaw :: Gen [Int]
genRaw = do
  n <- choose (0, 12)
  vectorOf n (choose (-50, 50))

genLevelSeed :: Gen Int
genLevelSeed = choose (0, 64)

-- A burst: 1..8 raw frames (the flow / barycenter laws pool them at equal mass internally).
genBurst :: Gen [[Int]]
genBurst = do
  k <- choose (1, 8)
  vectorOf k genRaw

tests :: TestTree
tests = testGroup "V21Transport (1-D OT displacement flow; the recovered time axis)"
  [ testProperty "quantiles/histOf are inverse (inverse-CDF is a bijection)" $
      forAll genLevelSeed $ \l -> forAll genRaw $ lawQuantileRoundTrip l
  , testProperty "transport map reconstructs the target frame exactly" $
      forAll genLevelSeed $ \l -> forAll genRaw $ \a -> forAll genRaw $ lawTransportReconstructs l a
  , testProperty "transport is reversible (negated displacement inverts)" $
      forAll genLevelSeed $ \l -> forAll genRaw $ \a -> forAll genRaw $ lawTransportReversible l a
  , testProperty "transport cost equals the CDF-L1 Wasserstein-1 (optimal map)" $
      forAll genLevelSeed $ \l -> forAll genRaw $ \a -> forAll genRaw $ lawTransportCostIsW1 l a
  , testProperty "rigid drift transports at a constant shift (compression theorem)" $
      forAll genLevelSeed $ \l -> forAll genRaw $ \s -> forAll (choose (-9, 9)) $ lawTranslateIsConstantShift l s
  , testProperty "transport composes additively along ranks (geodesic)" $
      forAll genLevelSeed $ \l -> forAll genRaw $ \a -> forAll genRaw $ \b -> forAll genRaw $ lawFlowAdditiveInRank l a b
  , testProperty "flow recovers ALL time slices byte-for-byte (time is recovered)" $
      forAll genLevelSeed $ \l -> forAll genBurst $ lawFlowRecoversAllSlices l
  , testProperty "barycenter is the per-rank mean of the quantiles (closed form)" $
      forAll genLevelSeed $ \l -> forAll genBurst $ lawBarycenterIsRankMean l
  , testProperty "barycenter of translates is a single translate (defining symmetry)" $
      forAll genLevelSeed $ \l -> forAll genRaw $ lawBarycenterOfTranslatesIsTranslate l
  , testProperty "GIF derives from the flow data (deploy contract: GIF in/out is a projection)" $
      forAll genLevelSeed $ \l -> forAll genBurst $ lawGifDerivesFromFlow l
  , testProperty "the flow is a full training set (reconstructs every slice)" $
      forAll genLevelSeed $ \l -> forAll genBurst $ lawFlowIsFullTrainingSet l
  , testProperty "barycenter-anchored flow recovers every slice (the airdrop format is lossless)" $
      forAll genLevelSeed $ \l -> forAll genBurst $ lawBarycenterFlowRecovers l
  , testProperty "RLE is exact (map compression loses nothing)" $
      forAll genRaw lawRleRoundTrip
  , testProperty "rigid drift RLE-encodes to one run (the compression, concretely)" $
      forAll genLevelSeed $ \l -> forAll genRaw $ \s -> forAll (choose (-9, 9)) $ lawRigidDriftIsOneRun l s
  ]
