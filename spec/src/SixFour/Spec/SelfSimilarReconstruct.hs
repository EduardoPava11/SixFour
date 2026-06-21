{- |
Module      : SixFour.Spec.SelfSimilarReconstruct
Description : The SELF-SIMILAR 256³ reconstruction — the SAME octant operator applied twice (16³→64³ replays HELD EXACT detail; 64³→256³ synthesises INVENTED CONTINUOUS detail = the latent tail re-entered to Q16), the two ladder steps differing only in DETAIL SOURCE.

The pipeline's central thesis, finally composed as ONE chain of typed functions.
The cube ladder is self-similar: @16³ : 64³ :: 64³ : 256³@ because
@levelsBetween 64 16 == levelsBetween 256 64 == 2@ (already proven in
"SixFour.Spec.OctreeCell" 'lawLadderSelfSimilar'). So ONE octant operator
("SixFour.Spec.OctreeCell" 'octantSynthesize') covers BOTH rung steps — same shape,
applied twice.

But the two applications differ in EPISTEMIC STATUS, and that difference is the
whole point. This module makes the difference a TYPE (the 'DetailSource') and pins
it with laws, so "same operator, different detail source" cannot be merely asserted:

  * __16³ → 64³ (within capture).__ The detail bands are HELD EXACT integers — the
    "SixFour.Spec.RemainderTail" @Surfaced@ rung, the
    "SixFour.Spec.SuccessiveRefinement" @held@ remainder. Replaying them is BIT-EXACT
    (it IS @SuccessiveRefinement.refine@); the reconstruction recovers the capture.
    This is 'Held' detail.

  * __64³ → 256³ (beyond capture).__ There is NO captured high-frequency above the
    substrate, so the detail must be INVENTED. The source is the continuous latent
    tail ("SixFour.Spec.RemainderTail" @Remainder@ ≅ "SixFour.Spec.ByteCarrier"
    @Latent@), a Mac-side float that CANNOT carry a device byte. It crosses to the
    integer floor through the ONE sanctioned seam, 'ByteCarrier.reenterQ16'
    (@zero-genome == floor@), and only THEN feeds the octant operator. With a
    zero latent this degenerates to "SixFour.Spec.CubeLadder" 'synthBeyond' — the
    nearest-neighbour zero-detail floor the net replaces. This is 'Invented' detail.

== What is additive here

Nothing is re-pinned: this module only WIRES already-proven organs.

  * the operator is "SixFour.Spec.OctreeCell" 'octantSynthesize' (untouched);
  * the held-exact step delegates to "SixFour.Spec.SuccessiveRefinement" 'refine'
    and "SixFour.Spec.OctreeForward" 'refineOne' (untouched);
  * the float→device crossing is "SixFour.Spec.ByteCarrier" 'reenterQ16' =
    @AtlasGame.quantizeQ16@ (untouched, the @zero-genome == floor@);
  * the self-similar shape is "SixFour.Spec.OctreeCell" 'lawLadderSelfSimilar'
    (delegated, not re-derived);
  * the zero-detail floor is "SixFour.Spec.CubeLadder" 'synthBeyond' (the limit
    'Invented' degenerates to).

No golden contract (@slotLookDims@ / @NetContract@ / @net_shape@) is touched and no
golden-gated module is edited. GHC-boot-only; laws are exported predicates,
QuickCheck'd in @Properties.SelfSimilarReconstruct@.
-}
module SixFour.Spec.SelfSimilarReconstruct
  ( -- * The two detail sources (the epistemic split, as a type)
    DetailSource(..)
  , detailBands
    -- * The latent tail → Q16 detail bands (the invented, beyond-capture source)
  , LatentTail(..)
  , tailToDetail
    -- * The shared octant operator, applied once per rung step
  , octantLift
    -- * The self-similar two-rung chain
  , Rungs(..)
  , reconstruct256
    -- * Rung geometry (delegated)
  , levelsPerStep
    -- * Laws (QuickCheck'd in @Properties.SelfSimilarReconstruct@)
  , lawSameOperatorBothRungs
  , lawWithinCaptureExact
  , lawBeyondCaptureInvented
  , lawZeroTailIsFloor
  ) where

import SixFour.Spec.OctreeCell           ( Detail, octantSynthesize, levelsBetween )
import SixFour.Spec.SuccessiveRefinement ( SurfacedSplit(..), split, refine )
import SixFour.Spec.OctreeGenome         ( octreeLeafCount )
import SixFour.Spec.ByteCarrier          ( Latent, reenterQ16, toByte, mkLatent )

-- | The two epistemic sources of an octant step's detail bands. The SAME octant
-- operator ('octantLift') consumes either; the difference is ONLY where the detail
-- comes from — that is the whole thesis, here made a type.
data DetailSource
  = -- | HELD EXACT detail (within capture): the integer bands kept by the
    -- successive-refinement split (the @Surfaced@ rung's remainder). Replaying
    -- these is bit-exact.
    Held [[Detail]]
  | -- | INVENTED CONTINUOUS detail (beyond capture): the latent tail, ALREADY
    -- re-entered to the Q16 integer floor via 'ByteCarrier.reenterQ16'. The
    -- @[[Detail]]@ here is downstream of the float→device crossing — no raw
    -- 'Latent' is carried.
    Invented [[Detail]]
  deriving (Eq, Show)

-- | Extract the integer detail bands a source feeds to the octant operator. Both
-- arms yield @[[Detail]]@ (integers) — by the time detail reaches the operator it is
-- ON the floor, whether it was held-exact or re-entered-from-latent.
detailBands :: DetailSource -> [[Detail]]
detailBands (Held     ds) = ds
detailBands (Invented ds) = ds

-- | The continuous latent tail = the "SixFour.Spec.RemainderTail" @Remainder@ viewed
-- as a cube of "SixFour.Spec.ByteCarrier" @Latent@ scalars. Mac-side float; barred by
-- type from a byte. Each entry is ONE invented detail coefficient awaiting re-entry.
newtype LatentTail = LatentTail { tailLatents :: [[ (Latent,Latent,Latent,Latent,Latent,Latent,Latent) ]] }

-- | Re-enter a continuous latent tail to the Q16 floor, producing the integer detail
-- bands the octant operator consumes. THIS is the only place a float becomes a byte
-- in the beyond-capture step: each scalar crosses through 'ByteCarrier.reenterQ16'
-- (= @AtlasGame.quantizeQ16@, the @zero-genome == floor@). A zero latent re-enters to
-- zeroed detail — the "SixFour.Spec.CubeLadder" 'synthBeyond' floor the net replaces.
tailToDetail :: LatentTail -> [[Detail]]
tailToDetail = map (map reenter7) . tailLatents
  where
    reenter7 (a,b,c,d,e,f,g) =
      ( q a, q b, q c, q d, q e, q f, q g )
    q :: Latent -> Int
    q = toByte . reenterQ16   -- the single sanctioned float→device crossing

-- | The SHARED octant operator, ONE rung step: replay a coarse cube plus its detail
-- bands one level finer. This is literally "SixFour.Spec.OctreeCell" 'octantSynthesize'
-- partially applied — the SAME function for both the held-exact and the invented step.
-- Differing only in which 'DetailSource' supplies @det@.
octantLift :: [Int] -> [[Detail]] -> [Int]
octantLift coarse det = octantSynthesize (coarse, det)

-- | A self-similar two-rung reconstruction: the @16³@ base, the HELD detail that
-- replays it up to @64³@ (within capture, exact), and the INVENTED tail that
-- synthesises @256³@ from @64³@ (beyond capture, re-entered to Q16).
data Rungs = Rungs
  { base16   :: SurfacedSplit  -- ^ the surfaced @16³@ + its held bands (the within-capture source).
  , depth16  :: Int            -- ^ octree depth of the @16³@→@64³@ refine (= 'levelsPerStep').
  , tail256  :: LatentTail     -- ^ the invented continuous tail for @64³@→@256³@ (Mac-side latent).
  }

-- | RECONSTRUCT @256³@ by the self-similar relation, the SAME octant operator twice:
--
--   1. @16³ → 64³@: replay HELD EXACT detail (delegates to
--      "SixFour.Spec.SuccessiveRefinement" 'refine' — bit-exact, within capture).
--   2. @64³ → 256³@: synthesise INVENTED detail — re-enter the latent tail to Q16
--      ('tailToDetail') then apply the SAME 'octantLift' (= 'octantSynthesize').
--
-- The output is all-integer (Q16): no raw 'Latent' survives the second step.
reconstruct256 :: Rungs -> [Int]
reconstruct256 r =
  let cube64  = refine (depth16 r) (base16 r)          -- step 1: held-exact replay
      invDet  = tailToDetail (tail256 r)               -- latent tail → Q16 detail
      cube256 = octantLift cube64 invDet               -- step 2: SAME operator, invented detail
  in cube256

-- | The octree distance per ladder step: @levelsBetween 64 16 == levelsBetween 256 64 == 2@.
-- Delegated to "SixFour.Spec.OctreeCell"; not re-derived here.
levelsPerStep :: Int
levelsPerStep = levelsBetween 64 16

-- ============================================================================
-- Laws (predicates; QuickCheck'd in Properties.SelfSimilarReconstruct)
-- ============================================================================

-- | The 16→64 and 64→256 lifts are the SAME octant operator, and each spans exactly
-- @levelsBetween == 2@ octree levels. Delegates to "SixFour.Spec.OctreeCell"
-- 'lawLadderSelfSimilar' for the equal-distance fact, and witnesses operator
-- identity: 'octantLift' applied to a held source and to an invented source is the
-- SAME function (it ignores which arm of 'DetailSource' produced the bands).
lawSameOperatorBothRungs :: [Int] -> [[Detail]] -> Bool
lawSameOperatorBothRungs coarse det =
     levelsBetween 64 16 == 2
  && levelsBetween 256 64 == 2
  && levelsBetween 64 16 == levelsBetween 256 64        -- = OctreeCell.lawLadderSelfSimilar
  && octantLift coarse (detailBands (Held det))
       == octantLift coarse (detailBands (Invented det)) -- one operator, source-agnostic

-- | The 16→64 step is EXACT integer reconstruction (within capture): the held-detail
-- replay (which IS @reconstruct256@'s step 1) recovers the captured cube bit-for-bit.
-- Delegates to "SixFour.Spec.SuccessiveRefinement" 'lawRefineRoundTrip': build a
-- valid @(surfaced, held)@ split by 'split'ting a real capture, then assert step 1
-- of 'reconstruct256' equals the capture. The held source carries NO continuous
-- tail, so the within-capture step is a pure integer function.
lawWithinCaptureExact :: Int -> Int -> [Int] -> Bool
lawWithinCaptureExact k d cap =
  not (d >= 0 && k >= 0 && k <= d && length cap == octreeLeafCount d)
    || let sp      = split k d cap            -- a valid surfaced/held split of a real capture
           cube64  = refine d sp              -- = reconstruct256 step 1 (held-exact replay)
       in cube64 == take (octreeLeafCount d) cap

-- | The 64→256 detail is INVENTED and CONTINUOUS: it is NOT bit-exact-derivable from
-- the 16³ alone — a NONZERO latent tail changes the @256³@ output, so the second step
-- carries information absent from the held (within-capture) data. Witnesses
-- non-injectivity of "capture ↦ 256³": the same 64³ with two different latent tails
-- gives two different reconstructions (the invented half is real, not a pool).
lawBeyondCaptureInvented :: [Int] -> Bool
lawBeyondCaptureInvented cube64 =
  not (length cube64 == 8)   -- one octant's worth of coarse (8^1 children of one node)
    || let zeroTail = LatentTail [[ (z,z,z,z,z,z,z) ]]
           oneTail  = LatentTail [[ (one,one,one,one,one,one,one) ]]
           z   = mkLatent 0
           one = mkLatent 1
           out0 = octantLift cube64 (tailToDetail zeroTail)
           out1 = octantLift cube64 (tailToDetail oneTail)
       in out0 /= out1    -- invented detail is NOT derivable from cube64 alone

-- | A ZERO latent tail re-enters to ZEROED detail, so the beyond-capture step
-- degenerates to the deterministic zero-detail octant floor — the @zero-genome ==
-- floor@ short-circuit (and the limit "SixFour.Spec.CubeLadder" 'synthBeyond' the net
-- replaces). NON-vacuous: it fails if 'tailToDetail' of a zero latent were not
-- all-zero (e.g. a rounding bug in the seam, @reenterQ16 0 ≠ 0@).
--
-- The stronger "no raw 'Latent' reaches a byte" is a TYPE guarantee, not a runtime
-- law: 'reconstruct256' returns @[Int]@ and the only float→device path is
-- 'ByteCarrier.reenterQ16', so a @Latent -> Int@ bypass does not type-check (see
-- "SixFour.Spec.ByteCarrier").
lawZeroTailIsFloor :: [Int] -> Bool
lawZeroTailIsFloor cube64 =
  not (length cube64 == 8)
    || let z        = mkLatent 0
           zeroTail = LatentTail [[ (z,z,z,z,z,z,z) ]]
           floorDet = [[ (0,0,0,0,0,0,0) ]]
       in tailToDetail zeroTail == floorDet                       -- the seam zeroes (reenterQ16 0 == 0)
          && octantLift cube64 (tailToDetail zeroTail)
               == octantLift cube64 floorDet                      -- ...so the step is the zero-detail floor
