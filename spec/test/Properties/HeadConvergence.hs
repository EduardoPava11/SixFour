module Properties.HeadConvergence (tests) where

import Test.Tasty
import Test.Tasty.QuickCheck

import SixFour.Spec.HeadConvergence

tests :: TestTree
tests = testGroup "HeadConvergence (ViT head: readout PROVEN convex/converges, trunk PROVEN non-convex)"
  [ testProperty "readout loss is convex in the weights (fixed features)" lawReadoutLossConvexInWeights
  , testProperty "a readout gradient step decreases the loss"            lawReadoutGradStepDecreases
  , testProperty "readout min is unique iff the feature is informative"  lawReadoutUniqueMinIffFeatureInformative
  , testProperty "HONEST SCOPE: the trunk loss can be non-convex (ReLU witness)" (once lawTrunkLossCanBeNonConvex)
  , testProperty "CAPSTONE: the readout converges given features"        (once lawReadoutConvergesGivenFeatures)
  , testProperty "head-descent scope is readout (proven) not trunk (demonstrated)" (once lawHeadDescentScopeIsReadoutNotTrunk)
  ]
