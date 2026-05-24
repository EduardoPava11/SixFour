module Properties.Color (tests) where

import Test.Tasty
import Test.Tasty.QuickCheck
import Test.QuickCheck

import SixFour.Spec.Color
import SixFour.Spec.Laws (lawOKLabRoundTrip)

newtype InGamut = InGamut SRGB deriving Show

instance Arbitrary InGamut where
  arbitrary = do
    r <- choose (0, 1) :: Gen Double
    g <- choose (0, 1)
    b <- choose (0, 1)
    pure (InGamut (SRGB r g b))

tests :: TestTree
tests = testGroup "Color"
  [ testProperty "OKLab round-trip ≤ 1e-6 (Double precision)" $
      \(InGamut s) -> lawOKLabRoundTrip 1e-6 s
  , testProperty "okLabDistanceSquared is symmetric" $
      \(InGamut s1) (InGamut s2) ->
        let l1 = srgbToOKLab s1
            l2 = srgbToOKLab s2
        in okLabDistanceSquared l1 l2 == okLabDistanceSquared l2 l1
  , testProperty "okLabDistanceSquared (x, x) == 0" $
      \(InGamut s) ->
        let l = srgbToOKLab s
        in okLabDistanceSquared l l == 0
  ]
