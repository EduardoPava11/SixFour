module Properties.Boundary (tests) where

import Test.Tasty
import Test.Tasty.QuickCheck

import SixFour.Spec.Boundary

tests :: TestTree
tests = testGroup "Boundary (stepped rounded-rect Stage geometry — Boundary.swift source of truth)"
  [ testProperty "derived bounds = insets against the lattice" $
      once lawDerivedBounds

  , testProperty "every inside cell lies within the 100×218 lattice" $
      once lawInsideWithinLattice

  , testProperty "an outline cell is always an inside cell" $
      once lawOutlineImpliesInside

  , testProperty "the four inset-rect corners are NOT inside (genuinely rounded)" $
      once lawCornersAreRounded

  , testProperty "the screen centre is inside the Stage" $
      once lawCentreInside

  , testProperty "insets clear the OS safe area (island + home indicator)" $
      once lawClearsSafeArea

  , testProperty "corner radius matches the device (14·4 = 56 pt)" $
      once lawCornerMatchesDevice

  , testProperty "boundary constants golden: the pinned insets" $
      once $    (insetX === 3) .&&. (insetTop === 16)
           .&&. (insetBottom === 10) .&&. (cornerCells === 14)
           .&&. (minC === 3) .&&. (maxC === 97)
           .&&. (minR === 16) .&&. (maxR === 208)

  , testProperty "the named lawConstantsPinned predicate holds (gates the inset constants by name)" $
      once lawConstantsPinned
  ]
