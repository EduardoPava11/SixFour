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
  * __The TIME axis stays data-manufactured too.__ The Option-2 inter-frame targets — the
    POLICY target (frame @t+1@'s index, "SixFour.Spec.ConstructionEncoder" @policyDelta@) and the
    VALUE target (frame @t+1@'s recoloured pixels, @valueDelta@ → @buildPixels@) — are pure
    functions of the NEXT CAPTURED FRAME, no @θ@. So the self-produced "predict my own rolled
    forward latent" target (the @L_close@ family, whose global minimum is the trivial constant
    orbit @R z == z@) is never formed, and the circular time axis inherits the same
    collapse-impossibility as the spatial band ('lawTemporalDeltaTargetIsDataManufactured').
  * __No self-produced rollout target, GLOBALLY.__ Quantifying over both target provenances
    ('RolloutTargetSource'), the only admissible one is the next frame's DATA; a rolled-forward
    self target is inadmissible precisely because the constant orbit matches it for free (its
    global minimum). This closes the @L_close@ trap on ANY time-axis term, not just the
    policy/value path ('lawNoSelfProducedRolloutTarget').

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
  , lawTemporalDeltaTargetIsDataManufactured
  , lawNoSelfProducedRolloutTarget
  ) where

import SixFour.Spec.OctreeGenome (octreeLeafCount)
import SixFour.Spec.SameObjectInvariance (Cube(..))
import SixFour.Spec.ConstructionEncoder
  ( Construction(..), buildPixels, policyDelta, valueDelta )
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
-- 'lawNoSelfProducedRolloutTarget' quantifies over exactly these two cases.
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

-- | THE TIME-AXIS COLLAPSE GUARD (Option 2 — policy\/value temporal deltas). The inter-frame
-- POLICY target (frame @t+1@'s index map, "SixFour.Spec.ConstructionEncoder" 'policyDelta') and
-- VALUE target (frame @t+1@'s recoloured pixels, 'valueDelta' → 'buildPixels') are PURE FUNCTIONS
-- OF THE DATA — the next captured frame — exactly as the spatial 'maskedTargetBand' is. They take
-- no @θ@, so the predictor cannot move them, and the self-produced "predict my own rolled-forward
-- latent" target (the @L_close@ family, whose global minimum is the trivial constant orbit
-- @R z == z@) is NEVER formed. This keeps the circular time axis on the data-manufactured
-- (collapse-IMPOSSIBLE) side, not the BYOL\/EMA (collapse-prone) side — the temporal analogue of
-- 'lawTargetFixedUnderPredictorTraining'. Teeth: the constant\/identity-orbit predictor (predict
-- frame @t+1 := t@) STRICTLY misses a frame that actually moved (so collapse provably loses), and
-- the policy\/value targets are exactly frame @t+1@'s OWN index\/palette (so they are @θ@-free
-- data, not an encoder output).
lawTemporalDeltaTargetIsDataManufactured :: Bool
lawTemporalDeltaTargetIsDataManufactured =
  let ct     = Construction 0 [(10,20,30)] [0]
      ctNext = Construction 0 [(40,50,60)] [0]       -- a pure recolour: the VALUE channel moved
      Cube l0 a0 b0 = buildPixels ct                 -- the identity\/constant-orbit prediction (t+1 := t)
      Cube l1 a1 b1 = buildPixels ctNext             -- the data-manufactured VALUE target
  in (l0, a0, b0) /= (l1, a1, b1)                          -- constant orbit STRICTLY misses the moved frame
     && cPalette (valueDelta  ct ctNext) == cPalette ctNext  -- VALUE target = frame t+1's OWN palette (θ-free)
     && cIndex   (policyDelta ct ctNext) == cIndex   ctNext  -- POLICY target = frame t+1's OWN index (θ-free)

-- | GLOBAL TIME-AXIS COLLAPSE PROHIBITION. Quantifying over BOTH rollout-target provenances
-- ('RolloutTargetSource'), the only admissible one is the next frame's DATA ('NextFrameData'), and
-- it is admissible PRECISELY because the trivial constant\/identity orbit is strictly penalised
-- against it, while the self-produced ('RolledForwardSelf') target — the @L_close@ family — is
-- INADMISSIBLE because the constant orbit matches it for free (loss 0) and is therefore its global
-- minimum. This closes the trap GLOBALLY, not only on the policy\/value path of
-- 'lawTemporalDeltaTargetIsDataManufactured': no time-axis gradient term may take a self-produced
-- target. Teeth: flipping 'admissibleRolloutSource' to accept 'RolledForwardSelf', or making the
-- constant orbit penalised against it, breaks the law.
lawNoSelfProducedRolloutTarget :: Bool
lawNoSelfProducedRolloutTarget =
  let ct     = Construction 0 [(10,20,30)] [0]
      ctNext = Construction 0 [(40,50,60)] [0]               -- a moving frame (recolour)
      curr   = buildPixels ct
      next   = buildPixels ctNext
  in admissibleRolloutSource NextFrameData                      -- the data target is admitted
     && not (admissibleRolloutSource RolledForwardSelf)         -- the self-produced target is forbidden
     && constantOrbitPenalised NextFrameData curr next          -- ...the constant orbit is strictly penalised by the data target
     && not (constantOrbitPenalised RolledForwardSelf curr next)  -- ...but matched for free by the self target (why it collapses)
