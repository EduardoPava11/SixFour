{- |
Module      : SixFour.Spec.SevenSeg
Description : The 7-segment digit register — golden masks for the count readout.

The source of truth for the GRID CountReadout's digits (design language §6.9: a
"fixed 3-digit two-ink 7-seg" so the colour count **never reflows**). This is the
first complete register of the eventual @CellFont@; it is shipped on its own (not a
stubbed @CellFont@ with empty wordmark/Cozette registers) per the no-stubs rule.

== Parametric, not hand-drawn

A 7-segment glyph is geometry + a per-digit bitmask, so the masks are *derived*, not
authored cell-by-cell. Seven segment rectangles tile a @10×18@ box; each digit lights
a standard subset. The two-ink LED look (lit = white, unlit = opaque @ledGhost@) is a
consequence: a digit draws the full "8" mask in ghost, then its lit segments in white
on top — which is precisely why a digit can never reflow (every digit occupies the
identical 96-cell footprint).

@
   AAAA        segments:  A top      D bottom
  F    B                  B top-right E bottom-left
  F    B                  C bot-right F top-left
   GGGG                   G middle
  E    C
  E    C
   DDDD
@

Laws (see @Properties.SevenSeg@): ten digits; every segment cell is inside the
@10×18@ box; the segments are disjoint; digit 8 lights all seven; digit 0 omits the
middle; digit 1 lights exactly the two right verticals; and pinned cell-count goldens.
-}
module SixFour.Spec.SevenSeg
  ( -- * Geometry
    digitBoxCols
  , digitBoxRows
  , Segment(..)
  , allSegments
  , segmentRect
  , segmentCells
    -- * Digits
  , digitSegments
  , litCells
  , allSegmentCells
    -- * Laws
  , lawDigitCount
  , lawSegmentsInBounds
  , lawSegmentsDisjoint
  , lawEightAllLit
  , lawZeroNoMiddle
  , lawOneRightVerticals
  , lawDigitFootprintGolden
  ) where

import Data.List (nub, sort)

-- Geometry ------------------------------------------------------------------

-- | Digit box width in cells.
digitBoxCols :: Int
digitBoxCols = 10

-- | Digit box height in cells.
digitBoxRows :: Int
digitBoxRows = 18

-- | The seven segments of a 7-segment display.
data Segment = SegA  -- ^ top
             | SegB  -- ^ top-right
             | SegC  -- ^ bottom-right
             | SegD  -- ^ bottom
             | SegE  -- ^ bottom-left
             | SegF  -- ^ top-left
             | SegG  -- ^ middle
  deriving (Eq, Show, Enum, Bounded, Ord)

-- | All seven segments.
allSegments :: [Segment]
allSegments = [minBound .. maxBound]

-- | Each segment's inclusive cell rectangle @((c0,c1),(r0,r1))@ in the 10×18 box.
-- Horizontals span cols 1–8 (2 rows thick); verticals span cols {0–1, 8–9} (6 rows
-- tall), in the gaps between the horizontals — so no two segments overlap.
segmentRect :: Segment -> ((Int, Int), (Int, Int))
segmentRect s = case s of
  SegA -> ((1, 8), (0, 1))     -- top
  SegG -> ((1, 8), (8, 9))     -- middle
  SegD -> ((1, 8), (16, 17))   -- bottom
  SegF -> ((0, 1), (2, 7))     -- top-left
  SegB -> ((8, 9), (2, 7))     -- top-right
  SegE -> ((0, 1), (10, 15))   -- bottom-left
  SegC -> ((8, 9), (10, 15))   -- bottom-right

-- | The cells of a segment, row-major.
segmentCells :: Segment -> [(Int, Int)]
segmentCells s =
  let ((c0, c1), (r0, r1)) = segmentRect s
  in [ (c, r) | r <- [r0 .. r1], c <- [c0 .. c1] ]

-- Digits --------------------------------------------------------------------

-- | The segments lit for each digit 0–9 (standard 7-segment encoding). Any other
-- input is blank (no segments).
digitSegments :: Int -> [Segment]
digitSegments d = case d of
  0 -> [SegA, SegB, SegC, SegD, SegE, SegF]
  1 -> [SegB, SegC]
  2 -> [SegA, SegB, SegG, SegE, SegD]
  3 -> [SegA, SegB, SegG, SegC, SegD]
  4 -> [SegF, SegG, SegB, SegC]
  5 -> [SegA, SegF, SegG, SegC, SegD]
  6 -> [SegA, SegF, SegG, SegE, SegC, SegD]
  7 -> [SegA, SegB, SegC]
  8 -> [SegA, SegB, SegC, SegD, SegE, SegF, SegG]
  9 -> [SegA, SegB, SegC, SegD, SegF, SegG]
  _ -> []

-- | The lit cells of a digit (union of its segments), sorted row-major.
litCells :: Int -> [(Int, Int)]
litCells d = sort (nub (concatMap segmentCells (digitSegments d)))

-- | The full "8" footprint — every segment cell. Drawn in ghost so any digit (and a
-- blanked leading digit) occupies the identical footprint and never reflows.
allSegmentCells :: [(Int, Int)]
allSegmentCells = litCells 8

-- Laws ----------------------------------------------------------------------

-- | Ten digits 0–9 each have a non-empty segment set.
lawDigitCount :: Bool
lawDigitCount = all (not . null . digitSegments) [0 .. 9]

-- | Every segment cell lies inside the 10×18 box.
lawSegmentsInBounds :: Bool
lawSegmentsInBounds =
  all (\(c, r) -> c >= 0 && c < digitBoxCols && r >= 0 && r < digitBoxRows)
      (concatMap segmentCells allSegments)

-- | No two segments share a cell (the union's size = the sum of the parts).
lawSegmentsDisjoint :: Bool
lawSegmentsDisjoint =
  let cells = concatMap segmentCells allSegments
  in length cells == length (nub cells)

-- | Digit 8 lights all seven segments.
lawEightAllLit :: Bool
lawEightAllLit = sort (digitSegments 8) == sort allSegments

-- | Digit 0 omits the middle bar; digit 8 includes it.
lawZeroNoMiddle :: Bool
lawZeroNoMiddle = SegG `notElem` digitSegments 0 && SegG `elem` digitSegments 8

-- | Digit 1 lights exactly the two right verticals (B and C).
lawOneRightVerticals :: Bool
lawOneRightVerticals = sort (digitSegments 1) == sort [SegB, SegC]

-- | Pinned cell-count goldens: the full footprint is 96 cells, digit 1 is 24, digit 0
-- is 80. (Horizontals 8×2=16 ×3, verticals 2×6=12 ×4 → 48+48 = 96.)
lawDigitFootprintGolden :: Bool
lawDigitFootprintGolden =
     length allSegmentCells == 96
  && length (litCells 1) == 24
  && length (litCells 0) == 80
