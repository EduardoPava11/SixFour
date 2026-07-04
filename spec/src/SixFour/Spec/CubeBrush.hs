{- |
Module      : SixFour.Spec.CubeBrush
Description : FORM FOLLOWS FUNCTION — paint returns, carrying RESOLUTION. The user paints with rung-typed brushes: a 16-brush lays 4×4×4 cubes (in 64³ terms), a 32-brush 2×2×2, a 64-brush voxels; strokes are a set of OVERLAPPING CUBES and the network constructs the 64³ GIF inside the granted volume. This module is the keystone of the change: the cube-set semantics in exact arithmetic.

THE SEMANTICS: a cube set induces a per-voxel depth field by POINTWISE MAX
(finest wins at overlaps, 'lawFinestWinsAtOverlap'). Max is a semilattice —
strokes COMMUTE and duplicates ABSORB ('lawStrokesCommuteAndAbsorb'), so the
input is order-free and undo-friendly by algebra, not by bookkeeping. A cube
moves only its own voxels ('lawCubeIsLocal' — the PullField locality,
survived).

THE AMBIGUITY OBJECTION, DISSOLVED ('lawTypedPaintHasFullBandwidth'): the
committed W1 binary mask provably underdetermines depth
("SixFour.Spec.ChoiceTraining" lawPaintUnderdeterminesDepth, 3^n fields on
2^n masks). Resolution-typed cubes are SURJECTIVE onto fields: every region
field is realized by a canonical cube set (all d-blocks of each region at its
depth), and the induced voxel render agrees with the PullField region render
— typed paint says WHERE and HOW DEEP in one gesture. Choice
("Spec.ChoiceTraining") is re-scoped, not retired: it trains TASTE on what
the user didn't say (the network's proposals), while cubes are the user's
direct, full-bandwidth channel.

WHY THE NETWORK MUST CONSTRUCT (the honest pair):
  * 'lawWholeBlockDeepeningImprovesFidelity': adding a cube over UNIFORMLY
    shallower voxels never increases the exact SSE (the sub-block mean is the
    L2-optimal constant) — clean refinement is monotone, as in
    "SixFour.Spec.FidelityLadder".
  * TEETH 'lawOverlapPullCanRegress': with OVERLAPPING freeform cubes,
    pull-only rendering can STRICTLY REGRESS fidelity (exact witness: an
    exactly-rendered outlier pollutes the finer mean its neighbours get
    pulled to). So the pull is only the FLOOR; inside granted cubes the
    NETWORK (θ_up invention, gated exactly like the committed W1 arm)
    constructs the content. "We let the network construct the 64³ GIF" is
    not a preference — the algebra forces it.

PORT MAP (docs/CUBE-BRUSH-PLAN.md): the W1 mask becomes the depth ≥ 1
superlevel set of the cube field, and the per-transition invention masks are
the nested superlevels ({depth ≥ 2} ⊆ {depth ≥ 1}, automatic from max) — the
committed gate machinery is REUSED, fed by a richer input. Backward
compatible: an old binary mask is exactly a cube set of depth-2 cubes.
-}
-- COMPARTMENT: PURE-SPEC-WALL | tag:none
module SixFour.Spec.CubeBrush
  ( -- * Cubes and the induced voxel field
    Cube (..)
  , cubeSideOf
  , coversVoxel
  , depthField
    -- * The pull floor over a voxel field, and exact fidelity
  , renderPullV
  , sseQV
    -- * The canonical realization of a region field
  , canonicalCubes
    -- * Laws
  , lawStrokesCommuteAndAbsorb
  , lawFinestWinsAtOverlap
  , lawCubeIsLocal
  , lawTypedPaintHasFullBandwidth
  , lawWholeBlockDeepeningImprovesFidelity
  , lawOverlapPullCanRegress
  ) where

import Data.Ratio ((%))

import SixFour.Spec.PullField
  ( Volume, volumeFromList, Field, regionOf, renderPull, side )

