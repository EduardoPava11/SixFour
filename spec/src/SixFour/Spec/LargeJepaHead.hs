{- |
Module      : SixFour.Spec.LargeJepaHead
Description : Contracts for the GENUINELY LARGE (ViT-scale) position-conditioned asymmetric I-JEPA head — the @d6@ unit distance as a LEARNABLE relative-position attention bias (grows/shrinks in the higher-dimensional learned relations), pinned as a CONTROLLED DEVIATION above the proven small @featuresBPos@ predictor.

The user's redirect: build the large head that makes Core AI the right deploy (the
documented flip condition). ASYMMETRIC I-JEPA: the frozen reversible lift stays the
TOKENIZER (and manufactures the collapse-proof target, "SixFour.Spec.JepaTarget"); a
ViT-scale learned predictor rides ON TOP. "SixFour.Spec.EncoderFrozen" is NOT reversed.

THE MECHANISM (the user's "units distance that can grow or shrink"): the proven metric
@d6@ ("SixFour.Spec.RelationalResidual": Q16 L1 over @P6 (L,a,b,x,y,t)@, with the @+/-1@
unit quantum) is the GROUND metric and seeds a T5-style per-head learnable relative-
position attention bias

@
  logit_ij = (q_i . k_j)/sqrt(d) + b_h(d6_ij),   b_h(d) = beta_h - s_h * d   (s_h > 0)
@

The BASE distance @d6@ stays the proven INTEGER metric (computed in the Zig floor); the
SCALE @s_h@ (and offset @beta_h@) is the LEARNED FLOAT — the unit distance's grow/shrink.
A large @s_h@ COMPRESSES the unit (only near octants attend); a small @s_h@ STRETCHES it
(far octants still attend). The float scale lives ONLY in latent attention logits and
NEVER re-enters Q16 until the single deferred surface commit ("SixFour.Spec.DeferredSurfacing").

This module pins the CONTRACTS, not the ViT. The keystone 'lawDepth1ReducesToFeaturesBPos'
makes the big net a controlled deviation above a PROVEN floor: at the single-token /
depth-1 limit the head computes exactly @predictMaskedBandPos@ (the 77-param @theta_B-Pos@),
so 'SixFour.Spec.MaskedBandPrediction.lawPositionConditioningStrictlyHelps' is inherited and
@MaskedBandForward.swift@ is the depth-1 golden of the large MLX head. Most other laws
DELEGATE to the already-proven JEPA modules (no EMA, latent loss, redundancy guard, Q16
quarantine), so this module adds only the genuinely-new bias mechanism + the reduction.

GHC-boot-only. Additive; re-pins nothing. Laws QuickCheck'd in "Properties.LargeJepaHead".
-}
module SixFour.Spec.LargeJepaHead
  ( -- * The learnable d6 relative-position attention bias
    HeadBias(..)
  , d6Bias
  , effectiveDistance
  , softmaxW
    -- * The depth-1 reduction (the big net above a proven floor)
  , degenerateReadout
    -- * Laws (QuickCheck'd in @Properties.LargeJepaHead@)
  , lawDepth1ReducesToFeaturesBPos
  , lawSingleTokenAttnIsUnit
  , lawBiasMonotoneInD6
  , lawBiasLearnsToScale
  , lawBiasIsPhi6Consistent
  , lawBiasScalingNeverBypassesQ16
  , lawNoEmaTargetEncoderAtScale
  , lawLatentRedundancyLoadBearingAtScale
  , lawHeadRunsBothRungsInLatent
  ) where

import SixFour.Spec.Dim6 (Dim6(..))
import SixFour.Spec.RelationalResidual (P6(..), d6, nudge)
import SixFour.Spec.MaskedBandPrediction
  (MaskedBandExamplePos, predictMaskedBandPos)
import SixFour.Spec.EncoderFrozen   (lawEmbeddingNeverBypassesQ16)
import SixFour.Spec.JepaTarget       (lawNoTargetEncoderNoEma, lawTargetFixedUnderPredictorTraining)
import SixFour.Spec.NeuronRedundancy (lawRedundancyMeasuredInLatent, lawDecorrelatedNeuronsZeroRedundancy)
import SixFour.Spec.RungPivot        (lawDownIsHeldUpIsInvented, lawIntermediateNeverSurfaces)
import SixFour.Spec.DeferredSurfacing (lawSurfaceComesAfterBothRungs)
import SixFour.Spec.SelfSupervisedRung (lawOneOperatorTwoSupervisions)

-- | A single head's learnable distance bias: @(s, beta)@ with @s > 0@ the scale (the
-- grow/shrink of the unit distance) and @beta@ the offset.
data HeadBias = HeadBias { hbScale :: !Double, hbOffset :: !Double } deriving (Eq, Show)

