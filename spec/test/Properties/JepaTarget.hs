module Properties.JepaTarget (tests) where

import Test.Tasty
import Test.Tasty.QuickCheck

import SixFour.Spec.JepaTarget

tests :: TestTree
tests = testGroup "JepaTarget (the I-JEPA correspondence: data-manufactured target ⇒ no EMA, no collapse)"
  [ testProperty "the target is MANUFACTURED from data, not encoded (refine.split==id)" $
      once lawTargetIsDataManufacturedNotEncoded
  , testProperty "NO-COLLAPSE: the target is FIXED under predictor training (no EMA co-evolution)" $
      once lawTargetFixedUnderPredictorTraining
  , testProperty "no target-encoder ⇒ no EMA (the target's encoder is the param-free lift)" $
      once lawNoTargetEncoderNoEma
  , testProperty "collapse is rejected (a constant predictor incurs strictly positive loss)" $
      once lawCollapseIsRejected
  , testProperty "the target carries info beyond the context (prediction is genuine work)" $
      once lawTargetCarriesInfoBeyondContext
  , testProperty "TIME axis stays data-manufactured (policy/value next-frame targets are θ-free; no L_close collapse)" $
      once lawTemporalDeltaTargetIsDataManufactured
  , testProperty "GLOBAL guard: no self-produced rollout target on any time-axis term (L_close inadmissible)" $
      once lawNoSelfProducedRolloutTarget
  ]
