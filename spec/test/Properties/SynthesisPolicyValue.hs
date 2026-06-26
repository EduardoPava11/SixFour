module Properties.SynthesisPolicyValue (tests) where

import Test.Tasty
import Test.Tasty.QuickCheck

import SixFour.Spec.SynthesisPolicyValue

tests :: TestTree
tests = testGroup "SynthesisPolicyValue (the GIF synthesis as policy[index] + value[palette])"
  [ testProperty "KEYSTONE: pixels = value[policy] + per-frame ≤K budget, on one object (teeth: bad index rejected)" $
      once lawSynthesisIsPolicyValue
  , testProperty "the committed policy is an integer argmax in [0,K) (no float commits a byte)" $
      once lawPolicyIsIntegerArgmax
  , testProperty "the value obeys the per-frame ≤K palette budget (delegate; teeth: K=1 fails)" $
      once lawValueIsPerFrameBudget
  , testProperty "TEETH: colours find a home in relation to each other (d6 entry ordering)" $
      once lawPaletteRelationallyOrdered
  , testProperty "at 16³ the policy is identity and the value IS the frame (16²=256)" $
      once lawSixteenCubedIsIdentity
  , testProperty "reconstruction agreement is gauge-invariant in FUSED palette[index] space (raw forms differ)" $
      once lawReconstructionGaugeInvariant
  , testProperty "the two content heads live at labelled rungs (8^6=262144; 16²=256; 256³ = separate deterministic endgame)" $
      once lawHeadsLiveAtLabeledRungs
  ]
