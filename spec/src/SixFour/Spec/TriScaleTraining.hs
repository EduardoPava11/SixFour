{- |
Module      : SixFour.Spec.TriScaleTraining
Description : CAN THE APP TRAIN ALL THREE SCALES WITH THE APPROPRIATE INFORMATION DENSITY? Yes — and this module gates the exact arithmetic of why. The ladder trains TRANSITIONS, never marginals: the chain rule W(fine) = W(coarse totals) × ∏ W(within-block) ("SixFour.Spec.PaletteKinetics") telescopes across BOTH rung transitions ('lawLadderTelescopesExactly'), so the 16→32 head and the 32→64 head consume DISJOINT bits — no bit is ever counted twice, and the 16-rung itself is the realized palette (GCT), never a training target.

The density accounting, exact:
  * Each transition to side s offers 7·(s/2)³ detail values per window (the 7
    graded bands per 2×2×2 block, "SixFour.Spec.OctantViews") — samples scale
    ×8 per rung ('lawDetailSamplesScaleByEight'), and so does compute (blocks),
    so INFORMATION-PER-COMPUTE IS RUNG-INVARIANT: exactly 7 values per block
    at every rung ('lawInfoPerComputeIsRungInvariant'). No rung is a better
    deal than another; the ladder has no free lunch and no bad rung.
  * Therefore training BOTH transitions costs exactly 9/8 of training the
    finest alone: 8·(d₆₄ + d₃₂) == 9·d₆₄ ('lawTriScaleOverheadIsNineEighths')
    — the coarse head rides along for 12.5%.
  * WITHIN a rung, the appropriate density is metered per block: a transition
    block whose within-group counts are concentrated has W = 1 — exactly zero
    conditional bits — and is SKIPPED, not trained
    ('lawConcentratedTransitionIsFree'). Mass (photon count on the x420 path)
    weights the rest: shot noise gives variance ≈ gain × mean, so certainty is
    bought by mass (physics NOTE, per PaletteKinetics — not law).

Cadence fit (doc, measured elsewhere): the transitions emit at the GIF-exact
cadences (32→64 at 10 Hz pairs, 16→32 at 5 Hz), pooling costs ~0.5 ms/frame
(palette16_bench) and a θ_up step ~12.4 ms (AtlasTrainer proof, device) — one
step per transition per window uses <1% of the 3.2 s window. The constraint
is information, not compute, which is exactly how it should be.
-}
-- COMPARTMENT: PURE-SPEC-WALL | tag:none
module SixFour.Spec.TriScaleTraining
  ( -- * Density accounting
    blocksPerTransition
  , detailValuesPerTransition
    -- * Laws
  , lawDetailSamplesScaleByEight
  , lawInfoPerComputeIsRungInvariant
  , lawTriScaleOverheadIsNineEighths
  , lawLadderTelescopesExactly
  , lawConcentratedTransitionIsFree
  ) where

import SixFour.Spec.PaletteKinetics (microstates)
import SixFour.Spec.RootLatticeDetail (numDetailBands)

-- | Blocks per window for the transition INTO side s: one 2×2×2 spacetime
-- block per coarse voxel, (s/2)³.
blocksPerTransition :: Integer -> Integer
blocksPerTransition s = (s `div` 2) ^ (3 :: Int)

-- | Detail values that transition offers per window: 7 graded bands per block
-- (rank A₇ = 'numDetailBands' 8, the octant grading).
detailValuesPerTransition :: Integer -> Integer
detailValuesPerTransition s =
  fromIntegral (numDetailBands 8) * blocksPerTransition s

-- | LAW (the 8× ladder): each rung up multiplies the per-window training
-- signal by exactly 8 — for every rung, not asymptotically.
lawDetailSamplesScaleByEight :: Bool
lawDetailSamplesScaleByEight =
  and [ detailValuesPerTransition (2 * s) == 8 * detailValuesPerTransition s
      | s <- [16, 32, 64, 128] ]

-- | LAW (no bad rung): information-per-compute is RUNG-INVARIANT — exactly 7
-- detail values per 2×2×2 block at every scale. Training budget allocated per
-- block buys the same bits everywhere on the ladder.
lawInfoPerComputeIsRungInvariant :: Bool
lawInfoPerComputeIsRungInvariant =
  and [ detailValuesPerTransition s == 7 * blocksPerTransition s
      | s <- [16, 32, 64, 128, 256] ]

-- | LAW (the price of all three scales): both transitions together cost
-- exactly 9/8 of the finest transition alone — 8·(d₆₄ + d₃₂) == 9·d₆₄,
-- an integer identity, not an estimate. The coarse head is a 12.5% rider.
lawTriScaleOverheadIsNineEighths :: Bool
lawTriScaleOverheadIsNineEighths =
  8 * (detailValuesPerTransition 64 + detailValuesPerTransition 32)
    == 9 * detailValuesPerTransition 64

-- | LAW (KEYSTONE — no bit counted twice): the microstate chain rule
-- TELESCOPES across the two-transition ladder. For fine counts grouped
-- 4 → 2 → 1 (values into mid-rung blocks into the coarsest):
-- W(fine) == W(mid within-blocks) × W(coarse within-block) × W(top) with
-- W(top) == 1 — the full ladder's entropy is the PRODUCT of per-transition
-- conditional factors, so the 16→32 and 32→64 heads consume disjoint bits.
lawLadderTelescopesExactly :: [Integer] -> Bool
lawLadderTelescopesExactly raw =
  microstates cs
    == microstates [a, b] * microstates [c, d]     -- 32→64 within-block factors
       * microstates [a + b, c + d]                -- 16→32 within-block factor
       * microstates [a + b + c + d]               -- W(coarsest) == 1
  where
    cs@[a, b, c, d] = map ((`mod` 10) . abs) (take 4 (raw ++ repeat 0))

-- | LAW (skip what carries nothing): a transition block's conditional factor
-- is 1 — zero bits to learn — exactly when its within-group mass is
-- concentrated on one child. The density meter that says WHERE to train.
lawConcentratedTransitionIsFree :: [Integer] -> Bool
lawConcentratedTransitionIsFree raw =
  (microstates cs == 1) == (length (filter (> 0) cs) <= 1)
  where cs = map ((`mod` 10) . abs) (take 4 raw)
