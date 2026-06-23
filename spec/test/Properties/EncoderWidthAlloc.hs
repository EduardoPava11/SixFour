module Properties.EncoderWidthAlloc (tests) where

import Test.Tasty
import Test.Tasty.QuickCheck

import SixFour.Spec.EncoderWidthAlloc

tests :: TestTree
tests = testGroup "EncoderWidthAlloc (the earned channel widths — entropy share of the fixed 512)"
  [ testProperty "widths sum to EXACTLY 512 for any loads (teeth: naive round → 513)" $
      once lawWidthsSumToDModel
  , testProperty "widths follow the entropy-load order (bigger load ⇒ bigger width)" $
      once lawEncoderWidthIsEntropyShare
  , testProperty "a small palette load earns a width BELOW uniform 512/3 (no wasted channels)" $
      once lawUniformWidthWastesOnGreyscale
  , testProperty "TIE: a full-gamut palette earns more channels than greyscale (bands fixed)" $
      once lawColourfulPaletteEarnsMoreWidthThanGreyscale
  ]
