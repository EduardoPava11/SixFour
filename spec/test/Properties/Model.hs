module Properties.Model (tests) where

import Test.Tasty
import Test.Tasty.QuickCheck

import SixFour.Spec.Model

tests :: TestTree
tests = testGroup "Model (the single-source model boundary + the honest load-bearing/contract taxonomy)"
  [ testProperty "the output is renderable per-frame value × content"
      lawOutputIsPerFrameValueContent
  , testProperty "zero paint builds the deterministic byte-exact floor"
      lawNeutralNudgeIsAllFloor
  , testProperty "the joint objective IDENTIFIES the full palette (w_value>0); identifiability, not reachability"
      lawJointObjectiveIdentifiesFullPalette
  , testProperty "the paradigm is STRUCTURALLY sound (not an empirical-training claim)"
      lawParadigmIsStructurallySound
  , testProperty "the held-out target replaces masking across scale and time"
      lawHeldOutReplacesMasking
  , testProperty "HONESTY: no model law overclaims the model trains/works; the contract markers are pinned"
      (once lawNoEmpiricalOverclaim)
  ]
