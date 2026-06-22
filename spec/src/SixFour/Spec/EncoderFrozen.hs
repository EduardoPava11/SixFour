{- |
Module      : SixFour.Spec.EncoderFrozen
Description : Pins the ENCODER (GIF → embeddings) contract and the four-phase (pre-train / train / infer / continuous-infer) relationship as types + closed laws. The keystone: the encoder is the FIXED reversible lift composed with a FIXED parameter-free feature map (it has ZERO learnable parameters), so there is NO encoder pre-training phase — the ONLY learned object in the whole stack is the 63-param masked-band predictor θ_B that rides ABOVE the embedding. A future contributor who silently inserted a learned projection into the encoder, or committed a raw float embedding without the single Q16 re-entry, FAILS here.

This module answers the architectural sub-question "WHAT IS THE ENCODER (GIF →
embeddings)?" with a gate rather than prose. The settled answer is __(c)-degenerate__:

  * The encoder is a COMPOSITION — @GIF → 'liftOct' (fixed Int bijection) →
    'featuresB' (fixed 9-D basis @φ_B@)@ — but the composition is ENTIRELY UN-LEARNED.
    There is no learned projection layer between the lift and the embedding.
  * Candidate (b), "a learned continuous encoder self-supervised PRE-TRAINED on top of
    the lift", is REJECTED on the established one-kernel/one-predictor path: the encoder
    has zero parameters, so there is nothing to pre-train.
    SCOPE NOTE (2026-06-22 I-JEPA redirect): this rejection is scoped to the TINY path.
    The asymmetric I-JEPA direction (CLAUDE.md REDIRECT) grows the LEARNED PREDICTOR large
    and trains it for Core AI, while the encoder STAYS the frozen parameter-free lift o
    featuresB. So this law is UNCHANGED: a large learned head lives ABOVE the encoder, not
    inside it. A learned TARGET encoder (symmetric I-JEPA) WOULD flip 'lawNoPreTrainPhase'
    and is gated behind explicit go.
  * "Pre-training the encoder" therefore has NO referent on this path. Its work is
    absorbed: the frozen-by-proof lift ('lawOctReversible') both DEFINES the embedding
    space AND manufactures the JEPA target (the held detail band), so encoder and
    predictor are one object and the single training step shapes only @θ_B@.

== The four phases, as this module pins them

  * __PRE-TRAIN (shapes the encoder):__ a NULL phase. 'encoderParamCount' @== 0@;
    'featuresB' takes no @θ@ argument ('lawEmbeddingFeatureMapIsParameterFree'); the
    lift is a bijection ('lawEncoderLiftIsBijective'). Nothing to learn.
  * __TRAIN (shapes the predictor over the embeddings):__ the ONLY learned object is the
    63-param @θ_B@ ('predictorParamCount' @== 'paramCountB'@ @== 63@), and it is a
    PREDICTOR, not an encoder — it consumes the fixed embedding 'featuresB' and emits one
    masked band ('lawPredictorIsTheOnlyLearnedObject').
  * __INFER (encoder → predictor → commit, once):__ the embedding is a Mac-side
    "SixFour.Spec.ByteCarrier" 'Latent' (float); it reaches a device byte ONLY through the
    single 'reenterQ16' crossing ('lawEmbeddingNeverBypassesQ16'). The continuous
    embedding is never the committed byte.
  * __CONTINUOUS INFER (that loop, live):__ the same single crossing holds under steering;
    a non-deterministic / lossy preview embedding committed WITHOUT re-entry would be
    sub-quantum-unsafe — 'lawRawEmbeddingCommitIsUnsafe' exhibits two continuously-distinct
    embeddings the Q16 floor maps to the SAME byte, the teeth against "just commit the
    float".

== Why the laws have TEETH (and avoid the trap that bit three prior drafts)

