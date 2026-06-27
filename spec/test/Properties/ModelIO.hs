module Properties.ModelIO (tests) where

import Test.Tasty
import Test.Tasty.QuickCheck

import SixFour.Spec.ModelIO

tests :: TestTree
tests = testGroup "ModelIO (the model boundary: paintable in, renderable 256^3 out)"
  [ testProperty "output is per-frame value x content (renderable GIF89a)"
      lawOutputIsPerFrameValueContent
  , testProperty "the neutral (unpainted) nudge is all-floor" $
      forAll (choose (0, 99)) lawNeutralNudgeIsAllFloor
  , testProperty "the input nudge is the 9-channel paintable surface" lawInputIsPaintable
  , testProperty "a painted 16^3 cell governs a 256^3 subtree" lawNudgeGovernsSuperRes
  ]
