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

__Act IV — the global pack {16³, 64³, 256³}__ (see @docs/SIXFOUR-PALETTE-STORY-WORKFLOW.md@).
The committed global palette renders at three rungs of the ×4 cube ladder, all from the ONE
64³ index cube (GIFB): GIFC 16³ = 'downsample2D' (4×4 block __mode__ — the dominant index per
block, gamut-closed), GIFB 64³ = identity, GIFD 256³ = 'replicate2D'. @16 = 64/4@, @256 = 64·4@,
so the pack is @{16,64,256}@ spatially and in frames. The downsample is index-domain too (mode
picks an actual block index — no colour invented), so GIFC shares GIFB's exact palette.
-}
module SixFour.Spec.Export
  ( upscaleFactor
  , sourceSide
  , outputSide
  , previewSide
  , packSides
  , replicate2D
  , downsample2D
    -- * Laws
  , lawReplicateLength
  , lawReplicatePreservesUsedSet
  , lawReplicateCountsScale
  , lawDownsampleLength
  , lawDownsampleGamutClosed
  , lawDownsampleConstantBlock
  , lawCubeLadder
  ) where

import Data.List (nub, sort, group)

-- | The export upscale factor: 1 source pixel → a 4×4 output block.
upscaleFactor :: Int
upscaleFactor = 4

-- | The GIF source side (the working cube face).
sourceSide :: Int
sourceSide = 64

-- | The exported GIF side: @sourceSide * upscaleFactor = 256@.
outputSide :: Int
outputSide = sourceSide * upscaleFactor

-- | The preview (GIFC) side: @sourceSide \`div\` upscaleFactor = 16@.
previewSide :: Int
previewSide = sourceSide `div` upscaleFactor

-- | The global pack's three spatial rungs of the ×4 cube ladder: @[16, 64, 256]@ (= frame counts too).
packSides :: [Int]
packSides = [previewSide, sourceSide, outputSide]

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

-- ---------------------------------------------------------------------------
-- GIFC downsample (64² → 16²): the dual of 'replicate2D', in the index domain
-- ---------------------------------------------------------------------------

-- | Downsample a @side×side@ row-major grid to @(side\`div\`factor)×(side\`div\`factor)@ by taking, for
-- each @factor×factor@ source block, its __mode__ (most frequent index; ties resolve to the lowest index
-- — a total, device-stable rule). Index-domain, so the output uses only source indices (gamut-closed):
-- GIFC shares GIFB's exact global palette, no colour invented.
downsample2D :: Ord a => Int -> Int -> [a] -> [a]
downsample2D factor side cells =
  [ modeLowest [ cells !! ((by * factor + dy) * side + (bx * factor + dx))
               | dy <- [0 .. factor - 1], dx <- [0 .. factor - 1] ]
  | by <- [0 .. side `div` factor - 1]
  , bx <- [0 .. side `div` factor - 1]
  ]

-- | Most frequent element; ties broken toward the smallest (the runs are value-ascending, so the first
-- max-count run is the least value with that count).
modeLowest :: Ord a => [a] -> a
modeLowest xs =
  let runs     = map (\g -> (length g, head g)) (group (sort xs))
      maxCount = maximum (map fst runs)
  in head [ v | (c, v) <- runs, c == maxCount ]

-- | Downsampling a full @side²@ grid yields exactly @(side\`div\`factor)²@ cells.
lawDownsampleLength :: Ord a => Int -> Int -> [a] -> Bool
lawDownsampleLength factor side cells =
  factor <= 0 || side `mod` factor /= 0 || length cells /= side * side
    || length (downsample2D factor side cells) == (side `div` factor) * (side `div` factor)

-- | The downsample invents NO colour — its index set is a subset of the source's (mode picks an actual
-- block index). This is what lets GIFC reuse GIFB's exact global palette.
lawDownsampleGamutClosed :: Ord a => Int -> Int -> [a] -> Bool
lawDownsampleGamutClosed factor side cells =
  factor <= 0 || side `mod` factor /= 0 || length cells /= side * side
    || all (`elem` nub cells) (downsample2D factor side cells)

-- | A constant grid downsamples to that same single value, repeated @(side\`div\`factor)²@ times.
lawDownsampleConstantBlock :: Int -> Int -> Int -> Bool
lawDownsampleConstantBlock factor side v =
  factor <= 0 || side <= 0 || side `mod` factor /= 0
    || downsample2D factor side (replicate (side * side) v)
         == replicate ((side `div` factor) * (side `div` factor)) v

-- | The ×4 cube ladder is exact: @previewSide·factor = sourceSide@ and @sourceSide·factor = outputSide@,
-- so the pack is @[16, 64, 256]@.
lawCubeLadder :: Bool
lawCubeLadder =
     previewSide * upscaleFactor == sourceSide
  && sourceSide * upscaleFactor == outputSide
  && packSides == [16, 64, 256]
