{- |
Module      : SixFour.Spec.JepaTarget
Description : The I-JEPA correspondence, as theorems — SixFour's JEPA prediction target is a DATA-MANUFACTURED EXACT label (the reversible lift's held detail band), NOT the output of a learnable EMA target-encoder. So there is no target-encoder to EMA, and representation collapse is structurally IMPOSSIBLE: the target is a fixed real value the predictor moves toward, never a co-evolving encoder output the predictor could trivially match.

I-JEPA (Assran et al., CVPR 2023) predicts, in latent space, the output of a TARGET
ENCODER from the output of a CONTEXT ENCODER. Both encoders are learnable; the target
encoder is an EMA of the context encoder, and a STOP-GRADIENT + EMA are REQUIRED to stop
the pair collapsing to a constant (the trivial "predict 0, encode 0" solution).

SixFour occupies the same JEPA template but replaces the learned EMA'd encoder pair with
ONE proven-reversible integer encoder ("SixFour.Spec.EncoderFrozen"), and that single
substitution removes the collapse problem. This module pins the correspondence as laws:

  * __The target is MANUFACTURED, not ENCODED.__ The masked band's target is the lift's
    HELD detail band, recoverable from the capture by the reversible split
    (@refine . split == id@) — a bit-exact, data-generated label, not an encoder output
    ('lawTargetIsDataManufacturedNotEncoded').
  * __The target is FIXED under predictor training.__ Unlike I-JEPA's EMA target (which
    co-evolves with the context encoder), SixFour's target is a pure function of the DATA:
    'MaskedBandPrediction.maskedTargetBand' takes no @θ@, so training the predictor cannot
    move the target — the predictor moves to a target that never moves to meet it
    ('lawTargetFixedUnderPredictorTraining'). This is precisely the condition I-JEPA's
    stop-gradient/EMA exists to enforce; here it is structural.
  * __No target-encoder ⇒ no EMA.__ The "encoder" that produces the target is the frozen
    lift, with ZERO parameters ("SixFour.Spec.EncoderFrozen" @encoderParamCount == 0@), so
    there is nothing to maintain an EMA of ('lawNoTargetEncoderNoEma').
  * __Collapse is rejected.__ The trivial collapse solution (a constant predictor) incurs
    STRICTLY POSITIVE loss on an off-floor target and is improved by one SGD step
    ('lawCollapseIsRejected', delegating "SixFour.Spec.DetailMaskedPrediction"
    @lawConstantPredictorIncursLoss@) — because the target is a real value, not a constant
    the predictor and a co-encoder could agree on.
  * __The target carries information BEYOND the context.__ A predictor fit to one masked
    answer misses a different one at the same context, so prediction is genuine work, not
    copying ('lawTargetCarriesInfoBeyondContext').
  * __The TIME axis: the constant orbit misses a moved frame.__ On the inter-frame axis, the
    identity/constant-orbit prediction (predict frame @t+1 := t@) STRICTLY misses a frame that
    actually moved, so the persistence baseline provably loses ('lawConstantOrbitMissesMovedFrame').
    This is the real motion witness; the surrounding design intent (the @L_close@ self-produced
    rollout target is inadmissible because the constant orbit is its free global minimum) is
    carried by the 'RolloutTargetSource' / 'admissibleRolloutSource' design types, not asserted as
    a law (the earlier @lawNoSelfProducedRolloutTarget@ merely restated those definitions and was
    retired in the model-spec unification — see @SIXFOUR-MODEL.md@).

Additive: a pure law module assembling existing teeth from "SixFour.Spec.SelfSupervisedRung",
"SixFour.Spec.MaskedBandPrediction", "SixFour.Spec.EncoderFrozen",
"SixFour.Spec.DetailMaskedPrediction". Re-pins NOTHING; no golden vector. GHC-boot-only;
laws @once@-tested in "Properties.JepaTarget".
-}
-- COMPARTMENT: MLX-MODEL | tag:MacTag
module SixFour.Spec.JepaTarget
  ( -- * The rollout-target provenance model (the global time-axis collapse guard)
    RolloutTargetSource(..)
  , admissibleRolloutSource
  , constantOrbitPenalised
    -- * Laws (closed :: Bool; @once@-tested in @Properties.JepaTarget@)
  , lawTargetIsDataManufacturedNotEncoded
  , lawTargetFixedUnderPredictorTraining
  , lawNoTargetEncoderNoEma
  , lawCollapseIsRejected
  , lawTargetCarriesInfoBeyondContext
  , lawConstantOrbitMissesMovedFrame
  ) where

