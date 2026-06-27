module Properties.PonderHaltDistribution (tests) where

import Test.Tasty
import Test.Tasty.QuickCheck

import SixFour.Spec.PonderHaltDistribution

genProbs :: Gen [Double]
genProbs = listOf (choose (0, 1))

tests :: TestTree
tests = testGroup "PonderHaltDistribution (strong PonderNet: proper geometric halting + KL)"
  [ testProperty "halt distribution sums to 1 (proper)" $ forAll genProbs lawHaltIsProperDistribution
  , testProperty "expected loss is a convex combination of per-step losses" $
      forAll genProbs $ \ls -> forAll (listOf (choose (0, 50))) $ \xs ->
        lawExpectedLossIsConvex ls xs
  , testProperty "geometric prior sums to 1" $
      forAll (choose (0.0, 1.0)) $ \lp -> forAll (choose (0, 40)) $ \n ->
        lawGeometricPriorSumsToOne lp n
  , testProperty "KL is zero at self" $
      forAll (choose (0.0, 1.0)) $ \lp -> forAll (choose (0, 40)) $ \n ->
        lawKLZeroAtSelf lp n
  , testProperty "lower halt (more budget) refines more (deeper)" lawLowerHaltRefinesMore
  ]
