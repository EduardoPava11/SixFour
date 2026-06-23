{- |
Module      : SixFour.Spec.PerAxisTraining
Description : Verifies the six-axis ledger BY TRAINING, not just by op-structure — each of the seven octant detail bands (the search axes a, b, x, y and their slots) is INDEPENDENTLY learnable: training one band recovers its target while leaving every other band at the floor, and distinct bands learn distinct targets with no cross-talk.

The architectural answer pinned that the search axes (a, b, x, y) are the masked detail
bands the predictor θ_B regresses, while the carriers (L, t) are the un-predicted DC
balance. That attribution rested on the FIXED 'liftOct' band layout — op-structure, not a
training run. This module closes that gap: it actually TRAINS individual bands and checks
the per-axis isolation empirically (GHCi-verified), as @once@-tested laws.

The independence is structural in θ_B (one parameter ROW per band, so
"SixFour.Spec.MaskedBandPrediction" @maskedBandGradient@ fills only the masked band's row),
and these laws confirm it end-to-end through training:

  * 'lawBandLearnedInIsolation' — train ONLY band 0; it recovers its target while band 1,
    never trained, stays at the floor (no leak across rows).
  * 'lawPerBandTargetsAreIndependent' — train bands 0 and 1 to DIFFERENT targets at once;
    each recovers ITS OWN target (no cross-talk — the strongest per-axis isolation).
  * 'lawEverySearchBandIsIndependentlyLearnable' — EVERY one of the seven detail bands is
    independently trainable to a target (the full six-axis ledger, verified by training).

Additive: a pure law module over "SixFour.Spec.MaskedBandPrediction"
(@trainBandJoint@/@predictMaskedBand@/@setBand@/@numBands@). Re-pins NOTHING; no golden
vector. Moderate coarse value (ṽ ≈ 0.305) keeps the trainer convergent. GHC-boot-only; laws
@once@-tested in "Properties.PerAxisTraining".
-}
-- COMPARTMENT: MLX-MODEL | tag:MacTag
module SixFour.Spec.PerAxisTraining
  ( -- * Laws (closed :: Bool; @once@-tested in @Properties.PerAxisTraining@)
    lawBandLearnedInIsolation
  , lawPerBandTargetsAreIndependent
  , lawEverySearchBandIsIndependentlyLearnable
  ) where

import SixFour.Spec.OctreeCell (Detail)
import SixFour.Spec.MaskedBandPrediction
  ( MaskedBandExample, numBands, setBand, trainBandJoint, predictMaskedBand )

-- | The all-floor detail (the zero 7-tuple) — the base a single band's target is set onto.
zeroDetail :: Detail
zeroDetail = (0, 0, 0, 0, 0, 0, 0)

-- ============================================================================
-- Laws (closed predicates; @once@-tested in Properties.PerAxisTraining)
-- ============================================================================

-- | A band is learned IN ISOLATION: training θ_B on examples that mask ONLY band 0 makes it
-- recover its off-floor target, while band 1 — whose parameter row was never touched — stays
-- at the floor. Teeth: if training band 0 leaked into another band's row (shared params), the
-- untrained band's prediction would drift off the floor and fail. (GHCi-verified: band0 → 3000,
-- band1 → 0.)
lawBandLearnedInIsolation :: Bool
lawBandLearnedInIsolation =
  let exBand0 = (20000, setBand zeroDetail 0 3000, 0)   -- mask band 0, target 3000
      th      = trainBandJoint 2000 [exBand0]
      exBand1 = (20000, setBand zeroDetail 0 3000, 1)   -- mask band 1 (untrained row), target 0
  in predictMaskedBand th exBand0 == 3000               -- band 0 LEARNED its target
     && predictMaskedBand th exBand1 == 0               -- band 1 untouched (still the floor)

-- | Distinct bands learn DISTINCT targets with NO cross-talk: train bands 0 and 1
-- simultaneously to different off-floor targets, and each recovers its OWN. Teeth: shared
-- params (one band's training corrupting another's readout) would make at least one band miss
-- its target. (GHCi-verified: band0 → 3000, band1 → 5000.) This is the strongest per-axis
-- isolation — the search axes are learned in genuinely separate parameter rows.
lawPerBandTargetsAreIndependent :: Bool
lawPerBandTargetsAreIndependent =
  let full = setBand (setBand zeroDetail 0 3000) 1 5000  -- band0 = 3000, band1 = 5000
      ex0  = (20000, full, 0)
      ex1  = (20000, full, 1)
      th   = trainBandJoint 2000 [ex0, ex1]
  in predictMaskedBand th ex0 == 3000                    -- band 0 recovers its target
     && predictMaskedBand th ex1 == 5000                 -- band 1 recovers its DIFFERENT target

-- | The FULL six-axis ledger, verified by training: EVERY one of the seven octant detail
-- bands is independently learnable. For each band @j@, training θ_B on a target placed only on
-- band @j@ recovers that target. Teeth: a band with no parameter row (or a layout that fused
-- two axes into one slot) could not be fit and would fail. This converts the per-axis
-- attribution from op-structure to a trained guarantee across all bands.
lawEverySearchBandIsIndependentlyLearnable :: Bool
lawEverySearchBandIsIndependentlyLearnable =
  all bandLearns [0 .. numBands - 1]
  where
    bandLearns :: Int -> Bool
    bandLearns j =
      let ex = (20000, setBand zeroDetail j 3000, j) :: MaskedBandExample
          th = trainBandJoint 2000 [ex]
      in predictMaskedBand th ex == 3000
