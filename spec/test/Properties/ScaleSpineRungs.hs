module Properties.ScaleSpineRungs (tests) where

import Test.Tasty
import Test.Tasty.QuickCheck

import SixFour.Spec.ScaleSpineRungs

tests :: TestTree
tests = testGroup "ScaleSpineRungs (the two held rungs bind to the matrix target)"
  [ testProperty "the two rungs are exactly the two held axes (scale, time)" lawTwoRungsAreTheTwoHeldAxes
  , testProperty "both rungs score the cell-aggregate matrix" lawRungTargetIsCellAggregate
  , testProperty "both rungs run the 2-level self-similar operator" lawBothRungsSelfSimilar
  , testProperty "scale rung invents, time rung holds" lawScaleInventedTimeHeld
  ]
