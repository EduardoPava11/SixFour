{- |
Module      : SixFour.Spec.RenderSelect
Description : THE SELECT RENDER — rung 1 of The Loom, and the render that KEEPS the scales independent. Given three INDEPENDENT volumes (V16, V32, V64 — separate exposures, "SixFour.Spec.MultiScaleCapture") and a per-region depth field (CubeBrush's @depthField@, one depth per 4×4×4 region = the 16³ paint grid), produce ONE 64³ output where each region shows its CHOSEN scale's OWN measurement, block-replicated up to 64³ on the shared nested clock (16³ frame spans 4 output frames, 32³ spans 2 — the 4:2:1 cadence). Deterministic, byte-exact, no network: this is the "paint which evidence you want per region" render.

WHY IT IS *SELECT*, NOT *PULL* (the load-bearing distinction): "SixFour.Spec.PullField" renders by POOLING one volume to its block mean — it assumes the coarse view is DERIVED from the fine. RenderSelect instead READS the depth-d region from V_d, the scale's own independent volume, so a coarse region shows the long-exposure measurement DIRECTLY, unaffected by the fine one ('lawSelectReadsChosenSourceOnly'). The render preserves the independence the capture bought: the coarse pixels come from the outside world (V16), never from a pool of V64. The witness 'lawCoarseSelectsIndependentCoarse' pins this on a scene where @pool(V64) /= V16@ — exactly the independent case PullField could not express.

Isotropy: spatial block side and temporal replication share the 4:2:1 ratio (a depth-0 voxel is a 4×4×4 spacetime block), so a coarse region is constant across its 4-frame window ('lawTemporalReplicateOnSharedClock') — the render side of the shared clock. Depth 2 everywhere is the identity on V64 ('lawFineIsIdentity'); one region's depth moves only its own voxels ('lawSelectIsLocal'). Mirrored byte-exact by @Native/src/render_select.zig@ (s4_render_select).
-}
-- COMPARTMENT: PURE-SPEC-WALL | tag:none
module SixFour.Spec.RenderSelect
  ( -- * The three independent volumes and the select render
    outSide
  , blockSideAt
  , srcSideAt
  , volN
  , renderSelect
    -- * Laws
  , lawFineIsIdentity
  , lawCoarseSelectsIndependentCoarse
  , lawSelectReadsChosenSourceOnly
  , lawSelectIsLocal
  , lawTemporalReplicateOnSharedClock
  ) where

import SixFour.Spec.PullField (Field, regionOf, regionSide)

-- | The output cube side — the miniature 64³ (8³ so all three depths exist:
-- 4×4×4 / 2×2×2 / single-voxel blocks), matching PullField's test volume.
outSide :: Int
outSide = 8

-- | The spacetime block a depth-@d@ region replicates: 4 (16³), 2 (32³), 1 (64³).
blockSideAt :: Int -> Int
blockSideAt d = regionSide `div` (2 ^ max 0 (min 2 d))

-- | The side of the INDEPENDENT source volume read at depth @d@:
-- @outSide/blockSide@ = 2 (V16), 4 (V32), 8 (V64).
srcSideAt :: Int -> Int
srcSideAt d = outSide `div` blockSideAt d

-- | A side-@n@ volume from a flat @(t,y,x)@-major list (short lists pad 0).
volN :: Int -> [Integer] -> (Int, Int, Int) -> Integer
volN n xs (x, y, t) = padded !! ((t * n + y) * n + x)
  where padded = take (n * n * n) (xs ++ repeat 0)

-- | THE SELECT RENDER: each output voxel reads its region's CHOSEN scale from
-- that scale's own independent volume, block-replicated. @b = blockSideAt d@;
-- the source index is @(x\/b, y\/b, t\/b)@ (spatial AND temporal by the shared
-- 4:2:1 clock). NOT a pool — the three volumes are independent inputs.
renderSelect :: Field
             -> ((Int, Int, Int) -> Integer)   -- ^ V16 (side 2)
             -> ((Int, Int, Int) -> Integer)   -- ^ V32 (side 4)
             -> ((Int, Int, Int) -> Integer)   -- ^ V64 (side 8)
             -> (Int, Int, Int) -> Integer
renderSelect fld v16 v32 v64 (x, y, t) =
  let d = max 0 (min 2 (fld (regionOf (x, y, t))))
      b = blockSideAt d
      src = case d of
              0 -> v16
              1 -> v32
              _ -> v64
  in src (x `div` b, y `div` b, t `div` b)

allVoxels :: [(Int, Int, Int)]
allVoxels = [ (x, y, t) | t <- [0 .. outSide - 1], y <- [0 .. outSide - 1], x <- [0 .. outSide - 1] ]

-- helpers to build the three volumes for laws
mkV16, mkV32, mkV64 :: [Integer] -> (Int, Int, Int) -> Integer
mkV16 = volN 2
mkV32 = volN 4
mkV64 = volN 8

-- | LAW (full depth is the fine identity): depth 2 everywhere renders exactly
-- V64 — the untouched 64³ measurement.
lawFineIsIdentity :: [Integer] -> Bool
lawFineIsIdentity xs =
  and [ renderSelect (const 2) (mkV16 []) (mkV32 []) v64 p == v64 p | p <- allVoxels ]
  where v64 = mkV64 xs

-- | LAW (coarse reads the INDEPENDENT coarse volume, not a pool): depth 0
-- everywhere renders V16 block-replicated — verified against an independent 4×
-- replicate of V16, on a scene where the V16 measurement differs from any pool
-- of V64 (so the law is non-vacuous and could not be expressed by PullField).
lawCoarseSelectsIndependentCoarse :: [Integer] -> [Integer] -> Bool
lawCoarseSelectsIndependentCoarse xs16 xs64 =
  and [ renderSelect (const 0) v16 (mkV32 []) v64 (x, y, t) == v16 (x `div` 4, y `div` 4, t `div` 4)
      | (x, y, t) <- allVoxels ]
  where
    -- force independence: V16 is all 1, V64 is all 0 ⇒ pool(V64)=0 ≠ 1=V16.
    v16 = mkV16 (map (const 1) xs16 ++ [1])
    v64 = mkV64 (map (const 0) xs64)

-- | LAW (KEYSTONE — the render preserves independence): a region's output
-- depends ONLY on its chosen scale's volume. All-coarse output is invariant to
-- V64 (the coarse measurement stands on its own); all-fine output is invariant
-- to V16. The coarse pixels come from the outside world, never a derived pool.
lawSelectReadsChosenSourceOnly :: [Integer] -> [Integer] -> [Integer] -> [Integer] -> Bool
lawSelectReadsChosenSourceOnly a16 b64a b64b b16 =
  -- all-coarse: perturbing V64 changes nothing
  and [ renderSelect (const 0) v16 z32 v64a p == renderSelect (const 0) v16 z32 v64b p | p <- allVoxels ]
    -- all-fine: perturbing V16 changes nothing
    && and [ renderSelect (const 2) v16a z32 v64 p == renderSelect (const 2) v16b z32 v64 p | p <- allVoxels ]
  where
    z32 = mkV32 []
    v16 = mkV16 a16
    v64a = mkV64 b64a
    v64b = mkV64 (map (+ 1) b64a)   -- a genuinely different V64
    v16a = mkV16 b16
    v16b = mkV16 (map (+ 1) b16)
    v64 = mkV64 b64a

-- | LAW (one region, one block): raising a single region's depth changes output
-- voxels only inside that region; every other voxel is byte-identical.
lawSelectIsLocal :: Int -> [Integer] -> [Integer] -> [Integer] -> Bool
lawSelectIsLocal rRaw x16 x32 x64 =
  and [ regionOf p == r || base p == bumped p | p <- allVoxels ]
  where
    r = abs rRaw `mod` 8
    v16 = mkV16 x16; v32 = mkV32 x32; v64 = mkV64 x64
    base   = renderSelect (const 0) v16 v32 v64
    bumped = renderSelect (\q -> if q == r then 2 else 0) v16 v32 v64

-- | LAW (shared clock, render side): a depth-0 region is IDENTICAL across every
-- frame of its 4-frame window — the coarse scale's slow cadence, replicated in
-- output time. (The temporal half of isotropy; pairs with
-- SixFour.Spec.MultiScaleCapture lawSharedTimeIsNested.)
lawTemporalReplicateOnSharedClock :: [Integer] -> Bool
lawTemporalReplicateOnSharedClock xs =
  and [ r (x, y, t) == r (x, y, t + 1)
      | t <- [0 .. outSide - 2], y <- [0 .. outSide - 1], x <- [0 .. outSide - 1]
      , t `div` regionSide == (t + 1) `div` regionSide ]
  where r = renderSelect (const 0) (mkV16 xs) (mkV32 []) (mkV64 [])
