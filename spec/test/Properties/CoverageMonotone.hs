module Properties.CoverageMonotone (tests) where

import Test.Tasty
import Test.Tasty.QuickCheck

import SixFour.Spec.CoverageMonotone

tests :: TestTree
tests = testGroup "CoverageMonotone (coverage is a monotone set function; the numeric threshold stays empirical)"
  [ testProperty "more data weakly REDUCES held error: errB subset errA when seenA subset seenB" lawCoverageMonotone
  , testProperty "teeth (a): a forgetful learner BREAKS monotonicity (the law has content)"      (once lawForgetfulLearnerBreaksMonotone)
  , testProperty "teeth (b): a disjoint held input stays in error for every run (no conjuring)"  (once lawDisjointInputAlwaysInError)
  , testProperty "teeth (c): on-support exactness inherited from Generalization (0 held error)"  lawOnSupportZeroHeldError
  , testProperty "CAPSTONE: coverage is a monotone set function over generator/targetMap"        lawCoverageIsMonotoneSetFunction
  ]
