{- |
Module      : SixFour.Spec.SteeringSpine
Description : The form-follows-function CAPSTONE — the one module where the steering dataflow's arrows connect: latent → nudge → project (16³) → commit → reconstruct (256³).

The other modules are organised by CONCERN (byte boundary, gesture group, octant
cell, projection, reconstruction). This capstone is organised by DATAFLOW: it
co-locates the two visible stages as functions whose TYPES make the pipeline
readable in one place (the trace's "no spine" gap). Following the
"SixFour.Spec.OctreeForward" pattern, it adds only composition + cardinality content
and DELEGATES every heavy proof to the organ that owns it.

== The two visible arrows

  * 'steerShown' : @Gesture -> LatentCube -> [Q16]@ — the LIVE rung. One gesture
    nudges the one shared latent ("SixFour.Spec.NudgeStep" 'nudge'), then the
    canonical projection __P__ ("SixFour.Spec.LatentProjection" 'LP.project', the
    structural octant POOL — chosen over the scalar @NudgeStep.project@ because it
    carries the real coarser-than-latent claim) reads it down to the shown 16³.
  * 'commitReconstruct' : @Rungs -> [Int]@ — on satisfaction, the self-similar
    lift to 256³ ("SixFour.Spec.SelfSimilarReconstruct" 'reconstruct256').

== What the types already guarantee (no runtime law needed)

The end-to-end "output is on the Q16 floor" is a TYPE fact: 'steerShown' returns
@[Q16]@ and 'commitReconstruct' returns @[Int]@ built only through
'ByteCarrier.reenterQ16'; a @Latent -> Int@ bypass does not type-check (see
"SixFour.Spec.ByteCarrier"). So this module does NOT restate it as a (vacuous)
runtime predicate.

== The one genuinely-new law

'lawSpineShownIsCoarser' — the shown rung is STRICTLY SMALLER than the latent: P is
dimension-reducing, the executable form of "a pixel is a PROJECTION of the one
latent, not the latent". The rest delegate ('lawSpineReconstructSelfSimilar' →
'SelfSimilarReconstruct.lawSameOperatorBothRungs'; 'lawSpineWithinCaptureExact' →
'SelfSimilarReconstruct.lawWithinCaptureExact'); 'lawSpineUsesStructuralP' is a
design-PIN (a regression tripwire that the canonical P is the structural pool, not
the scalar seam).

Additive: imports only proven organs, re-pins no golden contract, deletes nothing.
The deeper unification (feeding the shown rung itself into 'commitReconstruct'
instead of a separate capture split) is a future refinement, noted not forced.
-}
-- COMPARTMENT: SWIFT-COREAI | tag:DisplaySide | STRADDLER
module SixFour.Spec.SteeringSpine
  ( -- * The visible dataflow (form follows function)
    steerShown
  , commitReconstruct
  , spineCut
    -- * Laws (QuickCheck'd in @Properties.SteeringSpine@)
  , lawSpineShownIsCoarser
  , lawSpineUsesStructuralP
  , lawSpineReconstructSelfSimilar
  , lawSpineWithinCaptureExact
  ) where

import SixFour.Spec.ByteCarrier          (Q16, toByte)
import SixFour.Spec.LatentNavigation     (Gesture)
import SixFour.Spec.NudgeStep            (LatentCube, mkLatentCube, nudge)
import qualified SixFour.Spec.LatentProjection as LP
import SixFour.Spec.SelfSimilarReconstruct
  ( Rungs, reconstruct256, lawSameOperatorBothRungs, lawWithinCaptureExact )
import SixFour.Spec.OctreeCell           (Detail)
import SixFour.Spec.OctreeGenome         (octreeLeafCount)

-- | The product cut: @64³ → 16³@ is 2 octree levels (@levelsBetween 64 16@).
spineCut :: Int
spineCut = 2

-- | The LIVE 16³ rung: nudge the one shared latent by one gesture, then project it
-- down through the canonical structural pool __P__ to the shown @[Q16]@.
steerShown :: Int -> Gesture -> LatentCube -> [Q16]
steerShown cut g = LP.project cut . nudge g

-- | On satisfaction, the self-similar lift of the settled rungs to the 256³ @[Int]@
-- (delegates "SixFour.Spec.SelfSimilarReconstruct" 'reconstruct256').
commitReconstruct :: Rungs -> [Int]
commitReconstruct = reconstruct256

-- ============================================================================
-- Laws (predicates; QuickCheck'd in Properties.SteeringSpine)
-- ============================================================================

-- | THE new content: the shown rung is STRICTLY SMALLER than the latent — P is
-- dimension-reducing (the shown 16³ is a coarser PROJECTION of the latent, not the
-- latent). For an @8^d@ latent (@d ≥ 1@) projected at @cut = 1@, the shown rung has
-- @8^(d-1) < 8^d@ voxels. Falsifiable: it fails if P ever preserved cardinality.
lawSpineShownIsCoarser :: Int -> Gesture -> [Double] -> Bool
lawSpineShownIsCoarser d g xs =
  not (d >= 1 && length xs == octreeLeafCount d)
    || length (steerShown 1 g (mkLatentCube xs)) < length xs

-- | DESIGN-PIN (regression tripwire, not a theorem): 'steerShown' uses the canonical
-- structural pool 'LP.project', so the shown rung equals projecting the nudged
-- latent. Fails if someone re-wires the spine onto the scalar @NudgeStep.project@.
lawSpineUsesStructuralP :: Int -> Gesture -> [Double] -> Bool
lawSpineUsesStructuralP cut g xs =
  let lc = mkLatentCube xs
  in map toByte (steerShown cut g lc) == map toByte (LP.project cut (nudge g lc))

-- | The 256³ reconstruction uses the SAME octant operator both rungs — delegates
-- "SixFour.Spec.SelfSimilarReconstruct" 'lawSameOperatorBothRungs'.
lawSpineReconstructSelfSimilar :: [Int] -> [[Detail]] -> Bool
lawSpineReconstructSelfSimilar = lawSameOperatorBothRungs

-- | The 16³→64³ step is bit-exact within capture — delegates
-- "SixFour.Spec.SelfSimilarReconstruct" 'lawWithinCaptureExact'.
lawSpineWithinCaptureExact :: Int -> Int -> [Int] -> Bool
lawSpineWithinCaptureExact = lawWithinCaptureExact
