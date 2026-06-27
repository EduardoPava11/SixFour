module Properties.ParadigmRobustness (tests) where

import Test.Tasty
import Test.Tasty.QuickCheck

import SixFour.Spec.ParadigmRobustness

tests :: TestTree
tests = testGroup "ParadigmRobustness (the convergence conjunct is seed-universal, not single-witness)"
  [ testProperty "converges for ALL seeds at w_value=1 (not a lucky seed)"        lawConvergesAllSeedsAtPositiveWeight
  , testProperty "diverges for ALL seeds at w_value=0 (load-bearing universally)" lawDivergesAllSeedsAtZeroWeight
  , testProperty "the pinned constant is ONE INSTANCE of the predicate"           (once lawPinnedConstantIsOneInstance)
  , testProperty "KEYSTONE: the seed choice is without loss of generality"        lawSeedChoiceIsWithoutLossOfGenerality
  , testProperty "COROLLARY: the weight threshold is exactly 0 for all seeds"     lawSeedWeightThresholdIsZeroForAllSeeds
  ]
