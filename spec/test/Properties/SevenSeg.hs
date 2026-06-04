module Properties.SevenSeg (tests) where

import Test.Tasty
import Test.Tasty.QuickCheck

import SixFour.Spec.SevenSeg

tests :: TestTree
tests = testGroup "SevenSeg (7-segment digit register — CountReadout source of truth)"
  [ testProperty "ten digits 0–9 each light ≥1 segment" $
      once lawDigitCount

  , testProperty "every segment cell is inside the 10×18 box" $
      once lawSegmentsInBounds

  , testProperty "segments are pairwise disjoint (no shared cell)" $
      once lawSegmentsDisjoint

  , testProperty "digit 8 lights all seven segments" $
      once lawEightAllLit

  , testProperty "digit 0 omits the middle bar; 8 includes it" $
      once lawZeroNoMiddle

  , testProperty "digit 1 = the two right verticals (B, C)" $
      once lawOneRightVerticals

  , testProperty "footprint goldens: full=96, '1'=24, '0'=80 cells" $
      once lawDigitFootprintGolden
  ]
