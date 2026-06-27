module Properties.MotionFloorCorpus (tests) where

import Test.Tasty
import Test.Tasty.QuickCheck

import SixFour.Spec.MotionFloorCorpus

tests :: TestTree
tests = testGroup "MotionFloorCorpus (temporal collapse guard: motion + off-floor texture)"
  [ testProperty "the corpus has a motion floor (persistence loses on motion)" lawCorpusHasMotionFloor
  , testProperty "a static corpus starves the gradient (the guarded failure)" lawStaticCorpusStarvesGradient
  , testProperty "the corpus has off-floor texture (something to invent)" lawCorpusHasOffFloorTexture
  ]
