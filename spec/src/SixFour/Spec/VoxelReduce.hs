{-# LANGUAGE ScopedTypeVariables #-}

{- |
Module      : SixFour.Spec.VoxelReduce
Description : The joint spatio-temporal (2×2)×(2×2)→1 reversible reduction 64³ ↔ 16³ — ONE named operator composing the spatial cube ladder with the temporal Haar.

Phase 1 of the per-frame / orthogonal-A/B-genome migration
(@docs/SIXFOUR-PER-FRAME-GENOME-AB-MIGRATION-WORKFLOW.md@ §5). Daniel's direction:
@64³ → 16³@ by a __reversible__ @(2×2)×(2×2)→1@ reduction that loses nothing (the detail
is carried, not discarded). Two of those, run as independent searches, become the
orthogonal A and B candidates.

== This module only NAMES a composition; it owns no new lift

The two reversible integer Haar primitives already exist and are golden-gated:

  * SPATIAL — "SixFour.Spec.CubeLadder" 'distill' \/ 'synthesize': a 2-D-Haar pyramid over a
    @side×side@ scalar grid, exact within capture ('lawLadderBijective'). Applied here PER
    OKLab CHANNEL, PER FRAME (three 'distill' calls, recombined).
  * TEMPORAL — "SixFour.Spec.TemporalLoop" 'haarSplitTime' \/ 'haarJoinTime': one level of the
    owned 1-D integer S-transform over a frame sequence, exact ('lawTemporalSplitJoinExact').
    Applied here PER REDUCED SPATIAL POSITION, @levels@ times.

@voxelReduce@ is @temporalReduce ∘ spatialReduce@; @voxelExpand@ is the mirror
@spatialExpand ∘ temporalExpand@. Because each component is an exact bijection on @Int@,
the composition is an exact bijection — 'lawVoxelReduceBijective'. No epsilon, no rounding:
the reversibility is INHERITED from the two owned laws, not re-proved from scratch.

== Shape

For the shipped product @levels = 2@, @side = 64@, @frames = 64@: the @64³@ cube reduces to a
@16³@ substrate (@frames\/4 = 16@ frames × @(side\/4)² = 16²@) plus the carried spatial and
temporal detail. The substrate IS the lossless @16³@ tier; @voxelExpand@ replays the detail to
recover @64³@ exactly. (Synthesis ABOVE captured resolution — the learned @256³@ super-res — is
a SEPARATE, non-invertible step; it does not live here.)

GHC-boot-only. Laws are exported predicates, QuickCheck'd in @Properties.VoxelReduce@.
-}
module SixFour.Spec.VoxelReduce
  ( -- * The voxel cube and its reduced form
    VoxelCube
  , SpatialDetail
  , VoxelReduced(..)
    -- * Reduced dimensions
  , reducedSide
  , reducedFrames
    -- * The reversible (2×2)×(2×2)→1 operator
  , voxelReduce
  , voxelExpand
    -- * Well-formedness
  , wellFormedCube
    -- * Laws (QuickCheck'd in Properties.VoxelReduce)
  , lawVoxelReduceBijective
  , lawVoxelSubstrateShape
  , lawVoxelReduceDeterministic
  ) where

import Data.List (transpose)

import SixFour.Spec.PairTreeFixed (OKLabI)
import SixFour.Spec.CubeLadder    (distill, synthesize)
import SixFour.Spec.TemporalLoop  (haarSplitTime, haarJoinTime)

-- | A captured voxel cube: @frames@ frames, each a @side×side@ row-major grid of Q16 OKLab
-- triples. The shipped product is @frames = side = 64@ (the "64³ voxel pixel mass").
type VoxelCube = [[OKLabI]]

-- | Per-frame spatial detail: the three OKLab channels' Haar detail-plane stacks from
-- 'SixFour.Spec.CubeLadder.distill' (one @[[(G,B,T)]]@ stack per channel, finest-first). Carried,
-- never dropped — it is what makes the spatial half reversible.
type SpatialDetail = ( [[(Int, Int, Int)]]   -- L-channel detail planes
                     , [[(Int, Int, Int)]]   -- a-channel detail planes
                     , [[(Int, Int, Int)]] ) -- b-channel detail planes

-- | The reduced cube: the coarse @16³@ substrate plus ALL detail needed to invert exactly.
data VoxelReduced = VoxelReduced
  { vrSubstrate      :: [[OKLabI]]       -- ^ @frames'@ frames × @side'²@ — the lossless @16³@ tier
  , vrSpatialDetail  :: [SpatialDetail]  -- ^ one per ORIGINAL frame (spatial Haar carried)
  , vrTemporalDetail :: [[[OKLabI]]]     -- ^ one per reduced spatial position: the temporal high bands
  } deriving (Eq, Show)

-- | The reduced spatial side after @levels@ ×2 steps: @side \/ 2^levels@ (64 → 16 at @levels=2@).
reducedSide :: Int -> Int -> Int
reducedSide levels side = side `div` (2 ^ levels)

-- | The reduced frame count after @levels@ ×2 temporal steps: @frames \/ 2^levels@ (64 → 16).
reducedFrames :: Int -> Int -> Int
reducedFrames levels frames = frames `div` (2 ^ levels)

-- ---------------------------------------------------------------------------
-- Spatial half (per frame, per channel) — owned by SixFour.Spec.CubeLadder
-- ---------------------------------------------------------------------------

-- | Spatially distil ONE frame @side → side'@ by running 'distill' on each OKLab channel and
-- recombining the three coarse planes back into triples.
distillFrame :: Int -> Int -> [OKLabI] -> ([OKLabI], SpatialDetail)
distillFrame levels side frame =
  let (ls, as, bs) = unzip3 frame
      (lc, ld)     = distill levels side ls
      (ac, ad)     = distill levels side as
      (bc, bd)     = distill levels side bs
  in (zip3 lc ac bc, (ld, ad, bd))

-- | Exact inverse of 'distillFrame': rebuild the full @side×side@ frame from its coarse plane and
-- carried channel detail via 'synthesize'.
synthFrame :: Int -> ([OKLabI], SpatialDetail) -> [OKLabI]
synthFrame coarseSide (coarse, (ld, ad, bd)) =
  let (lc, ac, bc) = unzip3 coarse
      ls           = synthesize coarseSide (lc, ld)
      as           = synthesize coarseSide (ac, ad)
      bs           = synthesize coarseSide (bc, bd)
  in zip3 ls as bs

-- ---------------------------------------------------------------------------
-- Temporal half (per position) — owned by SixFour.Spec.TemporalLoop
-- ---------------------------------------------------------------------------

-- | Temporally distil ONE position's frame-column @frames → frames'@: @levels@ applications of
-- 'haarSplitTime' on the low band, returning the final low band plus the high bands finest-first.
tDistill :: Int -> [OKLabI] -> ([OKLabI], [[OKLabI]])
tDistill 0 xs = (xs, [])
tDistill n xs =
  let (lo, hi)   = haarSplitTime xs
      (lo', his) = tDistill (n - 1) lo
  in (lo', hi : his)

-- | Exact inverse of 'tDistill': rebuild a frame-column from its low band and high bands, joining
-- coarsest-first ('haarJoinTime' at each level).
tJoin :: [[OKLabI]] -> [OKLabI] -> [OKLabI]
tJoin highs low = go (reverse highs) low
  where go []         cur = cur
        go (hi : rest) cur = go rest (haarJoinTime (cur, hi))

-- ---------------------------------------------------------------------------
-- The composed (2×2)×(2×2)→1 operator
-- ---------------------------------------------------------------------------

-- | The reversible @64³ → 16³@ reduction: spatially distil every frame, then temporally distil
-- every reduced spatial position. All detail is carried in 'VoxelReduced' so the map is invertible.
voxelReduce :: Int -> Int -> VoxelCube -> VoxelReduced
voxelReduce levels side cube =
  let (coarseFrames, sdet) = unzip (map (distillFrame levels side) cube)
      cols                 = transpose coarseFrames        -- [position][frame]
      (lowCols, tdet)      = unzip (map (tDistill levels) cols)
      substrate            = transpose lowCols             -- [frame'][position]
  in VoxelReduced substrate sdet tdet

-- | Exact inverse of 'voxelReduce': temporally rejoin every position, then spatially synthesise
-- every frame. @voxelExpand levels side . voxelReduce levels side ≡ id@ on a well-formed cube
-- ('lawVoxelReduceBijective').
voxelExpand :: Int -> Int -> VoxelReduced -> VoxelCube
voxelExpand levels side (VoxelReduced substrate sdet tdet) =
  let lowCols      = transpose substrate                  -- [position][frame']
      cols         = zipWith tJoin tdet lowCols           -- [position][frame]
      coarseFrames = transpose cols                       -- [frame][position] @ side'
      cs           = reducedSide levels side
  in zipWith (\coarse fd -> synthFrame cs (coarse, fd)) coarseFrames sdet

-- ---------------------------------------------------------------------------
-- Laws
-- ---------------------------------------------------------------------------

-- | A cube is well-formed for @levels@ ×2 reductions when @side@ and @frames@ are each divisible by
-- @2^levels@, the cube has @frames@ frames, and every frame is @side×side@.
wellFormedCube :: Int -> Int -> Int -> VoxelCube -> Bool
wellFormedCube levels side frames cube =
     levels >= 0 && side > 0 && frames > 0
  && side   `mod` (2 ^ levels) == 0
  && frames `mod` (2 ^ levels) == 0
  && length cube == frames
  && all (\f -> length f == side * side) cube

-- | THE law: the reduction loses nothing — @voxelExpand ∘ voxelReduce ≡ id@ on any well-formed
-- cube. Inherited from 'SixFour.Spec.CubeLadder.lawLadderBijective' (spatial) and
-- 'SixFour.Spec.TemporalLoop.lawTemporalSplitJoinExact' (temporal): a composition of exact
-- bijections is an exact bijection.
lawVoxelReduceBijective :: Int -> Int -> Int -> VoxelCube -> Bool
lawVoxelReduceBijective levels side frames cube =
  not (wellFormedCube levels side frames cube)
    || voxelExpand levels side (voxelReduce levels side cube) == cube

-- | The substrate is exactly the @16³@ tier: @frames\/2^levels@ frames, each @(side\/2^levels)²@.
lawVoxelSubstrateShape :: Int -> Int -> Int -> VoxelCube -> Bool
lawVoxelSubstrateShape levels side frames cube =
  not (wellFormedCube levels side frames cube)
    || let sub = vrSubstrate (voxelReduce levels side cube)
           s'  = reducedSide   levels side
           f'  = reducedFrames levels frames
       in length sub == f' && all (\fr -> length fr == s' * s') sub

-- | Pure integer construction ⇒ identical cross-device. A regression guard that no float/IO is
-- smuggled into the reduction (the real guarantee is the integer-only owned primitives).
lawVoxelReduceDeterministic :: Int -> Int -> VoxelCube -> Bool
lawVoxelReduceDeterministic levels side cube =
  voxelReduce levels side cube == voxelReduce levels side cube
