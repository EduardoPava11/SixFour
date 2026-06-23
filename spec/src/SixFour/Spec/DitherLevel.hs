{- |
Module      : SixFour.Spec.DitherLevel
Description : Dither as the per-pixel continuous latent z (H-JEPA §4.6), realized into a binary spatiotemporal stream by a MOMENT-CONSERVING DECODER — unbiased in the loop mean, but NOT reversible at finite T. The float-side wrapper over "SixFour.Spec.Dither"; lives on the display (METAL-GPU) side, never on the Q16 floor.

A dithered pixel over the T-frame loop is a Bernoulli process whose continuous position
@p ∈ [0,1]@ is the latent the network organizes. The eye time-averages, so the perceived
colour is the loop MEAN @(1-p)·anchor + p·partner@ ("SixFour.Spec.Dither" @ditheredColor@).
This module names the @p@-field ↔ realized-stream map as what it is: a decoder whose
pushforward conserves the FIRST MOMENT (the colour) while DESTROYING the per-frame bit.

  * 'realizeStream' — the T-frame bit stream for a continuous @p@ under the golden
    low-discrepancy ordering ("SixFour.Spec.Dither" @realize@ ∘ @goldenThresholds@).
  * 'lawRealizationUnbiased' — the loop mean recovers @p@ to within the ordering's
    discrepancy (the colour survives).
  * 'lawRealizationIsNotReversible' — the deliberately NEGATIVE keystone: two DISTINCT @p@
    values produce the SAME finite-T stream, so the forward map is not injective and the
    per-frame bit is unrecoverable. This is why dither is a display decoder, NOT a reversible
    Q16-floor operation.
  * 'lawDitherFlickerPeaksAtHalf' — the flicker (the latent's variance, the unpredictable
    residual) is maximal at @p = 0.5@ ("SixFour.Spec.Dither" @lawVarianceMaxAtHalf@); the
    golden ordering tames it while preserving the mean.

Additive: a thin float wrapper delegating "SixFour.Spec.Dither" + "SixFour.Spec.Color". No
Q16 floor touched (dither commits via the integer @SpatialDither.ditherFrameQ16@ path, which
needs no float crossing; this module is the latent-side description). GHC-boot-only. Laws
QuickCheck'd in "Properties.DitherLevel".
-}
-- COMPARTMENT: METAL-GPU | tag:none
module SixFour.Spec.DitherLevel
  ( -- * The continuous dither latent and its realization
    realizeStream
  , latentColour
    -- * Laws (QuickCheck'd in @Properties.DitherLevel@)
  , lawRealizationUnbiased
  , lawRealizationIsNotReversible
  , lawDitherFlickerPeaksAtHalf
  , lawContinuousReducesToDiscrete
  , lawGoldenOrderingTamesLatent
  ) where

import SixFour.Spec.Color  (OKLab(..))
import SixFour.Spec.Dither
  ( realize, temporalMean, goldenThresholds, ditheredColor
  , lawVarianceMaxAtHalf )

-- | The realized T-frame binary stream for a continuous dither position @p@, under the golden
-- low-discrepancy temporal ordering: frame @n@ shows the partner iff @p > goldenThreshold n@.
-- This is the exact stream "SixFour.Spec.Dither" @lawDitherMeanRecoversP@ averages.
realizeStream :: Int -> Double -> [Bool]
realizeStream t p = map (realize p) (goldenThresholds t)

-- | The perceived colour of the latent @p@ between a pair: the loop mean
-- @(1-p)·anchor + p·partner@ (delegates "SixFour.Spec.Dither" @ditheredColor@). This is what
-- Encoder B embeds; the per-frame bit never reaches it.
latentColour :: Double -> OKLab -> OKLab -> OKLab
latentColour = ditheredColor

-- ============================================================================
-- Laws (predicates; QuickCheck'd in Properties.DitherLevel)
-- ============================================================================

-- | UNBIASED: the loop mean of the golden-ordered stream recovers the latent @p@ to within
-- the ordering's (low) discrepancy, at the boundaries AND interior points. So the colour (the
-- first moment) survives the realization. Binds 'realizeStream' directly. Teeth: a constant or
-- white-noise ordering would blow the discrepancy past @tol@ and fail.
lawRealizationUnbiased :: Bool
lawRealizationUnbiased = all ok [0.0, 0.2, 0.5, 0.8, 1.0]
  where
    n   = 64
    tol = 0.05                                   -- ~3.2/n; golden discrepancy is below this
    ok p = abs (temporalMean (realizeStream n p) - p) <= tol

-- | NOT REVERSIBLE (the honest negative keystone): two DISTINCT latent positions @p1 ≠ p2@,
-- both below the smallest golden threshold, realize to the SAME stream (the all-anchor stream).
-- So the forward @p ↦ stream@ map is not injective at finite T: the per-frame bit is destroyed
-- and only the loop mean is recoverable. This is precisely why dither is a moment-conserving
-- display DECODER, not a reversible Q16-floor coordinatisation. Teeth: a claim that the map is
-- injective\/reversible fails on this witness.
lawRealizationIsNotReversible :: Bool
lawRealizationIsNotReversible =
  let n    = 64
      tmin = minimum (goldenThresholds n)
      p1   = tmin / 3
      p2   = 2 * tmin / 3
  in p1 /= p2
     && realizeStream n p1 == realizeStream n p2     -- distinct latents, identical stream
     && not (or (realizeStream n p1))                -- both are the all-anchor stream (mean 0)

-- | The flicker (the latent's VARIANCE, the unpredictable residual the encoder must discard)
-- is maximal at @p = 0.5@ and falls toward the pure endpoints: delegates "SixFour.Spec.Dither"
-- @lawVarianceMaxAtHalf@ across the dither line. The golden ordering tames this variance while
-- 'lawRealizationUnbiased' keeps the mean, which is the information-bound on the latent.
lawDitherFlickerPeaksAtHalf :: Bool
lawDitherFlickerPeaksAtHalf = all (lawVarianceMaxAtHalf 64) [0.0, 0.25, 0.5, 0.75, 1.0]

-- | The continuous latent REDUCES TO THE DISCRETE corner at @p ∈ {0,1}@: @p = 0@ realizes to
-- the all-anchor stream and @p = 1@ to the all-partner stream, i.e. a single deterministic
-- palette choice per site, the byte-exact "SixFour.Spec.ConstructionEncoder" @Construction@
-- corner. So the continuous @p@-field is a strict EXTENSION of the discrete construction, not a
-- replacement: the discrete GIF is the @p ∈ {0,1}@ slice. Teeth: an interior @p@ produces a
-- mixed stream the discrete single-index form cannot represent, so @p@ adds a real dimension.
lawContinuousReducesToDiscrete :: Bool
lawContinuousReducesToDiscrete =
  let n = 64
  in not (or (realizeStream n 0.0))                 -- p=0 ⇒ all anchor (a discrete corner)
     && and (realizeStream n 1.0)                    -- p=1 ⇒ all partner (a discrete corner)
     && or (realizeStream n 0.5)                     -- an interior p is genuinely mixed (extension)
     && not (and (realizeStream n 0.5))

-- | The ORDERING bounds the latent's information: under the golden low-discrepancy ordering the
-- loop mean recovers @p@, but a degenerate CONSTANT-threshold ordering does NOT. So the choice
-- of temporal ordering is what tames the latent's running-average variance toward zero while
-- preserving the mean (the information-bound that stops the per-pixel @z@ from explaining away
-- the signal; this is latent regularization, NOT the predictor anti-collapse, which is
-- "SixFour.Spec.JepaTarget" @lawCollapseIsRejected@). Teeth: a white\/constant ordering fails.
lawGoldenOrderingTamesLatent :: Bool
lawGoldenOrderingTamesLatent =
  let n        = 64
      p        = 0.2
      golden   = temporalMean (realizeStream n p)
      constant = temporalMean (map (realize p) (replicate n 0.5))
  in abs (golden - p) <= 0.05      -- golden ordering recovers the mean (tames the latent)
     && abs (constant - p) > 0.1    -- a constant ordering does NOT: ordering is load-bearing
