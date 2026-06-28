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
  , testProperty "teaching 8 HEAD-CONVERGENCE (readout proven, trunk scoped out)" (once teachingHeadConvergence)
  , testProperty "teaching 9 GENERALIZATION (no distribution shift)" (once teachingGeneralization)
  , testProperty "MASTER: the paradigm is STRUCTURALLY sound (w_value on; not an empirical-training claim)" (once lawParadigmIsStructurallySound)
  , testProperty "the structural-soundness side condition is load-bearing (false at w_value=0)" (once lawStructuralSoundnessNeedsValueHead)
  ]
