{- |
Module      : SixFour.Spec.Export
Description : Export upscale — 64×64 → 256×256 by 1→4×4 index replication.

The 64×64 GIF is upscaled to 256×256 at export by replicating each source cell into
a @factor×factor@ block (nearest-neighbour, factor = 4). Crucially this happens in
the INDEX domain — each output cell copies a source palette INDEX — so:

  * the per-frame palette (the colour table) is byte-identical: replication adds no
    colour, so the GIF's Local Color Tables are untouched;
  * **no transparency is introduced**: every output cell carries a real source index,
    and the source is gated by 'SixFour.Spec.Significance' (every cell backed, no
    air), so 'lawReplicatePreservesUsedSet' carries that opacity guarantee up to 256².

This is a pure, population-preserving 16× scale (4² = 16): the brand/significance
gate stays on the 64×64 SOURCE volume, and replication is proven not to disturb it,
so re-proving at 256² is unnecessary.
-}
module SixFour.Spec.Export
  ( upscaleFactor
  , sourceSide
  , outputSide
  , replicate2D
    -- * Laws
  , lawReplicateLength
  , lawReplicatePreservesUsedSet
  , lawReplicateCountsScale
  ) where

import Data.List (nub, sort)

-- | The export upscale factor: 1 source pixel → a 4×4 output block.
upscaleFactor :: Int
upscaleFactor = 4

-- | The GIF source side (the working cube face).
sourceSide :: Int
sourceSide = 64

-- | The exported GIF side: @sourceSide * upscaleFactor = 256@.
outputSide :: Int
outputSide = sourceSide * upscaleFactor

-- | Replicate each cell of a @side×side@ row-major grid into a @factor×factor@
-- block, producing a @(factor·side)×(factor·side)@ row-major grid. Nearest-
-- neighbour in the INDEX domain: output cell @(ox,oy)@ copies source cell
-- @(ox \`div\` factor, oy \`div\` factor)@. No colour synthesis.
replicate2D :: Int -> Int -> [a] -> [a]
replicate2D factor side cells =
  [ cells !! (oy `div` factor * side + ox `div` factor)
  | oy <- [0 .. factor * side - 1]
  , ox <- [0 .. factor * side - 1]
  ]

-- * Laws

-- | The output has exactly @(factor·side)²@ cells (when the input is a full
-- @side²@ grid).
lawReplicateLength :: Int -> Int -> [a] -> Bool
lawReplicateLength factor side cells =
  length cells /= side * side
    || length (replicate2D factor side cells) == (factor * side) * (factor * side)

-- | Replication introduces NO new value and loses none — the set of indices is
-- exactly preserved. This is the opacity guarantee lifted to 256²: every output
-- cell is one of the source's (significance-backed, opaque) indices, never a new
-- (e.g. transparent) sentinel.
lawReplicatePreservesUsedSet :: Ord a => Int -> Int -> [a] -> Bool
lawReplicatePreservesUsedSet factor side cells =
  length cells /= side * side
    || sort (nub (replicate2D factor side cells)) == sort (nub cells)

-- | Each value's population scales by exactly @factor²@ — a uniform 16× (for
-- factor 4) magnification, so the per-frame significance counts scale uniformly
-- and the gate verdict is preserved.
lawReplicateCountsScale :: Eq a => Int -> Int -> [a] -> Bool
lawReplicateCountsScale factor side cells =
  length cells /= side * side || all scaled (nub cells)
  where
    out = replicate2D factor side cells
    count v xs = length (filter (== v) xs)
    scaled v = count v out == factor * factor * count v cells
