module Properties.ValueWeightThreshold (tests) where

import Test.Tasty
import Test.Tasty.QuickCheck

import SixFour.Spec.ValueWeightThreshold

tests :: TestTree
tests = testGroup "ValueWeightThreshold (the w_value>0 threshold, proven exact over the whole weight domain)"
  [ testProperty "the shifted-vs-target gap is linear in the weight (= 4*w)"        lawShiftedGapIsLinearInWeight
  , testProperty "a fractional positive weight still gives a unique minimum"        lawFractionalWeightStillUnique
  , testProperty "a negative weight breaks the global minimum (target not the min)" lawNegativeWeightBreaksGlobalMin
  , testProperty "CAPSTONE: the convergence threshold is exactly zero (iff w>0)"    lawConvergenceThresholdIsExactlyZero
  , testProperty "BRIDGE: the paradigmStructurallySound guard IS the convergence threshold"     lawParadigmGuardIsExactlyConvergenceThreshold
  ]
