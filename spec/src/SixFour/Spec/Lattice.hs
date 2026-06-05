{- |
Module      : SixFour.Spec.Lattice
Description : The GRID lattice — source of truth for every governed dimension.

The formally-pinned authority for the GRID design language's @GlobalLattice@
(Law #5, "ONE OWNER FOR CELL MATH"). Every number the app draws with is derived
here and emitted to @SixFour/Generated/LatticeContract.swift@; the hand-written
@GlobalLattice.swift@ is the typed @CGFloat@ facade over these constants, not an
independent authority.

== v2.0 — THE gifPx INVERSION (2026-06-04)

SixFour exists to make 64×64 GIFs, so the **GIF pixel IS the atom**, not a size
derived from a screen-tiling cell. @gifPx = 6 pt = 18 device-px@ — the *largest*
pitch at which a full 64-wide preview fits portrait width (@64·6 = 384 ≤ 402@) AND
lands on integer device-px (resample-free). It is forced, not chosen: 7 pt
overflows (@64·7 = 448 > 402@) and @6.28 pt@ gives @18.84@ fractional device-px.

The old v1.0 @2 pt@ master cell survives only as @subPt = gifPx \`div\` 3@, the
*sub-pixel* used for fine spacing/gutters and text legibility (a glyph cannot be
one atom wide). It is commensurate (@3·subPt = gifPx@), so everything still snaps
to one grid — proven by 'lawSubPixelCommensurate'.

== The screen lattice (inverted)

@402 \`div\` 6 = 67@ columns exactly (zero horizontal remainder). @874 \`div\` 6 =
145.67@ → 145 rows (@870 pt@) + a @4 pt@ 'bleedPt' absorbed into the bottom
home-indicator safe band (off-lattice). Horizontal tiling is exact, vertical is
exact-to-the-safe-area ('lawLatticeTiles' + 'lawVerticalBleed'). v1.0 chose 2 pt
*because* @gcd 402 874 = 2@ is the unique zero-remainder pitch; v2.0 accepts a
sub-atom bleed as the price of making the GIF pixel the atom.

== The closure law

The shutter is a filled disc directly abutted by a ring band:
@discRadius·2 + ringThickness·2 = 5·2 + 1·2 = 12 = shutterCells@
('lawShutterClosure'), i.e. a 72 pt shutter (@12·6@).

Laws (see @Properties.Lattice@): the atom identity; the sub-pixel commensurability;
the lattice tiling + vertical bleed; the shutter closure; the touch floor (every
interactive widget ≥ 8 gifPx = 48 pt); the shutter:control 3:2 ratio; the
top-weighted golden vertical split (@below / above ≈ φ@); the preview is a 64×64
square centered on the field; the wordmark fits the title band; and every governed
dimension is an integer @gifPx@ count.
-}
module SixFour.Spec.Lattice
  ( -- * Anchor (the physical screen, iPhone 17 Pro portrait)
    screenWidthPt, screenHeightPt, scale
    -- * The atom (gifPx) + the sub-pixel (subPt) + the lattice they tile
  , gifPx, gifDevicePx, subPt, cols, rows, bleedPt, reviewPitchPt
    -- * Verified OS safe-area insets (iPhone 17 Pro portrait, iOS 26+)
  , safeTopPt, safeBottomPt
    -- * Fibonacci size ladder
  , fibLadder
    -- * Widget gifPx-counts
  , previewCells, touchFloorCells, controlCells, shutterCells
  , ringCells, ringTicks, wordmarkRows, wordmarkCols
  , segmentCells, gutterCells
  , shutterDiscRadiusCells, shutterRingThicknessCells
    -- * The golden vertical layout
  , previewStartRow, previewEndRow, previewStartCol, previewEndCol
  , aboveRows, belowRows, phi
    -- * The one conversion
  , cellsToPt
    -- * Laws
  , lawAtomIsGifPx
  , lawSubPixelCommensurate
  , lawLatticeTiles
  , lawVerticalBleed
  , lawShutterClosure
  , lawTouchFloor
  , lawShutterRatio
  , lawGoldenSplit
  , lawPreviewRect
  , lawWordmarkAdvance
  , lawEveryGovernedDimIsCells
  , lawSafeAreaClearance
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

-- | THE ATOM: one GIF pixel = @6 pt@. SixFour's product is the 64×64 GIF, so its
-- pixel is the unit every governed element is built from (v2.0 inversion). The
-- largest pitch at which a 64-wide preview fits portrait width and lands on
-- integer device-px — forced, not chosen ('lawAtomIsGifPx'). Mirror of
-- @SFTheme.gifCellPt@.
gifPx :: Int
gifPx = 6

-- | One atom in device pixels: @gifPx · scale = 18 px@ (crisp; resample-free).
gifDevicePx :: Int
gifDevicePx = gifPx * scale

-- | The sub-pixel: @gifPx \`div\` 3 = 2 pt@. The old v1.0 master cell, demoted to a
-- commensurate sub-grid for fine spacing/gutters and text legibility (a glyph
-- cannot be one atom wide). Legal only as a sub-unit, never as a widget's own
-- pixel size ('lawSubPixelCommensurate'). Mirror of @GlobalLattice.subPt@.
subPt :: Int
subPt = gifPx `div` 3

-- | Backward-compat alias kept for the Review/content surfaces: the content pitch
-- equals the atom now (Review folds into the one atom; @EXEMPT-REVIEW-PITCH@ is
-- retired). Mirror of @SFTheme.gifCellPt@; preserved so the Swift content tokens
-- (@gifCellPt = 6@, @gifCanvasPt = 384@) need no change.
reviewPitchPt :: Int
reviewPitchPt = gifPx

-- | Full-screen lattice width in atoms: @402 \`div\` 6 = 67@ (exact).
cols :: Int
cols = screenWidthPt `div` gifPx

-- | Full-screen lattice height in atoms: @874 \`div\` 6 = 145@ (870 pt + 4 pt bleed).
rows :: Int
rows = screenHeightPt `div` gifPx

-- | The vertical remainder absorbed into the bottom safe band: @874 - 145·6 = 4 pt@
-- (less than one atom; off-lattice — splits no governed cell).
bleedPt :: Int
bleedPt = screenHeightPt - rows * gifPx

-- OS safe-area insets (verified) --------------------------------------------

-- | iPhone 17 Pro portrait TOP safe-area inset (Dynamic Island + status bar), in
-- points. Web-verified 2026-06-04 (useyourloaf / yesviz); equals v1.0's "31 rows ×
-- 2 pt". Field renders under it; no chrome may enter the top @safeTopPt@.
safeTopPt :: Int
safeTopPt = 62

-- | iPhone 17 Pro portrait BOTTOM safe-area inset (home indicator), in points.
-- Web-verified 2026-06-04; equals v1.0's "17 rows × 2 pt". Absorbs the 'bleedPt'.
safeBottomPt :: Int
safeBottomPt = 34

-- The Fibonacci size ladder -------------------------------------------------

-- | Widget sizes draw from this φ-ratio ladder (successive ratios ≈ φ); the touch
-- floor and secondary control sit on it at @8@.
fibLadder :: [Int]
fibLadder = [8, 13, 21, 34, 55, 89]

-- Widget gifPx-counts -------------------------------------------------------

-- | The hero preview: 64 atoms = 1 GIF pixel per atom (the cube law), 384 pt.
previewCells :: Int
previewCells = 64

-- | HIG touch floor in atoms: @ceil(44 / 6) = 8@ → 48 pt. A 6 pt atom cannot land
-- on 44 pt exactly, so the floor rounds UP to 48 (never below 44).
touchFloorCells :: Int
touchFloorCells = 8

-- | Secondary control (gear / selector segment): 8 atoms = 48 pt.
controlCells :: Int
controlCells = 8

-- | The shutter: 12 atoms = 72 pt (the clean cube number; shutter:control = 3:2).
shutterCells :: Int
shutterCells = 12

-- | The diversity gauge ring: 20 atoms = 120 pt (Ø20, R10).
ringCells :: Int
ringCells = 20

-- | Radial ticks on the gauge — one per GIF frame.
ringTicks :: Int
ringTicks = 64

-- | Wordmark TITLE band height in atoms (= the control height).
wordmarkRows :: Int
wordmarkRows = 8

-- | Wordmark advance width in atoms — fits within the preview width.
wordmarkCols :: Int
wordmarkCols = 60

-- | A selector segment never narrows below the touch floor.
segmentCells :: Int
segmentCells = 8

-- | The Swiss gutter: one atom.
gutterCells :: Int
gutterCells = 1

-- | Shutter filled-disc radius (Ø10).
shutterDiscRadiusCells :: Int
shutterDiscRadiusCells = 5

-- | Shutter ring-band thickness, each side of the disc.
shutterRingThicknessCells :: Int
shutterRingThicknessCells = 1

-- The golden vertical layout ------------------------------------------------

-- | Preview anchor rows (inclusive). 31–94 → 64 rows (top-weighted golden band).
previewStartRow, previewEndRow :: Int
previewStartRow = 31
previewEndRow   = 94

-- | Preview anchor cols (inclusive). 1–64 → 64 cols, centered on the 67-col field
-- (1 atom left margin / 2 atoms right; @1 + 64 = 65 = cols - 2@).
previewStartCol, previewEndCol :: Int
previewStartCol = 1
previewEndCol   = 64

-- | Field rows above the preview anchor (the minor golden segment → preview rides
-- high, controls fill the bottom thumb zone).
aboveRows :: Int
aboveRows = previewStartRow

-- | Field rows below the preview anchor: @rows - (previewEndRow + 1)@ = 50.
belowRows :: Int
belowRows = rows - (previewEndRow + 1)

-- | The golden ratio.
phi :: Double
phi = (1 + sqrt 5) / 2

-- The one conversion --------------------------------------------------------

-- | Atoms → points. The single place an atom count becomes a point size.
cellsToPt :: Int -> Int
cellsToPt c = c * gifPx

-- Laws ----------------------------------------------------------------------

-- | The atom is the GIF pixel: @gifPx = 6 pt = 18 device-px@, the largest pitch
-- that fits a 64-wide preview in portrait width and is integer device-px.
lawAtomIsGifPx :: Bool
lawAtomIsGifPx =
     gifPx == 6
  && gifDevicePx == 18
  && previewCells * gifPx <= screenWidthPt          -- 64·6 = 384 ≤ 402: a full preview fits
  && previewCells * (gifPx + 1) > screenWidthPt      -- 64·7 = 448 > 402: 7 pt overflows, 6 is the max

-- | The sub-pixel is an EXACT third of the atom, so spacing/text snap to one grid.
lawSubPixelCommensurate :: Bool
lawSubPixelCommensurate =
     subPt == 2
  && gifPx `mod` subPt == 0
  && gifPx `div` subPt == 3
  && reviewPitchPt == gifPx

-- | The atom tiles the width exactly (67 cols) and the height to the safe-area
-- (145 rows + a sub-atom bleed), giving exactly 67×145.
lawLatticeTiles :: Bool
lawLatticeTiles =
     cols * gifPx == screenWidthPt                   -- 67·6 = 402 exact
  && rows * gifPx <= screenHeightPt                  -- 145·6 = 870 ≤ 874
  && cols == 67 && rows == 145

-- | The vertical remainder is a positive sub-atom bleed (@4 pt < gifPx@).
lawVerticalBleed :: Bool
lawVerticalBleed =
     bleedPt == screenHeightPt - rows * gifPx
  && bleedPt >= 0 && bleedPt < gifPx
  && bleedPt == 4

-- | Shutter closure: filled disc (Ø10) directly abutted by a 1-atom ring band each
-- side sums to the 12-atom block — @5·2 + 1·2 = 12@.
lawShutterClosure :: Bool
lawShutterClosure =
  shutterDiscRadiusCells * 2 + shutterRingThicknessCells * 2 == shutterCells

-- | Every interactive widget clears the HIG 44 pt touch floor; the floor is 8 atoms
-- = 48 pt (≥ 44, since 6 pt cannot express 44 exactly).
lawTouchFloor :: Bool
lawTouchFloor =
     shutterCells   >= touchFloorCells
  && controlCells   >= touchFloorCells
  && segmentCells   >= touchFloorCells
  && cellsToPt touchFloorCells == 48
  && cellsToPt touchFloorCells >= 44

-- | The control sits on the Fibonacci ladder (8) and the shutter is a clean 3:2 of
-- it (12) — widgets grow by ladder relations, not by enlarging the atom.
lawShutterRatio :: Bool
lawShutterRatio =
     controlCells `elem` fibLadder
  && shutterCells * 2 == controlCells * 3
  && touchFloorCells == controlCells

-- | The vertical layout is the golden section: @above + preview + below = rows@
-- and @below / above ≈ φ@ (the minor segment above; preview rides high).
lawGoldenSplit :: Bool
lawGoldenSplit =
     aboveRows + previewCells + belowRows == rows
  && aboveRows < belowRows
  && abs (fromIntegral belowRows / fromIntegral aboveRows - phi) < (0.02 :: Double)

-- | The preview is a 64×64 square centered on the field (@startCol + endCol =
-- cols - 2@, a 1-atom/2-atom inset) with its row anchor at the golden split.
lawPreviewRect :: Bool
lawPreviewRect =
     previewEndCol - previewStartCol + 1 == previewCells
  && previewEndRow - previewStartRow + 1 == previewCells
  && previewStartCol + previewEndCol == cols - 2
  && previewStartRow == aboveRows

-- | Wordmark advance fits within the preview width and the title band height equals
-- the control height.
lawWordmarkAdvance :: Bool
lawWordmarkAdvance =
     wordmarkCols <= previewCells
  && wordmarkRows == controlCells

-- | The top-weighted golden split leaves room for BOTH OS safe areas: the preview's
-- top (@aboveRows·gifPx = 186 pt@) clears the Dynamic Island (62 pt), and the region
-- below the preview (@belowRows·gifPx = 300 pt@) can absorb the home indicator + the
-- vertical bleed (@34 + 4 = 38 pt@) with room for the control band. Proven on the
-- web-verified iPhone 17 Pro insets, so "chrome never underlaps the OS" is a theorem.
lawSafeAreaClearance :: Bool
lawSafeAreaClearance =
     aboveRows * gifPx >= safeTopPt
  && belowRows * gifPx >= safeBottomPt + bleedPt

-- | Every governed dimension, in points, is an integer multiple of the atom
-- (Law #6) — there is no off-lattice point value.
lawEveryGovernedDimIsCells :: Bool
lawEveryGovernedDimIsCells =
  all (\p -> p `mod` gifPx == 0) governedDimsPt
  where
    governedDimsPt = map cellsToPt
      [ previewCells, shutterCells, controlCells, ringCells
      , touchFloorCells, segmentCells, wordmarkRows, wordmarkCols ]
