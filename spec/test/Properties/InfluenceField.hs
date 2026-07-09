module Properties.InfluenceField (tests) where

import Test.Tasty
import Test.Tasty.QuickCheck

import SixFour.Spec.InfluenceField
import SixFour.Spec.WeaveOrder (WeaveRung (W16), unitsOf)

tests :: TestTree
tests = testGroup "InfluenceField (radiation-ground tunables — FieldTuning source of truth)"
  [ testProperty "both source reaches are positive" $
      once lawReachesPositive

  , testProperty "unit-interval fractions stay in [0,1]" $
      once lawFractionsUnit

  , testProperty "lifting genuinely dims the field (liftDim < 1)" $
      once lawLiftDims

  , testProperty "lift ramp is a positive number of ticks" $
      once lawRampPositive

  , testProperty "breathing drift is positive" $
      once lawDriftPositive

  , testProperty "both inks are in the sRGB8 gamut" $
      once lawInksInGamut

  , testProperty "far-field ink is darker than the seam neutral" $
      once lawFarDarkerThanNeutral

  , testProperty "dither noise is a valid [0,1) threshold at every sample" $
      once lawNoiseInUnit

  , testProperty "falloff weight is bounded to [0,1]" $
      once lawFalloffBounds

  , testProperty "falloff is full (1) at the source edge" $
      once lawFalloffFullAtZero

  , testProperty "falloff is 0 at and beyond the reach" $
      once lawFalloffZeroBeyondReach

  , testProperty "falloff is monotone non-increasing in distance" $
      once lawFalloffMonotone

  , testProperty "field tunables golden: the pinned values" $
      once $    (driftPerTick === 0.2) .&&. (reachArrangement === 34.0)
           .&&. (reachSet === 40.0) .&&. (usageReachMin === 0.22)
           .&&. (seamMute === 0.85) .&&. (liftDim === 0.4)
           .&&. (liftRampTicks === 4)
           .&&. (neutralInk === (11, 11, 16)) .&&. (farDarkInk === (6, 6, 10))

  , testProperty "E9: live-idle energy genuinely dims (0 < e < 1)" $
      once lawLiveIdleDims

  , testProperty "E9: capture pour ramp beats at the 16-rung pool cadence" $
      once lawPourRampIsPoolCadence

  -- NON-VACUITY: the ramp period is not a free constant — it must equal the
  -- coarse rung's weave units (the same 4 the ControlFace BEAT reads), so the
  -- ground's capture pulse and the intake tallies provably share ONE clock.
  , testProperty "E9: pour ramp == unitsOf W16 (one clock, cross-module)" $
      once $ capturePourRampTicks === unitsOf W16

  , testProperty "E9 golden: liveIdleEnergy pinned" $
      once $ liveIdleEnergy === 0.25
  ]
