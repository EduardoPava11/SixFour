-- COMPARTMENT: MLX-MODEL | tag:MacTag
{- |
Module      : SixFour.Spec.TriScaleBench
Description : The tri-scale comparison contract — a 16³ change is comparable to a 256³ change ONLY at the coarse band, via a tail-INDEPENDENT re-downsample round-trip. The spec object the Tri-Scale Linked-Delta Bench stands on.

The design language shows three rungs at once (16³ editable / 64³ deterministic preview / 256³
shipped) and lets the user compare a change at 16³ to its change at 256³. That comparison is only
WELL-POSED at the coarse band: the up-direction INVENTS detail (the latent tail), so a single 16³
seed determines a whole FAMILY of 256³ cubes, and the invented detail has no 16³ pre-image. What IS
well-posed: re-downsampling the 256³ back to a coarser rung recovers the lower rung EXACTLY, and
that recovery is BLIND to the invented tail (it lives in the discarded detail null space, exactly as
"SixFour.Spec.RedownsampleGate" @lawGateIgnoresInventedDetail@ proves).

This module pins that as laws over the two-rung self-similar lift (16³ → 64³ → 256³ is one octant
operator applied twice; cf. "SixFour.Spec.SelfSimilarReconstruct"):

  * 'twoRungLift' — base ──(held detail)──> mid ──(invented detail)──> fine, both rungs the SAME
    "SixFour.Spec.OctreeCell" @octantSynthesize@.
  * 'lawSixteenComparableAtCoarseOnly' — re-downsampling the fine cube two rungs recovers the base
    (the 16³ seed) EXACTLY, and one rung recovers the mid (the 64³ capture): the comparison key is
    the coarse band.
  * 'lawTailHasNoCoarseFootprint' — two DIFFERENT invented tails give the SAME coarse band (the 256³
    change is invisible at 16³) while the fine cubes genuinely DIFFER (the change is real at 256³).
    So "compare Δ16 to Δ256" is tail-independent at the coarse band and undefined in the fine band.

Additive: composes "SixFour.Spec.OctreeCell", "SixFour.Spec.RedownsampleGate" (@redownsample@) and
"SixFour.Spec.NudgeContamination" (@bumpDetail@, the representative invented-detail edit). Re-pins
nothing. GHC-boot-only. Laws QuickCheck'd in "Properties.TriScaleBench".
-}
module SixFour.Spec.TriScaleBench
  ( twoRungLift
    -- * Laws (QuickCheck'd in @Properties.TriScaleBench@)
  , lawSixteenComparableAtCoarseOnly
  , lawTailHasNoCoarseFootprint
  ) where

import SixFour.Spec.OctreeCell        (Detail, octantDistill, octantSynthesize)
import SixFour.Spec.RedownsampleGate   (redownsample)
import SixFour.Spec.NudgeContamination (bumpDetail)

-- | The two-rung self-similar lift: a @base@ cube lifted by its @held@ detail to the @mid@ rung,
-- then by the @invented@ detail (the latent tail) to the @fine@ rung — the SAME octant operator
-- ("SixFour.Spec.OctreeCell" @octantSynthesize@) applied twice, the 16³→64³→256³ skeleton.
twoRungLift :: [Int] -> [[Detail]] -> [[Detail]] -> [Int]
twoRungLift base held invented =
  octantSynthesize (octantSynthesize (base, held), invented)

-- | KEYSTONE — the tri-scale comparison is at the COARSE band: re-downsampling the @fine@ (256³)
-- cube one rung recovers the @mid@ (the 64³ capture) EXACTLY, and two rungs recovers the @base@ (the
-- 16³ seed) EXACTLY. So a 16³ change shows up as the coarse part of a 256³ change, and that part
-- survives re-downsampling unchanged. Built by distilling a 4096-voxel @fine0@ (the 256³-analog) DOWN
-- to its 64³ @mid@ then 16³ @base@ — so every band is correctly shaped — and proving the two-rung lift
-- exactly reconstructs it. Teeth: a lossy lift, or one whose detail leaked into the coarse plane,
-- would fail the exact recovery.
lawSixteenComparableAtCoarseOnly :: [Int] -> Bool
lawSixteenComparableAtCoarseOnly fine0 =
  length fine0 /= 4096
    || let (mid,  invented) = octantDistill 2 fine0        -- 256³ ↦ (64³ mid, 2 invented levels)
           (base, held)     = octantDistill 2 mid          -- 64³  ↦ (16³ base, 2 held levels)
           fine             = twoRungLift base held invented
       in fine == fine0                                     -- the two-rung lift reconstructs (bijection)
          && redownsample 2 fine == mid                     -- 256³ ↦ 64³ recovers the capture
          && redownsample 4 fine == base                    -- 256³ ↦ 16³ recovers the seed

-- | The invented TAIL has NO coarse footprint: two different tails (@b1@, @b2@) leave the
-- re-downsampled coarse band identical (the 256³ change is invisible at 64³\/16³), while the fine
-- cubes genuinely DIFFER (the change is real at 256³). This is why "compare a 16³ change to a 256³
-- change" is tail-independent at the coarse band and a category error in the fine band. Teeth: a tail
-- that moved the coarse band, or a lift non-injective in the detail, breaks one of the two conjuncts.
lawTailHasNoCoarseFootprint :: [Int] -> Int -> Int -> Bool
lawTailHasNoCoarseFootprint fine0 b1 b2 =
  length fine0 /= 4096
    || let (mid, invented) = octantDistill 2 fine0
           fineOf b        = octantSynthesize (mid, map (map (bumpDetail b)) invented)
       in redownsample 2 (fineOf b1) == redownsample 2 (fineOf b2)   -- same coarse (tail-blind)
          && (b1 == b2 || fineOf b1 /= fineOf b2)                     -- ...but the 256³ cubes differ
