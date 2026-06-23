module Properties.EncoderModalityLoad (tests) where

import Test.Tasty
import Test.Tasty.QuickCheck

import SixFour.Spec.EncoderModalityLoad

tests :: TestTree
tests = testGroup "EncoderModalityLoad (the three modality loads on one non-negative bit axis)"
  [ testProperty "the ridged palette load is non-negative on every palette" $
      once lawPaletteLoadNonNegative
  , testProperty "TEETH: ridged ≥0 where the naive differential entropy is NEGATIVE (−9.559), and monotone" $
      once lawRidgedBeatsNaiveOnTightPalette
  , testProperty "all three modality loads are non-negative bits (commensurable for allocation)" $
      once lawLoadsAreNonNegativeBits
  ]
