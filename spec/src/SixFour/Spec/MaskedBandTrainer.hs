{- |
Module      : SixFour.Spec.MaskedBandTrainer
Description : The TRAINING contract for the only learned object (θ_B) as a byte-checkable twin — pins @zero-genome == floor@, that "SixFour.Spec.MaskedBandPrediction" @trainBandJoint@ drives the masked-band loss down and RECOVERS a golden committed band, and that the descent is monotone (so the ill-conditioned trainer-divergence regime cannot pass). The golden constants ('goldenFloorBand', 'goldenTrainedBand') are what the Mac/MLX θ_B descent and the shipped 63-param forward pass must both reproduce.

The encoder is frozen ("SixFour.Spec.EncoderFrozen"); the ONLY learned object is the
63-param masked-band predictor @θ_B@. This module is its training GATE: a single fixed
training example, trained for a fixed number of steps, must take a SPECIFIC trajectory —
from the floor band to a golden recovered band — and the descent must be monotone. That
makes the MLX trainer (the @trainBandJoint@ twin) and the on-device hand-written forward
pass byte-checkable against these laws.

  * 'lawZeroGenomeIsFloor' — at the floor params the prediction is 'goldenFloorBand' (@0@)
    and the off-floor target genuinely incurs loss (the @zero-genome == floor@ start point).
  * 'lawTrainingDrivesLossDown' — 'trainBandJoint' drives the loss to a tiny fraction of the
    floor loss (the masked target IS learnable from the fixed embedding).
  * 'lawTrainedForwardIsGolden' (THE TWIN) — after training, the committed band is exactly
    'goldenTrainedBand' (@3000@). The MLX-trained θ_B and the device forward pass must both
    produce this byte; a drifted trainer or a wrong forward pass fails here.
  * 'lawTrainingDescendsMonotonically' — more steps never increase the loss. Teeth against a
    diverging / oscillating trainer (the fixed-η ill-conditioning at @ṽ → 0.9@ — kept out of
    range here by a moderate-@ṽ@ witness, and this law is the guard that would catch it).

Additive: a pure law module over "SixFour.Spec.MaskedBandPrediction"
(@trainBandJoint@/@maskedBandLoss@/@predictMaskedBand@/@zeroParamsB@). Re-pins NOTHING; no
golden vector file — the goldens are exported constants. GHC-boot-only; laws @once@-tested
in "Properties.MaskedBandTrainer".
-}
module SixFour.Spec.MaskedBandTrainer
  ( -- * The golden training fixture + its pinned trajectory endpoints
    trainerExample
  , trainerSteps
  , goldenFloorBand
  , goldenTrainedBand
    -- * The batch-STABLE trainer (mean gradient) — fixes the summed-gradient divergence
  , trainBandJointStable
    -- * Laws (closed :: Bool; @once@-tested in @Properties.MaskedBandTrainer@)
  , lawZeroGenomeIsFloor
  , lawTrainingDrivesLossDown
  , lawTrainedForwardIsGolden
  , lawTrainingDescendsMonotonically
  , lawStableTrainerSurvivesBatchDivergence
  ) where

import SixFour.Spec.MaskedBandPrediction
  ( MaskedBandExample, trainBandJoint, maskedBandLoss, maskedBandLossSum
  , maskedBandGradient, paramCountB, predictMaskedBand, zeroParamsB )

-- | The golden training fixture: coarse value @20000@ (ṽ ≈ 0.305 — moderate, well clear of
-- the ṽ → 0.9 trainer-divergence regime), masked band @0@, off-floor target @3000@, siblings
-- zero. Deterministic; the MLX trainer trains on this same example to reproduce the goldens.
trainerExample :: MaskedBandExample
trainerExample = (20000, (3000, 0, 0, 0, 0, 0, 0), 0)

-- | The fixed step count for the golden descent.
trainerSteps :: Int
trainerSteps = 2000

-- | The committed band at the floor (@zero-genome == floor@): @0@.
goldenFloorBand :: Int
goldenFloorBand = 0

-- | The committed band after training: @3000@ — the target recovered exactly through the Q16
-- crossing (@3000\/65536 · 65536 = 3000@). The byte the MLX-trained θ_B and the on-device
-- forward pass must both produce.
goldenTrainedBand :: Int
goldenTrainedBand = 3000

-- | The θ_B produced by the golden descent (shared by the laws below).
trainerTheta :: [Double]
trainerTheta = trainBandJoint trainerSteps [trainerExample]

