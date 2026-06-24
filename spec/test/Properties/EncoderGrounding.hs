module Properties.EncoderGrounding (tests) where

import Test.Tasty
import Test.Tasty.QuickCheck

import SixFour.Spec.EncoderGrounding

tests :: TestTree
tests = testGroup "EncoderGrounding (the perceptual load IS the JEPA target entropy — H-JEPA grounded)"
  [ testProperty "KEYSTONE: ∀ band, the load band == the JEPA held-target list AND their codedBits agree" $
      once lawPerceptualLoadIsJepaTargetEntropy
  , testProperty "the grounding is non-vacuous (witness octants carry real detail)" $
      once lawGroundingIsNonVacuous
  , testProperty "TEETH: a misaligned band breaks the identity (constrains band alignment)" $
      once lawMisalignedBandBreaksGrounding
  ]
