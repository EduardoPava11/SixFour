{- |
Module      : SixFour.Spec.PullField
Description : INFLUENCE IS THE GAME — all three rungs coexist in ONE GIF89a as a per-region resolution field. A region under 16-rung influence renders as a 4×4×4 voxel PULLED to one color; under 32-rung influence as 2×2×2 pulls; under full 64-rung influence, pixel-exact. The mixed render is a single 64-canvas, 64-frame, delay-5 GIF — no format extension: a coarse pull is just BLOCK-REPLICATED indices, and the standard rewards it twice ('lawInteriorRunsAreFree': a pulled block contributes ZERO interior index transitions, so LZW pays almost nothing for coarseness; 'lawTemporalPullSkipsFrames': a pulled block is IDENTICAL across its 4-frame window, so the per-frame Image Descriptor's changed-rectangle can omit it entirely). Bytes follow influence.

(Naming: NOT "SixFour.Spec.InfluenceField" — that existing module owns the
decorative radiation-ground UI tunables; this one owns the RESOLUTION pull.)

The field is the HALTING FIELD made visible: depth(region) ∈ {0,1,2} is the
rung the region halted at (0 = 16-rung / 4×4×4 pull, 1 = 32-rung / 2×2×2,
2 = 64-rung / free), fed by exactly the machinery already landed — the
certified kinematic order ("SixFour.Spec.KinematicHaltPrior": regions whose
window certifies low order NEED no detail), the concentrated-block skip
("SixFour.Spec.TriScaleTraining": W = 1 blocks CARRY no detail), and the
user's paint ("SixFour.Spec.ModelForward", the committed W1 gate: paint says
where influence is ALLOWED). The render-side laws mirror the paint laws
one-for-one: 'lawZeroInfluenceIsCoarsePull' is lawZeroPaintVolumeIsFloor seen
from the pixels (no influence anywhere == the block-replicated 16-rung, the
deterministic floor); 'lawFullInfluenceIsIdentity' (full influence == the 64³
untouched); 'lawInfluenceIsLocal' (raising one region's depth moves ONLY that
region's pixels — one painted cell, one block, now in render space).

The pull itself is the sums carrier realized: a region's pulled color is the
round-half-up mean of its block (@Native/palette16.zig@ s4_sums_to_srgb8
semantics) — the coarse look "pops" at print not because resolution is stored
anywhere but because the pull is COMPUTED from the colors it governs.
Resolution is emergent from influence, never a stored property.

HONEST BOUNDARY: this gates the RENDER algebra (which pixels a field moves,
what the standard charges). The GIF wire realization (LZW sub-blocks,
changed-rect packing) lives in kernels.zig s4_gif_assemble under its own byte
goldens; the pull field only ever changes INDICES, never the GCT. Graded
(fractional) influence — energy-weighted pulls over the V2.1 curves — is
design headroom, deliberately not landed: this module is the binary field.
-}
-- COMPARTMENT: PURE-SPEC-WALL | tag:none
module SixFour.Spec.PullField
  ( -- * The volume and the field
    side
  , regionSide
  , Volume
  , volumeFromList
  , Field
  , regionOf
    -- * The render: pull each region to its rung
  , renderPull
    -- * Laws
  , lawFullInfluenceIsIdentity
  , lawZeroInfluenceIsCoarsePull
  , lawInfluenceIsLocal
  , lawInteriorRunsAreFree
  , lawTemporalPullSkipsFrames
  ) where

-- | The miniature test volume: an 8³ stand-in for the 64³ GIF (same algebra,
-- 8 = 2³ so all three depths exist: 4×4×4 pulls, 2×2×2 pulls, free voxels).
side :: Int
side = 8

-- | The field's granularity: one depth per 4×4×4 region (the 16-rung block —
-- the coarsest pull, "the 16×16 with 4×4×4 voxel pulls").
regionSide :: Int
regionSide = 4

-- | A volume assigns a value (a palette index / channel byte) to each voxel.
type Volume = (Int, Int, Int) -> Integer

-- | Build a volume from a flat list in (t-major, then y, then x) order;
-- short lists pad with 0. The QuickCheck-friendly constructor.
volumeFromList :: [Integer] -> Volume
volumeFromList xs (x, y, t) = padded !! ((t * side + y) * side + x)
  where padded = take (side * side * side) (xs ++ repeat 0)

-- | The influence field: a depth 0..2 per 4×4×4 region, region-major
-- (rt·4 + ry·2 + rx over the 2×2×2 grid of regions in the 8³ volume).
type Field = Int -> Int

