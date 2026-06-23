{- |
Module      : SixFour.Spec.LatentNavigation
Description : The single-16³ steering model — finger gestures as a NON-ABELIAN action on a shared latent, with undo as history-replay (not a spatial inverse).

Replaces the retired A/B-pick UI (see "SixFour.Spec.GenomePair"). There is ONE
evolving 16³; the user STEERS it with finger increments — up\/down = @A@ (red↔green),
left\/right = @B@ (yellow↔blue), plus a TURN (the @C4@ quarter-turn subgroup whose
gauge lives in "SixFour.Spec.ChromaRotation"). Each gesture is a step of MOVEMENT in
a shared latent; the single 16³ re-projects live; when satisfied, the settled rung
collapses to 256³ (the fractal lift) with minimal residual.

== Why undo is not fully feasible (SE ≠ NW⁻¹)

A SHARED latent is a curved, NON-COMMUTATIVE space: the turn re-frames the @(a,b)@
axes, so a "north-west" swipe is __not__ the inverse of an earlier "south-east"
swipe. Formally the gesture group is the rigid-motion semidirect product
@C4 ⋉ ℤ²@ (rotation acting on the @(a,b)@ shift), which is non-abelian:

  * 'lawNonAbelian' — @compose a b ≠ compose b a@: order\/direction matters.
  * 'lawStepHasInverse' \/ 'lawStepHasInverseLeft' — every SINGLE gesture still has
    an exact group inverse, so a single step is locally undoable __if you know the
    gesture__.
  * 'lawUndoNeedsHistoryNotInverse' — but appending the inverse of an EARLIER
    gesture does NOT remove it (intervening non-commuting gestures), so "swipe the
    opposite way" (SE↔NW) is __not__ undo. This is the @SE ≠ NW⁻¹@ fact as a proof.
  * 'lawHistoryUndoWellDefined' — the only exact undo is HISTORY REPLAY: drop the
    gesture from the recorded path and re-run. (Exact on the reversible rung; through
    the lossy JEPA readout it is only partial — undo is genuinely not fully feasible.)

The gesture action here is the reversible (integer, bit-exact) layer on the surfaced
rung; the JEPA predictor that turns a local edit into a globally-coherent pattern is
a separate, frozen, lossy pure-function readout (Mac-side) and is NOT modelled here.
-}
-- COMPARTMENT: SWIFT-COREAI | tag:DisplaySide
module SixFour.Spec.LatentNavigation
  ( -- * Gestures (the non-abelian steering group C4 ⋉ ℤ²)
    Gesture(..)
  , identityG
  , compose
  , inverse
  , quarterTurn
    -- * Trajectories and undo
  , Path
  , cumulative
  , undoLast
  , screenOpposite
    -- * A/B is the degenerate case
  , lawNavigationSubsumesPair
    -- * Laws (QuickCheck'd in @Properties.LatentNavigation@)
  , lawNonAbelian
  , lawStepHasInverse
  , lawStepHasInverseLeft
  , lawUndoNeedsHistoryNotInverse
  , lawHistoryUndoWellDefined
  ) where

-- | A finger gesture: a number of @C4@ quarter-turns plus an @(a,b)@ chroma shift.
-- (The continuous detents 30\/45\/60° are FLOAT-guidance handled in
-- "SixFour.Spec.ChromaRotation"; here the bit-exact @C4@ subgroup is the gauge.)
data Gesture = Gesture
  { gTurn  :: Int          -- ^ accumulated quarter-turns (not reduced mod 4, so composition is exact).
  , gShift :: (Int, Int)   -- ^ the @(a,b)@ translation increment in the CURRENT frame.
  } deriving (Eq, Show)

-- | The no-op gesture (the floor: no turn, no shift).
identityG :: Gesture
identityG = Gesture 0 (0, 0)

-- | Rotate an @(a,b)@ chroma vector by @k@ quarter-turns (bit-exact @C4@; the same
-- action whose gauge-fix lives in "SixFour.Spec.ChromaRotation"). Additive in @k@.
quarterTurn :: Int -> (Int, Int) -> (Int, Int)
quarterTurn k (x, y) = case (k `mod` 4 + 4) `mod` 4 of
  0 -> (x, y)
  1 -> (negate y, x)
  2 -> (negate x, negate y)
  _ -> (y, negate x)

-- | Group law of @C4 ⋉ ℤ²@: turns add; the second shift is re-framed by the first
-- gesture's accumulated turn before adding (this is what makes it non-abelian).
compose :: Gesture -> Gesture -> Gesture
compose (Gesture r1 (x1, y1)) (Gesture r2 t2) =
  let (x2, y2) = quarterTurn r1 t2
  in Gesture (r1 + r2) (x1 + x2, y1 + y2)

-- | The exact group inverse of a single gesture: @g ⋅ inverse g = identityG@.
inverse :: Gesture -> Gesture
inverse (Gesture r (x, y)) = Gesture (negate r) (quarterTurn (negate r) (negate x, negate y))

-- | A recorded trajectory of gestures (the undo history is just this list).
type Path = [Gesture]

-- | The net transform of a trajectory (left-fold under 'compose').
cumulative :: Path -> Gesture
cumulative = foldl compose identityG

-- | History undo: drop the most recent gesture from the recorded path.
undoLast :: Path -> Path
undoLast [] = []
undoLast xs = init xs

-- | The NAIVE "swipe the opposite way": same nothing-turn, negated screen shift.
-- It equals the group inverse ONLY for a pure shift with no intervening turn —
-- which is exactly why it fails as a general undo ('lawUndoNeedsHistoryNotInverse').
screenOpposite :: Gesture -> Gesture
screenOpposite (Gesture _ (x, y)) = Gesture 0 (negate x, negate y)

-- ============================================================================
-- Laws (predicates; QuickCheck'd in Properties.LatentNavigation)
-- ============================================================================

-- | The gesture group is NON-ABELIAN: there exist gestures with
-- @compose a b ≠ compose b a@ (a turn re-frames the following shift).
lawNonAbelian :: Bool
lawNonAbelian =
  let a = Gesture 1 (2, 0)
      b = Gesture 0 (0, 3)
  in compose a b /= compose b a

-- | A single gesture has an exact RIGHT inverse: @compose g (inverse g) = identityG@.
lawStepHasInverse :: Gesture -> Bool
lawStepHasInverse g = compose g (inverse g) == identityG

-- | …and an exact LEFT inverse: @compose (inverse g) g = identityG@.
lawStepHasInverseLeft :: Gesture -> Bool
lawStepHasInverseLeft g = compose (inverse g) g == identityG

-- | THE @SE ≠ NW⁻¹@ proof: appending the inverse of an EARLIER gesture does not
-- remove it once a non-commuting gesture intervenes, whereas HISTORY REPLAY (drop
-- it from the path) does. So "swipe the opposite way" is not undo; replay is.
lawUndoNeedsHistoryNotInverse :: Bool
lawUndoNeedsHistoryNotInverse =
  let a             = Gesture 1 (2, 0)   -- a turn+shift, done first
      b             = Gesture 0 (0, 3)   -- a later shift that does not commute with a
      lateInverse   = compose (cumulative [a, b]) (inverse a)  -- "undo a" by appending a⁻¹
      historyReplay = cumulative [b]                            -- undo a by removing it from history
  in lateInverse /= historyReplay

-- | History undo is well-defined and exact: replaying the path without its last
-- gesture is the cumulative transform of the truncated path.
lawHistoryUndoWellDefined :: Path -> Gesture -> Bool
lawHistoryUndoWellDefined p g =
  cumulative (undoLast (p ++ [g])) == cumulative p

-- | A\/B is the degenerate case: each option is a one-step trajectory, and
-- navigation generalises to any length (so a binary pick is subsumed, not special).
lawNavigationSubsumesPair :: Gesture -> Gesture -> Bool
lawNavigationSubsumesPair a b = cumulative [a] == a && cumulative [b] == b
