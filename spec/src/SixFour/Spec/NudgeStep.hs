{- |
Module      : SixFour.Spec.NudgeStep
Description : The ONE-DIRECTION-AT-A-TIME step — a single LatentNavigation gesture moves the ONE shared cube-shaped latent by one step, then P re-projects to a fresh 16³ Q16 rung.

The missing ARROW of the steering dataflow. Three organs already exist but were
never composed into the visible behaviour "swipe once ⇒ a fresh 16³ appears":

  * "SixFour.Spec.ByteCarrier" types a Mac-side float ('Latent') barred from bytes,
    and owns the ONLY sanctioned float→device crossing, 'reenterQ16' (the
    @zero-genome == floor@ requantisation, = @AtlasGame.quantizeQ16@). But its
    'Latent' is a single scalar, not the shared object the cube reads from.
  * "SixFour.Spec.LatentNavigation" owns the non-abelian gesture group @C4 ⋉ ℤ²@
    and the keystone @lawUndoNeedsHistoryNotInverse@ (undo = history replay). But
    its 'Gesture' acts on an abstract @(Int,Int)@, never on a 'Latent', and never
    re-projects to a 16³.
  * "SixFour.Spec.XYTLabDuality" says @(a,b) ≅ (x,y)@ are the SEARCH axes a gesture
    moves and @L ≅ t@ is the universal/balance axis it leaves alone.

This module makes the ONE shared latent a TYPE and wires the three together, at the
ADT\/smart-constructor\/QuickCheck layer (no DataKinds, no LiquidHaskell):

  * 'LatentCube' = a cube of "SixFour.Spec.ByteCarrier".'Latent' — the ONE shared
    continuous object stages 1–3 read\/write (NOT a fresh latent type: it reuses the
    proven byte-barred carrier, so no float can leak to a byte).
  * 'project' (= __P__) : @LatentCube -> [Q16]@ — the LOSSY, MANY-TO-ONE readout to
    the shown 16³ rung, built voxel-wise on the single sanctioned crossing
    'reenterQ16'. Each voxel is a PROJECTION of the latent, not the latent
    ('lawProjectIsManyToOne': distinct latents collide).
  * 'nudge' : @Gesture -> LatentCube -> LatentCube@ — apply ONE gesture's @(a,b)@
    search-shift to the shared latent (delegating the algebra to
    'LatentNavigation.gShift' \/ the @(a,b)@ axes of "SixFour.Spec.XYTLabDuality").
    It is exactly ONE 'LatentNavigation.compose' step, never a batch
    ('lawSingleNudgeIsOneStep').
  * 'nudgeThenProject' : @Gesture -> LatentCube -> [Q16]@ — the visible behaviour:
    move the latent one step, then re-project P to a FRESH well-defined 16³
    ('lawNudgeThenProject').

== Why undo is history-replay (not a spatial inverse)

P is MANY-TO-ONE ('lawProjectIsManyToOne'), so it has no inverse: from a fresh 16³
you cannot recover the latent that produced it, hence you cannot "swipe back". The
only exact undo is to drop the gesture from the recorded path and re-run — which is
exactly "SixFour.Spec.LatentNavigation"'s @lawUndoNeedsHistoryNotInverse@.
'lawNudgeUndoIsHistory' simply DELEGATES to that proof (it does not re-derive it),
so the two modules agree on one theorem rather than two.

This is the reversible-rung (Q16) layer: every device-bound value is a 'Q16'
integer; the float 'Latent' stays Mac-side and only ever reaches a byte through
'reenterQ16'. Additive: imports only already-proven modules, re-pins no golden
contract (slotLookDims\/NetContract\/net_shape untouched), deletes nothing.

GHC-boot-only. Laws are exported predicates, QuickCheck'd in @Properties.NudgeStep@.
-}
module SixFour.Spec.NudgeStep
  ( -- * The ONE shared cube-shaped latent (stage 1)
    LatentCube(..)
  , mkLatentCube
  , unLatentCube
    -- * P : the lossy many-to-one projection to the shown 16³ (stage 2)
  , project
    -- * The one-direction-at-a-time step (stage 3)
  , nudge
  , nudgeThenProject
  , nudgePath
    -- * Laws (QuickCheck'd in @Properties.NudgeStep@)
  , lawSingleNudgeIsOneStep
  , lawNudgeThenProject
  , lawProjectIsManyToOne
  , lawNudgeUndoIsHistory
  ) where

import SixFour.Spec.ByteCarrier      (Latent, Q16, mkLatent, unLatent, reenterQ16, toByte)
import SixFour.Spec.LatentNavigation
  ( Gesture(..), Path, compose, cumulative
  , lawUndoNeedsHistoryNotInverse )

-- | The ONE shared continuous latent, as a cube of byte-barred 'Latent' scalars
-- (Mac-side float). This is the single object that P projects from and a 'nudge'
-- moves. It reuses "SixFour.Spec.ByteCarrier".'Latent', so a voxel can never leak
-- to a device byte except through 'reenterQ16'.
newtype LatentCube = LatentCube [Latent]

-- | Build a shared latent cube from raw Mac-side floats (one per voxel).
mkLatentCube :: [Double] -> LatentCube
mkLatentCube = LatentCube . map mkLatent

-- | The latent cube's raw floats (Mac-side math only — there is no @LatentCube -> [Int]@).
unLatentCube :: LatentCube -> [Double]
unLatentCube (LatentCube ls) = map unLatent ls

-- | __P__ — the LOSSY, MANY-TO-ONE projection of the shared latent to the shown 16³
-- Q16 rung. Built voxel-wise on the ONE sanctioned float→device crossing
-- 'ByteCarrier.reenterQ16' (= @AtlasGame.quantizeQ16@, @zero-genome == floor@), so
-- it is the cube-shaped sibling of that proven scalar seam. Each output voxel is a
-- PROJECTION of the latent (a rounded readout), not the latent itself — and the
-- rounding is non-injective ('lawProjectIsManyToOne').
project :: LatentCube -> [Q16]
project (LatentCube ls) = map reenterQ16 ls

-- | ONE-DIRECTION-AT-A-TIME: apply a SINGLE gesture's @(a,b)@ search-shift to the
-- shared latent. The @(a,b)@ axes are the SEARCH factor of
-- "SixFour.Spec.XYTLabDuality" (a = red↔green up\/down, b = yellow↔blue
-- left\/right); the universal @L@\/@t@ balance axis is left untouched here. The shift
-- is added uniformly to every voxel (a single directional step on the whole shared
-- latent), in @1\/65536@ Q16 units so it lands cleanly on the floor.
--
-- This is exactly ONE step: the gesture is applied once, not folded over a batch
-- ('lawSingleNudgeIsOneStep').
nudge :: Gesture -> LatentCube -> LatentCube
nudge g (LatentCube ls) =
  let (da, db) = gShift g
      step     = (fromIntegral da + fromIntegral db) / 65536  -- one (a,b) search increment
  in LatentCube (map (mkLatent . (+ step) . unLatent) ls)

-- | The VISIBLE behaviour: move the shared latent one step, then re-project P to a
-- FRESH 16³ Q16 rung. This is the function the gesture→fresh-16³ arrow needed
-- ('lawNudgeThenProject').
nudgeThenProject :: Gesture -> LatentCube -> [Q16]
nudgeThenProject g = project . nudge g

-- | Replay a recorded 'LatentNavigation.Path' onto the shared latent as ONE
-- cumulative step (each entry is a single 'nudge'). Used by 'lawNudgeUndoIsHistory'
-- to show undo is path-truncation, not a spatial inverse of P.
nudgePath :: Path -> LatentCube -> LatentCube
nudgePath p lc = foldl (flip nudge) lc p

-- ============================================================================
-- Laws (predicates; QuickCheck'd in Properties.NudgeStep)
-- ============================================================================

-- | A nudge is EXACTLY ONE gesture step, not a batch: nudging by @g@ equals nudging
-- by the cumulative of the SINGLETON path @[g]@ (which is @compose identityG g == g@
-- in "SixFour.Spec.LatentNavigation"). Folding a multi-element path is strictly more
-- than one step, so this pins "one gesture compose, not a batch".
lawSingleNudgeIsOneStep :: Gesture -> [Double] -> Bool
lawSingleNudgeIsOneStep g xs =
  let lc = mkLatentCube xs
  in unLatentCube (nudge g lc) == unLatentCube (nudge (cumulative [g]) lc)
     && cumulative [g] == compose (Gesture 0 (0,0)) g

-- | Nudge THEN project is a well-defined fresh 16³: the visible @nudgeThenProject@
-- equals projecting the nudged latent, and the result has exactly one Q16 voxel per
-- input voxel (a total, same-shape readout — a genuine fresh rung, not a partial one).
lawNudgeThenProject :: Gesture -> [Double] -> Bool
lawNudgeThenProject g xs =
  let lc    = mkLatentCube xs
      fresh = nudgeThenProject g lc
  in map toByte fresh == map toByte (project (nudge g lc))
     && length fresh == length xs

-- | P is MANY-TO-ONE: there exist DISTINCT shared latents that project to the SAME
-- 16³ (two floats inside one @1\/65536@ Q16 cell round to the same integer). This is
-- WHY undo cannot be a spatial inverse of P — and it is the law the dataflow's
-- "each voxel is a projection of the latent, not the latent" demanded, which was
-- previously prose only.
lawProjectIsManyToOne :: Bool
lawProjectIsManyToOne =
  let a = mkLatentCube [0.0]
      b = mkLatentCube [0.4 / 65536]   -- distinct float, same Q16 cell (rounds to 0)
  in unLatentCube a /= unLatentCube b              -- the latents differ
     && map toByte (project a) == map toByte (project b)  -- ...but P collides them

-- | Undo is HISTORY-REPLAY, not a spatial inverse — DELEGATED to
-- "SixFour.Spec.LatentNavigation".@lawUndoNeedsHistoryNotInverse@ (the @SE ≠ NW⁻¹@
-- proof). Because P ('project') is many-to-one ('lawProjectIsManyToOne') it has no
-- inverse, so the only exact "one nudge back" is to drop the gesture from the
-- recorded path and re-run 'nudgePath'. This module does NOT re-derive that fact; it
-- pins that the steering layer's undo IS the navigation layer's proven undo.
lawNudgeUndoIsHistory :: Bool
lawNudgeUndoIsHistory = lawUndoNeedsHistoryNotInverse
