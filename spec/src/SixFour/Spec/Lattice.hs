{- |
Module      : SixFour.Spec.Lattice
Description : The GRID lattice — source of truth for every governed dimension.

The formally-pinned authority for the GRID design language's @GlobalLattice@
(Law #5, "ONE OWNER FOR CELL MATH"). Every number the app draws with is derived
here and emitted to @SixFour/Generated/LatticeContract.swift@; the hand-written
@GlobalLattice.swift@ is the typed @CGFloat@ facade over these constants, not an
independent authority.

== v3.0 — THE 4 pt ATOM (2026-06-06)

The one canonical atom is @gifPx = 4 pt = 12 device-px \@3x@. Unlike v2.0's 6 pt,
4 pt is NOT the largest pitch that fits a 64-wide preview — it is a deliberate
choice for two reasons: (1) it lands on integer device-px (@4·3 = 12@, crisp,
resample-free), and (2) it expresses the @44 pt@ HIG touch floor EXACTLY
(@11·4 = 44@), which 6 pt could not (6 pt forced a 48 pt floor). The preview is a
@64·4 = 256 pt@ hero with margin on every side — room to clear the rounded corners
and to rotate into the 64³ cube ('lawAtomIsGifPx').

The sub-pixel @subPt = gifPx \`div\` 2 = 2 pt@ survives for fine spacing/gutters and
text legibility (a glyph cannot be one atom wide). It is a commensurate HALF-atom
now (@2·subPt = gifPx@), not a third — proven by 'lawSubPixelCommensurate'. Note
@subPt@ is still @2 pt@, so every @GlobalLattice.pt(_:)@ spacing call-site is
physically unchanged across the v2.0→v3.0 re-base.

== The screen lattice (two-axis bleed)

@402 \`div\` 4 = 100@ columns (@400 pt@ + a @2 pt@ 'hBleedPt') and
@874 \`div\` 4 = 218@ rows (@872 pt@ + a @2 pt@ 'bleedPt'). At 4 pt NEITHER axis
tiles exactly, so both carry a sub-atom bleed absorbed off-lattice into the
safe-area edge ('lawLatticeTiles' + 'lawHorizontalBleed' + 'lawVerticalBleed').
(v2.0's 6 pt tiled the width exactly; v3.0 trades that for the exact 44 pt floor.)

== The closure law

The shutter is a filled disc abutted by a ring band:
@discRadius·2 + ringThickness·2 = 6·2 + 2·2 = 16 = shutterCells@
('lawShutterClosure'), a 64 pt block — matching the 16×16 palette-as-shutter
footprint on the capture scene.

== The capture-scene LAYOUT is NOT here

v2.0 pinned a golden vertical split (@previewStartRow@, @aboveRows@, …) in this
module. v3.0 removes it: the actual capture scene (preview high, palette in the
thumb zone) is the AS-BUILT layout, and its regions + disjointness are proven in
"SixFour.Spec.GridLayout" (the contention proof) — a property of the SCENE, not of
the lattice. This module only owns the atom, the lattice it tiles, and per-widget
sizes; where a widget GOES is GridLayout's job.

Laws (see @Properties.Lattice@): the atom identity; the sub-pixel commensurability;
the lattice tiling + both bleeds; the shutter closure; the touch floor (every
interactive widget ≥ 11 gifPx = 44 pt, exact); the size monotonicity
(shutter ≥ control ≥ touch floor); the wordmark fits the preview width; and every
governed dimension is an integer @gifPx@ count.
-}
-- COMPARTMENT: SWIFT-COREAI | tag:DisplaySide
module SixFour.Spec.Lattice
  ( -- * Anchor (the physical screen, iPhone 17 Pro portrait)
    screenWidthPt, screenHeightPt, scale
    -- * The atom (gifPx) + the sub-pixel (subPt) + the lattice they tile
  , gifPx, gifDevicePx, subPt, cols, rows, bleedPt, hBleedPt, reviewPitchPt
    -- * Verified OS safe-area insets (iPhone 17 Pro portrait, iOS 26+)
  , safeTopPt, safeBottomPt
    -- * The rounded display corner (approximation)
  , cornerRadiusPt, cornerRadiusCells, cornerExponent
  , cellOnScreen, onScreenCells
    -- * Fibonacci size ladder
  , fibLadder
    -- * Widget gifPx-counts
  , previewCells, touchFloorCells, controlCells, shutterCells
  , ringCells, ringTicks, wordmarkRows, wordmarkCols
  , segmentCells, gutterCells
  , shutterDiscRadiusCells, shutterRingThicknessCells
    -- * The one conversion
  , cellsToPt
    -- * Laws
  , lawAtomIsGifPx
  , lawSubPixelCommensurate
  , lawLatticeTiles
  , lawHorizontalBleed
  , lawVerticalBleed
  , lawShutterClosure
  , lawTouchFloor
  , lawShutterRatio
  , lawWordmarkAdvance
  , lawEveryGovernedDimIsCells
  , lawCornerRadiusIsCells
  , lawCornersSymmetric
  , lawCornerMonotone
  , lawGridSpansScreen
  ) where

-- The reference anchor ------------------------------------------------------

-- | iPhone 17 Pro portrait logical width in points.
screenWidthPt :: Int
screenWidthPt = 402

-- | iPhone 17 Pro portrait logical height in points.
screenHeightPt :: Int
screenHeightPt = 874

-- | Point → device-pixel scale (@\@3x@).
scale :: Int
scale = 3

-- The atom and the lattice --------------------------------------------------

-- | THE ATOM: one GIF pixel = @4 pt@ (v3.0). Chosen, not forced: it lands on
-- integer device-px (@4·3 = 12@) AND expresses the @44 pt@ touch floor exactly
-- (@11·4@), which 6 pt could not. The preview is @64·4 = 256 pt@ with margin to
-- spare ('lawAtomIsGifPx'). Mirror of @SFTheme.gifCellPt@.
gifPx :: Int
gifPx = 4

-- | One atom in device pixels: @gifPx · scale = 12 px@ (crisp; resample-free).
gifDevicePx :: Int
gifDevicePx = gifPx * scale

-- | The sub-pixel: @gifPx \`div\` 2 = 2 pt@ (v3.0 — a commensurate HALF-atom, was a
-- third at 6 pt). The fine sub-grid for spacing/gutters and text legibility (a
-- glyph cannot be one atom wide). Legal only as a sub-unit, never as a widget's own
-- pixel size ('lawSubPixelCommensurate'). Still @2 pt@, so spacing call-sites are
-- physically unchanged across the re-base. Mirror of @GlobalLattice.subPt@.
subPt :: Int
subPt = gifPx `div` 2

-- | Backward-compat alias kept for the Review/content surfaces: the content pitch
-- equals the atom. Mirror of @SFTheme.gifCellPt@; preserved so the Swift content
-- tokens (@gifCellPt@, @gifCanvasPt@) reference one place.
reviewPitchPt :: Int
reviewPitchPt = gifPx

-- | Full-screen lattice width in atoms: @402 \`div\` 4 = 100@ (400 pt + 2 pt bleed).
cols :: Int
cols = screenWidthPt `div` gifPx

-- | Full-screen lattice height in atoms: @874 \`div\` 4 = 218@ (872 pt + 2 pt bleed).
rows :: Int
rows = screenHeightPt `div` gifPx

-- | The HORIZONTAL remainder absorbed into the right safe edge: @402 - 100·4 = 2 pt@
-- (less than one atom; off-lattice — splits no governed cell). New at 4 pt (6 pt
-- tiled the width exactly).
hBleedPt :: Int
hBleedPt = screenWidthPt - cols * gifPx

-- | The VERTICAL remainder absorbed into the bottom safe band: @874 - 218·4 = 2 pt@
-- (less than one atom; off-lattice).
bleedPt :: Int
bleedPt = screenHeightPt - rows * gifPx

-- OS safe-area insets (verified) --------------------------------------------

-- | iPhone 17 Pro portrait TOP safe-area inset (Dynamic Island + status bar), in
-- points. Web-verified 2026-06-04. Field renders under it; no chrome may enter it.
safeTopPt :: Int
safeTopPt = 62

-- | iPhone 17 Pro portrait BOTTOM safe-area inset (home indicator), in points.
-- Web-verified 2026-06-04. Absorbs the 'bleedPt'.
safeBottomPt :: Int
safeBottomPt = 34

-- The rounded display corner (approximation) --------------------------------

-- | The iPhone 17 Pro DISPLAY CORNER RADIUS in points, snapped to an exact atom
-- count. The physical continuous-corner radius is ~55 pt (the 14/15/16 Pro
-- lineage, iPhone 14 Pro is a measured 55.0 pt; Apple does not publish this and
-- 17 Pro is not in the public tables, so it is DEVICE-VERIFY PENDING). We snap it
-- UP to @14·4 = 56 pt@ so the radius is an integer atom count (Law #6), one atom
-- of head-room over 55. Apple's corners are a CONTINUOUS curve (superellipse),
-- not a circle; 'cornerExponent' selects how faithfully we approximate it.
cornerRadiusPt :: Int
cornerRadiusPt = 56

-- | The corner radius in atoms: @56 \`div\` 4 = 14@.
cornerRadiusCells :: Int
cornerRadiusCells = cornerRadiusPt `div` gifPx

-- | The superellipse exponent for the corner approximation. @2@ = a true circular
-- quarter-disc (v1: provable and simple, coarse on a 14-atom radius); @~5@
-- approximates Apple's continuous "squircle" corner. Raise it to trade fidelity
-- for arithmetic size WITHOUT changing the shape of any law below.
cornerExponent :: Int
cornerExponent = 2

-- | Does the cell @(col,row)@ fall on the physical (rounded) display? A cell in a
-- corner box that lies OUTSIDE the corner arc is clipped (off-screen); everything
-- else on the @100×218@ lattice is on-screen. Measured at cell CENTRES against a
-- superellipse of exponent 'cornerExponent' (n=2 ⇒ circular quarter-disc). All
-- integer, in doubled half-cell units, so no float ever enters the geometry.
cellOnScreen :: (Int, Int) -> Bool
cellOnScreen (c, r)
  | not inBounds = False
  | otherwise    = dc == 0 || dr == 0 || (dc ^ n + dr ^ n) <= radHalf ^ n
  where
    inBounds = c >= 0 && c < cols && r >= 0 && r < rows
    n        = cornerExponent
    radHalf  = 2 * cornerRadiusCells                     -- radius in half-cells
    -- half-cell offset of this cell PAST the arc centre toward the nearest edge;
    -- clamped to 0 means the cell sits in the straight band on that axis (the
    -- corner does not constrain it).
    dc       = max 0 (radHalf - (2 * min c (cols - 1 - c) + 1))
    dr       = max 0 (radHalf - (2 * min r (rows - 1 - r) + 1))

-- | Every cell that falls on the rounded display: the full-screen span MINUS the
-- four clipped corner arcs. This is the substrate a full-bleed background owner
-- covers (the rounded-rect analogue of 'SixFour.Spec.GridLayout.screenCells').
onScreenCells :: [(Int, Int)]
onScreenCells = filter cellOnScreen [ (c, r) | r <- [0 .. rows - 1], c <- [0 .. cols - 1] ]

-- The Fibonacci size ladder -------------------------------------------------

-- | Widget sizes draw from this φ-ratio ladder (successive ratios ≈ φ). At 4 pt the
-- touch floor (11) is OFF the ladder by design — the exact 44 pt floor wins over
-- ladder membership ('lawTouchFloor'); the ladder remains a documented size guide.
fibLadder :: [Int]
fibLadder = [8, 13, 21, 34, 55, 89]

-- Widget gifPx-counts -------------------------------------------------------

-- | The hero preview: 64 atoms = 1 GIF pixel per atom (the cube law), 256 pt.
previewCells :: Int
previewCells = 64

-- | HIG touch floor in atoms: @44 \`div\` 4 = 11@ → 44 pt EXACTLY (the v3.0 win —
-- 4 pt lands the HIG floor on the nose, where 6 pt had to round up to 48).
touchFloorCells :: Int
touchFloorCells = 11

-- | Secondary control (gear / selector segment): 12 atoms = 48 pt (a comfortable
-- target above the 44 pt floor).
controlCells :: Int
controlCells = 12

-- | The shutter: 16 atoms = 64 pt — the 16×16 palette-as-shutter footprint on the
-- capture scene. (The standalone shutter glyph is retired; this sizes the closure.)
shutterCells :: Int
shutterCells = 16

-- | The diversity gauge ring: 20 atoms = 80 pt (Ø20, R10). The radius is fixed in
-- CELLS, not points: at R10 the 64 ticks pack ≈1 cell apart so the arc is gap-free
-- (8-adjacent), the proven 'Properties.CellShapes' invariant. R15 would spread them
-- to ≈1.5 cells and open gaps — so the cell count is the law, the pt size downstream.
ringCells :: Int
ringCells = 20

-- | Radial ticks on the gauge — one per GIF frame.
ringTicks :: Int
ringTicks = 64

-- | Wordmark TITLE band height in atoms (≥ the touch floor; a legible title band).
wordmarkRows :: Int
wordmarkRows = 11

-- | Wordmark advance width in atoms — fits within the preview width.
wordmarkCols :: Int
wordmarkCols = 60

-- | A selector segment never narrows below the touch floor.
segmentCells :: Int
segmentCells = 11

-- | The Swiss gutter: one atom.
gutterCells :: Int
gutterCells = 1

-- | Shutter filled-disc radius (Ø12).
shutterDiscRadiusCells :: Int
shutterDiscRadiusCells = 6

-- | Shutter ring-band thickness, each side of the disc.
shutterRingThicknessCells :: Int
shutterRingThicknessCells = 2

-- The one conversion --------------------------------------------------------

-- | Atoms → points. The single place an atom count becomes a point size.
cellsToPt :: Int -> Int
cellsToPt c = c * gifPx

-- Laws ----------------------------------------------------------------------

-- | The atom is @gifPx = 4 pt = 12 device-px@: integer device-px (crisp), it fits a
-- 64-wide preview in portrait width WITH margin, and — the v3.0 point — it expresses
-- the 44 pt HIG touch floor exactly (@44 \`mod\` gifPx == 0@), which 6 pt cannot.
lawAtomIsGifPx :: Bool
lawAtomIsGifPx =
     gifPx == 4
  && gifDevicePx == 12
  && gifDevicePx == gifPx * scale                   -- integer device-px (crisp)
  && previewCells * gifPx <= screenWidthPt          -- 64·4 = 256 ≤ 402: fits with margin
  && 44 `mod` gifPx == 0                             -- the 44 pt floor is exact (the reason for 4)

-- | The sub-pixel is an EXACT half of the atom, so spacing/text snap to one grid.
lawSubPixelCommensurate :: Bool
lawSubPixelCommensurate =
     subPt == 2
  && gifPx `mod` subPt == 0
  && gifPx `div` subPt == 2
  && reviewPitchPt == gifPx

-- | The atom tiles each axis to the safe-area with a sub-atom bleed, giving exactly
-- 100×218 atoms.
lawLatticeTiles :: Bool
lawLatticeTiles =
     cols * gifPx <= screenWidthPt
  && screenWidthPt - cols * gifPx < gifPx           -- width bleed < one atom
  && rows * gifPx <= screenHeightPt
  && screenHeightPt - rows * gifPx < gifPx          -- height bleed < one atom
  && cols == 100 && rows == 218

-- | The horizontal remainder is a positive sub-atom bleed (@2 pt < gifPx@).
lawHorizontalBleed :: Bool
lawHorizontalBleed =
     hBleedPt == screenWidthPt - cols * gifPx
  && hBleedPt >= 0 && hBleedPt < gifPx
  && hBleedPt == 2

-- | The vertical remainder is a positive sub-atom bleed (@2 pt < gifPx@).
lawVerticalBleed :: Bool
lawVerticalBleed =
     bleedPt == screenHeightPt - rows * gifPx
  && bleedPt >= 0 && bleedPt < gifPx
  && bleedPt == 2

-- | Shutter closure: filled disc (Ø12) directly abutted by a 2-atom ring band each
-- side sums to the 16-atom block — @6·2 + 2·2 = 16@.
lawShutterClosure :: Bool
lawShutterClosure =
  shutterDiscRadiusCells * 2 + shutterRingThicknessCells * 2 == shutterCells

-- | Every interactive widget clears the HIG 44 pt touch floor; the floor is 11 atoms
-- = 44 pt EXACTLY (the reason 4 pt was chosen).
lawTouchFloor :: Bool
lawTouchFloor =
     shutterCells   >= touchFloorCells
  && controlCells   >= touchFloorCells
  && segmentCells   >= touchFloorCells
  && cellsToPt touchFloorCells == 44
  && cellsToPt touchFloorCells >= 44

-- | Widgets grow by using MORE atoms, never a bigger atom: the size order is
-- @shutter ≥ control ≥ touch floor@ (monotone; the v2.0 fixed 3:2 ratio + ladder
-- membership is relaxed at 4 pt, where the exact 44 pt floor is off-ladder).
lawShutterRatio :: Bool
lawShutterRatio =
     shutterCells >= controlCells
  && controlCells >= touchFloorCells

-- | Wordmark advance fits within the preview width.
lawWordmarkAdvance :: Bool
lawWordmarkAdvance =
  wordmarkCols <= previewCells

-- | Every governed dimension, in points, is an integer multiple of the atom
-- (Law #6) — there is no off-lattice point value.
lawEveryGovernedDimIsCells :: Bool
lawEveryGovernedDimIsCells =
  all (\p -> p `mod` gifPx == 0) governedDimsPt
  where
    governedDimsPt = map cellsToPt
      [ previewCells, shutterCells, controlCells, ringCells
      , touchFloorCells, segmentCells, wordmarkRows, wordmarkCols ]

-- | The corner radius is an integer atom count (Law #6), snapped UP from the ~55 pt
-- physical radius by less than one atom, and small enough that the two arcs on an
-- axis never meet (@2·radius ≤ the short screen dimension@).
lawCornerRadiusIsCells :: Bool
lawCornerRadiusIsCells =
     cornerRadiusPt == cornerRadiusCells * gifPx        -- integer atoms
  && cornerRadiusCells == 14
  && cornerRadiusPt >= 55                                -- covers the physical radius
  && cornerRadiusPt - 55 < gifPx                         -- snapped up by < one atom
  && 2 * cornerRadiusCells <= min cols rows              -- both arcs fit, never meet

-- | The four corners are identical: 'cellOnScreen' is invariant under horizontal
-- and vertical mirror, so the approximation is symmetric on all four corners.
lawCornersSymmetric :: Bool
lawCornersSymmetric =
  and [ cellOnScreen (c, r) == cellOnScreen (cols - 1 - c, r)
     && cellOnScreen (c, r) == cellOnScreen (c, rows - 1 - r)
      | r <- [0 .. rows - 1], c <- [0 .. cols - 1] ]

-- | The corner is a CLEAN monotone arc, no holes or islands: inside the top-left
-- corner box, if a cell is on-screen then the cells one step toward the interior
-- (right and down) are on-screen too. With 'lawCornersSymmetric' this governs all
-- four corners, the clipped region of each corner is one contiguous blob.
lawCornerMonotone :: Bool
lawCornerMonotone =
  and [ (not on || cellOnScreen (c + 1, r)) && (not on || cellOnScreen (c, r + 1))
      | c <- [0 .. cornerRadiusCells - 1], r <- [0 .. cornerRadiusCells - 1]
      , let on = cellOnScreen (c, r) ]

-- | SPANS THE WHOLE SCREEN: the on-screen region reaches all four physical edges,
-- and clipping is confined to the four corner boxes, every cell that is NOT in a
-- corner box is on-screen. So the grid is full-bleed, with only the rounded
-- corners removed.
lawGridSpansScreen :: Bool
lawGridSpansScreen =
     any (\r -> cellOnScreen (0, r))         [0 .. rows - 1]   -- touches left edge
  && any (\r -> cellOnScreen (cols - 1, r))  [0 .. rows - 1]   -- touches right edge
  && any (\c -> cellOnScreen (c, 0))         [0 .. cols - 1]   -- touches top edge
  && any (\c -> cellOnScreen (c, rows - 1))  [0 .. cols - 1]   -- touches bottom edge
  && all cellOnScreen
       [ (c, r) | r <- [0 .. rows - 1], c <- [0 .. cols - 1], not (inCornerBox c r) ]
  where
    inCornerBox c r =
      min c (cols - 1 - c) < cornerRadiusCells && min r (rows - 1 - r) < cornerRadiusCells
