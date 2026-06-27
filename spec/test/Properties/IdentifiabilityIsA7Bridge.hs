module Properties.IdentifiabilityIsA7Bridge (tests) where

import Test.Tasty
import Test.Tasty.QuickCheck

import SixFour.Spec.IdentifiabilityIsA7Bridge

tests :: TestTree
tests = testGroup "IdentifiabilityIsA7Bridge (fold A_7 membership into the master identifiability conjunct)"
  [ testProperty "HALF 1: master-theorem identifiability holds"                 (once lawMasterIdentifiabilityHolds)
  , testProperty "HALF 2: recovered complement admitted as A_7 (typed consumer)" (once lawRecoveredComplementAdmittedAsA7)
  , testProperty "TEETH: a non-A_7 (Sigma!=0) direction cannot masquerade"      (once lawNonA7DirectionCannotMasquerade)
  , testProperty "the 9 + 15 = 24 DOF accounting closes"                        (once lawDofAccountingCloses)
  , testProperty "FOLD: identifiability AND A_7-membership as one law"          (once lawIdentifiabilityComplementIsA7)
  ]
