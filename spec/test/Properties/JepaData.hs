module Properties.JepaData (tests) where

import Test.Tasty
import Test.Tasty.QuickCheck

import SixFour.Spec.OctreeCell (V8(..))
import SixFour.Spec.JepaData

genV8 :: Gen (V8 Int)
genV8 = V8 <$> g <*> g <*> g <*> g <*> g <*> g <*> g <*> g
  where g = choose (-32768, 32768)

genMask :: Gen Int
genMask = choose (0, 6)

tests :: TestTree
tests = testGroup "JepaData (the I-JEPA data engine: manufacture records + the round-trip that closes the non-invertibility trap)"
  [ testProperty "KEYSTONE: the data engine is INVERTIBLE (reconstruct (manufacture cube m) == cube)" $
      forAll genV8 $ \cube -> forAll genMask $ \m -> lawDataEngineRoundTrips cube m
  , testProperty "the manufactured target IS the held detail band (the label is real)" $
      forAll genV8 $ \cube -> forAll genMask $ \m -> lawManufacturedTargetIsTheHeldBand cube m
  , testProperty "NO PEEK: the masked target is excluded from the 6-band context" $
      forAll genV8 $ \cube -> forAll genMask $ \m -> lawHeldTargetIsExcludedFromContext cube m
  ]
