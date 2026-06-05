module Properties.Lattice (tests) where

import Test.Tasty
import Test.Tasty.QuickCheck

import SixFour.Spec.Lattice

tests :: TestTree
tests = testGroup "Lattice (GRID geometry — GlobalLattice source of truth, v2.0 gifPx atom)"
  [ testProperty "atom is the GIF pixel: gifPx = 6 pt = 18 device-px, 64-wide preview fits" $
      once lawAtomIsGifPx

  , testProperty "sub-pixel commensurate: subPt = 2 = gifPx/3 (one grid)" $
      once lawSubPixelCommensurate

  , testProperty "lattice tiles: 67 cols exact, 145 rows" $
      once lawLatticeTiles

  , testProperty "vertical bleed: 874 - 145·6 = 4 pt (< one atom)" $
      once lawVerticalBleed

  , testProperty "shutter closure: 5·2 + 1·2 = 12" $
      once lawShutterClosure

  , testProperty "touch floor: shutter/control/segment ≥ 8 atoms (48 pt)" $
      once lawTouchFloor

  , testProperty "shutter:control = 3:2, control on the Fibonacci ladder (8)" $
      once lawShutterRatio

  , testProperty "golden split: above + preview + below = rows, below/above ≈ φ (top-weighted)" $
      once lawGoldenSplit

  , testProperty "preview rect: 64×64, centered horizontally, golden row anchor" $
      once lawPreviewRect

  , testProperty "wordmark advance fits the preview width; title band = control height" $
      once lawWordmarkAdvance

  , testProperty "every governed dimension is an integer atom count" $
      once lawEveryGovernedDimIsCells

  , testProperty "chrome clears both OS safe areas (island 62 pt / home indicator 34 pt)" $
      once lawSafeAreaClearance

  , testProperty "lattice arithmetic golden: the pinned constants" $
      once $    (gifPx === 6) .&&. (gifDevicePx === 18) .&&. (subPt === 2)
           .&&. (reviewPitchPt === 6)
           .&&. (cols === 67) .&&. (rows === 145) .&&. (bleedPt === 4)
           .&&. (previewCells === 64) .&&. (shutterCells === 12)
           .&&. (controlCells === 8) .&&. (touchFloorCells === 8)
           .&&. (ringCells === 20)   .&&. (ringTicks === 64)
           .&&. (aboveRows === 31)   .&&. (belowRows === 50)
           .&&. (safeTopPt === 62)   .&&. (safeBottomPt === 34)
  ]
