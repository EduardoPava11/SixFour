{- |
Module      : SixFour.Spec.MoveRadiusSchedule
Description : The GEOMETRIC move-radius schedule for the A/B genome — anneal the IsometryMove magnitude (wide early → floored) + a hard cumulative-displacement cap, all exact Q16.

Distinct from 'SixFour.Spec.DivergenceSchedule', which owns the policy:value MIX-RATIO gap
@Δ = |r_A − r_B|@ (search guidance, Double, ε-laws). This module owns the GEOMETRIC magnitude of
the 'SixFour.Spec.IsometryMove' translation: how FAR each round's move may shift the palette, and a
hard CAP on the cumulative displacement from the original capture so repeated rounds cannot drift
into noise (the degradation). Both reuse the same @halfLife \/ (n + halfLife)@ decay SHAPE, but the
meanings — and the units (a ratio vs a Q16 distance) — differ, so they are siblings, not one
overloaded schedule.

Integer Q16 throughout (it bounds the EXACT integer move), so every law is a no-tolerance
equality\/inequality. The per-round radius anneals from @rMax@ (cold start — A and B visibly
different) to a floor @rMin > 0@ (every round still moves); the cumulative cap clamps the total
displacement into an L∞ ball so the look stays near the capture forever.

Laws (QuickCheck'd in @Properties.MoveRadiusSchedule@, EXACT — no ε):

  * 'lawRadiusStartsWide'   — @moveRadius s 0 == rMax@.
  * 'lawRadiusMonotone'     — @moveRadius s (n+1) ≤ moveRadius s n@ (close the gap each round).
  * 'lawRadiusBoundedBelow' — @moveRadius s n ≥ rMin > 0@ (A\/B never collapse).
  * 'lawRadiusBoundedAbove' — @moveRadius s n ≤ rMax@.
  * 'lawClampWithinCap'     — every axis of @clampToCap s t@ is within @[−cap, cap]@.
  * 'lawClampIdempotent'    — clamping twice equals clamping once.
  * 'lawClampPreservesInside' — a displacement already inside the ball is unchanged.

GHC-boot-only.
-}
module SixFour.Spec.MoveRadiusSchedule
  ( MoveRadiusSchedule(..)
  , defaultMoveSchedule
    -- * The schedule
  , moveRadius
  , clampToCap
    -- * Laws (QuickCheck'd in Properties.MoveRadiusSchedule, EXACT — no ε)
  , lawRadiusStartsWide
  , lawRadiusMonotone
  , lawRadiusBoundedBelow
  , lawRadiusBoundedAbove
  , lawClampWithinCap
  , lawClampIdempotent
  , lawClampPreservesInside
  ) where

import SixFour.Spec.PairTreeFixed (OKLabI)

-- | The annealing parameters of the geometric move radius. Requires @rMax ≥ rMin ≥ 0@ and
-- @halfLife > 0@ (the 'defaultMoveSchedule' satisfies these; the laws are stated over it).
data MoveRadiusSchedule = MoveRadiusSchedule
  { mrRadiusMax :: Int   -- ^ Q16 — the cold-start per-round move radius (A and B visibly different)
  , mrRadiusMin :: Int   -- ^ Q16 — the floor radius (@> 0@): every round still moves
  , mrHalfLife  :: Int   -- ^ picks to halve the EXCESS radius @(rMax − rMin)@
  , mrCumCap    :: Int   -- ^ Q16 — hard per-axis cap on cumulative displacement from the capture
  } deriving (Eq, Show)

-- | The shipped schedule: cold-start radius @8192@ Q16 (≈ 0.125 OKLab), floor @1024@ (≈ 0.0156,
-- one JND, the old fixed step), half-life @8@ picks, cumulative cap @16384@ (≈ 0.25, the ceiling
-- @leafTint@ used). So early rounds move a visible amount, late rounds a JND, never beyond ±0.25.
defaultMoveSchedule :: MoveRadiusSchedule
defaultMoveSchedule = MoveRadiusSchedule 8192 1024 8 16384

-- | The per-round move radius (Q16): @rMin + (rMax − rMin)·halfLife `div` (n + halfLife)@. Integer
-- division ⇒ exact + deterministic. @rMax@ at @n = 0@; monotone ↓ to @rMin@. Negative @n@ clamps
-- to @0@ (cold start).
moveRadius :: MoveRadiusSchedule -> Int -> Int
moveRadius s n =
  mrRadiusMin s + ((mrRadiusMax s - mrRadiusMin s) * mrHalfLife s) `div` (max 0 n + mrHalfLife s)

-- | Project a cumulative displacement into the L∞ ball of radius @mrCumCap@: clamp each axis to
-- @[−cap, cap]@. Exact, idempotent, the identity inside the ball — so the chosen look can never
-- drift more than @cap@ from the original capture, no matter how many rounds accrue.
clampToCap :: MoveRadiusSchedule -> OKLabI -> OKLabI
clampToCap s (l, a, b) = (c l, c a, c b)
  where cap = mrCumCap s
        c x = max (negate cap) (min cap x)

-- ---------------------------------------------------------------------------
-- Laws (over 'defaultMoveSchedule'; @n@ quantified over Int, @t@ over OKLabI)
-- ---------------------------------------------------------------------------

-- | Cold start is the widest radius: @moveRadius s 0 == rMax@ (the decay is 1 at @n = 0@).
lawRadiusStartsWide :: Bool
lawRadiusStartsWide = moveRadius defaultMoveSchedule 0 == mrRadiusMax defaultMoveSchedule

-- | The radius is monotone NON-INCREASING in the pick count: @moveRadius (n+1) ≤ moveRadius n@.
lawRadiusMonotone :: Int -> Bool
lawRadiusMonotone n =
  let m = max 0 n in moveRadius defaultMoveSchedule (m + 1) <= moveRadius defaultMoveSchedule m

-- | The radius never falls below @rMin > 0@: every round still moves (A\/B never identical).
lawRadiusBoundedBelow :: Int -> Bool
lawRadiusBoundedBelow n =
  moveRadius defaultMoveSchedule (max 0 n) >= mrRadiusMin defaultMoveSchedule

-- | The radius never exceeds the cold-start @rMax@.
lawRadiusBoundedAbove :: Int -> Bool
lawRadiusBoundedAbove n =
  moveRadius defaultMoveSchedule (max 0 n) <= mrRadiusMax defaultMoveSchedule

-- | Every axis of a clamped displacement lies within @[−cap, cap]@ — the hard drift bound.
lawClampWithinCap :: OKLabI -> Bool
lawClampWithinCap t =
  let (l, a, b) = clampToCap defaultMoveSchedule t
      cap = mrCumCap defaultMoveSchedule
  in all (\x -> x >= negate cap && x <= cap) [l, a, b]

-- | Clamping is idempotent: a second clamp is a no-op.
lawClampIdempotent :: OKLabI -> Bool
lawClampIdempotent t =
  clampToCap defaultMoveSchedule (clampToCap defaultMoveSchedule t)
    == clampToCap defaultMoveSchedule t

-- | A displacement already inside the ball is returned unchanged (the clamp only bites outside).
lawClampPreservesInside :: OKLabI -> Bool
lawClampPreservesInside t@(l, a, b) =
  let cap = mrCumCap defaultMoveSchedule
  in not (all (\x -> abs x <= cap) [l, a, b]) || clampToCap defaultMoveSchedule t == t
