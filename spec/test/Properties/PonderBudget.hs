module Properties.PonderBudget (tests) where

import Test.Tasty
import Test.Tasty.QuickCheck

import SixFour.Spec.PonderBudget

tests :: TestTree
tests = testGroup "PonderBudget (the user nudge: paintable budget, octant-twiceness brush)"
  [ testProperty "the brush spans the two-level octant twiceness (64 finest octants)"
      lawTwicenessBrushIsTwoLevels
  , testProperty "zero budget = the byte-exact floor (no invention)" $
      forAll (choose (0, 256)) lawZeroBudgetIsFloor
  , testProperty "painting up invents exactly the brush block, monotone" $
      forAll (choose (0, 3)) lawBudgetMonotoneInvention
  , testProperty "painting is local (other blocks untouched)" lawBudgetIsLocal
  , testProperty "budget clamped non-negative (no sub-floor invention)" $
      forAll (choose (-9, 9)) $ \s -> forAll (choose (-9, 9)) $ \v ->
        lawNudgeBoundedNonNegative s v
  ]
