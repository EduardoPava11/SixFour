{- |
Module      : SixFour.Spec.LatentProjection
Description : P : Latent-cube -> [Q16] as a LOSSY, MANY-TO-ONE readout BY POOLING — "each voxel is a projection of the one shared latent, NOT the latent" — and why undo = history-replay (non-injective P).

"SixFour.Spec.NudgeStep" already wired the ONE shared 'NudgeStep.LatentCube' to a
projection @P = map reenterQ16@ and to the gesture step. But that @P@ is
__voxel-wise scalar re-entry__: it keeps the cube's cardinality, so its
many-to-one-ness is only FLOAT-ROUNDING (two floats in one Q16 cell). The
pipeline's stronger claim is STRUCTURAL: the shown @16³@ rung is COARSER than the
shared latent, so @P@ is a __dimension-reducing POOL__ — many distinct fine
latents collapse to one coarse rung because the octant pool DISCARDS the fine
detail bands, not merely because of rounding.

This module is that POOLING readout, scoped to the three contract laws:

> @project :: Int -> LatentCube -> [Q16]@ = @map reenterQ16 . poolToRung@

where 'poolToRung' is the lossy, many-to-one half (Mac-side octant pooling via
"SixFour.Spec.SuccessiveRefinement" 'split') and 'ByteCarrier.reenterQ16' is the
ONE sanctioned float→device crossing (@= AtlasGame.quantizeQ16@,
@zero-genome == floor@). @P@ owns no other crossing.

== The three contract laws

  * 'lawProjectionManyToOne' — a CONCRETE WITNESS: two DISTINCT latents that pool
    (and hence 'project') to the SAME @[Q16]@. They differ only inside an octant
    the cut pools away, so the shown rung does not determine the latent — "each
    voxel is a projection of the latent, NOT the latent".
  * 'lawProjectionThroughReentry' — @P@ FACTORS through 'ByteCarrier.reenterQ16':
    every projected component is 'reenterQ16' of the corresponding pooled
    component, so the ONLY float→device crossing is the sanctioned seam (no raw
    @round@).
  * 'lawProjectionIsPooling' — the lossy half IS pooling: DELEGATES to
    "SixFour.Spec.SuccessiveRefinement" 'lawMarkovByPooling' (the coarse rung is a
    deterministic pool of the fine; the no-rate-penalty / Markov condition).

== Why undo = history-replay (non-injective P)

'lawUndoNeedsReplayBecauseNonInjective' ties the dataflow's STATED cause to the
proof: because @P@ is non-injective ('lawProjectionManyToOne'), the shown @[Q16]@
has no right inverse to a 'LatentCube', so "invert the visible rung" is ill-posed;
the only exact undo is to replay the latent's recorded gesture history. This is the
complement of "SixFour.Spec.LatentNavigation" 'lawUndoNeedsHistoryNotInverse'
(which derives the SAME conclusion from gesture NON-COMMUTATIVITY): two independent
reasons, one conclusion.

== Additive / golden-safe

Imports only already-proven modules; the lossy step delegates to
'SuccessiveRefinement.split'\/'lawMarkovByPooling', the crossing to
'ByteCarrier.reenterQ16', the shared-latent type to "SixFour.Spec.NudgeStep". It
re-pins NO golden contract (@slotLookDims@\/@NetContract@\/@net_shape@ untouched)
and deletes nothing. GHC-boot-only; laws are exported predicates, QuickCheck'd in
@Properties.LatentProjection@.
-}
-- COMPARTMENT: SWIFT-COREAI | tag:DeviceTag | STRADDLER
module SixFour.Spec.LatentProjection
  ( -- * The lossy, many-to-one pool (Mac-side, where information dies)
    poolToRung
    -- * P : Latent-cube -> [Q16] (the readout; the only crossing is reenterQ16)
  , project
    -- * Laws (QuickCheck'd in @Properties.LatentProjection@)
  , lawProjectionManyToOne
  , lawProjectionThroughReentry
  , lawProjectionIsPooling
  , lawUndoNeedsReplayBecauseNonInjective
  ) where

import SixFour.Spec.ByteCarrier
  ( Q16, mkLatent, reenterQ16, toByte )
import SixFour.Spec.NudgeStep
  ( LatentCube(..), mkLatentCube, unLatentCube )
import SixFour.Spec.SuccessiveRefinement
  ( split, surfaced, lawMarkovByPooling )
import SixFour.Spec.OctreeGenome (octreeLeafCount)

-- | The octree depth a latent cube stands in for when its size is @8^d@.
-- (Total: returns @0@ off the octree grid; callers gate on @8^d@ size.)
latentDepth :: LatentCube -> Int
latentDepth lc = go 0 (length (unLatentCube lc))
  where go n m = if m <= 1 then n else go (n + 1) (m `div` 8)

-- | POOL the fine shared latent down to the surfaced coarse rung — the LOSSY,
-- MANY-TO-ONE half of @P@. Each continuous component is floored to its integer
-- grid (the Mac-side pre-quantisation), then the @cut@ finest octree levels are
-- pooled away by "SixFour.Spec.SuccessiveRefinement" 'split' — exactly the
-- deterministic pool the surfaced rung is built from. The result is the integer
-- coarse rung (still Mac-side; the device crossing is 'project'). Off the octree
-- grid it returns the floored cube unchanged.
poolToRung :: Int -> LatentCube -> [Int]
poolToRung cut lc =
  let fine = map floor (unLatentCube lc) :: [Int]
      d    = latentDepth lc
  in if length fine == octreeLeafCount d && cut >= 0 && cut <= d
        then surfaced (split cut d fine)
        else fine

-- | @P@: the LOSSY, MANY-TO-ONE readout of the shared latent to the shown coarse
-- rung. It is @map reenterQ16 . poolToRung@: 'poolToRung' destroys information
-- (many fine latents → one coarse rung), then EACH pooled component crosses the
-- float→device boundary through the ONE sanctioned seam 'ByteCarrier.reenterQ16'.
-- The result type @[Q16]@ is device bytes — "each voxel is a PROJECTION of the
-- latent (a Q16), NOT the latent (a Mac float)".
project :: Int -> LatentCube -> [Q16]
project cut = map (reenterQ16 . mkLatent . fromIntegral) . poolToRung cut

-- ============================================================================
-- Laws (predicates; QuickCheck'd in Properties.LatentProjection)
-- ============================================================================

-- | MANY-TO-ONE (the keystone): two DISTINCT latents that 'project' to the SAME
-- @[Q16]@ — a concrete witness. Both depth-1 cubes pool (@cut = 1@) to the coarse
-- rung @[0]@, differing only in the finest detail band the pool discards, so the
-- shown rung does not determine the latent. (Verified collision pair.)
lawProjectionManyToOne :: Bool
lawProjectionManyToOne =
  let cut = 1
      -- distinct fine latents, SAME pooled DC (both pool to [0]):
      l1  = mkLatentCube [0,0,0,0,0,0,0,0]
      l2  = mkLatentCube [0,0,0,0,0,0,0,1]
      pA  = map toByte (project cut l1)
      pB  = map toByte (project cut l2)
  in unLatentCube l1 /= unLatentCube l2   -- the latents differ
       && pA == pB                         -- ...but P collides them

-- | @P@ FACTORS THROUGH 'ByteCarrier.reenterQ16': every component of the
-- projection equals 'reenterQ16' of the corresponding pooled component — the ONLY
-- float→device crossing @P@ performs is the sanctioned seam (no raw @round@).
lawProjectionThroughReentry :: Int -> [Double] -> Bool
lawProjectionThroughReentry cut xs =
  let lc      = mkLatentCube xs
      pooled  = poolToRung cut lc
      viaP    = map toByte (project cut lc)
      viaSeam = map (toByte . reenterQ16 . mkLatent . fromIntegral) pooled
  in viaP == viaSeam

-- | @P@'s lossy step IS pooling: DELEGATES to
-- "SixFour.Spec.SuccessiveRefinement" 'lawMarkovByPooling' (the coarse rung is a
-- deterministic pool of the fine — zeroing the pooled-away detail then re-deriving
-- the surfaced yields the same surfaced, the no-rate-penalty condition). It also
-- pins that 'poolToRung' on a floored latent IS that proven 'surfaced' pool, so
-- @P@'s many-to-one-ness is the Markov pool, not an accident.
lawProjectionIsPooling :: Int -> Int -> [Double] -> Bool
lawProjectionIsPooling cut d xs =
  let fine = map floor xs :: [Int]
  in not (d >= 0 && cut >= 0 && cut <= d && length fine == octreeLeafCount d)
       || ( poolToRung cut (mkLatentCube (map fromIntegral fine))
              == surfaced (split cut d fine)   -- pool = the proven surfaced split
            && lawMarkovByPooling cut d fine ) -- ...which is a deterministic pool (delegated)

-- | The non-injective-@P@ reason for history-replay: because two distinct latents
-- share one projection ('lawProjectionManyToOne'), the shown @[Q16]@ has NO right
-- inverse to a 'LatentCube', so "invert the visible rung" is ill-posed and the
-- only exact undo is replaying the latent's gesture history. Complements
-- "SixFour.Spec.LatentNavigation" 'lawUndoNeedsHistoryNotInverse' (same conclusion
-- from non-commutativity) — two reasons, one undo.
lawUndoNeedsReplayBecauseNonInjective :: Bool
lawUndoNeedsReplayBecauseNonInjective =
  let cut = 1
      l1  = mkLatentCube [0,0,0,0,0,0,0,0]
      l2  = mkLatentCube [0,0,0,0,0,0,0,1]
      sameShown  = map toByte (project cut l1) == map toByte (project cut l2)
      diffLatent = unLatentCube l1 /= unLatentCube l2
  -- equal projection + distinct latent ⇒ P has no right inverse ⇒ undo by
  -- inverting the shown rung is impossible; history-replay is the only exact undo.
  in sameShown && diffLatent
