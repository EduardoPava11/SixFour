module Properties.EncoderEntropyFloor (tests) where

import Test.Tasty
import Test.Tasty.QuickCheck

import SixFour.Spec.EncoderEntropyFloor

tests :: TestTree
tests = testGroup "EncoderEntropyFloor (the source-coding lower bound: learned ≥ floor)"
  [ testProperty "the corpus floor is the Hamilton entropy share (sums to 512, follows load order)" $
      once lawCorpusFloorIsEntropyShare
  , testProperty "learned ≥ floor passes, sub-floor fails (active floor, teeth: starved palette)" $
      once lawEncoderChannelsAtLeastEntropyShare
  ]
