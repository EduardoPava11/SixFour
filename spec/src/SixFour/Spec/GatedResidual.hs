{- |
Module      : SixFour.Spec.GatedResidual
Description : The determinism-SAFE way to introduce the learned float gene — the residual is scaled by a gate s = tanh α before the Q16 crossing, so α = 0 is the byte-exact lossless floor and any α only PULLS TOWARD the floor (|gated| ≤ |raw|), never overshoots. The gate α starts at 0 and the gene contributes nothing until it earns it.

The research (@docs/PER-CAPTURE-LEARNING-RESEARCH.md@ §3, "gated-residual insertion")
names the safe way to add a float learner over a byte-exact floor: multiply the invented
residual by @tanh α@ with @α@ initialised at @0@. This module makes that a contract:

  * The ungated readout is "SixFour.Spec.DetailPredictor" @rawBands@ (@θ·φ(v)@ per band).
  * The GATE is the scalar @s = tanh α ∈ (-1, 1)@; the gated band is @s · rawⱼ(v)@.
  * The committed band is the gated readout re-entered to Q16 (the ONE float→device
    crossing, "SixFour.Spec.ByteCarrier" @reenterQ16@ via 'gatedCommitted').

Two determinism-safety properties fall out, and they are the whole point:

  * 'lawZeroGateIsFloor' — @tanh 0 = 0@, so at @α = 0@ EVERY gated band is @0@ and the
    committed detail is the all-zero floor, BY ARITHMETIC (no sentinel) — exactly the
    "SixFour.Spec.DetailPredictor" @zeroParams == floor@ contract, now reachable by the
    GATE instead of only by zero weights. A gene mid-training can be dialled to the floor.
  * 'lawGateContractive' — @|tanh α| < 1@, so @|s · rawⱼ| ≤ |rawⱼ|@: introducing the gate
    can only move the committed detail TOWARD the floor, never past the ungated invention.
    Worst case (any α, any θ) the output stays inside the band the ungated head already
    occupies, so the gate can never make a capture WORSE than shipping the full gene — the
    property that lets a float learner ride the lossless path safely.

Plus the monotone-earn shape: 'lawGateMonotoneOnNonneg' (for @α ≥ 0@, @|gated|@ grows with
@α@ toward @|raw|@) and 'lawGateApproachesUngated' (@α → ∞ ⇒ s → 1 ⇒ gated → raw@), so the
gene EARNS its contribution smoothly from the floor. 'lawGateSignPreserving' pins that a
positive gate never flips a band's sign.

Additive: a sibling of "SixFour.Spec.DetailPredictor"; nothing imports it, so no shipped
contract is re-pinned. GHC-boot only; the device output is integer Q16, the gate is a
Mac-side float that re-enters through the one sanctioned crossing.
-}
-- COMPARTMENT: MLX-MODEL | tag:MacTag
module SixFour.Spec.GatedResidual
  ( -- * The gate
    gate
    -- * Gated forward (the determinism-safe learned residual)
  , gatedRawBands
  , gatedCommitted
    -- * Laws (QuickCheck'd in @Properties.GatedResidual@)
  , lawZeroGateIsFloor
  , lawGateContractive
  , lawGateMonotoneOnNonneg
  , lawGateApproachesUngated
  , lawGateSignPreserving
  ) where

import SixFour.Spec.ByteCarrier  (mkLatent, reenterQ16, toByte)
import SixFour.Spec.DetailPredictor (PredictorShape, rawBands)

-- | The GATE: @s = tanh α ∈ (-1, 1)@. @α = 0 ⇒ s = 0@ (the floor); @α → ±∞ ⇒ s → ±1@
-- (the ungated head). The single knob that dials the gene's contribution from nothing
-- (lossless floor) to full invention, continuously.
gate :: Double -> Double
gate = tanh

-- | The gated raw bands: each ungated readout @rawⱼ(v)@ scaled by the gate @tanh α@,
-- BEFORE the Q16 crossing (the gate is a float multiply on a Latent, never on a byte).
gatedRawBands :: PredictorShape -> [Double] -> Int -> Double -> [Double]
gatedRawBands sh ps v alpha = map (gate alpha *) (rawBands sh ps v)

-- | The committed gated detail: the gated readout re-entered to Q16 (round-half-to-even),
-- the same crossing "SixFour.Spec.DetailPredictor" @predictDetail@ uses. At @α = 0@ every
-- entry is @0@ = the byte-exact floor.
gatedCommitted :: PredictorShape -> [Double] -> Int -> Double -> [Int]
gatedCommitted sh ps v alpha =
  map (toByte . reenterQ16 . mkLatent) (gatedRawBands sh ps v alpha)

-- ---------------------------------------------------------------------------
-- Laws
-- ---------------------------------------------------------------------------

-- | ZERO GATE IS THE FLOOR: at @α = 0@ the committed detail is all-zero for every band,
-- by arithmetic (@tanh 0 = 0@, @reenterQ16 0 = 0@) — the gene dialled fully to the
-- lossless floor without touching its weights.
lawZeroGateIsFloor :: PredictorShape -> [Double] -> Int -> Bool
lawZeroGateIsFloor sh ps v = all (== 0) (gatedCommitted sh ps v 0)

-- | CONTRACTIVE: the gated raw band never exceeds the ungated one in magnitude
-- (@|tanh α| < 1@), so the gate only pulls toward the floor — never overshoots the
-- invention the ungated head would make. The determinism-safe insertion property.
lawGateContractive :: PredictorShape -> [Double] -> Int -> Double -> Bool
lawGateContractive sh ps v alpha =
  and (zipWith (\g r -> abs g <= abs r + 1e-12) (gatedRawBands sh ps v alpha) (rawBands sh ps v))

-- | MONOTONE ON NON-NEGATIVE α: for @0 ≤ α₁ ≤ α₂@, each gated band's magnitude grows
-- (weakly) with α toward the ungated value — the gene EARNS its contribution smoothly.
lawGateMonotoneOnNonneg :: PredictorShape -> [Double] -> Int -> Double -> Double -> Bool
lawGateMonotoneOnNonneg sh ps v a1 a2 =
  let (lo, hi) = (min (abs a1) (abs a2), max (abs a1) (abs a2))
      gl = gatedRawBands sh ps v lo
      gh = gatedRawBands sh ps v hi
  in and (zipWith (\l h -> abs l <= abs h + 1e-12) gl gh)

-- | APPROACHES THE UNGATED HEAD: at large α the gate → 1, so the gated bands converge to
-- the ungated @rawBands@ — full invention is the α → ∞ limit.
lawGateApproachesUngated :: PredictorShape -> [Double] -> Int -> Bool
lawGateApproachesUngated sh ps v =
  and (zipWith (\g r -> abs (g - r) <= 1e-6 * (1 + abs r)) (gatedRawBands sh ps v 20) (rawBands sh ps v))

-- | SIGN PRESERVING: a positive gate (@α > 0 ⇒ tanh α > 0@) scales without flipping any
-- band's sign, so gating never inverts the direction of an invented detail.
lawGateSignPreserving :: PredictorShape -> [Double] -> Int -> Double -> Bool
lawGateSignPreserving sh ps v alpha =
  let s = signum (gate (abs alpha + 1))     -- strictly positive gate
  in and (zipWith (\g r -> signum g == signum (s * r)) (gatedRawBands sh ps v (abs alpha + 1)) (rawBands sh ps v))
