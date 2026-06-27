module Properties.AboveFloorMargin (tests) where

import Test.Tasty
import Test.Tasty.QuickCheck

import SixFour.Spec.AboveFloorMargin

tests :: TestTree
tests = testGroup "AboveFloorMargin (training go/no-go: the Q16 survival margin)"
  [ testProperty "the floor margin is finite and positive (½ LSB rounds to floor, 1 LSB survives)"
      lawFloorMarginIsFinite
  , testProperty "above the margin the floor is not absorbing (a 1-LSB invention moves the output)"
      lawAboveFloorMarginReachable
  , testProperty "the surviving detail is a legal A_7 residual (mean-free)"
      lawSurvivingDetailIsA7
  ]