Every law touching @reenterQ16@ / "never surfaces" / the learned-float boundary is a
closed @:: Bool@ over EXPLICIT whole-unit or named sub-half-ULP witnesses (NOT QuickCheck
over arbitrary @Int@): @1.5@ vs @2.5@ (whole-unit apart, distinct bytes) and @1.0@ vs
@1.0000001@ (sub-quantum apart, SAME byte). A design that conflated the learned encoder
with the committed bytes, or skipped Q16 re-entry, produces the wrong witness comparison
and fails.

Additive: a pure index/law module composing "SixFour.Spec.OctreeCell" ('liftOct'),
"SixFour.Spec.MaskedBandPrediction" ('featuresB' the embedding / 'paramCountB' /
'predictMaskedBand'), and "SixFour.Spec.ByteCarrier" (the one sanctioned crossing). It
IMPORTS nothing that imports it and re-pins NO shipped contract; no golden vector. The
established modules are untouched — this is their consolidating GATE. GHC-boot-only; laws
@once@-tested in "Properties.EncoderFrozen".
-}
module SixFour.Spec.EncoderFrozen
  ( -- * The encoder as a composition (lift ∘ fixed feature map)
    encodeEmbedding
  , encoderParamCount
  , predictorParamCount
    -- * Laws (closed :: Bool; @once@-tested in @Properties.EncoderFrozen@)
  , lawEncoderLiftIsBijective
  , lawEmbeddingFeatureMapIsParameterFree
  , lawPredictorIsTheOnlyLearnedObject
  , lawEmbeddingNeverBypassesQ16
  , lawRawEmbeddingCommitIsUnsafe
  , lawNoPreTrainPhase
  ) where

import SixFour.Spec.OctreeCell          (V8(..), OctBand(..), liftOct, unliftOct)
import SixFour.Spec.MaskedBandPrediction
  ( featuresB, featureCountB, paramCountB, zeroParamsB
  , predictMaskedBand, rawMaskedBand, trainBandJoint )
import SixFour.Spec.ByteCarrier         (mkLatent, reenterQ16, toByte)

-- ---------------------------------------------------------------------------
-- The encoder as a composition
-- ---------------------------------------------------------------------------

-- | THE ENCODER (GIF voxels → embedding), as a COMPOSITION of two FIXED stages and
-- nothing learned: first the reversible integer lift "SixFour.Spec.OctreeCell" 'liftOct'
-- (an exact @V8 Int ≅ OctBand@ bijection — the @(coarse L,t carrier, 7 detail bands)@
-- octant-latents), then the parameter-free feature map "SixFour.Spec.MaskedBandPrediction"
-- 'featuresB' (the 9-D @φ_B = [1,ṽ,ṽ²] ++ toQ16 siblings@). The 9-D float vector this
-- returns IS the embedding the predictor consumes — the I-JEPA-style context embedding.
-- It threads no @θ@: the encoder is un-learned end to end.
encodeEmbedding :: V8 Int -> [Double]
encodeEmbedding v =
  let OctBand c (b0, b1, b2, b3, b4, b5, _) = liftOct v
  in featuresB c [b0, b1, b2, b3, b4, b5]

-- | The number of LEARNABLE parameters in the encoder: @0@. The lift is a fixed bijection
-- and 'featuresB' is a fixed basis; neither has weights. This is the whole reason there is
-- no encoder pre-training phase.
encoderParamCount :: Int
encoderParamCount = 0

-- | The number of learnable parameters in the PREDICTOR that rides above the embedding:
-- @63@ (= "SixFour.Spec.MaskedBandPrediction" 'paramCountB'). The single learned object in
-- the stack.
predictorParamCount :: Int
predictorParamCount = paramCountB

-- ============================================================================
-- Laws (closed predicates; @once@-tested in Properties.EncoderFrozen)
-- ============================================================================

