module Properties.HeldOutTarget (tests) where

import Test.Tasty
import Test.Tasty.QuickCheck

import SixFour.Spec.HeldOutTarget

tests :: TestTree
tests = testGroup "HeldOutTarget (the crux: a held-out target replaces masking, no per-pair mask)"
  [ testProperty "SCALE: target not a function of input (same coarse, different detail)"
      lawScaleTargetNotAFunctionOfInput
  , testProperty "SCALE: identity/floor predictor incurs loss" lawScaleIdentityIncursLoss
  , testProperty "TIME: target not a function of input (same t, different t+1)"
      lawTimeTargetNotAFunctionOfInput
  , testProperty "TIME: identity (persistence) incurs loss on motion" lawTimeIdentityIncursLoss
  , testProperty "target is the WHOLE held set (7 bands), not one masked pair"
      lawTargetIsWholeNotMaskedPair
  , testProperty "KEYSTONE: the held-out gap replaces masking (collapse-proof, no mask)"
      lawHeldOutReplacesMasking
  , testProperty "held across both scale and time" lawHeldAcrossScaleAndTime
  ]
