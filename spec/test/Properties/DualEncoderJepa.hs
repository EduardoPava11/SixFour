module Properties.DualEncoderJepa (tests) where

import Test.Tasty
import Test.Tasty.QuickCheck

import SixFour.Spec.DualEncoderJepa

-- | A monotonicity sanity generator: the joint (A,B) context floor is never worse than the
-- B-only floor (a finer partition cannot increase best-constant loss).
genExamples :: Gen [DualExample]
genExamples = listOf (DualExample <$> choose (0, 3) <*> choose (0, 3) <*> choose (0, 9))

tests :: TestTree
tests = testGroup "DualEncoderJepa (the redesigned cross-encoder I-JEPA objective)"
  [ testProperty "KEYSTONE: cross-encoder context strictly helps (with redundancy teeth)" $
      once lawCrossEncoderContextStrictlyHelps
  , testProperty "joint context floor is never worse than B-only (finer partition)" $
      forAll genExamples $ \exs -> jointLoss exs <= bOnlyLoss exs
  , testProperty "the dual target is data-manufactured (no EMA, no collapse)" $
      once lawDualTargetIsDataManufactured
  , testProperty "the cross-encoder prediction reuses the H-JEPA scale spine" $
      once lawDualReusesScaleSpine
  , testProperty "neither encoder bypasses the Q16 floor" $
      once lawNoEncoderBypassesQ16
  ]
