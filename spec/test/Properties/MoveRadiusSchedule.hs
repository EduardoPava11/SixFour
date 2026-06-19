module Properties.MoveRadiusSchedule (tests) where

import Test.Tasty
import Test.Tasty.QuickCheck

import SixFour.Spec.PairTreeFixed (OKLabI)
import SixFour.Spec.MoveRadiusSchedule

-- A Q16 OKLab displacement that straddles the cumulative cap (so the clamp laws exercise
-- both the inside and the outside of the ball).
genDispI :: Gen OKLabI
genDispI = (,,) <$> choose (-32768, 32768) <*> choose (-32768, 32768) <*> choose (-32768, 32768)

tests :: TestTree
tests = testGroup "MoveRadiusSchedule (annealed Q16 move radius + cumulative cap — no tolerance)"
  [ testProperty "radius starts at rMax (cold start)" $
      once lawRadiusStartsWide

  , testProperty "radius is monotone non-increasing in the pick count" $
      forAll (choose (0, 4096)) lawRadiusMonotone

  , testProperty "radius is bounded below by rMin > 0 (A/B never collapse)" $
      forAll (choose (0, 4096)) lawRadiusBoundedBelow

  , testProperty "radius is bounded above by rMax" $
      forAll (choose (0, 4096)) lawRadiusBoundedAbove

  , testProperty "clamp keeps every axis within the cumulative cap" $
      forAll genDispI lawClampWithinCap

  , testProperty "clamp is idempotent" $
      forAll genDispI lawClampIdempotent

  , testProperty "clamp is the identity inside the ball" $
      forAll genDispI lawClampPreservesInside
  ]
