module Properties.DivergenceSchedule (tests) where

import Test.Tasty
import Test.Tasty.QuickCheck

import SixFour.Spec.DivergenceSchedule

tests :: TestTree
tests = testGroup "DivergenceSchedule (A/B policy:value gap — start wide, converge, never identical)"
  [ testProperty "starts wide: Δ(0) = Δ_max" (once lawDivergenceStartsWide)

  , testProperty "monotone non-increasing in Compares (close the gap each round)" $
      \(NonNegative n) -> lawDivergenceMonotone n

  , testProperty "bounded below by Δ_min > 0 (A and B never collapse to identical)" $
      \(NonNegative n) -> lawDivergenceBoundedBelow n

  , testProperty "ratios straddle the center (A explores ≥ center ≥ B exploits)" $
      \(NonNegative n) -> lawRatiosStraddleCenter n

  , testProperty "gap = r_A − r_B = Δ" $
      \(NonNegative n) -> lawRatiosGapIsDivergence n

  , testProperty "ratios stay in [0,1]" $
      \(NonNegative n) -> lawRatiosInUnit n
  ]