-- | Which region a voxel belongs to.
regionOf :: (Int, Int, Int) -> Int
regionOf (x, y, t) =
  ((t `div` regionSide) * 2 + (y `div` regionSide)) * 2 + (x `div` regionSide)

-- | The block a voxel is pulled to at depth d: side 4 at depth 0, 2 at
-- depth 1, 1 (itself) at depth 2.
blockSideAt :: Int -> Int
blockSideAt d = regionSide `div` (2 ^ max 0 (min 2 d))

-- | THE RENDER: every voxel takes the round-half-up mean of its depth-block —
-- the PULL toward one color. Depth-2 blocks are single voxels (identity);
-- depth-0 blocks are 4×4×4 = 64 voxels sharing one pulled color.
renderPull :: Field -> Volume -> Volume
renderPull field v (x, y, t) =
  let d  = field (regionOf (x, y, t))
      b  = blockSideAt d
      x0 = (x `div` b) * b
      y0 = (y `div` b) * b
      t0 = (t `div` b) * b
      n  = fromIntegral (b * b * b) :: Integer
      s  = sum [ v (x0 + i, y0 + j, t0 + k)
               | i <- [0 .. b - 1], j <- [0 .. b - 1], k <- [0 .. b - 1] ]
  in (s + n `div` 2) `div` n

allVoxels :: [(Int, Int, Int)]
allVoxels = [ (x, y, t) | t <- [0 .. side - 1], y <- [0 .. side - 1], x <- [0 .. side - 1] ]

-- | LAW: full influence everywhere is the identity — the 64-rung untouched.
lawFullInfluenceIsIdentity :: [Integer] -> Bool
lawFullInfluenceIsIdentity xs =
  and [ renderPull (const 2) v p == v p | p <- allVoxels ]
  where v = volumeFromList xs

-- | LAW (the floor, render-side): zero influence everywhere is the coarse
-- pull — every 4×4×4 region flat at its round-half-up mean, verified against
-- an INDEPENDENT pool-then-replicate implementation. This is
-- lawZeroPaintVolumeIsFloor seen from the pixels.
lawZeroInfluenceIsCoarsePull :: [Integer] -> Bool
lawZeroInfluenceIsCoarsePull xs =
  and [ renderPull (const 0) v p == replicated p | p <- allVoxels ]
  where
    v = volumeFromList xs
    replicated (x, y, t) =
      let x0 = (x `div` 4) * 4; y0 = (y `div` 4) * 4; t0 = (t `div` 4) * 4
          s = sum [ v (x0 + i, y0 + j, t0 + k)
                  | i <- [0 .. 3], j <- [0 .. 3], k <- [0 .. 3] ]
      in (s + 32) `div` 64

-- | LAW (one region, one block — the paint law in render space): raising a
-- single region's depth changes pixels ONLY inside that region; every other
-- voxel is byte-identical.
lawInfluenceIsLocal :: Int -> [Integer] -> Bool
lawInfluenceIsLocal rRaw xs =
  and [ regionOf p == r || base p == bumped p | p <- allVoxels ]
  where
    r = abs rRaw `mod` 8
    v = volumeFromList xs
    base   = renderPull (const 0) v
    bumped = renderPull (\q -> if q == r then 2 else 0) v

-- | LAW (bytes follow influence, the spatial half): a depth-0 region has ZERO
-- interior index transitions on every scanline — flat runs are what LZW
-- compresses to almost nothing. Coarse pulls are nearly free on the wire.
lawInteriorRunsAreFree :: [Integer] -> Bool
lawInteriorRunsAreFree xs =
  and [ r (x, y, t) == r (x + 1, y, t)
      | t <- [0 .. side - 1], y <- [0 .. side - 1], x <- [0 .. side - 2]
      , x `div` regionSide == (x + 1) `div` regionSide ]
  where r = renderPull (const 0) (volumeFromList xs)

-- | LAW (bytes follow influence, the temporal half): a depth-0 region is
-- IDENTICAL across every frame of its 4-frame window — so GIF89a's per-frame
-- changed-rectangle (the Image Descriptor sub-rect) can omit it entirely.
-- Temporal coarseness = frames that need not be rewritten.
lawTemporalPullSkipsFrames :: [Integer] -> Bool
lawTemporalPullSkipsFrames xs =
  and [ r (x, y, t) == r (x, y, t + 1)
      | t <- [0 .. side - 2], y <- [0 .. side - 1], x <- [0 .. side - 1]
      , t `div` regionSide == (t + 1) `div` regionSide ]
  where r = renderPull (const 0) (volumeFromList xs)
