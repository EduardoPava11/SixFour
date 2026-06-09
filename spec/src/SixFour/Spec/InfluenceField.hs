{- |
Module      : SixFour.Spec.InfluenceField
Description : The influence-field TUNABLES — source of truth for the radiation ground.

The formally-pinned parameters of the decorative influence FIELD — the radiation
ground that surrounds the widgets (order) with chaos
(docs/SIXFOUR-INFLUENCE-FIELD-WORKFLOW.md). These constants are emitted to BOTH
@SixFour/Generated/FieldTuningContract.swift@ (the Swift @FieldTuning@ facade) AND
@SixFour/Generated/FieldTuning.metal.h@ (the Metal shader's constants), so the CPU
reference and the future GPU shader read ONE source and can never drift
(docs/SIXFOUR-METAL-FIELD-SPEC-ALIGNMENT.md S1b).

== Determinism class — PRESENTATION, not PRODUCT

Unlike the byte-exact Stage geometry ("SixFour.Spec.Boundary") and the byte-exact
GIF core (Zig), the field is a FLOAT decorative effect. This module pins its
PARAMETERS exactly, but the field FUNCTION it parameterises is gated only to a
TOLERANCE (S1c: a CPU reference + an ε-golden the GPU shader must match within a
few sRGB8 levels) — never to cross-device bit-exactness, which would over-constrain
a fragment shader. Pinning the *params* here is what keeps Swift and the shader in
lock-step; the *function* tolerance-golden lands next.

Laws (see @Properties.InfluenceField@): the reaches are positive; the fractions
(usage-reach floor, seam mute, lift dim) lie in the unit interval; lift genuinely
DIMS (@liftDim < 1@); the ramp + drift are positive; the inks are in gamut and the
far-field ink is darker than the seam neutral.
-}
module SixFour.Spec.InfluenceField
  ( -- * Falloff / radiation
    driftPerTick, reachArrangement, reachSet, usageReachMin
    -- * Seam + lift
  , seamMute, liftDim, liftRampTicks
    -- * Inks (sRGB8 component triples)
  , neutralInk, farDarkInk
    -- * Laws
  , lawReachesPositive
  , lawFractionsUnit
  , lawLiftDims
  , lawRampPositive
  , lawDriftPositive
  , lawInksInGamut
  , lawFarDarkerThanNeutral
  ) where

-- Falloff / radiation -------------------------------------------------------

-- | Outward drift of the breathing speckle, in CELLS PER 20 fps TICK — the chaos
-- flows out of the widgets each tick rather than re-rolling in place (F1).
driftPerTick :: Double
driftPerTick = 0.2

-- | Falloff reach (cells) of an @.arrangement@ source (the preview; uniform).
reachArrangement :: Double
reachArrangement = 34.0

-- | Base falloff reach (cells) of a @.set@ source (the palette), before usage scaling.
reachSet :: Double
reachSet = 40.0

-- | Usage→reach scaling for @.set@ spokes: an unused colour still reaches
-- @usageReachMin · reachSet@; the most-used reaches the full @reachSet@.
usageReachMin :: Double
usageReachMin = 0.22

-- Seam + lift ---------------------------------------------------------------

-- | How hard a chaos SEAM (two widgets contesting) mutes toward the neutral (0…1).
seamMute :: Double
seamMute = 0.85

-- | Energy multiplier at full lift — the radiation recedes while a widget is lifted.
liftDim :: Double
liftDim = 0.4

-- | Ticks over which the lift-dim ramps in/out (F3) — recede/return, not a snap.
liftRampTicks :: Int
liftRampTicks = 4

-- Inks (sRGB8 component triples) --------------------------------------------

-- | The neutral a seam mutes toward, and the calm unlit ink (sRGB8 @r,g,b@).
neutralInk :: (Int, Int, Int)
neutralInk = (11, 11, 16)

-- | The far-field calm ink — darker than the neutral (sRGB8 @r,g,b@).
farDarkInk :: (Int, Int, Int)
farDarkInk = (6, 6, 10)

-- Laws ----------------------------------------------------------------------

-- | Both source reaches are positive (a source radiates outward).
lawReachesPositive :: Bool
lawReachesPositive = reachArrangement > 0 && reachSet > 0

-- | The unit-interval fractions stay in @[0,1]@ (usage floor strictly positive).
lawFractionsUnit :: Bool
lawFractionsUnit =
  usageReachMin > 0 && usageReachMin <= 1
    && seamMute >= 0 && seamMute <= 1
    && liftDim >= 0 && liftDim <= 1

-- | Lifting a widget genuinely DIMS the field (@liftDim < 1@), so the lifted piece
-- of order reads as pulled out of the chaos.
lawLiftDims :: Bool
lawLiftDims = liftDim < 1

-- | The lift ramp is a positive number of ticks (it eases over time).
lawRampPositive :: Bool
lawRampPositive = liftRampTicks > 0

-- | The breathing drift is positive (the chaos moves outward each tick).
lawDriftPositive :: Bool
lawDriftPositive = driftPerTick > 0

-- | Both inks are in the sRGB8 gamut @[0,255]@.
lawInksInGamut :: Bool
lawInksInGamut = inGamut neutralInk && inGamut farDarkInk
  where inGamut (r, g, b) = all ok [r, g, b]
        ok v = v >= 0 && v <= 255

-- | The far-field ink is darker than the seam neutral (the field fades to a deeper
-- calm than the interplay seams).
lawFarDarkerThanNeutral :: Bool
lawFarDarkerThanNeutral = luma farDarkInk < luma neutralInk
  where luma (r, g, b) = r + g + b
