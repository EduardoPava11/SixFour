module Properties.Lattice (tests) where

import Test.Tasty
import Test.Tasty.QuickCheck

import SixFour.Spec.Lattice

tests :: TestTree
tests = testGroup "Lattice (GRID capture-HUD geometry — GlobalLattice source of truth)"
  [ testProperty "gcd pitch: gcd(402,874) = cellPt = 2" $
      once lawGcdPitch

  , testProperty "pitch tiles the screen: 201×437, no remainder" $
      once lawPitchTilesScreen

  , testProperty "shutter closure: 15·2 + 2·2 = 34" $
      once lawShutterClosure

  , testProperty "touch floor: shutter/control/segment ≥ 22 cells (44 pt)" $
      once lawTouchFloor

  , testProperty "shutter sits on the Fibonacci ladder (34 ∈ [8,13,21,34,55,89])" $
      once lawShutterOnLadder

  , testProperty "golden split: above + preview + below = rows, below/above ≈ φ" $
      once lawGoldenSplit

  , testProperty "preview rect: 64×64, even+centered horizontally, golden row anchor" $
      once lawPreviewRect

  , testProperty "wordmark advance: 7·16 + 6·2 = 124 cells" $
      once lawWordmarkAdvance

  , testProperty "every governed dimension is an integer cell count" $
      once lawEveryGovernedDimIsCells

  , testProperty "lattice arithmetic golden: the pinned constants" $
      once $    (cellPt === 2) .&&. (cellPx === 6)
           .&&. (cols === 201) .&&. (rows === 437)
           .&&. (previewCells === 64) .&&. (shutterCells === 34)
           .&&. (controlCells === 24) .&&. (touchFloorCells === 22)
           .&&. (ringCells === 60)    .&&. (ringTicks === 64)
           .&&. (aboveRows === 143)   .&&. (belowRows === 230)
  ]
