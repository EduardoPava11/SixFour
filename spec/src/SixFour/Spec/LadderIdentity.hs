{- |
Module      : SixFour.Spec.LadderIdentity
Description : Disambiguate the two operators both called "cube ladder" and PIN one (VolumeOctant) as the learned token substrate — closes gap B2.

The design audit (workflow @wg1bfjk5s@) found a blocker: __two different operators
share the name "cube ladder"__ and the losslessness argument silently inherited
whichever was wired.

  * "SixFour.Spec.CubeLadder" is a __2-D Haar__ over a @side×side@ SCALAR plane
    (one OKLab channel, one feature frame): each 'SixFour.Spec.CubeLadder.liftLevel'
    is ×2 linear = ×4 AREA, detail is a @(G,B,T)@ 3-tuple.
  * "SixFour.Spec.OctreeCell" is a __3-D octant__ ladder over an @8^d@ VOLUME: each
    'SixFour.Spec.OctreeCell.octantStep' is ×2 linear = ×8 VOLUME, detail is a
    7-tuple, and @16³=8^4@, @64³=8^6@, @256³=8^8@.

They are NOT interchangeable (different volume factor, different detail shape, a
plane vs a voxel mass), so the next-scale token sequence cannot be both. This
module makes the distinction a PROOF (the laws destructure the real operators) and
pins the role-split that resolves B2 __without deleting either__:

  * 'tokenSubstrate' = 'VolumeOctant' — THE canonical learned scale ladder the
    L-trunk autoregresses over (the @16³/64³/256³@ voxel rungs are its tiers).
  * 'withinRungOp' = 'SpatialHaar' — DEMOTED to the bit-exact within-rung reversible
    integer op (Zig-owned), per channel per frame. It stops competing as a ladder.

The role-split closes the tension by giving each operator one job (learned
substrate vs bit-exact decode), not by deletion — additive, golden-safe.
-}
module SixFour.Spec.LadderIdentity
  ( -- * The two operators, named apart
    Ladder(..)
    -- * Their distinguishing invariants
  , levelLinearFactor
  , levelVolumeFactor
  , detailBandCount
  , levelsPerRung
    -- * The pinned role-split (B2 resolution)
  , tokenSubstrate
  , withinRungOp
    -- * Tier shapes (volume vs plane)
  , octantTierLeaves
  , haarTierCells
    -- * Laws (QuickCheck'd in @Properties.LadderIdentity@)
  , lawDistinctVolumeFactor
  , lawDistinctDetailShape
  , lawSameLevelsPerRung
  , lawVolumeRungsAreOctant
  , lawHaarTierIsPlaneNotVolume
  , lawTokenSubstrateIsOctant
  , lawLadderSelfSimilarShared
  ) where

import SixFour.Spec.RGBTLift  (liftQuad)
import SixFour.Spec.OctreeCell
  ( V8(..), OctBand(..), liftOct
  , octreeDepth, levelsBetween, lawLadderSelfSimilar
  )

-- | The two distinct operators that were both being called "cube ladder".
data Ladder
  = SpatialHaar    -- ^ "SixFour.Spec.CubeLadder": 2-D Haar over a scalar plane (×4 area, 3 detail).
  | VolumeOctant   -- ^ "SixFour.Spec.OctreeCell": 3-D octant over a voxel volume (×8 volume, 7 detail).
  deriving (Eq, Show, Enum, Bounded)

-- | Linear (per-axis) shrink of ONE level — ×2 for both (this is the only thing
-- they share, and it is why both have @levelsPerRung == 2@).
levelLinearFactor :: Ladder -> Int
levelLinearFactor _ = 2

-- | The data-volume factor of ONE level: ×4 (area, 2-D plane) for 'SpatialHaar',
-- ×8 (volume, 3-D voxel mass) for 'VolumeOctant'. The factor that proves they are
-- different operators.
levelVolumeFactor :: Ladder -> Int
levelVolumeFactor SpatialHaar  = 4
levelVolumeFactor VolumeOctant = 8

-- | The number of detail sub-bands one level emits: @(G,B,T)@ = 3 for 'SpatialHaar'
-- ("SixFour.Spec.RGBTLift"), the 7 octant sub-bands for 'VolumeOctant'
-- ("SixFour.Spec.OctreeCell"'s 'OctBand').
detailBandCount :: Ladder -> Int
detailBandCount SpatialHaar  = 3
detailBandCount VolumeOctant = 7

-- | A cube-ladder __rung__ (@16³↔64³↔256³@, ×4 linear) is exactly 2 levels of
-- either operator — the self-similarity that lets ONE operator cover every rung.
levelsPerRung :: Int
levelsPerRung = 2

-- | THE pinned learned scale ladder (the L-trunk's next-scale token substrate).
tokenSubstrate :: Ladder
tokenSubstrate = VolumeOctant

-- | The demoted operator: the within-rung bit-exact reversible integer op
-- (Zig-owned, per channel per frame), no longer a competing ladder.
withinRungOp :: Ladder
withinRungOp = SpatialHaar

-- | The octant leaf count of a power-of-two linear dim @d@ — the size of the @d³@
-- VOLUME as @8^(octreeDepth d)@ (e.g. @octantTierLeaves 16 = 8^4 = 4096 = 16³@).
octantTierLeaves :: Int -> Int
octantTierLeaves d = 8 ^ octreeDepth d

-- | The Haar tier cell count for a linear side @s@ — a @s×s@ PLANE (per channel,
-- per frame), @s²@, NOT a volume.
haarTierCells :: Int -> Int
haarTierCells s = s * s

-- ============================================================================
-- Laws (predicates; QuickCheck'd in Properties.LadderIdentity)
-- ============================================================================

-- | The two operators have different per-level data factors (4 ≠ 8): they are NOT
-- the same operator wearing one name.
lawDistinctVolumeFactor :: Bool
lawDistinctVolumeFactor =
  levelVolumeFactor SpatialHaar /= levelVolumeFactor VolumeOctant

-- | The detail shapes differ, PROVEN by destructuring the real operators: a
-- 'liftQuad' emits 3 detail bands @(G,B,T)@, a 'liftOct' emits 7 ('ocDetail'), and
-- the constants 'detailBandCount' record exactly those arities.
lawDistinctDetailShape :: V8 Int -> (Int,Int,Int,Int) -> Bool
lawDistinctDetailShape v q =
  let OctBand _ (a,b,c,d,e,f,g) = liftOct v
      (_, g', b', t')           = liftQuad q
  in length [a,b,c,d,e,f,g] == detailBandCount VolumeOctant
     && length [g', b', t']  == detailBandCount SpatialHaar
     && detailBandCount SpatialHaar /= detailBandCount VolumeOctant

-- | Both operators reach a rung in 'levelsPerRung' steps (delegates to
-- 'levelsBetween'): @levelsBetween 64 16 == levelsBetween 256 64 == 2@. This shared
-- self-similarity is why pinning ONE operator (the octant) covers every rung.
lawSameLevelsPerRung :: Bool
lawSameLevelsPerRung =
  levelsBetween 64 16 == levelsPerRung && levelsBetween 256 64 == levelsPerRung

-- | The voxel rungs are octant tiers: @octantTierLeaves d == d³@ for the canonical
-- rungs (so @16³/64³/256³@ as VOLUMES are produced only by 'VolumeOctant').
lawVolumeRungsAreOctant :: Bool
lawVolumeRungsAreOctant =
  all (\d -> octantTierLeaves d == d * d * d) [16, 64, 256]

-- | A power of two (the domain on which 'octreeDepth' is exact: @2^octreeDepth s == s@).
isPow2 :: Int -> Bool
isPow2 s = s > 0 && 2 ^ octreeDepth s == s

-- | A Haar tier is a PLANE (@s²@); the octant tier is the VOLUME (@s³@); they differ.
-- Restricted to powers of two (where @octantTierLeaves s = 8^octreeDepth s = s³@
-- genuinely), so the inequality holds because plane ≠ volume — not by luck off the
-- 'octreeDepth' grid.
lawHaarTierIsPlaneNotVolume :: Int -> Bool
lawHaarTierIsPlaneNotVolume s =
  not (s > 1 && isPow2 s)
    || (haarTierCells s == s * s
        && octantTierLeaves s == s * s * s
        && haarTierCells s /= octantTierLeaves s)

-- | The B2 decision, pinned: the token substrate is the octant, the demoted op is
-- the Haar, and they are distinct roles.
lawTokenSubstrateIsOctant :: Bool
lawTokenSubstrateIsOctant =
  tokenSubstrate == VolumeOctant
    && withinRungOp == SpatialHaar
    && tokenSubstrate /= withinRungOp

-- | Re-states "SixFour.Spec.OctreeCell"'s @16³:64³::64³:256³@ self-similarity as the
-- justification for one shared operator across all rungs.
lawLadderSelfSimilarShared :: Bool
lawLadderSelfSimilarShared = lawLadderSelfSimilar