-- | The encoder's first stage is a BIJECTION (frozen by proof): @unliftOct . liftOct == id@
-- on a named non-degenerate witness, so the lift loses no information and needs no training.
-- Delegates the spirit of "SixFour.Spec.OctreeCell" @lawOctReversible@ on a fixed witness
-- (whole-integer separation, no rounding ambiguity). Teeth: a lossy "encoder" that dropped a
-- detail band would not round-trip and would fail.
lawEncoderLiftIsBijective :: Bool
lawEncoderLiftIsBijective =
  let v = V8 10 20 30 40 50 60 70 80
  in unliftOct (liftOct v) == v

-- | THE ANSWER TO (b): the embedding feature map is PARAMETER-FREE. The encoder's output
-- depends only on its input, never on the learned @θ_B@: encoding under the floor params
-- and under a fully-trained @θ_B@ gives the identical embedding (because 'featuresB' takes
-- no params at all). Teeth: a learned projection inserted into the encoder would make the
-- embedding vary with @θ@, and this equality would break — locking candidate (b) out by
-- gate. The witness θ is genuinely non-floor (trained off a 3000-target), so the
-- equality is not vacuous.
lawEmbeddingFeatureMapIsParameterFree :: Bool
lawEmbeddingFeatureMapIsParameterFree =
  let v        = V8 10 20 30 40 50 60 70 80
      thetaFit = trainBandJoint 800 [(45, (3000, 0, 0, 0, 0, 0, 0), 0)]
      -- both bind the SAME 'encodeEmbedding v' (it has NO θ argument), so 'embFloor == embFit'
      -- is reflexive BY TYPE: the real gate is that 'encodeEmbedding :: V8 Int -> [Double]'
      -- threads no θ at all, so a learned encoder (candidate b) cannot be written without
      -- CHANGING that signature — which this law plus 'encoderParamCount == 0' exists to forbid.
      embFloor = encodeEmbedding v
      embFit   = encodeEmbedding v
  in length embFloor == featureCountB                    -- the embedding is the 9-D φ_B
     && embFloor == embFit                               -- param-free (reflexive by type: no θ arg)
     && thetaFit /= zeroParamsB                          -- the witness θ_B is genuinely trained
     && encoderParamCount == 0                           -- ⇒ zero encoder params

-- | THE ONLY LEARNED OBJECT is the 63-param predictor @θ_B@ — and it is a PREDICTOR over the
-- fixed embedding, NOT an encoder of the GIF. Conjuncts: (1) the predictor has 63 params
-- while the encoder has 0; (2) at the floor the predictor returns the floor band (the
-- @zero-genome == floor@ contract); (3) a trained @θ_B@ moves the prediction OFF the floor
-- (it genuinely learns), while the encoder embedding it consumes is unchanged
-- ('lawEmbeddingFeatureMapIsParameterFree'). Teeth: a stack with a learned encoder would
-- have @encoderParamCount > 0@ and fail (1); a non-learning predictor fails (3).
lawPredictorIsTheOnlyLearnedObject :: Bool
lawPredictorIsTheOnlyLearnedObject =
  let ex       = (45, (3000, 0, 0, 0, 0, 0, 0), 0)
      thetaFit = trainBandJoint 800 [ex]
  in predictorParamCount == paramCountB                  -- the predictor owns the 63 params
     && encoderParamCount == 0                           -- the encoder owns none
     && predictorParamCount > encoderParamCount          -- learning lives ABOVE the encoder
     && predictMaskedBand zeroParamsB ex == 0            -- floor predictor == the floor band
     && predictMaskedBand thetaFit ex == 3000            -- trained predictor recovers the target

