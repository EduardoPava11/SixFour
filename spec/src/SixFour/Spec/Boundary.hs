{- |
Module      : SixFour.Spec.Boundary
Description : The canonical STAGE — a whole-cell rounded-rect inset, source of truth.

The formally-pinned authority for the on-screen "Stage": the inset rounded
rectangle, stepped in WHOLE cells, that the cell field renders inside. Every
cell of the Stage is a full @gifPx@ square that fits the physical iPhone 17 Pro
screen — clear of the Dynamic Island (top), the home indicator (bottom), and the
four physically rounded display corners. Outside the Stage nothing renders (it is
the black bezel). This is the ONE grid every act shares
(docs/SIXFOUR-INFLUENCE-FIELD-WORKFLOW.md §4).

Promotes the hand-written @SixFour/UI/Components/Boundary.swift@ (which names
itself "a faithful Swift mirror of the designed Spec.Boundary") to a golden-pinned
spec module, emitted to @SixFour/Generated/BoundaryContract.swift@; the Swift file
becomes the typed facade over these constants, NOT an independent authority.

== Determinism class

The Stage is INTEGER geometry, so it is __byte-exact__ across every backend (the
same cell is inside on Swift and in a Metal in-shader mask). This contrasts with
the decorative influence-FIELD colour ("SixFour.Spec.InfluenceField"), which is a
float GPU effect gated only to a tolerance. The geometry here is exact
(docs/SIXFOUR-METAL-FIELD-SPEC-ALIGNMENT.md §1).

== The shape

A plain rectangle @[minC,maxC) × [minR,maxR)@ EXCEPT in the four corner quadrants,
where a cell must lie within the quarter-disc of radius 'cornerCells' (an integer
Euclidean test, the same disc mirrored four-fold). @cornerCells · gifPx = 56 pt@
matches the device display-corner radius, so a square widget can never be moved
where the physical rounding would crop it ('lawCornerMatchesDevice').

Laws (see @Properties.Boundary@): the pinned insets; the derived bounds; every
inside cell lies within the lattice; an outline cell is always inside; the four
inset-rect corners are NOT inside (it is genuinely rounded, not a square); the
centre is inside; the insets clear the OS safe area; the corner radius matches the
device.
-}
-- COMPARTMENT: SWIFT-COREAI | tag:DisplaySide | STRADDLER
module SixFour.Spec.Boundary
  ( -- * Inset margins (whole cells) + the derived frame bounds
    insetX, insetTop, insetBottom, cornerCells
  , minC, maxC, minR, maxR
    -- * The Stage predicates
  , inside, footprintFits, isOutline
    -- * Laws
  , lawConstantsPinned
  , lawDerivedBounds
  , lawInsideWithinLattice
  , lawOutlineImpliesInside
  , lawCornersAreRounded
  , lawCentreInside
  , lawClearsSafeArea
  , lawCornerMatchesDevice
  ) where

import qualified SixFour.Spec.Lattice as L

-- Inset margins (whole cells) -----------------------------------------------

-- | Side inset from each screen edge (a clear visible gutter), in cells.
insetX :: Int
insetX = 3

-- | Top inset — clears the Dynamic Island (@16·4 = 64 pt > 62 pt safe top@).
insetTop :: Int
insetTop = 16

-- | Bottom inset — clears the home indicator (@10·4 = 40 pt > 34 pt safe bottom@).
insetBottom :: Int
insetBottom = 10

-- | Corner radius in cells. @14·4 = 56 pt@ MATCHES the iPhone 17 Pro display
-- corner, so the four-corner 'footprintFits' test keeps a square widget fully
-- inside the curved screen ('lawCornerMatchesDevice').
cornerCells :: Int
cornerCells = 14

-- The derived frame bounds (the rect [minC,maxC) × [minR,maxR)) ------------

-- | Left bound (inclusive).
minC :: Int
minC = insetX

-- | Right bound (exclusive).
maxC :: Int
maxC = L.cols - insetX

-- | Top bound (inclusive).
minR :: Int
minR = insetTop

-- | Bottom bound (exclusive).
maxR :: Int
maxR = L.rows - insetBottom

