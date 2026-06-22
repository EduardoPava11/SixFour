module Properties.LargeJepaHead (tests) where

import Test.Tasty
import Test.Tasty.QuickCheck

import SixFour.Spec.OctreeCell (Detail)
import SixFour.Spec.RelationalResidual (P6(..))
import SixFour.Spec.LargeJepaHead

genD :: Gen Double
genD = choose (-2.0, 2.0)

genP6 :: Gen P6
genP6 = P6 <$> g <*> g <*> g <*> g <*> g <*> g
  where g = choose (-32768, 32768)

genDetail :: Gen Detail
genDetail = (,,,,,,) <$> b <*> b <*> b <*> b <*> b <*> b <*> b
  where b = choose (-32768, 32768)

genExPos :: Gen (Int, Detail, Int, (Int, Int))
genExPos = (,,,)
  <$> choose (0, 65536)
  <*> genDetail
  <*> choose (0, 6)
  <*> ((,) <$> choose (0, 65536) <*> choose (0, 65536))

genParams77 :: Gen [Double]
genParams77 = vectorOf 77 (choose (-2.0, 2.0))

tests :: TestTree
tests = testGroup "LargeJepaHead (the large ViT I-JEPA head as a controlled deviation above the proven floor)"
  [ testProperty "single-token attention is the identity (weight 1)" $
      forAll genD lawSingleTokenAttnIsUnit
  , testProperty "KEYSTONE: depth-1 / single-token head == the proven featuresBPos predictor" $
      forAll genParams77 $ \ps -> forAll genExPos $ \ex -> lawDepth1ReducesToFeaturesBPos ps ex
  , testProperty "the d6 bias is monotone (non-increasing) in distance at init" $
      forAll genD $ \s -> forAll (choose (0, 64)) $ \d1 -> forAll (choose (0, 64)) $ \d2 ->
        lawBiasMonotoneInD6 s d1 d2
  , testProperty "GROW/SHRINK: the unit distance scales with the learnable s_h" $
      forAll genD $ \a -> forAll genD $ \b -> forAll (choose (0, 64)) $ \d ->
        lawBiasLearnsToScale a b d
  , testProperty "the bias is phi6-consistent (a<->x, b<->y, L<->t same distance)" $
      forAll genP6 lawBiasIsPhi6Consistent
  , testProperty "the float scale never bypasses the Q16 floor" $
      once lawBiasScalingNeverBypassesQ16
  , testProperty "no EMA target encoder at scale (asymmetric)" $
      once lawNoEmaTargetEncoderAtScale
  , testProperty "VICReg redundancy guard is load-bearing at scale" $
      once lawLatentRedundancyLoadBearingAtScale
  ]
