module Properties.DetentNudge (tests) where

import Test.Tasty
import Test.Tasty.QuickCheck

import SixFour.Spec.ChromaRotation (Detent(..))
import SixFour.Spec.DetentNudge

genDetent :: Gen Detent
genDetent = elements [C12, C8, C6]

genQ :: Gen Int
genQ = choose (-1, 5)            -- includes out-of-range to exercise rejection

genSign :: Gen Sign
genSign = elements [Minus, Plus]

genAxis :: Gen ABAxis
genAxis = elements [AxisA, AxisB]

genV :: Gen (Int, Int)
genV = (,) <$> choose (-64, 64) <*> choose (-64, 64)

tests :: TestTree
tests = testGroup "DetentNudge (the angle-gated +/-1 swipe; admissible only at detents)"
  [ testProperty "a step is admissible IFF its angle is on the detent grid" $
      forAll genDetent $ \d -> forAll genQ $ \q -> forAll genSign $ \s -> forAll genAxis $ \ax ->
        lawStepOnlyAtDetent d q s ax

  , testProperty "a 90/270 step on the 60deg (C6) grid is unconstructible" $
      once lawNonDetentStepInadmissible

  , testProperty "the increment is the unit +/-1 in the rotated frame (unit length)" $
      forAll genDetent $ \d -> forAll genQ $ \q -> forAll genSign $ \s -> forAll genAxis $ \ax ->
        lawStepIsUnitInRotatedFrame d q s ax

  , testProperty "the opposite-sign step undoes it (unit-step reversibility)" $
      forAll genDetent $ \d -> forAll genQ $ \q -> forAll genSign $ \s -> forAll genAxis $ \ax ->
        forAll genV (lawStepReversible d q s ax)
  ]
