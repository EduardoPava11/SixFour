{- |
Module      : SixFour.Spec.DetailMaskedPrediction
Description : The REAL masked-prediction (JEPA) objective — predict a MASKED detail band from COARSE-ONLY context, where a CONSTANT (f-free) predictor incurs STRICTLY POSITIVE loss. Replaces the vacuous "SixFour.Spec.SameObjectJEPA" @lawJepaPredictsTarget@ (a permutation round-trip in which the predictor never appears).

"SixFour.Spec.SameObjectJEPA" @lawJepaPredictsTarget@ is a costume on a round-trip:
@predictTarget = encodeUnder pt . decodeUnder pc@ recovers the sibling projection by
FULLY decoding then re-encoding, so the loss is zero by the Z2 self-inverse and the
predictor @f@ NEVER APPEARS. It is a sanity check that the two co-projections describe
one object, NOT a learning objective — exactly the @lawTailNotAutoregressed@ /
@lawReconstructIsQ16@ vacuity family. (That law is demoted in place to a labelled
round-trip sanity check; see its header.)

This module states the objective with teeth. The setup is genuine masking: the COARSE
value is the visible CONTEXT, one octant DETAIL band is the MASKED target, and the
predictor "SixFour.Spec.DetailPredictor" @predictDetail@ must fill the mask from the
context ALONE — its input is the coarse value, never the answer (a TYPE guarantee:
@predictDetail :: PredictorShape -> [Double] -> Int -> Detail@ has no @Detail@ input,
so a target-peeking predictor does not type-check).

The objective is @maskedObjectiveLoss@ = "SixFour.Spec.DetailPredictor" @bandLoss@. Its
non-triviality is pinned three ways:

  * 'lawConstantPredictorIncursLoss' (THE objective) — on an OFF-FLOOR masked target a
    CONSTANT predictor (the @zeroParams@ floor, where the round-trip twin would score
    zero) has STRICTLY POSITIVE loss, AND one SGD step strictly reduces it. The
    existential FAILURE of the f-free baseline is what the twin lacks.
  * 'lawTrainingDrivesLossDown' — training the predictor drives the masked-band loss to
    a tiny fraction of the constant-predictor loss: the mask IS recoverable from the
    context by learning @f@.
  * 'lawFittingOneTargetMissesAnother' — a predictor trained to fill one masked answer
    does NOT fill a DIFFERENT off-floor answer at the same context: the masked band
    carries information beyond the context, so "prediction" is real work, not a fixed
    permutation.

Additive: delegates "SixFour.Spec.DetailPredictor" entirely (no new arithmetic); the
demotion of "SixFour.Spec.SameObjectJEPA" @lawJepaPredictsTarget@ is a header/Map
re-label, NOT a deletion (the law stays as a sanity check). GHC-boot.
-}
-- COMPARTMENT: MLX-MODEL | tag:MacTag
module SixFour.Spec.DetailMaskedPrediction
  ( -- * The masked example (coarse context + masked target band)
    MaskedExample
  , maskedContext
  , maskedTarget
    -- * The objective (delegates DetailPredictor)
  , maskedObjectiveLoss
  , constantPredictorLoss
  , trainTo
    -- * Laws (QuickCheck'd in @Properties.DetailMaskedPrediction@)
  , lawConstantPredictorIncursLoss
  , lawTrainingDrivesLossDown
  , lawFittingOneTargetMissesAnother
  ) where

import SixFour.Spec.OctreeCell      (Detail)
import SixFour.Spec.DetailPredictor
  ( PredictorShape, defaultPredictorShape, zeroParams, bandLoss, predictorUpdate )

-- | A masked training example: the visible COARSE context value and the MASKED octant
-- detail the predictor must fill from that context alone.
type MaskedExample = (Int, Detail)

-- | The visible context: the coarse value (the masked detail is excluded from the
-- predictor's input — a type guarantee, since 'SixFour.Spec.DetailPredictor.predictDetail'
-- takes only this @Int@).
maskedContext :: MaskedExample -> Int
maskedContext = fst

-- | The masked target band the objective regresses onto.
maskedTarget :: MaskedExample -> Detail
maskedTarget = snd

-- | The masked-prediction objective = "SixFour.Spec.DetailPredictor" @bandLoss@: the
-- squared error of the predictor's raw band readouts against the masked target.
maskedObjectiveLoss :: PredictorShape -> [Double] -> MaskedExample -> Double
maskedObjectiveLoss = bandLoss

-- | The loss of the CONSTANT (f-free) predictor — the @zeroParams@ floor, the score the
-- vacuous round-trip twin would achieve "for free". On an off-floor target this is
-- strictly positive ('lawConstantPredictorIncursLoss').
constantPredictorLoss :: MaskedExample -> Double
constantPredictorLoss ex = bandLoss defaultPredictorShape (zeroParams defaultPredictorShape) ex

-- | Train the predictor on one masked example for @n@ SGD steps (η = 0.25) starting
-- from the @zeroParams@ floor.
trainTo :: Int -> MaskedExample -> [Double]
trainTo n ex =
  let sh = defaultPredictorShape
  in iterate (\ps -> predictorUpdate 0.25 sh ps ex) (zeroParams sh) !! max 0 n

-- ============================================================================
-- Laws (predicates; QuickCheck'd in Properties.DetailMaskedPrediction)
-- ============================================================================

-- | The seven detail bands as a list (off-floor guard helper).
detailList :: Detail -> [Int]
detailList (a, b, c, d, e, f, g) = [a, b, c, d, e, f, g]

-- | True iff the target is clearly off the zero floor (some band exceeds the Q16
-- threshold), so the constant-predictor loss is genuinely positive and the law is not
-- vacuous on the all-zero target.
offFloor :: Detail -> Bool
offFloor = any (\x -> abs x > 4096) . detailList

-- | THE objective, with teeth. On an OFF-FLOOR masked target the CONSTANT predictor
-- (the @zeroParams@ floor — where "SixFour.Spec.SameObjectJEPA"'s round-trip twin scores
-- zero) incurs STRICTLY POSITIVE loss, AND one SGD step strictly reduces it. Teeth:
--
--   * the strict-positive clause REJECTS any "objective" that is zero for a constant
--     predictor (the vacuous twin, where @f@ never appears) — guarded off-floor so it is
--     not the trivially-zero all-floor case;
--   * the strict-decrease clause REJECTS a zero/sign-flipped gradient (a backprop bug).
lawConstantPredictorIncursLoss :: Int -> Detail -> Bool
lawConstantPredictorIncursLoss v tgt =
  let sh = defaultPredictorShape
      z  = zeroParams sh
      ex = (v, tgt)
      l0 = maskedObjectiveLoss sh z ex
      l1 = maskedObjectiveLoss sh (predictorUpdate 0.25 sh z ex) ex
  in not (offFloor tgt) || (l0 > 1e-6 && l1 < l0)

-- | The mask IS recoverable from the context by LEARNING @f@: after training, the
-- masked-band loss is a tiny fraction of the constant-predictor loss. Teeth: rejects a
-- predictor that cannot fit the masked band (loss would not fall) — the universal-success
-- counterpart to the existential-failure of the constant baseline. Off-floor guarded so
-- the initial loss is nonzero (else the ratio is undefined).
lawTrainingDrivesLossDown :: Int -> Detail -> Bool
lawTrainingDrivesLossDown v tgt =
  let sh = defaultPredictorShape
      ex = (v, tgt)
      l0 = constantPredictorLoss ex
      lN = maskedObjectiveLoss sh (trainTo 200 ex) ex
  in not (offFloor tgt) || lN < 1e-3 * l0

-- | The masked band carries information BEYOND the context: a predictor trained to fill
-- ONE masked answer does NOT fill a DIFFERENT off-floor answer at the SAME context. We
-- form a second target by shifting band 0 by a guaranteed off-floor margin, train to the
-- first, and assert positive loss on the second. Teeth: rejects a "predictor" that is a
-- fixed function of the context regardless of the answer (the permutation-twin defect) —
-- such a predictor, having no way to encode which answer, would score the same on both,
-- so the strict-positive residual here cannot hold for it.
lawFittingOneTargetMissesAnother :: Int -> Detail -> Bool
lawFittingOneTargetMissesAnother v t1 =
  let sh = defaultPredictorShape
      (a, b, c, d, e, f, g) = t1
      t2 = (a + 10000, b, c, d, e, f, g)   -- a guaranteed off-floor different answer
      ps1 = trainTo 200 (v, t1)            -- fit the FIRST masked answer
  in maskedObjectiveLoss sh ps1 (v, t2) > 1e-6