import SixFour.Spec.OctreeGenome (octreeLeafCount)
import SixFour.Spec.SameObjectInvariance (Cube(..))
import SixFour.Spec.ConstructionEncoder
  ( Construction(..), buildPixels )
import SixFour.Spec.SelfSupervisedRung
  ( Rung(..), Supervision(..), supervisionOf, hasHeldTarget
  , lawHeldLabelIsDataManufactured )
import SixFour.Spec.MaskedBandPrediction
  ( maskedTargetBand, trainBandJoint, predictMaskedBand, zeroParamsB )
import SixFour.Spec.EncoderFrozen (encoderParamCount)
import SixFour.Spec.DetailMaskedPrediction
  ( lawConstantPredictorIncursLoss, lawFittingOneTargetMissesAnother )

-- ============================================================================
-- The rollout-target provenance model (what the global guard quantifies over)
-- ============================================================================

-- | The PROVENANCE of a rollout-step prediction target on the circular time axis. The guard
-- 'lawConstantOrbitMissesMovedFrame' uses exactly these two cases.
data RolloutTargetSource
  = NextFrameData      -- ^ frame @t+1@'s own policy\/value data ('policyDelta'\/'valueDelta') — θ-free, collapse-impossible.
  | RolledForwardSelf  -- ^ the net's own rolled-forward latent @R^k z@ — θ-dependent, the @L_close@ self-produced target.
  deriving (Eq, Show)

-- | The ONLY admissible rollout-target source is the next frame's DATA. A self-produced (rolled
-- forward) target is inadmissible — this is the global guard that the @L_close@ family cannot be
-- attached to ANY time-axis term. Teeth: returning 'True' for 'RolledForwardSelf' breaks the law.
admissibleRolloutSource :: RolloutTargetSource -> Bool
admissibleRolloutSource NextFrameData     = True
admissibleRolloutSource RolledForwardSelf = False

-- | Is the trivial constant\/identity orbit (predict @t+1 := t@) STRICTLY PENALISED against a
-- target of the given provenance, on a moving frame @(curr, next)@? A 'NextFrameData' target
-- penalises it by the real motion (@curr /= next@ ⇒ 'True'); a 'RolledForwardSelf' target is
-- matched by the constant orbit for free (@loss 0@ ⇒ 'False'), which is exactly why the constant
-- orbit is the self-produced objective's global minimum.
constantOrbitPenalised :: RolloutTargetSource -> Cube -> Cube -> Bool
constantOrbitPenalised NextFrameData     (Cube l0 a0 b0) (Cube l1 a1 b1) = (l0, a0, b0) /= (l1, a1, b1)
constantOrbitPenalised RolledForwardSelf _               _               = False

-- ============================================================================
-- Laws (closed predicates; @once@-tested in Properties.JepaTarget)
-- ============================================================================

-- | The JEPA target is MANUFACTURED from the data by the reversible lift, NOT produced by a
-- learned encoder. The held detail band reconstructs the capture exactly
-- (@refine . split == id@; delegates "SixFour.Spec.SelfSupervisedRung"
-- @lawHeldLabelIsDataManufactured@), and the within-capture (Held) rung carries that
-- manufactured target ('SelfSupervisedLoss'). Teeth: a non-reversible split would make the
-- "label" fiction and fail the delegated round-trip.
lawTargetIsDataManufacturedNotEncoded :: Bool
lawTargetIsDataManufacturedNotEncoded =
     lawHeldLabelIsDataManufactured 2 2 [0 .. octreeLeafCount 2 - 1]  -- the data manufactures the label
  && hasHeldTarget HeldRung                                          -- the Held rung HAS a target
  && supervisionOf HeldRung == SelfSupervisedLoss                    -- ...scored against it (not a gate)

-- | THE NO-COLLAPSE STRUCTURE: the target is FIXED under predictor training. The target band
-- is a pure function of the DATA ('maskedTargetBand' takes no @θ@), so training the predictor
-- cannot move it: the predictor starts away from the fixed target and converges TO it, while
-- the target never moves to meet the predictor. This is exactly what I-JEPA's stop-gradient +
-- EMA exist to enforce on a co-evolving encoded target — here it is structural, not a trick.
-- Teeth: a θ-dependent (EMA-style) target would not satisfy "the predictor reaches a value the
-- data fixed in advance".
lawTargetFixedUnderPredictorTraining :: Bool
lawTargetFixedUnderPredictorTraining =
  let ex  = (20000, (3000, 0, 0, 0, 0, 0, 0), 0)
      th  = trainBandJoint 2000 [ex]
      tgt = maskedTargetBand ex                       -- the target, a pure function of the data
  in tgt == 3000
     && predictMaskedBand zeroParamsB ex /= tgt        -- the predictor starts AWAY from the fixed target
     && predictMaskedBand th ex == tgt                 -- ...and moves to it (the target never moved)

