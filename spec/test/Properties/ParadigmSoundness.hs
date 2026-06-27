module Properties.ParadigmSoundness (tests) where

import Test.Tasty
import Test.Tasty.QuickCheck

import SixFour.Spec.ParadigmSoundness

tests :: TestTree
tests = testGroup "ParadigmSoundness (the master theorem: all seven teachings hold iff w_value>0)"
  [ testProperty "teaching 1 SIGNAL (d6 lattice + Z[i] lenses)"   (once teachingSignal)
  , testProperty "teaching 2 EXPRESSIVITY (A7, above floor)"      (once teachingExpressivity)
  , testProperty "teaching 3 IDENTIFIABILITY (sufficient statistic)" (once teachingIdentifiability)
  , testProperty "teaching 4 CONVERGENCE (unique min, GD reaches)" (once teachingConvergence)
  , testProperty "teaching 5 NO-COLLAPSE (variance guard)"        (once teachingNoCollapse)
  , testProperty "teaching 6 ANTI-CHEAT (data-manufactured target)" (once teachingAntiCheat)
  , testProperty "teaching 7 DETERMINISM (byte-exact Q16 re-entry)" (once teachingDeterminism)
  , testProperty "MASTER: the paradigm is sound (w_value on)"     (once lawParadigmIsSound)
  , testProperty "the soundness side condition is load-bearing (false at w_value=0)" (once lawParadigmNeedsValueHead)
  ]
