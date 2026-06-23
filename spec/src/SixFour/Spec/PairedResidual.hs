{- |
Module      : SixFour.Spec.PairedResidual
Description : Capture-anchored super-res — the 256³ detail is a residual KEYED BY the 64³ coarse value it refines (a value->residual codebook), applied self-similarly. "The residual IS the token, keyed by the coarse value."

The most important reconstruction refinement. "SixFour.Spec.SelfSimilarReconstruct"
builds the @64³→256³@ step from a FREE 'LatentTail' (per-position invented detail).
This module is the ANCHORED alternative the user asked for: the residual is a
deterministic FUNCTION of the coarse value, @r = r(v)@, so the @256³@ block under each
coarse voxel is @unliftOct (OctBand v (r v))@. The @64³@ capture (real and complete:
@64³ = 8⁶@ = the octant leaf count exactly) is the ANCHOR; the residual is the learned
refinement keyed by the value it expands.

== Capture-anchored, by construction

@64³→256³@ is TWO octant levels (×4 linear). 'pairedLift' applies the value-keyed
octant lift 'liftKeyed' SELF-SIMILARLY twice (each level keyed by its own coarse
values, the SAME book). Because @ocCoarse (liftOct (unliftOct (OctBand v r))) == v@
for ANY @r@ ("SixFour.Spec.OctreeCell" @lawOctReversible'@), re-pooling recovers the
@64³@ EXACTLY whatever the residual is — so "SixFour.Spec.RedownsampleGate" 'passesGate'
holds by construction ('lawPairedRepoolsToCoarse'), and the residual lives entirely in
the gate's null space ('lawDistinctBooksSameCoarse'). The anchor is never disturbed;
only detail above capture is added.

== The residual IS the token

'residualFor' is a codebook lookup keyed by the integer coarse value — the residual is
a referenceable, named entry (the embedding-table idiom of
"SixFour.Spec.ProjectionOrdering" @orderingHash@ / "SixFour.Spec.AtlasMove" @GenomeHash@),
not a free coefficient. Pure-value keying ('lawResidualPureValue'): same value ⇒ same
residual. Unseen values fall back to the zero floor ('lawUnseenKeyIsFloor' =
@zero-genome == floor@).

Additive: a new sibling module. "SixFour.Spec.SelfSimilarReconstruct"'s latent-tail
path stays byte-identical (free/exploratory vs anchored/shippable — keep both).
GHC-boot (@containers@). The codebook keys & values are integers already on the Q16
floor, so it is bit-exact and cross-device stable.
-}
-- COMPARTMENT: MLX-MODEL | tag:MacTag | STRADDLER
module SixFour.Spec.PairedResidual
  ( ResidualBook            -- opaque: build only via 'mkResidualBook'
  , floorResidual
  , mkResidualBook
  , residualFor
  , liftKeyed
  , pairedLift
    -- * Laws (QuickCheck'd in @Properties.PairedResidual@)
  , lawPairedRepoolsToCoarse
  , lawDistinctBooksSameCoarse
  , lawResidualPureValue
  , lawPairedReversible
  , lawResidualIsToken
  , lawUnseenKeyIsFloor
  , lawTwoLevelsTo256
  ) where

import qualified Data.Map.Strict as Map

import SixFour.Spec.OctreeCell     (Detail, OctBand(..), liftOct, unliftOct, octantSynthesize)
import SixFour.Spec.RedownsampleGate (passesGate)

-- | The value->residual codebook: a finite map from a coarse @64³@ Q16 value to the
-- 7-tuple detail one octant level expands it by. Build only via 'mkResidualBook'.
newtype ResidualBook = ResidualBook (Map.Map Int Detail)
  deriving (Eq, Show)

-- | The zero detail (the @synthBeyond@ / zero-genome==floor fallback for unseen values).
floorResidual :: Detail
floorResidual = (0, 0, 0, 0, 0, 0, 0)

-- | Build a codebook from value/residual pairs (last wins on duplicate keys, per
-- 'Map.fromList').
mkResidualBook :: [(Int, Detail)] -> ResidualBook
mkResidualBook = ResidualBook . Map.fromList

-- | The residual keyed by a coarse value (total: unseen values get 'floorResidual').
-- This is the codebook/token lookup — "the residual for @v@".
residualFor :: ResidualBook -> Int -> Detail
residualFor (ResidualBook m) v = Map.findWithDefault floorResidual v m

-- | ONE value-keyed octant level: each coarse value is paired with ITS OWN residual
-- and expanded by 'unliftOct'. @8^k → 8^(k+1)@.
liftKeyed :: ResidualBook -> [Int] -> [Int]
liftKeyed book coarse = octantSynthesize (coarse, [map (residualFor book) coarse])

-- | @64³ → 256³@: the value-keyed lift applied SELF-SIMILARLY twice (two octant
-- levels, the SAME book at each — the 64³ level keyed by 64³ values, the 128³ level by
-- its values). The capture-anchored counterpart of
-- "SixFour.Spec.SelfSimilarReconstruct" @octantLift . tailToDetail@.
pairedLift :: ResidualBook -> [Int] -> [Int]
pairedLift book = liftKeyed book . liftKeyed book

-- ============================================================================
-- Laws (predicates; QuickCheck'd in Properties.PairedResidual)
-- ============================================================================

-- | CAPTURE-ANCHORED (the keystone): the @256³@ re-pools (2 levels) to EXACTLY the
-- @64³@, for ANY book — the anchor is never disturbed. Holds by octant reversibility;
-- 'SixFour.Spec.RedownsampleGate.passesGate' passes by construction.
lawPairedRepoolsToCoarse :: Int -> ResidualBook -> [Int] -> Bool
lawPairedRepoolsToCoarse d book cube =
  not (d >= 0 && length cube == 8 ^ d)
    || passesGate 2 cube (pairedLift book cube)

-- | TEETH: two DIFFERENT books over the same @64³@ both pass the gate — the residual is
-- real super-res living entirely in the gate's null space (it never moves the coarse).
lawDistinctBooksSameCoarse :: Int -> ResidualBook -> ResidualBook -> [Int] -> Bool
lawDistinctBooksSameCoarse d b1 b2 cube =
  not (d >= 0 && length cube == 8 ^ d)
    || (passesGate 2 cube (pairedLift b1 cube) && passesGate 2 cube (pairedLift b2 cube))

-- | PURE-VALUE keying (the design contract): the residual is a function of the VALUE
-- alone — same value ⇒ same residual, regardless of position.
lawResidualPureValue :: ResidualBook -> Int -> Int -> Bool
lawResidualPureValue book u v = u /= v || residualFor book u == residualFor book v

-- | The paired octant edge is reversible (delegates "SixFour.Spec.OctreeCell"
-- @lawOctReversible'@): @liftOct . unliftOct@ on @OctBand v (r v)@ is the identity.
lawPairedReversible :: ResidualBook -> Int -> Bool
lawPairedReversible book v =
  let r = residualFor book v
  in liftOct (unliftOct (OctBand v r)) == OctBand v r

-- | The residual IS the token: 'residualFor' is the codebook lookup (embedding-table
-- indexed by value). On distinct keys it equals the plain association lookup.
lawResidualIsToken :: [(Int, Detail)] -> Int -> Bool
lawResidualIsToken kvs v =
  residualFor (mkResidualBook kvs) v == maybe floorResidual id (lookup v kvs)

-- | Totality / @zero-genome == floor@: a value ABSENT from the book gets the zero
-- residual, so super-res degenerates to the deterministic floor for unseen values.
lawUnseenKeyIsFloor :: [(Int, Detail)] -> Int -> Bool
lawUnseenKeyIsFloor kvs v =
  notElem v (map fst kvs) <= (residualFor (mkResidualBook kvs) v == floorResidual)

-- | SELF-SIMILAR two levels: @pairedLift@ is 'liftKeyed' twice and reaches @×64@
-- voxels (= @256³@ from @64³@) — the same operator at both rungs.
lawTwoLevelsTo256 :: Int -> ResidualBook -> [Int] -> Bool
lawTwoLevelsTo256 d book cube =
  not (d >= 0 && length cube == 8 ^ d)
    || (pairedLift book cube == liftKeyed book (liftKeyed book cube)
        && length (pairedLift book cube) == 64 * length cube)