-- The Stage predicates ------------------------------------------------------

-- | Is cell @(c, r)@ INSIDE the inset rounded rect? A plain rectangle except in
-- the four corner quadrants, where it must lie within the quarter-disc of radius
-- 'cornerCells'. Integer Euclidean test (no floats) — byte-exact. Faithful mirror
-- of @Boundary.inside@ (Boundary.swift).
inside :: Int -> Int -> Bool
inside c r
  | c < minC || c >= maxC || r < minR || r >= maxR = False
  | otherwise = nx * nx + ny * ny <= rad * rad
  where
    rad = cornerCells
    nx | c < minC + rad  = (minC + rad) - c
       | c >= maxC - rad  = c - (maxC - rad - 1)
       | otherwise        = 0
    ny | r < minR + rad  = (minR + rad) - r
       | r >= maxR - rad  = r - (maxR - rad - 1)
       | otherwise        = 0

-- | Does a @w × h@ widget footprint at top-left @(col, row)@ fit ENTIRELY inside
-- the Stage? The region is convex, so testing the four corner cells suffices.
footprintFits :: Int -> Int -> Int -> Int -> Bool
footprintFits col row w h =
  inside col row && inside (col + w - 1) row
    && inside col (row + h - 1) && inside (col + w - 1) (row + h - 1)

-- | Is @(c, r)@ within 2 cells of the frame edge (the 2-cell-thick visible
-- outline)? Mirror of @Boundary.isOutline@.
isOutline :: Int -> Int -> Bool
isOutline c r
  | not (inside c r) = False
  | otherwise        = any edge [1, 2]
  where
    edge d = not (inside (c - d) r) || not (inside (c + d) r)
          || not (inside c (r - d)) || not (inside c (r + d))

-- Laws ----------------------------------------------------------------------

-- | The pinned inset constants (the byte-exact golden).
lawConstantsPinned :: Bool
lawConstantsPinned =
  insetX == 3 && insetTop == 16 && insetBottom == 10 && cornerCells == 14

-- | The derived bounds are the insets against the lattice extent.
lawDerivedBounds :: Bool
lawDerivedBounds =
  minC == insetX && maxC == L.cols - insetX
    && minR == insetTop && maxR == L.rows - insetBottom

-- | Every inside cell lies within the @cols × rows@ lattice (the Stage never
-- escapes the screen). Bounded scan over the whole lattice.
lawInsideWithinLattice :: Bool
lawInsideWithinLattice =
  and [ c >= 0 && c < L.cols && r >= 0 && r < L.rows
      | c <- [0 .. L.cols - 1], r <- [0 .. L.rows - 1], inside c r ]

-- | An outline cell is always an inside cell (the outline is a sub-band).
lawOutlineImpliesInside :: Bool
lawOutlineImpliesInside =
  and [ inside c r
      | c <- [0 .. L.cols - 1], r <- [0 .. L.rows - 1], isOutline c r ]

-- | The four corners of the inset bounding rect are NOT inside — the Stage is
-- genuinely ROUNDED, not a plain rectangle (so no unrenderable corner cells).
lawCornersAreRounded :: Bool
lawCornersAreRounded =
  not (inside minC minR) && not (inside (maxC - 1) minR)
    && not (inside minC (maxR - 1)) && not (inside (maxC - 1) (maxR - 1))

-- | The centre of the screen is inside the Stage (it is non-empty + convex-ish).
lawCentreInside :: Bool
lawCentreInside = inside (L.cols `div` 2) (L.rows `div` 2)

-- | The insets clear the OS safe area: top clears the Dynamic Island, bottom
-- clears the home indicator (in points).
lawClearsSafeArea :: Bool
lawClearsSafeArea =
  insetTop * L.gifPx >= L.safeTopPt && insetBottom * L.gifPx >= L.safeBottomPt

-- | The corner radius matches the iPhone 17 Pro display corner (56 pt), so a
-- fitted square widget is never cropped by the physical rounding.
lawCornerMatchesDevice :: Bool
lawCornerMatchesDevice = cornerCells * L.gifPx == 56
