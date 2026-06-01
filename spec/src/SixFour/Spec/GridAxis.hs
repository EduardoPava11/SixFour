{- |
Module      : SixFour.Spec.GridAxis
Description : User-assignable 2-axis coordinate grid for the 256-colour palette.

The source of truth for the Review screen's @PaletteGridView@ (the "flat 16×16 grid
where the user chooses what x and y MEAN"). Distinct from 'SixFour.Spec.SplitTree':
the SplitTree shows median-cut *nesting*; this lays the 256 colours out on **two
independent perceptual axes the user picks** (e.g. x = OKLab a, y = OKLab L).

== Placement: rank/sort, not absolute-range binning

A naïve "bin each colour by (x,y) into a 16×16 lattice" collides (many colours in
one cell) and leaves holes. Instead we place by **rank**, which fills every cell
exactly once with no collision logic and no normalisation constants:

  1. sort all @side²@ colours by @(xScalar, index)@  → @side@ columns of @side@;
  2. within each column, sort its @side@ colours by @(yScalar, index)@ → the rows.

Cell @(row, col)@ = the @row@-th smallest-Y colour of the @col@-th smallest-X block.
Row 0 is the smallest Y, column 0 the smallest X (the Swift renderer flips Y for
screen coordinates — that is a view concern, not a spec one).

The @index@ tie-break (a colour's pinned slot in @palettesForDisplay[frame]@) makes
the layout a **total order**, so @gridLayout@ is deterministic regardless of input
order — exactly the discipline 'SixFour.Spec.SplitTree' uses.

== Axes

All axes are pure functions of the colour. The perceptual ones come straight from
OKLab; @AxisHue@ uses @atan2 b a@ (origin at +a, increasing toward +b) and is
circular, so the red wrap at ±π is a known seam (documented, not resolved in v1).
@AxisIndex@ exposes the original slot order (the GIF's palette index).

Laws (see @Properties.GridAxis@): the layout is a bijection onto the input index
set (no loss/dup); dimensions are @side × side@; columns are X-ordered blocks; rows
are Y-sorted within a column; deterministic under input permutation; and a pinned
golden (@side=2@) fixes the exact placement.
-}
module SixFour.Spec.GridAxis
  ( -- * Axes
    GridAxis(..)
  , allAxes
  , gridScalar
    -- * Layout
  , IndexedColor(..)
  , gridSide
  , gridCells
  , gridLayout
  , gridLayoutN
    -- * Laws
  , lawLayoutIsBijection
  , lawLayoutDimensions
  , lawColumnsXOrdered
  , lawRowsYSorted
  , lawDeterministicUnderPermutation
  ) where

import Data.List (sortBy)
import Data.Ord  (comparing)

import SixFour.Spec.Color (OKLab(..))

-- | A colour with its pinned slot index (position in @palettesForDisplay[frame]@).
-- The index is the deterministic tie-break key, mirroring 'SixFour.Spec.SplitTree.IndexedColor'.
data IndexedColor = IndexedColor
  { icIndex :: !Int
  , icColor :: !OKLab
  } deriving (Eq, Show)

-- | The dimensions a grid axis can encode. All are pure functions of the colour
-- (plus, for 'AxisIndex', its pinned slot).
data GridAxis
  = AxisL        -- ^ OKLab lightness @L@.
  | AxisA        -- ^ OKLab green→red opponent @a@.
  | AxisB        -- ^ OKLab blue→yellow opponent @b@.
  | AxisChroma   -- ^ OKLCh chroma @C = √(a²+b²)@.
  | AxisHue      -- ^ OKLCh hue @atan2 b a@ (origin +a; circular, red seam at ±π).
  | AxisIndex    -- ^ The original palette slot index (GIF colour-table order).
  deriving (Eq, Show, Enum, Bounded)

-- | Every axis, in declaration order (drives the Swift @CaseIterable@ picker).
allAxes :: [GridAxis]
allAxes = [minBound .. maxBound]

-- | The scalar an axis projects a colour onto. Used only as a sort KEY, so no
-- normalisation is needed — magnitude and origin are irrelevant to the ranking.
gridScalar :: GridAxis -> IndexedColor -> Double
gridScalar ax (IndexedColor i (OKLab l a b)) = case ax of
  AxisL      -> l
  AxisA      -> a
  AxisB      -> b
  AxisChroma -> sqrt (a * a + b * b)
  AxisHue    -> atan2 b a
  AxisIndex  -> fromIntegral i

-- | The pinned grid side (16 → a 16×16 = 256-cell grid for the full palette).
gridSide :: Int
gridSide = 16

-- | Cells in a full grid: @gridSide² = 256@.
gridCells :: Int
gridCells = gridSide * gridSide

-- | The full 16×16 layout for the 256-colour palette.
gridLayout :: GridAxis -> GridAxis -> [IndexedColor] -> [[Int]]
gridLayout = gridLayoutN gridSide

-- | Lay @side²@ colours into a @side × side@ grid of slot indices, addressed
-- @result !! row !! col@. Rank/sort placement (see module header). If the input
-- length is not exactly @side²@ the result is empty (callers pass a full palette;
-- the law-checked contract assumes @length == side²@).
gridLayoutN :: Int -> GridAxis -> GridAxis -> [IndexedColor] -> [[Int]]
gridLayoutN side ax ay ics
  | side < 1 || length ics /= side * side = []
  | otherwise =
      -- 1. X-ordered total order, chunked into `side` columns of `side`.
      let byX     = sortBy (comparing (\ic -> (gridScalar ax ic, icIndex ic))) ics
          columns = chunksOf side byX
      -- 2. Each column sorted by Y → its rows (row 0 = smallest Y).
          colRows = [ map icIndex (sortBy (comparing (\ic -> (gridScalar ay ic, icIndex ic))) col)
                    | col <- columns ]
      -- 3. Address by [row][col]: transpose the column-major arrangement.
      in [ [ colRows !! c !! r | c <- [0 .. side - 1] ] | r <- [0 .. side - 1] ]

chunksOf :: Int -> [a] -> [[a]]
chunksOf _ [] = []
chunksOf n xs = let (h, t) = splitAt n xs in h : chunksOf n t

-- * Laws

-- | The layout uses every input slot exactly once (a bijection onto @[0..n-1]@'s
-- index set) — no colour lost, none duplicated.
lawLayoutIsBijection :: GridAxis -> GridAxis -> [IndexedColor] -> Bool
lawLayoutIsBijection ax ay ics =
  let placed = concat (gridLayout ax ay ics)
      want   = map icIndex ics
  in length placed == length want
     && sortBy compare placed == sortBy compare want

-- | A full layout is @gridSide@ rows of @gridSide@ columns.
lawLayoutDimensions :: GridAxis -> GridAxis -> [IndexedColor] -> Bool
lawLayoutDimensions ax ay ics =
  let g = gridLayout ax ay ics
  in length g == gridSide && all ((== gridSide) . length) g

-- | Columns are X-ordered blocks: the max X-scalar of column @c@ is ≤ the min
-- X-scalar of column @c+1@ (with the @index@ tie-break making the boundary exact).
lawColumnsXOrdered :: GridAxis -> GridAxis -> [IndexedColor] -> Bool
lawColumnsXOrdered ax ay ics =
  let g       = gridLayout ax ay ics
      byIdx i = head [ ic | ic <- ics, icIndex ic == i ]
      colKeys c = [ (gridScalar ax (byIdx (row !! c)), row !! c) | row <- g ]
      cols      = [ colKeys c | c <- [0 .. gridSide - 1] ]
  in null g
     || and [ maximum (cols !! c) <= minimum (cols !! (c + 1))
            | c <- [0 .. gridSide - 2] ]

-- | Within every column, the Y-scalar is non-decreasing as @row@ increases.
lawRowsYSorted :: GridAxis -> GridAxis -> [IndexedColor] -> Bool
lawRowsYSorted ax ay ics =
  let g       = gridLayout ax ay ics
      byIdx i = head [ ic | ic <- ics, icIndex ic == i ]
      colYs c = [ (gridScalar ay (byIdx (row !! c)), row !! c) | row <- g ]
  in null g
     || and [ nonDecreasing (colYs c) | c <- [0 .. gridSide - 1] ]
  where nonDecreasing xs = and (zipWith (<=) xs (drop 1 xs))

-- | The layout does not depend on input order (the @(scalar, index)@ tie-break
-- gives a total order). @gridLayout xs == gridLayout (reverse xs)@.
lawDeterministicUnderPermutation :: GridAxis -> GridAxis -> [IndexedColor] -> Bool
lawDeterministicUnderPermutation ax ay ics =
  gridLayout ax ay ics == gridLayout ax ay (reverse ics)