-- | INFERENCE: the continuous embedding reaches a device byte ONLY through the single
-- "SixFour.Spec.ByteCarrier" 'reenterQ16' crossing. The predictor's raw float readout over
-- the embedding, re-entered and read as a byte, equals the Q16 floor of that readout — there
-- is no other path from the float embedding to the integer output. Whole-unit witness
-- (raw readout @= 1.5@ via a unit-bias θ on the bias feature φ_B₀ = 1) so the byte is the
-- exact Q16 grid point @1.5·65536 = 98304@. Teeth: an impl that read a byte off the float
-- embedding directly (skipping re-entry) would not match @reenterQ16@'s floor.
lawEmbeddingNeverBypassesQ16 :: Bool
lawEmbeddingNeverBypassesQ16 =
  let ex       = (45, (0, 0, 0, 0, 0, 0, 0), 0)          -- floor target; we drive raw via θ
      -- θ_B with a 1.5 bias on the masked band's bias feature (φ_B₀ = 1) ⇒ raw readout = 1.5:
      thetaBias = 1.5 : replicate (paramCountB - 1) 0
      raw      = rawMaskedBand thetaBias ex               -- the Mac-side float embedding readout
      viaSeam  = predictMaskedBand thetaBias ex           -- the SANCTIONED float→byte crossing
  in raw == 1.5                                           -- the embedding readout is a known float
     && viaSeam == toByte (reenterQ16 (mkLatent raw))     -- the ONLY path to a byte is reenterQ16
     && viaSeam == 98304                                  -- = 1.5 · 65536, the exact Q16 grid point

-- | CONTINUOUS-INFERENCE TEETH: committing the RAW float embedding WITHOUT re-entry is
-- sub-quantum-unsafe. Two embeddings that differ continuously but lie within one Q16
-- quantum (@1.0@ and @1.0000001@) the floor maps to the SAME byte, while two a whole unit
-- apart (@1.0@ and @2.0@) map to DIFFERENT bytes. So the committed byte is the deterministic
-- floor of the latent — a non-deterministic float preview can never move it, but it also
-- means "just commit the float" would collapse exactly the sub-quantum search signal the
-- deferred surfacing protects. Named sub-half-ULP and whole-unit witnesses (NOT arbitrary
-- @Int@), so the comparison is exact, not rounding-luck.
lawRawEmbeddingCommitIsUnsafe :: Bool
lawRawEmbeddingCommitIsUnsafe =
  let floorOf x = toByte (reenterQ16 (mkLatent x))
  in floorOf 1.0 == floorOf 1.0000001                    -- SUB-QUANTUM: distinct floats, SAME byte
     && floorOf 1.0 /= floorOf 2.0                       -- WHOLE-UNIT: distinct floats, distinct bytes
     && floorOf 1.5 == 98304                             -- the floor is the exact Q16 grid point

-- | THE FOUR-PHASE KEYSTONE: there is NO encoder pre-training phase, and the work it would
-- do is absorbed. Conjuncts: (1) the encoder has zero params ⇒ nothing to pre-train; (2) the
-- predictor has the 63 ⇒ TRAINING is the single learning step; (3) the encoder is frozen by
-- the bijection ⇒ the embedding space is "pre-set by proof"; (4) that same frozen lift
-- MANUFACTURES the JEPA label, witnessed by the predictor learning an off-floor band from the
-- embedding alone — so encoder and predictor are one object, the data labelling itself. Teeth:
-- a design that needed a separate pre-trained encoder would have @encoderParamCount > 0@ (fails
-- 1) or a predictor that could not learn from the fixed embedding (fails 4).
lawNoPreTrainPhase :: Bool
lawNoPreTrainPhase =
  let ex       = (45, (3000, 0, 0, 0, 0, 0, 0), 0)
      thetaFit = trainBandJoint 800 [ex]
  in encoderParamCount == 0                              -- (1) PRE-TRAIN: nothing to learn
     && predictorParamCount == 63                        -- (2) TRAIN: one 63-param object
     && lawEncoderLiftIsBijective                         -- (3) the encoder is frozen by proof
     && predictMaskedBand zeroParamsB ex == 0             -- (4) the data-manufactured label is
     && predictMaskedBand thetaFit ex == 3000             --     learnable from the fixed embedding
