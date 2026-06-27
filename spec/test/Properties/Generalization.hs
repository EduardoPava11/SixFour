module Properties.Generalization (tests) where

import Test.Tasty
import Test.Tasty.QuickCheck

import SixFour.Spec.Generalization

tests :: TestTree
tests = testGroup "Generalization (held follows train: seed-independent target, no distribution shift)"
  [ testProperty "the target map is seed-independent (leaky target is the teeth)" lawTargetMapIsSeedIndependent
  , testProperty "no distribution shift: train and held share the target map"     lawNoDistributionShift
  , testProperty "held error is COVERAGE, not shift (on-support exact)"           lawHeldErrorIsCoverageNotShift
  , testProperty "the target is reachable from the visible context"              (once lawHeldReachableFromContext)
  , testProperty "CAPSTONE: the model generalizes up to coverage + masked residual" lawModelGeneralizesUpToCoverage
  ]
