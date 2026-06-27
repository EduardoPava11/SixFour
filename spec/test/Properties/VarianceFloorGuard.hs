module Properties.VarianceFloorGuard (tests) where

import Test.Tasty
import Test.Tasty.QuickCheck

import SixFour.Spec.VarianceFloorGuard

tests :: TestTree
tests = testGroup "VarianceFloorGuard (collapse guard: per-factor variance hinge on q, k)"
  [ testProperty "a flat factor trips the hinge" lawFlatFactorPenalised
  , testProperty "a varied factor passes" lawVariedFactorPasses
  , testProperty "the hinge fires at the std boundary" lawHingeAtBoundary
  , testProperty "a collapse in either factor trips the combined guard" lawEitherCollapseTripsGuard
  ]
