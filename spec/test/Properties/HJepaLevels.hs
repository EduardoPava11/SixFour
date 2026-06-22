module Properties.HJepaLevels (tests) where

import Test.Tasty
import Test.Tasty.QuickCheck

import SixFour.Spec.HJepaLevels

tests :: TestTree
tests = testGroup "HJepaLevels (where are the levels: SCALE is the H-JEPA spine; CHANNEL & TIME factor each level)"
  [ testProperty "KEYSTONE: SCALE is the spine (unique free symmetric intermediate, 32*128 = 64^2)" $
      once lawScaleIsTheSpine
  , testProperty "CHANNEL factors each scale level (no inter-level edge, not a planning level)" $
      once lawChannelFactorsEachScale
  , testProperty "TIME indexes each scale level (closed loop, no inter-level edge)" $
      once lawTemporalIndexesEachScale
  , testProperty "the inter-level predictor IS the cross-scale Analysis -> Synthesis hop" $
      once lawInterLevelPredictorIsCrossScale
  , testProperty "exactly the SCALE axis owns a free organisable intermediate" $
      once lawOnlyScaleHasFreeIntermediate
  , testProperty "plan = Analysis (16^3), execution = Synthesis (256^3); pivot is the anchor" $
      once lawPlanIsAnalysisExecuteIsSynthesis
  ]
