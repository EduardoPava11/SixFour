{- |
Module      : SixFour.Spec.GridScript
Description : The form-follows-function spine — one grid FORM, parameterized by a script.

"Form follows function": the FORM is one cell grid; the FUNCTION is the 'GridScript'
the calling scene supplies. A 'GridScript' is the composition @EMBEDDING . COLOR .
ORDER@ — conceptually the @Stage@ chain @EMBEDDING :> COLOR :> ORDER@
('SixFour.Spec.Pipeline'). Here the load-bearing, provable part is **ORDER** (the
centralized slot→rank authority, 'SixFour.Spec.Order'): COLOR is the runtime
palette and EMBEDDING is the lattice pitch (a view concern), so what a script
*pins* is /which order/ a scene binds.

== The render-equivalence law (the reason this module exists)

A 64×64 grid is drawn two ways for performance: the BITMAP backend writes one
linear @side²@ buffer (rank order), and the CANVAS backend iterates @(row,col)@
places. They MUST agree. 'surfaceBitmap' and 'surfaceCanvas' are the two code
paths; 'lawRenderEquivalence' proves @surfaceBitmap == concat surfaceCanvas@ for
every order and palette — the spec guarantee behind unifying the two Swift
backends behind one 'colorAt(rank)' contract without letting them diverge.

The surface is just the palette PERMUTED into screen order (no synthesis, no
blend — matching 'SixFour.Spec.CellFiber.lawNoSynthesis'): position @rank@ shows
@palette !! slotAt order rank@. Polymorphic in the element so the layout law is
proven independently of colour space (the Swift port carries @SIMD3<UInt8>@).
-}
-- COMPARTMENT: SWIFT-COREAI | tag:DisplaySide
module SixFour.Spec.GridScript
  ( GridScript(..)
  , captureScript
  , reviewAxisScript
    -- * The two render backends
  , surfaceBitmap
  , surfaceCanvas
    -- * Laws
  , lawSurfaceTotal
  , lawSurfacePermutes
  , lawRenderEquivalence
  ) where

import Data.List (sort)

import SixFour.Spec.GridAxis (GridAxis, IndexedColor)
import SixFour.Spec.Order    (Order, rowMajor, axisOrder, slotAt, size)

-- | A scene's script over the shared grid form. @gsSide@ is the grid side (so the
-- carrier is @gsSide²@ cells); @gsOrder@ is the bound ORDER (the only part the
-- layout law needs — COLOR is the runtime palette, EMBEDDING is the lattice pitch).
data GridScript = GridScript
  { gsName  :: !String
  , gsSide  :: !Int
  , gsOrder :: !Order
  } deriving (Eq, Show)

-- | The capture/preview script: row-major order (rank = slot) over a @side×side@
-- grid. The default fill — no per-frame re-sort jitter.
captureScript :: Int -> GridScript
captureScript side = GridScript "capture" side (rowMajor (side * side))

-- | The review script: the user-assignable 2-axis order over the full palette.
reviewAxisScript :: Int -> GridAxis -> GridAxis -> [IndexedColor] -> GridScript
reviewAxisScript side x y colors = GridScript "review" side (axisOrder x y colors)

-- | BITMAP backend: one linear @side²@ sequence in screen-rank order. Position
-- @rank@ shows @palette !! slotAt order rank@.
surfaceBitmap :: GridScript -> [a] -> [a]
surfaceBitmap gs palette =
  [ palette !! slotAt (gsOrder gs) r | r <- [0 .. n - 1] ]
  where n = length palette

-- | CANVAS backend: the same cells produced by a nested @(row,col)@ place loop,
-- as @side@ rows of @side@ entries. Place @(row,col)@ has row-major rank
-- @row*side + col@.
surfaceCanvas :: GridScript -> [a] -> [[a]]
surfaceCanvas gs palette =
  [ [ palette !! slotAt (gsOrder gs) (row * side + col) | col <- [0 .. side - 1] ]
  | row <- [0 .. side - 1] ]
  where side = gsSide gs

-- * Laws

-- | The bitmap surface has exactly one cell per palette slot (size preserved).
-- Valid when the order size matches the palette length and @side² = length@.
lawSurfaceTotal :: GridScript -> [a] -> Bool
lawSurfaceTotal gs palette =
  length (surfaceBitmap gs palette) == length palette

-- | The surface is a PERMUTATION of the palette — no colour synthesised, none
-- lost or duplicated (the no-blend contract). Uses @Ord@ to compare as multisets.
lawSurfacePermutes :: Ord a => GridScript -> [a] -> Bool
lawSurfacePermutes gs palette =
  sort (surfaceBitmap gs palette) == sort palette

-- | THE render-equivalence law: the linear bitmap backend and the nested-loop
-- canvas backend produce byte-identical cells. @surfaceBitmap == concat
-- surfaceCanvas@ for every order + palette (with @side² = length palette =
-- size order@).
lawRenderEquivalence :: Eq a => GridScript -> [a] -> Bool
lawRenderEquivalence gs palette =
  surfaceBitmap gs palette == concat (surfaceCanvas gs palette)
  && gsSide gs * gsSide gs == length palette
  && size (gsOrder gs) == length palette
