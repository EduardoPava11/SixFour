module Properties.CellShapes (tests) where

import Test.Tasty
import Test.Tasty.QuickCheck

import SixFour.Spec.CellShapes

tests :: TestTree
tests = testGroup "CellShapes (golden HUD cell-mask geometry — CellShapes source of truth)"
  [ testProperty "64 ring-tick endpoints" $
      once lawTickCount

  , testProperty "top tick is exactly (30, 1)" $
      once lawTickTopExact

  , testProperty "ticks advance clockwise (quarter-turn: 3 o'clock right, 6 o'clock below)" $
      once lawTickClockwise

  , testProperty "every endpoint lies inside the ringCells×ringCells sprite" $
      once lawTickInBounds

  , testProperty "vertical symmetry: row(k) = row(64−k)" $
      once lawTickVerticalSymmetry

  , testProperty "tick arc is gap-free (consecutive ticks same-or-8-adjacent; merges allowed at atom resolution)" $
      once lawTickNoMerge

  , testProperty "disc golden: radius-3 disc on 7×7 = 29 cells" $
      once lawDiscCount

  , testProperty "disc + ring band close to the shutter radius" $
      once lawDiscRingClosure
  ]
