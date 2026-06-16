module Properties.RGBTFeature (tests) where

import Test.Tasty
import Test.Tasty.QuickCheck

import SixFour.Spec.Collapse  (PxQ16)
import SixFour.Spec.Entropy   (RGBTWeights(..))
import SixFour.Spec.RGBTFeature

genPx :: Gen PxQ16
genPx = (,,) <$> choose (0, 65536) <*> choose (-26214, 26214) <*> choose (-26214, 26214)

-- A capture with EQUAL-length frames (as the real 64x64 capture guarantees).
genCapture :: Gen [[PxQ16]]
genCapture = do
  t <- choose (0, 8)
  p <- choose (1, 4)
  vectorOf t (vectorOf p genPx)

genWeights :: Gen RGBTWeights
genWeights = RGBTWeights <$> choose (0, 1) <*> choose (0, 1) <*> choose (0, 1) <*> choose (0, 1)

tests :: TestTree
tests = testGroup "RGBTFeature (1b feature layer — entropy-weighted temporal coherence)"
  [ testProperty "per-frame count unchanged (T -> T; 1b keeps per-frame)" $
      forAll genWeights $ \rw -> forAll genCapture (lawFeaturePerFrameCountUnchanged rw)

  , testProperty "preserves completeness: every feature pixel within its window's range" $
      forAll genWeights $ \rw -> forAll genCapture (lawFeaturePreservesCompleteness rw)

  , testProperty "R-only weight ⇒ feature = identity (EXACT; weights drive the blend)" $
      forAll genCapture lawFeatureRWeightIsIdentity

  , testProperty "gauge-consistent: rotation-equivariant (respects the loop C_n gauge)" $
      forAll genWeights $ \rw -> \(k :: Int) -> forAll genCapture (lawFeatureGaugeConsistent rw k)
  ]