-- | NO TARGET-ENCODER ⇒ NO EMA. The "encoder" that produces the target is the frozen lift,
-- with ZERO learnable parameters ("SixFour.Spec.EncoderFrozen" @encoderParamCount@), so there
-- is no target-encoder to keep an exponential moving average of — the whole EMA apparatus
-- I-JEPA needs has no referent. Yet the target still EXISTS ('hasHeldTarget'), manufactured by
-- that zero-param lift. Teeth: a design with a learned target encoder would have
-- @encoderParamCount > 0@ and fail.
lawNoTargetEncoderNoEma :: Bool
lawNoTargetEncoderNoEma =
     encoderParamCount == 0       -- nothing to EMA: the target's "encoder" is the param-free lift
  && hasHeldTarget HeldRung       -- yet the target exists, manufactured by the frozen lift

-- | COLLAPSE IS REJECTED by the objective. The trivial collapse solution — a constant
-- predictor (the floor) — incurs STRICTLY POSITIVE loss on an off-floor target AND is improved
-- by one SGD step (delegates "SixFour.Spec.DetailMaskedPrediction"
-- @lawConstantPredictorIncursLoss@). I-JEPA fears collapse because target+predictor can BOTH go
-- constant; here the target is a real off-floor value the data fixed, so the constant predictor
-- provably loses. Teeth: an objective that scored a constant predictor at zero (the vacuous
-- round-trip) would fail the delegated law.
lawCollapseIsRejected :: Bool
lawCollapseIsRejected =
  lawConstantPredictorIncursLoss 20000 (8000, 0, 0, 0, 0, 0, 0)

-- | The masked target carries information BEYOND the context: a predictor fit to ONE masked
-- answer misses a DIFFERENT off-floor answer at the same context (delegates
-- "SixFour.Spec.DetailMaskedPrediction" @lawFittingOneTargetMissesAnother@). So prediction is
-- genuine work, not copying the context — the JEPA objective is non-trivial. Teeth: a predictor
-- that was a fixed function of the context regardless of the answer would score the same on both
-- and fail.
lawTargetCarriesInfoBeyondContext :: Bool
lawTargetCarriesInfoBeyondContext =
  lawFittingOneTargetMissesAnother 20000 (3000, 0, 0, 0, 0, 0, 0)

-- | THE TIME-AXIS MOTION WITNESS. On the inter-frame axis the identity\/constant-orbit prediction
-- (predict frame @t+1 := t@) STRICTLY misses a frame that actually moved, so the persistence
-- baseline provably loses — the temporal analogue of 'lawCollapseIsRejected'. This is the genuine
-- computational content: a real recolour from @t@ to @t+1@ is not matched by copying @t@.
--
-- The broader design claim — that the @L_close@ self-produced rollout target is inadmissible because
-- the constant orbit is its free global minimum — is carried by the 'RolloutTargetSource' /
-- 'admissibleRolloutSource' / 'constantOrbitPenalised' DESIGN TYPES below, not asserted as a law: the
-- retired @lawNoSelfProducedRolloutTarget@ merely restated those definitions (3 of 4 conjuncts were
-- @not False@ \/ @True@ by construction), so it was a definitional consistency check dressed as a
-- theorem and was removed in the model-spec unification (see @SIXFOUR-MODEL.md@). The honest boundary:
-- the data-manufactured target STRUCTURE is encoded in the types; that it makes the real model train
-- is CONTRACT-ONLY (unproven until trained).
lawConstantOrbitMissesMovedFrame :: Bool
lawConstantOrbitMissesMovedFrame =
  let ct     = Construction 0 [(10,20,30)] [0]
      ctNext = Construction 0 [(40,50,60)] [0]       -- a pure recolour: the VALUE channel moved
      Cube l0 a0 b0 = buildPixels ct                 -- the identity\/constant-orbit prediction (t+1 := t)
      Cube l1 a1 b1 = buildPixels ctNext             -- the moved next frame
  in (l0, a0, b0) /= (l1, a1, b1)                     -- constant orbit STRICTLY misses the moved frame
     && constantOrbitPenalised NextFrameData (buildPixels ct) (buildPixels ctNext)  -- ...the data target penalises it
     && not (constantOrbitPenalised RolledForwardSelf (buildPixels ct) (buildPixels ctNext))  -- ...the self target does not (why L_close collapses)