-- | One stroke: a depth-typed cube, origin in BLOCK coordinates of its own
-- grid (alignment by construction — a d-cube sits on the d-grid).
data Cube = Cube
  { cubeDepth  :: Int              -- ^ 0 = 16-rung (4³), 1 = 32-rung (2³), 2 = 64-rung (voxel)
  , cubeOrigin :: (Int, Int, Int)  -- ^ block coordinates on the cube's own grid
  } deriving (Eq, Show)

-- | Voxel side of a depth-d cube in the 8³ test volume: 4, 2, 1.
cubeSideOf :: Int -> Int
cubeSideOf d = 4 `div` (2 ^ max 0 (min 2 d))

-- | Does a cube cover a voxel?
coversVoxel :: Cube -> (Int, Int, Int) -> Bool
coversVoxel (Cube d (ox, oy, ot)) (x, y, t) =
  x `div` b == ox && y `div` b == oy && t `div` b == ot
  where b = cubeSideOf d

-- | The induced per-voxel depth: the MAX depth of the covering cubes
-- (finest wins), floor 0 where nothing covers.
depthField :: [Cube] -> (Int, Int, Int) -> Int
depthField cs p = maximum (0 : [ max 0 (min 2 (cubeDepth c)) | c <- cs, coversVoxel c p ])