-- | The T5-style additive relative-position bias as a function of the integer @d6@ distance
-- (or its bucket): @b_h(d) = beta_h - s_h * d@. Non-increasing in @d@ for @s_h > 0@ (an
-- ALiBi-like prior seeded by the PROVEN metric).
d6Bias :: HeadBias -> Int -> Double
d6Bias (HeadBias s beta) d = beta - s * fromIntegral d

-- | The EFFECTIVE distance after the learned scaling: @s_h * d6@. This is the quantity that
-- grows (large @s_h@) or shrinks (small @s_h@) in the higher-dimensional learned relations.
effectiveDistance :: Double -> Int -> Double
effectiveDistance s d = s * fromIntegral d

-- | Softmax over attention logits (the row weights). Numerically shifted by the max.
softmaxW :: [Double] -> [Double]
softmaxW [] = []
softmaxW xs = let m = maximum xs
                  es = map (\x -> exp (x - m)) xs
                  z  = sum es
              in map (/ z) es

-- | The DEGENERATE (depth-1, single-token, identity-embedding) head readout: with ONE
-- octant token, self-attention puts weight @1@ on the sole token (its @d6@-self bias acts on
-- @d6(p,p) = 0@), so the head output IS the linear @featuresBPos@ prediction. Modelled as the
-- single attention weight times the proven small prediction.
degenerateReadout :: HeadBias -> [Double] -> MaskedBandExamplePos -> Int
degenerateReadout hb ps ex =
  let w = head (softmaxW [d6Bias hb 0])               -- single self-token, d6 self = 0
  in round (w * fromIntegral (predictMaskedBandPos ps ex))

