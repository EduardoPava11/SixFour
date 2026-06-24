module Properties.EncoderCorpus (tests) where

import Test.Tasty
import Test.Tasty.QuickCheck

import SixFour.Spec.EncoderCorpus

tests :: TestTree
tests = testGroup "EncoderCorpus (the corpus → loads → floor bridge: numbers respond to content)"
  [ testProperty "the corpus floor sums to 512 (preserves the fuse=midpoint waist)" $
      once lawCorpusFloorSumsTo512
  , testProperty "TEETH: a colourful corpus earns a larger palette floor than greyscale" $
      once lawColourfulCorpusEarnsMorePaletteFloor
  , testProperty "every clip contributes a load row to the floor (no silent subsampling)" $
      once lawEveryClipSizesTheFloor
  ]
