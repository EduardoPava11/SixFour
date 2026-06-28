module Properties.TrunkLinearization (tests) where

import Test.Tasty
import Test.Tasty.QuickCheck

import SixFour.Spec.TrunkLinearization

tests :: TestTree
tests = testGroup "TrunkLinearization (CONDITIONAL trunk-convergence: lazy-regime reduction to the convex readout)"
  [ testProperty "lazy regime: the linearized output is affine in the parameters"
      lawLinearizedOutputAffineInParams
  , testProperty "the linearized loss is convex in the parameter delta"
      lawLinearizedLossConvexInParams
  , testProperty "REDUCTION: the linearized loss IS a HeadConvergence readoutLoss (shifted target)"
      lawLinearizedLossIsReadout
  , testProperty "a gradient step on the parameter delta decreases the loss"
      lawLinGradStepDecreases
  , testProperty "TEETH: the lazy linearization fails across the ReLU kink (precondition non-vacuous)"
      (once lawLinearizationFailsAcrossKink)
  , testProperty "CAPSTONE: precondition ⇒ reduction ⇒ convergence; precondition fails for the bare trunk"
      (once lawConditionalTrunkConvergence)
  ]