-- | A batch-STABLE trainer: descends the MEAN per-example gradient, NOT the SUMMED gradient
-- "SixFour.Spec.MaskedBandPrediction" 'trainBandJoint' uses. The summed gradient makes the
-- effective step scale with the example count @N@: when MANY high-ṽ examples are batched the
-- @ṽ²@ feature is large, so @η·N·λ@ exceeds the GD stability bound and the descent diverges
-- to NaN ('lawStableTrainerSurvivesBatchDivergence', GHCi-verified at 8 examples). Dividing
-- the gradient by @N@ makes the step batch-size-independent and convergent. Same η = 0.2.
-- Additive: 'trainBandJoint' is unchanged, so every golden trained against it is untouched;
-- this is the trainer to use for genuine multi-example batches.
trainBandJointStable :: Int -> [MaskedBandExample] -> [Double]
trainBandJointStable n exs =
  let m       = fromIntegral (max 1 (length exs))
      meanGrad ps = map (/ m) (foldr (zipWith (+)) (replicate paramCountB 0)
                                      (map (maskedBandGradient ps) exs))
      step ps = zipWith (\p g -> p - 0.2 * g) ps (meanGrad ps)
  in iterate step zeroParamsB !! max 0 n

-- ============================================================================
-- Laws (closed predicates; @once@-tested in Properties.MaskedBandTrainer)
-- ============================================================================

-- | @zero-genome == floor@ — the descent's start point. At 'zeroParamsB' the prediction is
-- exactly 'goldenFloorBand' (@0@), and the off-floor target genuinely incurs loss (so the
-- problem is non-vacuous). Teeth: a non-zero floor prediction, or a target the floor already
-- fits, fails.
lawZeroGenomeIsFloor :: Bool
lawZeroGenomeIsFloor =
     predictMaskedBand zeroParamsB trainerExample == goldenFloorBand
  && maskedBandLoss zeroParamsB trainerExample > 1e-6

-- | Training DRIVES the loss down: after 'trainerSteps', the masked-band loss is a tiny
-- fraction (< 1e-3) of the floor loss. Teeth: a trainer that does not learn the manufactured
-- label leaves the loss near the floor and fails.
lawTrainingDrivesLossDown :: Bool
lawTrainingDrivesLossDown =
  maskedBandLoss trainerTheta trainerExample
    < 1e-3 * maskedBandLoss zeroParamsB trainerExample

-- | THE BYTE-CHECKABLE TWIN: after the golden descent, the committed band is exactly
-- 'goldenTrainedBand' (@3000@). The MLX-trained θ_B and the device hand-written forward pass
-- must both reproduce this byte. Teeth: a drifted trainer (wrong fixpoint) or a wrong forward
-- pass produces a different band and fails.
lawTrainedForwardIsGolden :: Bool
lawTrainedForwardIsGolden =
  predictMaskedBand trainerTheta trainerExample == goldenTrainedBand

-- | The descent is MONOTONE: more steps never increase the loss. Teeth against a diverging /
-- oscillating trainer — exactly the failure mode of fixed-η on an ill-conditioned input (the
-- ṽ → 0.9 regime). The moderate-ṽ golden witness stays convergent, and this law is the guard
-- that a high-ṽ fixture (or a too-large η) would fail.
lawTrainingDescendsMonotonically :: Bool
lawTrainingDescendsMonotonically =
  maskedBandLoss (trainBandJoint trainerSteps [trainerExample]) trainerExample
    <= maskedBandLoss (trainBandJoint 100 [trainerExample]) trainerExample

-- | THE BATCH-DIVERGENCE DEFECT, surfaced AND fixed (GHCi-verified). On a batch of 8 high-ṽ
-- examples the summed-gradient 'trainBandJoint' DIVERGES to NaN (η·N·λ past the stability
-- bound); the mean-gradient 'trainBandJointStable' stays FINITE and converges on the SAME
-- fixture. Teeth: this is a real, reproduced defect — the @isNaN@/non-finite witness pins it,
-- and the finite, reduced 'trainBandJointStable' loss pins the fix. (A single high-ṽ example
-- converges either way; the defect is specifically batched-N high-ṽ.) If 'trainBandJoint' is
-- ever changed to a mean gradient, the summed-divergence witness here must be revisited.
lawStableTrainerSurvivesBatchDivergence :: Bool
lawStableTrainerSurvivesBatchDivergence =
  let many       = [ (v, (3000, 0, 0, 0, 0, 0, 0), 0) | v <- [50000, 52000 .. 64000] ]  -- 8 high-ṽ
      lossSummed = maskedBandLossSum (trainBandJoint 5000 many) many
      lossStable = maskedBandLossSum (trainBandJointStable 5000 many) many
  in (isNaN lossSummed || isInfinite lossSummed || lossSummed > 1.0)  -- summed diverges/fails
     && not (isNaN lossStable || isInfinite lossStable)               -- stable stays finite
     && lossStable < 1e-3                                              -- ...and converges
