{- |
Module      : SixFour.Spec.RungPivot
Description : The canonical RUNG — one self-similar TWO-OCTANT-LEVEL hop pivoting on the 64³ capture, carrying the NEVER-SURFACED intermediate latent (32³ DOWN / 128³ UP) that sits exactly one octant level off the pivot. Closes the gap where the 32³/128³ intermediate was named in prose but had no type.

The 64³ capture is the PIVOT. A RUNG is one self-similar 2-octant-level hop pivoting
on 64³, traversed in one of two directions, carrying a NEVER-SURFACED intermediate
latent one octant level off the pivot:

  * __DOWN rung__ (analysis/distill):   @64³ → [32³ latent] → 16³ + residual@
    (within-capture, exact manufactured label — IS "SixFour.Spec.SuccessiveRefinement"
    @split 2 6@; Held).
  * __UP rung__ (synthesis/super-res):  @64³ + residual → [128³ latent] → 256³@
    (beyond-capture, invented detail — IS "SixFour.Spec.SelfSimilarReconstruct"
    @octantLift@; Invented).

Both rungs span @levelsBetween 64 16 == levelsBetween 256 64 == 2@ (proven in
"SixFour.Spec.OctreeCell" @lawLadderSelfSimilar@, re-exported as
"SixFour.Spec.SelfSimilarReconstruct" @levelsPerStep@). The intermediates 32³ and
128³ sit at SYMMETRIC octant positions around the pivot: @octreeDepth 32 = octreeDepth
64 − 1@, @octreeDepth 128 = octreeDepth 64 + 1@, and @32·128 == 64²@.

The intermediate is the ONE level the net is free to organise; it exists only as
latent neuron outputs and is NEVER committed to a cube. Surfacing it would cross
"SixFour.Spec.ByteCarrier" @reenterQ16@ and destroy sub-quantum information
('lawIntermediateNeverSurfaces' is the keystone — the same sub-quantum argument as
"SixFour.Spec.DeferredSurfacing" / "SixFour.Spec.NeuronRedundancy", now stated AT THE
RUNG TYPE). This is what makes a downstream cross-latent alignment objective LEGAL under
deferred surfacing.

Additive: composes "SixFour.Spec.OctreeCell" (@levelsBetween@/@octreeDepth@/@Detail@),
"SixFour.Spec.SuccessiveRefinement" (the surfaced 16³+residual @SurfacedSplit@),
"SixFour.Spec.SelfSimilarReconstruct" (@levelsPerStep@), "SixFour.Spec.ByteCarrier"
(the surfacing seam, for the keystone). The @irCoarse@ field is @[Double]@ (continuous
latent), NEVER @[Int]@: an integer intermediate would already be surfaced and would
silently weaken every downstream alignment law. Re-pins NOTHING; GHC-boot-only. Laws
QuickCheck'd in "Properties.RungPivot".
-}
module SixFour.Spec.RungPivot
  ( -- * Pivot and direction
    pivotSide
  , RungDir(..)
  , intermediateSide
  , isDown
  , isUp
    -- * The never-surfaced intermediate latent (the typed 32³/128³ gap)
  , IntermediateLatent(..)
  , latentSide
  , latentNeurons
    -- * A rung
  , Rung(..)
  , rungLevels
  , mkRung
    -- * Laws (QuickCheck'd in @Properties.RungPivot@)
  , lawPivotIs64
  , lawRungIsTwoLevels
  , lawRungSelfSimilar
  , lawIntermediateIsMidLevel
  , lawIntermediateNeverSurfaces
  , lawDownIsHeldUpIsInvented
  , lawRungEndpointExact
  ) where

import SixFour.Spec.OctreeCell            (Detail, octreeDepth, levelsBetween)
import SixFour.Spec.SuccessiveRefinement  (SurfacedSplit(..), split, refine)
import SixFour.Spec.SelfSimilarReconstruct (levelsPerStep)
import SixFour.Spec.OctreeGenome          (octreeLeafCount)
import SixFour.Spec.ByteCarrier           (mkLatent, reenterQ16, toByte)

-- | The capture PIVOT — the cube-ladder identity tier.
pivotSide :: Int
pivotSide = 64

-- | Direction of travel through the 64³ pivot. NEW — nothing names this today.
data RungDir
  = Down   -- ^ analysis/distill:    @64³ → [32³] → 16³ + residual@  (= @SuccessiveRefinement.split@; Held).
  | Up     -- ^ synthesis/super-res: @64³ + residual → [128³] → 256³@ (= @SelfSimilarReconstruct.octantLift@; Invented).
  deriving (Eq, Show)

-- | Is this the analysis (DOWN, 32³, Held) rung?
isDown :: RungDir -> Bool
isDown Down = True
isDown Up   = False

-- | Is this the synthesis (UP, 128³, Invented) rung?
isUp :: RungDir -> Bool
isUp = not . isDown

-- | The linear side of the never-surfaced intermediate: @32@ (Down) | @128@ (Up).
-- Both sit exactly ONE octant level off the 64³ pivot.
intermediateSide :: RungDir -> Int
intermediateSide Down = 32
intermediateSide Up   = 128

-- | The NON-VISUAL intermediate octant level — the one level the net is free to
-- organise, held ONLY as a latent neuron readout, NEVER a committed cube. @irCoarse@ /
-- @irDetail@ are the output of the FIRST octant step of the 2-level hop, before the
-- second level. Continuous (@Double@) by construction: surfacing it would cross
-- "SixFour.Spec.ByteCarrier" @reenterQ16@, which 'lawIntermediateNeverSurfaces' forbids
-- on the live path.
data IntermediateLatent = IntermediateLatent
  { irSide   :: Int        -- ^ @32@ (Down) | @128@ (Up).
  , irCoarse :: [Double]   -- ^ continuous coarse readout (latent, pre-surface) — NOT @[Int]@.
  , irDetail :: [Detail]   -- ^ that step's per-node detail bands (latent).
  } deriving (Eq, Show)

-- | The intermediate's linear side (@32@ | @128@).
latentSide :: IntermediateLatent -> Int
latentSide = irSide

-- | Flatten the intermediate to one sample-row for the
-- "SixFour.Spec.NeuronRedundancy" cross-latent machinery. Stays in @Double@ space
-- (latent), never surfaced. The detail 7-tuples are flattened to @Double@ in band order.
latentNeurons :: IntermediateLatent -> [Double]
latentNeurons il = irCoarse il ++ concatMap detail7 (irDetail il)
  where detail7 (a,b,c,d,e,f,g) = map fromIntegral [a,b,c,d,e,f,g]

-- | A RUNG: one self-similar 2-level octant hop pivoting on 64³, carrying its
-- otherwise-discarded intermediate latent and its surfaced endpoint + residual.
data Rung = Rung
  { rungDir      :: RungDir            -- ^ Down | Up.
  , rungMid      :: IntermediateLatent -- ^ the 32³/128³ never-surfaced latent.
  , rungEndpoint :: SurfacedSplit      -- ^ Down: surfaced 16³ + held residual; Up: 256³, @held = []@.
  } deriving (Eq, Show)

-- | A rung is ALWAYS two octant levels. Pinned to the existing self-similar constant
-- ("SixFour.Spec.SelfSimilarReconstruct" @levelsPerStep@); never a free field, so it
-- cannot drift per-value.
rungLevels :: Int
rungLevels = levelsPerStep            -- == levelsBetween 64 16 == 2

-- | Smart constructor: pins the intermediate side to the direction (rejects a Down rung
-- carrying a 128³ latent, etc.). The ONLY way to build a 'Rung'.
mkRung :: RungDir -> IntermediateLatent -> SurfacedSplit -> Maybe Rung
mkRung dir mid ep
  | irSide mid == intermediateSide dir = Just (Rung dir mid ep)
  | otherwise                          = Nothing

-- ============================================================================
-- Laws (predicates; QuickCheck'd in Properties.RungPivot)
-- ============================================================================

-- | The pivot is 64³ (the anchor).
lawPivotIs64 :: Bool
lawPivotIs64 = pivotSide == 64

-- | A rung is exactly TWO octant levels — pinned to @levelsPerStep@ so it cannot drift.
-- Teeth: any "rung = 1 level" or "rung = 3 levels" design fails.
lawRungIsTwoLevels :: Bool
lawRungIsTwoLevels = rungLevels == 2

-- | SELF-SIMILARITY: the DOWN (64→16) and UP (64→256) rungs span the same number of
-- octant levels around the pivot. Delegates "SixFour.Spec.OctreeCell"
-- @lawLadderSelfSimilar@. Teeth: an asymmetric ladder fails.
lawRungSelfSimilar :: Bool
lawRungSelfSimilar = levelsBetween 64 16 == levelsBetween 256 64
                  && levelsBetween 64 16 == rungLevels

-- | The intermediate sits at the geometric MID-LEVEL: exactly one octant level off the
-- pivot, symmetric (@32·128 == 64²@). Teeth: a latent placed at an endpoint (16/256) or
-- at the pivot fails — there would be no non-visual middle to organise. THIS makes the
-- symmetric-octant claim a theorem.
lawIntermediateIsMidLevel :: Bool
lawIntermediateIsMidLevel =
     octreeDepth (intermediateSide Down) == octreeDepth pivotSide - 1
  && octreeDepth (intermediateSide Up)   == octreeDepth pivotSide + 1
  && intermediateSide Down * intermediateSide Up == pivotSide * pivotSide

-- | KEYSTONE: the TYPED never-surfaced property. A pair of intermediate latent readouts
-- that DIFFER continuously collapse to the SAME bytes once surfaced through @reenterQ16@.
-- Teeth: a design that surfaced the intermediate (made it a real cube) would compare by
-- bytes and lose the distinction — the "SixFour.Spec.DeferredSurfacing" /
-- "SixFour.Spec.NeuronRedundancy" sub-quantum argument, now stated AT THE RUNG TYPE.
-- Being latent is the only way the mid-level survives. (Both values sit deep inside one
-- Q16 bin — well under half a ULP — so both surface to the floor byte.)
lawIntermediateNeverSurfaces :: Bool
lawIntermediateNeverSurfaces =
  let ulp  = 1 / 65536
      a    = [ 0.1 * ulp ]   -- sub-half-ULP, distinct
      b    = [ 0.3 * ulp ]   -- both round to the same floor byte
      surf = map (fromIntegral . toByte . reenterQ16 . mkLatent)
  in a /= b && surf a == (surf b :: [Double])

-- | RungDir ties to the "SixFour.Spec.SelfSupervisedRung" dichotomy: Down ⇒ Held
-- (within-capture, exact manufactured label), Up ⇒ Invented (beyond-capture,
-- consistency-gated). Aligns the vocabulary; the up-rung legitimately invents
-- information the down-rung lacks. (@dirIsHeld@ mirrors the @HeldRung@/@InventedRung@
-- split without importing it, keeping this module's only NN coupling structural.)
lawDownIsHeldUpIsInvented :: Bool
lawDownIsHeldUpIsInvented = dirIsHeld Down && not (dirIsHeld Up)
  where dirIsHeld = isDown

-- | The DOWN rung's surfaced endpoint round-trips exactly (@refine . split == id@),
-- delegating "SixFour.Spec.SuccessiveRefinement" @lawRefineRoundTrip@. The two
-- directions are mutual inverses of ONE rung: "16→64 held" and "64→16+residual" are one
-- reversible rung seen two ways. Teeth: a lossy down-rung fails. (Guarded to a valid
-- @(k,d,capture)@.)
lawRungEndpointExact :: Int -> Int -> [Int] -> Bool
lawRungEndpointExact k d cap =
  not (d >= 0 && k >= 0 && k <= d && length cap == octreeLeafCount d)
    || refine d (split k d cap) == take (octreeLeafCount d) cap
