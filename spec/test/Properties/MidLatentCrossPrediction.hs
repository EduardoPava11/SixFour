module Properties.MidLatentCrossPrediction (tests) where

import Test.Tasty
import Test.Tasty.QuickCheck

import SixFour.Spec.MidLatentCrossPrediction

tests :: TestTree
tests = testGroup "MidLatentCrossPrediction (the 32³-local cross-encoder objective)"
  [ testProperty "KEYSTONE: cross-encoder strictly helps at the midpoint (with redundancy teeth)" $
      once lawMidCrossEncoderStrictlyHelps
  , testProperty "the objective is midpoint-local (organisable level, not the inter-level hop)" $
      once lawMidObjectiveIsMidpointLocal
  , testProperty "the midpoint target is data-manufactured (no EMA)" $
      once lawMidTargetIsDataManufactured
  ]
