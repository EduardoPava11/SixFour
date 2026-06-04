{- |
Module      : SixFour.Spec.Lattice
Description : The GRID capture-HUD lattice — source of truth for every chrome dimension.

The formally-pinned authority for the GRID design language's @GlobalLattice@
(Law #5, "ONE OWNER FOR CELL MATH"). Every number the capture HUD draws with is
derived here and emitted to @SixFour/Generated/LatticeContract.swift@; the
hand-written @GlobalLattice.swift@ is the typed @CGFloat@ facade over these
constants, not an independent authority.

== Why the pitch is 2 pt (not a choice)

The iPhone 17 Pro portrait screen is @402 × 874@ pt. @gcd 402 874 = 2@, so a 2 pt
cell is the *unique* pitch that tiles the screen edge-to-edge with no remainder:
exactly @201 × 437@ cells. A 6 pt pitch cannot (@874 / 6@ is not integral), which
is *why* the HUD pitch is 2 pt. The pitch is a theorem (@lawGcdPitch@), not a token.

== The closure law

The shutter is a filled disc directly abutted by a ring band:
@discRadius·2 + ringThickness·2 = 15·2 + 2·2 = 34 = shutterCells@
(@lawShutterClosure@). This is the predicate the shipped code drifted from (the
disc was sized @d ≤ 13@, leaving an unspecified annulus); the spec asserts the
geometry the renderer must match.

Laws (see @Properties.Lattice@): the gcd pitch; the pitch tiles the screen; the
shutter closure; the touch floor (every interactive widget ≥ 22 cells = 44 pt);
the shutter sits on the Fibonacci ladder; the golden vertical split
(@below / above ≈ φ@); the preview is an even-anchored 64×64 square; the wordmark
advance (7 glyph boxes + 6 gaps = 124 cells); and every governed chrome dimension
is an integer cell count.
-}
module SixFour.Spec.Lattice
  ( -- * Anchor (the physical screen, iPhone 17 Pro portrait)
    screenWidthPt, screenHeightPt, scale
    -- * The pitch (gcd-derived) + the lattice it tiles
  , cellPt, cellPx, cols, rows
    -- * Fibonacci size ladder
  , fibLadder
    -- * Widget cell-counts
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
  , lawGcdPitch
  , lawPitchTilesScreen
  , lawShutterClosure
  , lawTouchFloor
  , lawShutterOnLadder
  , lawGoldenSplit
  , lawPreviewRect
  , lawWordmarkAdvance
  , lawEveryGovernedDimIsCells
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

-- The pitch and the lattice -------------------------------------------------

-- | The one pitch: @gcd 402 874 = 2 pt@ — the unique value that tiles the screen
-- with no remainder. Derived, not chosen (@lawGcdPitch@).
cellPt :: Int
cellPt = gcd screenWidthPt screenHeightPt

-- | One cell in device pixels: @cellPt · scale = 6 px@.
cellPx :: Int
cellPx = cellPt * scale

-- | Full-screen lattice width in cells: @402 / 2 = 201@.
cols :: Int
cols = screenWidthPt `div` cellPt

-- | Full-screen lattice height in cells: @874 / 2 = 437@.
rows :: Int
rows = screenHeightPt `div` cellPt

-- The Fibonacci size ladder -------------------------------------------------

-- | Widget sizes are drawn from this φ-ratio ladder (successive ratios ≈ φ).
fibLadder :: [Int]
fibLadder = [8, 13, 21, 34, 55, 89]

-- Widget cell-counts --------------------------------------------------------

-- | The hero preview: 64 cells = 1 GIF pixel per cell (the cube law).
previewCells :: Int
previewCells = 64

-- | HIG 44 pt minimum hit target, in cells (@22 · 2 = 44@).
touchFloorCells :: Int
touchFloorCells = 22

-- | HIG 48 pt comfortable secondary control, in cells (@24 · 2 = 48@).
controlCells :: Int
controlCells = 24

-- | The shutter: 34 cells = 68 pt (a ladder value).
shutterCells :: Int
shutterCells = 34

-- | The diversity gauge ring: 60 cells = 120 pt (Ø60, R30).
ringCells :: Int
ringCells = 60

-- | Radial ticks on the gauge — one per GIF frame.
ringTicks :: Int
ringTicks = 64

-- | Wordmark TITLE register height in cells (rows 96–115).
wordmarkRows :: Int
wordmarkRows = 20

-- | Wordmark advance width in cells (cols 68–191): see @lawWordmarkAdvance@.
wordmarkCols :: Int
wordmarkCols = 124

-- | A selector segment never narrows below the touch floor.
segmentCells :: Int
segmentCells = 22

-- | The Swiss gutter: one cell.
gutterCells :: Int
gutterCells = 1

-- | Shutter filled-disc radius (Ø30).
shutterDiscRadiusCells :: Int
shutterDiscRadiusCells = 15

-- | Shutter ring-band thickness, each side of the disc.
shutterRingThicknessCells :: Int
shutterRingThicknessCells = 2

-- The golden vertical layout ------------------------------------------------

-- | Preview anchor rows (inclusive). 143–206 → 64 rows.
previewStartRow, previewEndRow :: Int
previewStartRow = 143
previewEndRow   = 206

-- | Preview anchor cols (inclusive). 68–131 → 64 cols.
previewStartCol, previewEndCol :: Int
previewStartCol = 68
previewEndCol   = 131

-- | Field rows above the preview anchor.
aboveRows :: Int
aboveRows = previewStartRow

-- | Field rows below the preview anchor: @rows - (previewEndRow + 1)@ = 230.
belowRows :: Int
belowRows = rows - (previewEndRow + 1)

-- | The golden ratio.
phi :: Double
phi = (1 + sqrt 5) / 2

-- The one conversion --------------------------------------------------------

-- | Cells → points. The single place a cell count becomes a point size.
cellsToPt :: Int -> Int
cellsToPt c = c * cellPt

-- Laws ----------------------------------------------------------------------

-- | The pitch is the gcd of the screen dimensions — the unique tiling pitch (2 pt).
lawGcdPitch :: Bool
lawGcdPitch = cellPt == 2 && gcd screenWidthPt screenHeightPt == cellPt

-- | The pitch tiles the full screen with no remainder, giving exactly 201×437.
lawPitchTilesScreen :: Bool
lawPitchTilesScreen =
     screenWidthPt  `mod` cellPt == 0
  && screenHeightPt `mod` cellPt == 0
  && cols * cellPt == screenWidthPt
  && rows * cellPt == screenHeightPt
  && cols == 201 && rows == 437

-- | Shutter closure: filled disc (Ø30) directly abutted by a 2-cell ring band each
-- side sums to the 34-cell block — @15·2 + 2·2 = 34@.
lawShutterClosure :: Bool
lawShutterClosure =
  shutterDiscRadiusCells * 2 + shutterRingThicknessCells * 2 == shutterCells

-- | Every interactive widget clears the HIG 44 pt touch floor (= 22 cells).
lawTouchFloor :: Bool
lawTouchFloor =
     shutterCells   >= touchFloorCells
  && controlCells   >= touchFloorCells
  && segmentCells   >= touchFloorCells
  && cellsToPt touchFloorCells == 44

-- | The shutter size is a Fibonacci-ladder value (grows by ladder steps, not pitch).
lawShutterOnLadder :: Bool
lawShutterOnLadder = shutterCells `elem` fibLadder

-- | The vertical layout is the golden section: @above + preview + below = rows@
-- and @below / above ≈ φ@.
lawGoldenSplit :: Bool
lawGoldenSplit =
     aboveRows + previewCells + belowRows == rows
  && abs (fromIntegral belowRows / fromIntegral aboveRows - phi) < (0.02 :: Double)

-- | The preview is a 64×64 square, even-started and centered on the col-99.5
-- PATTERN-CENTERLINE horizontally (@68 + 131 = 199 = cols - 2@). Its ROW anchor is
-- fixed by the golden section (@lawGoldenSplit@), NOT by parity — 143 is odd on
-- purpose, because @230/143 ≈ φ@. (The doc's earlier "even-start on both axes" was
-- an over-claim corrected here: only the horizontal axis is even/centered.)
lawPreviewRect :: Bool
lawPreviewRect =
     previewEndCol - previewStartCol + 1 == previewCells
  && previewEndRow - previewStartRow + 1 == previewCells
  && even previewStartCol
  && previewStartCol + previewEndCol == cols - 2

-- | Wordmark advance: 7 glyph boxes (16 cells) + 6 gaps (2 cells) = 124 cells.
lawWordmarkAdvance :: Bool
lawWordmarkAdvance = 7 * 16 + 6 * 2 == wordmarkCols

-- | Every governed chrome dimension, expressed in points, is an integer multiple
-- of the pitch (Law #6) — there is no off-lattice point value.
lawEveryGovernedDimIsCells :: Bool
lawEveryGovernedDimIsCells =
  all (\p -> p `mod` cellPt == 0) governedDimsPt
  where
    governedDimsPt = map cellsToPt
      [ previewCells, shutterCells, controlCells, ringCells
      , touchFloorCells, segmentCells, wordmarkRows, wordmarkCols ]
