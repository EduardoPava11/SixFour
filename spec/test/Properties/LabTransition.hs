module Properties.LabTransition (tests) where

import Test.Tasty
import Test.Tasty.QuickCheck
import Data.Ratio ((%))

import SixFour.Spec.LabTransition

genRGB :: Gen (Integer, Integer, Integer)
genRGB = (,,) <$> ch <*> ch <*> ch where ch = choose (0, 65535)

genRGBs :: Gen [(Integer, Integer, Integer)]
genRGBs = choose (0, 24) >>= \n -> vectorOf n genRGB

genAB :: Gen (Integer, Integer)
genAB = (,) <$> choose (-32768, 32767) <*> choose (-32768, 32767)

genABs :: Gen [(Integer, Integer)]
genABs = choose (0, 24) >>= \n -> vectorOf n genAB

genRat :: Gen [Rational]
genRat = choose (0, 24) >>= \n -> vectorOf n rat
  where rat = do a <- choose (0, 4096) :: Gen Integer
                 b <- choose (1, 256)  :: Gen Integer
                 pure (a % b)

tests :: TestTree
tests = testGroup "LabTransition (pool on RGB, look on LAB; only the linear hue crosses scale-equivariantly)"
  [ testProperty "S₃ preserves DC/mass (R+G+B invariant)" $ forAll genRGB lawS3PreservesMass
  , testProperty "KEYSTONE: linear hue commutes with pooling (crosses the valve)" $
      forAll genRGBs lawLinearHueCommutesWithPool
  , testProperty "gray R=G=B fixed by the linear hue" $
      forAll (choose (0, 65535)) lawGrayFixedByLinearHue
  , testProperty "exact C₄ quarter-turn commutes with pooling" $
      forAll genABs lawQuarterTurnCommutesWithPool
  , testProperty "valve is nonlinear ⇒ pool first (Jensen)" $
      forAll genRat lawValveNonlinearNeedsPoolFirst
  , testProperty "LAYERING: linear crosses, nonlinear must be post-pool" $
      once lawLinearHueVsNonlinearValve
  ]