-- | The pull FLOOR over a per-voxel field: each voxel takes the round-half-up
-- mean of its own depth-block (generalizes PullField's region render to voxel
-- granularity; the network's invention rides above this floor).
renderPullV :: ((Int, Int, Int) -> Int) -> Volume -> Volume
renderPullV f v (x, y, t) =
  let b  = cubeSideOf (f (x, y, t))
      x0 = (x `div` b) * b
      y0 = (y `div` b) * b
      t0 = (t `div` b) * b
      n  = fromIntegral (b * b * b) :: Integer
      s  = sum [ v (x0 + i, y0 + j, t0 + k)
               | i <- [0 .. b - 1], j <- [0 .. b - 1], k <- [0 .. b - 1] ]
  in (s + n `div` 2) `div` n

allVoxels :: [(Int, Int, Int)]
allVoxels = [ (x, y, t) | t <- [0 .. side - 1], y <- [0 .. side - 1], x <- [0 .. side - 1] ]

-- | Exact squared error of the pull floor against the truth (rational means,
-- no rounding — the structural quantity).
sseQV :: ((Int, Int, Int) -> Int) -> Volume -> Rational
sseQV f v = sum [ (fromInteger (v p) - meanQ p) ^ (2 :: Int) | p <- allVoxels ]
  where
    meanQ (x, y, t) =
      let b  = cubeSideOf (f (x, y, t))
          x0 = (x `div` b) * b
          y0 = (y `div` b) * b
          t0 = (t `div` b) * b
          s  = sum [ v (x0 + i, y0 + j, t0 + k)
                   | i <- [0 .. b - 1], j <- [0 .. b - 1], k <- [0 .. b - 1] ]
      in s % fromIntegral (b * b * b)

-- | The canonical cube set realizing a region field: every d-block of each
-- region at the region's depth (depth-0 regions need no cubes — the floor).
canonicalCubes :: Field -> [Cube]
canonicalCubes f =
  [ Cube d (bx, by, bt)
  | rt <- [0, 1], ry <- [0, 1], rx <- [0, 1]
  , let r = (rt * 2 + ry) * 2 + rx
  , let d = max 0 (min 2 (f r))
  , d > 0
  , let b = cubeSideOf d
  , let per = 4 `div` b
  , bx <- [ rx * per .. rx * per + per - 1 ]
  , by <- [ ry * per .. ry * per + per - 1 ]
  , bt <- [ rt * per .. rt * per + per - 1 ]
  ]

-- | LAW (order-free, undo-friendly by algebra): strokes COMMUTE and
-- duplicates ABSORB — the induced field depends on the SET of cubes, never
-- the stroke order or repetition. Max is a semilattice.
lawStrokesCommuteAndAbsorb :: [Cube] -> Bool
lawStrokesCommuteAndAbsorb cs =
  and [ depthField (cs ++ reverse cs) p == depthField cs p | p <- allVoxels ]
    && and [ depthField (reverse cs) p == depthField cs p | p <- allVoxels ]

-- | LAW (finest wins): where cubes overlap, the induced depth is the MAX —
-- checked constructively on an overlapping pair.
lawFinestWinsAtOverlap :: Bool
lawFinestWinsAtOverlap =
  depthField [big, fine] (0, 0, 0) == 2      -- overlap: the fine cube wins
    && depthField [big, fine] (1, 1, 1) == 1 -- rest of the big cube: its own depth
    && depthField [big, fine] (7, 7, 7) == 0 -- uncovered: the floor
  where
    big  = Cube 1 (0, 0, 0)   -- the 2³ block at the origin (voxels 0..1 per axis)
    fine = Cube 2 (0, 0, 0)   -- the origin voxel alone

-- | LAW (a cube moves only its own voxels): adding a cube changes the pull
-- floor ONLY inside the cube; everywhere else is byte-identical.
lawCubeIsLocal :: Int -> (Int, Int, Int) -> [Cube] -> [Integer] -> Bool
lawCubeIsLocal dRaw oRaw cs xs =
  and [ coversVoxel c p || before p == after p | p <- allVoxels ]
  where
    d = abs dRaw `mod` 3
    b = cubeSideOf d
    per = 8 `div` b
    (ox, oy, ot) = oRaw
    c = Cube d (abs ox `mod` per, abs oy `mod` per, abs ot `mod` per)
    v = volumeFromList xs
    before = renderPullV (depthField cs) v
    after  = renderPullV (depthField (c : cs)) v

-- | LAW (the pigeonhole dissolved): resolution-typed paint is SURJECTIVE
-- onto region fields — the canonical cube set induces exactly the region
-- field, and its voxel render agrees with the PullField region render.
-- Typed paint says WHERE and HOW DEEP in one gesture; binary masks cannot
-- (ChoiceTraining's lawPaintUnderdeterminesDepth is the contrast).
lawTypedPaintHasFullBandwidth :: [Int] -> [Integer] -> Bool
lawTypedPaintHasFullBandwidth ds xs =
  and [ depthField cubes p == fld (regionOf p) | p <- allVoxels ]
    && and [ renderPullV (depthField cubes) v p == renderPull fld v p | p <- allVoxels ]
  where
    fld r = max 0 (min 2 (take 8 (ds ++ repeat 0) !! max 0 (min 7 r)))
    cubes = canonicalCubes fld
    v = volumeFromList xs

-- | LAW (clean refinement is monotone): adding a cube whose voxels were all
-- at a UNIFORMLY shallower depth never increases the exact SSE — the new
-- block mean is the L2-optimal constant over the voxels it claims
-- (FidelityLadder's descent, per stroke).
lawWholeBlockDeepeningImprovesFidelity :: Int -> (Int, Int, Int) -> [Integer] -> Bool
lawWholeBlockDeepeningImprovesFidelity dRaw oRaw xs =
  sseQV (depthField [c]) v <= sseQV (depthField []) v
  where
    d = 1 + abs dRaw `mod` 2                  -- deepen from the uniform floor
    b = cubeSideOf d
    per = 8 `div` b
    (ox, oy, ot) = oRaw
    c = Cube d (abs ox `mod` per, abs oy `mod` per, abs ot `mod` per)
    v = volumeFromList xs

-- | TEETH (why the NETWORK constructs): with OVERLAPPING cubes, pull-only
-- rendering can STRICTLY REGRESS. Witness: one voxel holds an outlier under
-- a depth-2 cube (renders exact); adding a depth-1 cube over its 2-block
-- pulls the 7 neighbours toward the outlier-polluted fine mean — SSE goes UP.
-- The pull is only the floor; inside granted cubes the network invents.
lawOverlapPullCanRegress :: Bool
lawOverlapPullCanRegress =
  sseQV (depthField [outlier, overlap]) v > sseQV (depthField [outlier]) v
  where
    -- volume: zeros everywhere except value 800 at the origin voxel
    v p = if p == (0, 0, 0) then 800 else 0
    outlier = Cube 2 (0, 0, 0)   -- the outlier voxel, rendered exact
    overlap = Cube 1 (0, 0, 0)   -- the user's overlapping coarser stroke