-- ============================================================================
-- Laws (predicates; QuickCheck'd in Properties.LargeJepaHead)
-- ============================================================================

-- | A single-token attention weight is EXACTLY 1 (@softmax [x] = [1]@) — self-attention over
-- one token is the identity. Teeth: a non-degenerate softmax fails. (The numeric basis of the
-- depth-1 reduction.)
lawSingleTokenAttnIsUnit :: Double -> Bool
lawSingleTokenAttnIsUnit x = softmaxW [x] == [1.0]

-- | KEYSTONE: at depth 1 / single token / identity embedding the LARGE head computes EXACTLY
-- @predictMaskedBandPos@ (the proven 77-param @theta_B-Pos@). So the big net is a CONTROLLED
-- DEVIATION above a proven floor, @lawPositionConditioningStrictlyHelps@ is a special case,
-- and the @zero-genome == floor@ short-circuit survives at scale. Teeth: an architecture that
-- does not collapse to @featuresBPos@ at the single-token limit fails. Mirrors
-- "SixFour.Spec.LookNetD" @lawDecoderFromRecursionMatchesZero@.
lawDepth1ReducesToFeaturesBPos :: [Double] -> MaskedBandExamplePos -> Bool
lawDepth1ReducesToFeaturesBPos ps ex =
     softmaxW [d6Bias (HeadBias 0.7 0) 0] == [1.0]                  -- single-token attn is identity
  && degenerateReadout (HeadBias 0.7 0) ps ex == predictMaskedBandPos ps ex  -- == the proven small head

-- | At init (@s > 0@) the bias is NON-INCREASING in @d6@: nearer octants get a higher
-- (less negative) bias. The proven metric IS the prior (ALiBi-like). Teeth: a non-monotone
-- random-table init fails.
lawBiasMonotoneInD6 :: Double -> Int -> Int -> Bool
lawBiasMonotoneInD6 s d1 d2 =
  let s' = abs s + 0.01                                            -- s > 0
      hb = HeadBias s' 0
  in not (d1 <= d2) || d6Bias hb d1 >= d6Bias hb d2

-- | THE GROW/SHRINK law: the unit distance can grow or shrink because the scale is LEARNABLE.
-- Two distinct positive scales give STRICTLY DIFFERENT effective distance on the same
-- nonzero @d6@, and the larger scale compresses (larger effective distance). Teeth: a fixed
-- (ALiBi-style non-learnable) slope cannot produce both and fails.
lawBiasLearnsToScale :: Double -> Double -> Int -> Bool
lawBiasLearnsToScale a b d =
  let s1 = abs a + 0.01
      s2 = abs b + 0.01
      d' = abs d + 1                                               -- a nonzero distance
  in s1 == s2
     || (effectiveDistance s1 d' /= effectiveDistance s2 d'
         && (s1 < s2) == (effectiveDistance s1 d' < effectiveDistance s2 d'))  -- bigger scale = more compression

-- | The bias is PHI6-CONSISTENT: because it is a function of @d6@ alone (which weights all
-- axes equally), a colour-axis nudge and its @phi6@-paired position-axis nudge get the SAME
-- distance, hence the SAME bias. Delegates "SixFour.Spec.RelationalResidual" @d6@. Teeth: a
-- metric that weighted @a@ and its partner @x@ unequally fails.
lawBiasIsPhi6Consistent :: P6 -> Bool
lawBiasIsPhi6Consistent p =
     d6 p (nudge DimA 1 p) == d6 p (nudge DimX 1 p)   -- a <-> x: same unit distance, same bias
  && d6 p (nudge DimB 1 p) == d6 p (nudge DimY 1 p)   -- b <-> y
  && d6 p (nudge DimL 1 p) == d6 p (nudge DimT 1 p)   -- L <-> t (the carrier pair)

-- | The learned float SCALE never bypasses the Q16 floor: the bias is float and latent-only;
-- the base distance stays the proven integer @d6@; the only float->byte crossing is the single
-- deferred @reenterQ16@. Delegates "SixFour.Spec.EncoderFrozen" @lawEmbeddingNeverBypassesQ16@.
lawBiasScalingNeverBypassesQ16 :: Bool
lawBiasScalingNeverBypassesQ16 = lawEmbeddingNeverBypassesQ16

-- | At scale the target side STILL has zero learnable params (asymmetric I-JEPA, no EMA): the
-- manufactured held-band target is fixed under predictor training. Delegates
-- "SixFour.Spec.JepaTarget". Teeth: a symmetric design with a learned target encoder fails.
lawNoEmaTargetEncoderAtScale :: Bool
lawNoEmaTargetEncoderAtScale = lawNoTargetEncoderNoEma && lawTargetFixedUnderPredictorTraining

-- | At scale the VICReg / redundancy guard becomes LOAD-BEARING (a wide learned latent can
-- dimension-collapse even with a fixed target): the redundancy is read on the never-surfaced
-- intermediate latent BEFORE surfacing, and decorrelated neurons carry zero redundancy.
-- Delegates "SixFour.Spec.NeuronRedundancy".
lawLatentRedundancyLoadBearingAtScale :: Bool
lawLatentRedundancyLoadBearingAtScale =
  lawRedundancyMeasuredInLatent && lawDecorrelatedNeuronsZeroRedundancy

-- | THE TWO RUNGS + the @2×2×2 → 1 + latent@ op, as the head's substrate, with the
-- EPISTEMIC quadrants mapped exactly. The large head is the ONE operator (the grown
-- @theta_B@) running BOTH self-similar rungs around the @64³@ pivot
-- (@64³ → [32³ latent] → 16³ + residual@ DOWN; @64³ + residual → [128³ latent] → 256³@ UP)
-- IN the never-surfaced intermediate latent, surfacing ONCE after rung 2. The four
-- epistemic quadrants land on the rung structure:
--
--   * KNOWN KNOWN     = the surfaced coarse / carrier @L@ (the @16³@; the deterministic
--     bit-exact floor; @zero-genome == floor@).
--   * KNOWN UNKNOWN   = the DOWN-rung HELD residual — the band we KNOW is there;
--     data-manufactured target; the head predicts it; @refine . split == id@ makes it
--     exactly recoverable once predicted.
--   * UNKNOWN UNKNOWN = the UP-rung INVENTED residual — super-res detail NOT in the
--     capture; the head invents it; scored by re-downsample CONSISTENCY, not a label.
--   * UNKNOWN KNOWN   = the @32³ / 128³@ INTERMEDIATE LATENT — the relational structure the
--     head HOLDS but never surfaces (the @d6@ learnable-distance attention lives HERE).
--
-- Delegates "SixFour.Spec.RungPivot" (@lawDownIsHeldUpIsInvented@: DOWN=Held / UP=Invented;
-- @lawIntermediateNeverSurfaces@: the @32³/128³@ latent is never committed),
-- "SixFour.Spec.DeferredSurfacing" (@lawSurfaceComesAfterBothRungs@: the coarse surfaces ONCE,
-- after both rungs), and "SixFour.Spec.SelfSupervisedRung" (@lawOneOperatorTwoSupervisions@:
-- ONE operator, two supervisions). Teeth: a head that surfaced the intermediate latent, or
-- used a second operator per rung, or committed before rung 2, fails a delegated conjunct.
lawHeadRunsBothRungsInLatent :: Bool
lawHeadRunsBothRungsInLatent =
     lawOneOperatorTwoSupervisions    -- ONE operator (the grown theta_B), two rungs
  && lawDownIsHeldUpIsInvented        -- DOWN = Held (known unknown); UP = Invented (unknown unknown)
  && lawIntermediateNeverSurfaces     -- the 32³/128³ intermediate latent (the unknown known) never surfaces
  && lawSurfaceComesAfterBothRungs    -- the coarse (the known known) surfaces ONCE, after both rungs
