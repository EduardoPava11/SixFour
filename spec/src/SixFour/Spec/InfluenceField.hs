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
-- COMPARTMENT: METAL-GPU | tag:none | STRADDLER
module SixFour.Spec.InfluenceField
  ( -- * Falloff / radiation
    driftPerTick, reachArrangement, reachSet, usageReachMin
    -- * Seam + lift
  , seamMute, liftDim, liftRampTicks
    -- * Inks (sRGB8 component triples)
  , neutralInk, farDarkInk
    -- * The field FUNCTION primitives (CPU reference for the GPU shader)
  , noiseHash, noiseUnit, falloff
  , noiseSamples, falloffSamples
    -- * Laws
  , lawReachesPositive
  , lawFractionsUnit
  , lawLiftDims
  , lawRampPositive
  , lawDriftPositive
  , lawInksInGamut
  , lawFarDarkerThanNeutral
  , lawNoiseInUnit
  , lawFalloffBounds
  , lawFalloffFullAtZero
  , lawFalloffZeroBeyondReach
  , lawFalloffMonotone
  ) where

import Data.Word (Word32)
import Data.Bits (xor, shiftR)

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

-- The field FUNCTION primitives (the CPU reference the GPU shader matches) -----

-- | The dither NOISE HASH — a 32-bit integer hash of cell @(c,r)@ + breathing phase
-- @f@, the heart of the speckle. PURE integer bit-ops, so it is BYTE-EXACT across the
-- Swift CPU reference and the Metal GPU shader (low-32-bit multiply/XOR is
-- truncation-invariant: 64-bit-then-truncate == 32-bit-direct). The single piece of the
-- field that MUST match bit-for-bit (a mismatch = a different speckle, invisibly). Mirror
-- of @FieldModel.noise@ (InfluenceField.swift).
noiseHash :: Int -> Int -> Int -> Word32
noiseHash c r f =
  let h0 = fromIntegral ((c * 73856093) `xor` (r * 19349663)
                          `xor` (f * 83492791) `xor` 0x9e3779b9) :: Word32
      h1 = h0 `xor` (h0 `shiftR` 13)
      h2 = h1 * 0x5bd1e995
      h3 = h2 `xor` (h2 `shiftR` 15)
  in h3

-- | The noise hash normalised to @[0,1)@ — the dither threshold the speckle density
-- compares against (@n < E@).
noiseUnit :: Int -> Int -> Int -> Double
noiseUnit c r f = fromIntegral (noiseHash c r f) / fromIntegral (maxBound :: Word32)

-- | A source's linear FALLOFF weight at distance @d@ (cells) for a given @reach@:
-- @max 0 (1 − d / max 1 reach)@ — 1 at the edge, 0 at/beyond the reach. The smooth
-- core of the energy field. Float, so it is gated to a TOLERANCE (Metal @float@ ≠
-- @Double@). Mirror of @FieldModel.weight@'s ramp.
falloff :: Double -> Double -> Double
falloff d reach = max 0 (1 - d / max 1 reach)

-- | Golden sample cells @(c, r, f)@ for the byte-exact noise hash (corners, mids, a
-- breathing phase) — codegen emits @noiseHash@ at each; Swift recomputes + compares exact.
noiseSamples :: [(Int, Int, Int)]
noiseSamples =
  [ (0,0,0), (1,0,0), (0,1,0), (13,7,0), (50,109,0)
  , (99,217,0), (42,142,0), (7,200,3), (64,64,1) ]

-- | Golden samples @(d, reach)@ for the tolerance falloff (at, before, and beyond reach).
falloffSamples :: [(Double, Double)]
falloffSamples =
  [ (0,34), (10,34), (34,34), (40,34), (0,40), (20,40), (8.8,40) ]

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

-- | The normalised noise is in @[0,1)@ at every golden sample (a valid dither threshold).
lawNoiseInUnit :: Bool
lawNoiseInUnit = all ok noiseSamples
  where ok (c, r, f) = let u = noiseUnit c r f in u >= 0 && u < 1

-- | The falloff weight is bounded to @[0,1]@ at every golden sample.
lawFalloffBounds :: Bool
lawFalloffBounds = all ok falloffSamples
  where ok (d, re) = let w = falloff d re in w >= 0 && w <= 1

-- | The falloff is full (1) at the source edge (@d = 0@).
lawFalloffFullAtZero :: Bool
lawFalloffFullAtZero = falloff 0 reachArrangement == 1 && falloff 0 reachSet == 1

-- | The falloff is 0 at and beyond the reach (the far field is calm).
lawFalloffZeroBeyondReach :: Bool
lawFalloffZeroBeyondReach =
  falloff reachArrangement reachArrangement == 0
    && falloff (reachArrangement + 10) reachArrangement == 0

-- | The falloff is monotone non-increasing in distance (closer = stronger).
lawFalloffMonotone :: Bool
lawFalloffMonotone =
  falloff 0 reachSet >= falloff 10 reachSet
    && falloff 10 reachSet >= falloff 30 reachSet
    && falloff 30 reachSet >= falloff reachSet reachSet
