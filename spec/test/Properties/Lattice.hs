module Properties.Lattice (tests) where

import Test.Tasty
import Test.Tasty.QuickCheck

import SixFour.Spec.Lattice

tests :: TestTree
tests = testGroup "Lattice (GRID geometry — GlobalLattice source of truth, v3.0 4 pt atom)"
  [ testProperty "atom is 4 pt = 12 device-px; 256 pt preview fits; 44 pt floor exact" $
      once lawAtomIsGifPx

  , testProperty "sub-pixel commensurate: subPt = 2 = gifPx/2 (one grid)" $
      once lawSubPixelCommensurate

  , testProperty "lattice tiles: 100 cols × 218 rows, sub-atom bleed each axis" $
      once lawLatticeTiles

  , testProperty "horizontal bleed: 402 - 100·4 = 2 pt (< one atom)" $
      once lawHorizontalBleed

  , testProperty "vertical bleed: 874 - 218·4 = 2 pt (< one atom)" $
      once lawVerticalBleed

  , testProperty "shutter closure: 6·2 + 2·2 = 16" $
      once lawShutterClosure

  , testProperty "touch floor: shutter/control/segment ≥ 11 atoms (44 pt exact)" $
      once lawTouchFloor

  , testProperty "size monotone: shutter ≥ control ≥ touch floor" $
      once lawShutterRatio

  , testProperty "wordmark advance fits the preview width" $
      once lawWordmarkAdvance

  , testProperty "every governed dimension is an integer atom count" $
      once lawEveryGovernedDimIsCells

  , testProperty "corner radius is an integer atom count (14 = 56 pt ≈ 55 pt physical)" $
      once lawCornerRadiusIsCells

  , testProperty "rounded corners symmetric under H and V mirror (all four identical)" $
      once lawCornersSymmetric

  , testProperty "corner is a clean monotone arc (no holes/islands)" $
      once lawCornerMonotone

  , testProperty "grid spans the whole screen: all four edges reached, clipping only in corners" $
      once lawGridSpansScreen

  , testProperty "lattice arithmetic golden: the pinned constants" $
      once $    (gifPx === 4) .&&. (gifDevicePx === 12) .&&. (subPt === 2)
           .&&. (reviewPitchPt === 4)
           .&&. (cols === 100) .&&. (rows === 218)
           .&&. (bleedPt === 2) .&&. (hBleedPt === 2)
           .&&. (previewCells === 64) .&&. (shutterCells === 16)
           .&&. (controlCells === 12) .&&. (touchFloorCells === 11)
           .&&. (ringCells === 20)   .&&. (ringTicks === 64)
           .&&. (safeTopPt === 62)   .&&. (safeBottomPt === 34)
           .&&. (cornerRadiusPt === 56) .&&. (cornerRadiusCells === 14)
           .&&. (cornerExponent === 2)
  ]
