{- |
Module      : SixFour.Spec.DualEncoderJepa
Description : THE REDESIGNED I-JEPA — a DUAL-ENCODER objective: predict a masked band of one encoder from the VISIBLE CONTEXT OF THE OTHER. Encoder A (construction: palette+index) and Encoder B (perceptual: the (L,a,b,x,y,t) cloud) are proven the same object ("SixFour.Spec.GifDualView"); this module makes cross-encoder context the learning signal, anchored by the data-manufactured target (no EMA, no collapse) and reusing the H-JEPA scale spine.

The old I-JEPA had ONE encoder (the frozen lift → φ_B) and predicted a masked band from
SAME-encoder siblings ("SixFour.Spec.MaskedBandPrediction"). The redesign adds the second
encoder and the cross-prediction: the masked region of Encoder B is predicted from Encoder
A's visible context (the palette + index of the visible region) and vice versa. Because the
palette is a GLOBAL object shared across the frame, A's visible context constrains B's masked
band in a way B's local siblings cannot — so the joint context is strictly more informative.

  * 'DualExample' — one masked-prediction example: the same masked band seen with a
    B-encoder context and an A-encoder context, plus the true held band.
  * 'bestLossUnder' — the minimal achievable squared-error of a predictor restricted to a
    given context key (the information floor of that context).
  * 'lawCrossEncoderContextStrictlyHelps' — KEYSTONE: when the A-context resolves an
    ambiguity the B-context leaves, the joint (A,B) predictor achieves STRICTLY lower loss
    than B-context alone (and exactly zero on the witness). The mirror of
    "SixFour.Spec.MaskedBandPrediction" @lawSiblingContextStrictlyHelps@ — this is WHY two
    encoders, not one. Teeth: when A is redundant (its context does not vary), the joint
    loss EQUALS the B-only loss — so the law is a genuine separation, not a tautology.
  * 'lawDualTargetIsDataManufactured' — the target is the bit-exact held band, NOT a learned
    EMA encoder output, so no collapse (delegates "SixFour.Spec.JepaTarget").
  * 'lawDualReusesScaleSpine' — the cross-prediction IS the H-JEPA inter-level hop (delegates
    "SixFour.Spec.HJepaLevels" @lawInterLevelPredictorIsCrossScale@).
  * 'lawNoEncoderBypassesQ16' — both encoders commit through the single @reenterQ16@ crossing
    (delegates "SixFour.Spec.EncoderFrozen").

Additive: reuses "SixFour.Spec.JepaTarget", "SixFour.Spec.HJepaLevels",
"SixFour.Spec.EncoderFrozen". GHC-boot-only. Laws QuickCheck'd in
"Properties.DualEncoderJepa".
-}
-- COMPARTMENT: MLX-MODEL | tag:MacTag
module SixFour.Spec.DualEncoderJepa
  ( -- * The dual-encoder masked-prediction example
    DualExample(..)
  , bestLossUnder
  , bOnlyLoss
  , jointLoss
    -- * Laws (QuickCheck'd in @Properties.DualEncoderJepa@)
  , lawCrossEncoderContextStrictlyHelps
  , lawDualTargetIsDataManufactured
  , lawDualReusesScaleSpine
  , lawNoEncoderBypassesQ16
  ) where

import Data.List (nub)

import qualified SixFour.Spec.JepaTarget   as JT
import qualified SixFour.Spec.HJepaLevels  as HJ
import qualified SixFour.Spec.EncoderFrozen as EF

-- | One masked-prediction example. 'exBContext' is what Encoder B reveals (its local visible
-- siblings, summarised as a key); 'exAContext' is what Encoder A reveals (the palette/index
-- structure of the visible region, summarised as a key); 'exTrueBand' is the held band the
-- predictor must regress.
data DualExample = DualExample
  { exBContext :: !Int   -- ^ Encoder B's visible context key.
  , exAContext :: !Int   -- ^ Encoder A's visible context key.
  , exTrueBand :: !Int   -- ^ the true held band (the data-manufactured target).
  } deriving (Eq, Show)

-- | Minimal sum of squared errors achievable by a single integer constant predictor over a
-- list of target values — the information floor: @min_c Σ (c - v)²@.
sseBestConst :: [Int] -> Int
sseBestConst [] = 0
sseBestConst vs =
  let lo = minimum vs; hi = maximum vs
  in minimum [ sum [ (c - v) ^ (2 :: Int) | v <- vs ] | c <- [lo .. hi] ]

-- | The best achievable loss of a predictor that may depend ONLY on the given context key:
-- group the examples by key, fit the best constant per group, sum. A larger (more
-- informative) key partitions finer, so its best loss is never larger.
bestLossUnder :: Eq k => (DualExample -> k) -> [DualExample] -> Int
bestLossUnder key exs =
  sum [ sseBestConst [ exTrueBand e | e <- exs, key e == k ]
      | k <- nub (map key exs) ]

-- | The information floor of the B-encoder context alone.
bOnlyLoss :: [DualExample] -> Int
bOnlyLoss = bestLossUnder exBContext

-- | The information floor of the JOINT (A,B) cross-encoder context.
jointLoss :: [DualExample] -> Int
jointLoss = bestLossUnder (\e -> (exBContext e, exAContext e))

-- ============================================================================
-- Laws (predicates; QuickCheck'd in Properties.DualEncoderJepa)
-- ============================================================================

-- | KEYSTONE: cross-encoder context STRICTLY helps. On a witness where two examples collide
-- under Encoder B's context (same 'exBContext') but are separated by Encoder A's context
-- (different 'exAContext') and have different true bands, the B-only predictor cannot tell
-- them apart and incurs positive loss, while the joint (A,B) predictor resolves them and
-- reaches zero. So @jointLoss < bOnlyLoss@. TEETH (the second clause): when A is REDUNDANT
-- (its context does not vary across the collision), the joint loss EQUALS the B-only loss —
-- proving the win comes from A carrying real information, not from the extra key alone. This
-- is the dual-encoder mirror of "SixFour.Spec.MaskedBandPrediction"
-- @lawSiblingContextStrictlyHelps@.
lawCrossEncoderContextStrictlyHelps :: Bool
lawCrossEncoderContextStrictlyHelps =
  let -- A resolves the collision B leaves: same B-context 5, different A-context, different band
      helpful   = [ DualExample 5 0 10, DualExample 5 1 20 ]
      -- A is redundant: same B-context, SAME A-context — A adds nothing
      redundant = [ DualExample 5 0 10, DualExample 5 0 20 ]
  in jointLoss helpful == 0                         -- A fully resolves the masked band
     && jointLoss helpful < bOnlyLoss helpful       -- cross-encoder context STRICTLY helps
     && bOnlyLoss helpful > 0                        -- B alone cannot (the collision)
     && jointLoss redundant == bOnlyLoss redundant   -- teeth: no free win when A is redundant

-- | The dual-encoder target is the bit-exact data-manufactured held band, NOT a learned EMA
-- target-encoder output — so there is nothing to collapse and no EMA. Delegates
-- "SixFour.Spec.JepaTarget" (the I-JEPA correspondence-as-theorems), which the redesign
-- inherits unchanged: adding a second CONTEXT encoder does not add a target encoder.
lawDualTargetIsDataManufactured :: Bool
lawDualTargetIsDataManufactured =
     JT.lawTargetIsDataManufacturedNotEncoded
  && JT.lawNoTargetEncoderNoEma
  && JT.lawCollapseIsRejected

-- | The cross-encoder prediction IS the H-JEPA inter-level hop: the single predictor edge of
-- the hierarchy is the cross-SCALE climb (Analysis → Synthesis), and the dual-encoder
-- objective rides exactly that edge. Delegates "SixFour.Spec.HJepaLevels"
-- @lawInterLevelPredictorIsCrossScale@.
lawDualReusesScaleSpine :: Bool
lawDualReusesScaleSpine = HJ.lawInterLevelPredictorIsCrossScale

-- | Neither encoder bypasses the integer floor: every embedding commits through the single
-- @reenterQ16@ crossing, so the dual-encoder predictor's float latents can never originate a
-- committed byte. Delegates "SixFour.Spec.EncoderFrozen" @lawEmbeddingNeverBypassesQ16@ (and
-- the frozen-lift bijection the tokenizer rests on).
lawNoEncoderBypassesQ16 :: Bool
lawNoEncoderBypassesQ16 =
     EF.lawEmbeddingNeverBypassesQ16
  && EF.lawEncoderLiftIsBijective
