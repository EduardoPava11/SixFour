module Properties.SyntheticCorpus (tests) where

import Test.Tasty
import Test.Tasty.QuickCheck

import SixFour.Spec.SyntheticCorpus

tests :: TestTree
tests = testGroup "SyntheticCorpus (the spec guarantees encoding across an entropy × Lab taxonomy)"
  [ testProperty "GUARANTEE: every entropy×Lab category encodes (non-neg bit loads, floor sums to 512)" $
      once lawEveryCategoryEncodes
  , testProperty "the floor responds to entropy (Flat perceptual load < High)" $
      once lawEntropyCategoriesSpanTheFloor
  , testProperty "the entropy taxonomy is monotone (Flat ≤ Low ≤ Mid ≤ High perceptual load)" $
      once lawEntropyTaxonomyIsMonotone
  , testProperty "the floor responds to colour (full-Lab palette load > greyscale)" $
      once lawLabAxesSpanThePaletteLoad
  ]
