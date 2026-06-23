{- |
Module      : SixFour.Spec.DivergenceSchedule
Description : The A/B divergence schedule Δ = |r_A − r_B| — the policy:value mix-ratio gap that starts WIDE (very different A/B) and NARROWS as the user picks (start-diverse-then-converge), floored above 0 so A and B never collapse.

Daniel's #3 (@docs/SIXFOUR-PER-FRAME-GENOME-AB-MIGRATION-WORKFLOW.md@, Phase 4): every capture
surfaces TWO independent searches A and B with DIFFERENT policy:value mix ratios @r_A ≠ r_B@ — A
explores (policy-heavy), B exploits (value-heavy). The gap @Δ = |r_A − r_B|@ IS the divergence
schedule: WIDE on the first round (very different looks), shrinking monotonically as Compares
accrue, bounded below by @Δ_min > 0@ so A and B NEVER collapse to identical. The gap is also the
headline MAP-Elites behavioural-descriptor axis.

The ratio @r ∈ [0,1]@ is the policy weight (1 = all policy \/ explore; 0 = all value \/ exploit) —
the explore\/exploit knob the Gumbel search already exposes
(@docs/SIXFOUR-ALPHAZERO-COLLAPSE-DESIGN.md@ §5.3). This module owns only the SCHEDULE (how the gap
anneals with the pick count @n@, e.g. 'SixFour.Spec.PersonalGenome.pgCompares'); it emits
@(r_A, r_B)@. The decay mirrors the @n \/ (n + halfLife)@ trust ramp of @personalBeta@ — here its
COMPLEMENT: the gap decays as @halfLife \/ (n + halfLife)@.

Double-valued search GUIDANCE (not byte-exact state — like the float search substrate in
@SIXFOUR-ALPHAZERO-COLLAPSE-DESIGN.md@ §3.4); the equality laws use a 1e-9 tolerance.
GHC-boot-only. Laws QuickCheck'd in @Properties.DivergenceSchedule@.
-}
-- COMPARTMENT: SWIFT-COREAI | tag:CommitSide
module SixFour.Spec.DivergenceSchedule
  ( DivergenceSchedule(..)
  , defaultSchedule
    -- * The schedule
  , deltaDecay
  , divergence
  , ratioA
  , ratioB
    -- * Laws (QuickCheck'd in Properties.DivergenceSchedule)
  , lawDivergenceStartsWide
  , lawDivergenceMonotone
  , lawDivergenceBoundedBelow
  , lawRatiosStraddleCenter
  , lawRatiosGapIsDivergence
  , lawRatiosInUnit
  ) where

-- | The annealing parameters of the A/B ratio gap.
data DivergenceSchedule = DivergenceSchedule
  { dsRatioCenter :: Double  -- ^ @r0@, the explore\/exploit center the pair straddles
  , dsDeltaMax    :: Double  -- ^ the widest gap (cold start, @n = 0@)
  , dsDeltaMin    :: Double  -- ^ the floor gap (@> 0@): A and B never collapse to identical
  , dsHalfLife    :: Double  -- ^ Compares to halve the EXCESS gap @(Δ_max − Δ_min)@
  } deriving (Eq, Show)

-- | The shipped schedule: center @0.5@, gap @0.8 → 0.05@, half-life @8@ Compares. The ratios stay
-- in @[0.1, 0.9] ⊂ [0,1]@ for all @n@ (no clamping needed, so the laws are clean).
defaultSchedule :: DivergenceSchedule
defaultSchedule = DivergenceSchedule 0.5 0.8 0.05 8

-- | The decay factor in @(0, 1]@: @halfLife \/ (n + halfLife)@. @1@ at @n = 0@, → @0@ as @n → ∞@.
-- Negative @n@ is clamped to @0@ (cold start).
deltaDecay :: DivergenceSchedule -> Int -> Double
deltaDecay s n = dsHalfLife s / (fromIntegral (max 0 n) + dsHalfLife s)

-- | The A\/B gap @Δ(n) = Δ_min + (Δ_max − Δ_min)·decay(n)@. @Δ(0) = Δ_max@; @Δ(∞) → Δ_min@.
divergence :: DivergenceSchedule -> Int -> Double
divergence s n = dsDeltaMin s + (dsDeltaMax s - dsDeltaMin s) * deltaDecay s n

-- | Candidate A's policy:value ratio — the EXPLORE pole (policy-heavy): @center + Δ\/2@.
ratioA :: DivergenceSchedule -> Int -> Double
ratioA s n = dsRatioCenter s + divergence s n / 2

-- | Candidate B's policy:value ratio — the EXPLOIT pole (value-heavy): @center − Δ\/2@.
ratioB :: DivergenceSchedule -> Int -> Double
ratioB s n = dsRatioCenter s - divergence s n / 2

-- ---------------------------------------------------------------------------
-- Laws (over 'defaultSchedule'; @n@ quantified over non-negative Int)
-- ---------------------------------------------------------------------------

approxEq :: Double -> Double -> Bool
approxEq a b = abs (a - b) < 1e-9

-- | Cold start is the widest gap: @Δ(0) = Δ_max@ (decay(0) = 1).
lawDivergenceStartsWide :: Bool
lawDivergenceStartsWide = divergence defaultSchedule 0 `approxEq` dsDeltaMax defaultSchedule

-- | The gap is monotone NON-INCREASING in the pick count: @Δ(n+1) ≤ Δ(n)@. This is
-- "close the differences a little each round" — A and B converge as the user picks.
lawDivergenceMonotone :: Int -> Bool
lawDivergenceMonotone n =
  let m = max 0 n in divergence defaultSchedule (m + 1) <= divergence defaultSchedule m

-- | The gap never falls below @Δ_min > 0@: A and B stay DISTINCT forever (no collapse).
lawDivergenceBoundedBelow :: Int -> Bool
lawDivergenceBoundedBelow n =
  divergence defaultSchedule (max 0 n) >= dsDeltaMin defaultSchedule

-- | The pair straddles the center: @r_B ≤ r0 ≤ r_A@ (A explores, B exploits).
lawRatiosStraddleCenter :: Int -> Bool
lawRatiosStraddleCenter n =
  let m = max 0 n; s = defaultSchedule
  in ratioB s m <= dsRatioCenter s && dsRatioCenter s <= ratioA s m

-- | The ratio gap IS the divergence: @r_A − r_B = Δ@.
lawRatiosGapIsDivergence :: Int -> Bool
lawRatiosGapIsDivergence n =
  let m = max 0 n; s = defaultSchedule
  in (ratioA s m - ratioB s m) `approxEq` divergence s m

-- | Both ratios are valid policy weights: @0 ≤ r_B@ and @r_A ≤ 1@ (the shipped schedule never
-- clamps — its gap-half @0.4@ keeps the pair inside @[0.1, 0.9]@).
lawRatiosInUnit :: Int -> Bool
lawRatiosInUnit n =
  let m = max 0 n; s = defaultSchedule
  in ratioB s m >= 0 && ratioA s m <= 1
