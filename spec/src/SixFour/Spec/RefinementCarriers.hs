{- |
Module      : SixFour.Spec.RefinementCarriers
Description : Wires the capstone spine "SixFour.Spec.RefinementSystem" to the model's PRODUCTION carriers so the abstraction GOVERNS the real call sites instead of merely paralleling them. Two wirings: (1) the VALUE delta @ColourDelta@ is a genuine @RModule ℤ@ — the instance (in "SixFour.Spec.HierarchicalDelta") maps the abstract @madd@\/@mneg@\/@smul@ to the existing concrete ops, and @lawColourModuleActsAsRecolour@ proves those abstract operations ARE recolour composition at the @applyValueDelta@ call site; (2) the octant @OctLeaf8@ is a genuine @ReversibleLift@ whose @liftF@ IS @OctreeCell.liftOct@ (the averaging S-transform), proven distinct from the class's generic prefix-difference default by @lawOctLeafOverridesDefault@.

HONEST BOUNDARY: @ColourDelta@'s ragged list representation makes the ℤ-module additive-inverse law
hold only up to trailing-zero normalization ('canonColourDelta') — @madd x (mneg x)@ is a run of
zeros, equal to @mzero = ColourDelta []@ as a recolour but not under the derived @Eq@. This module
records that as 'lawColourModuleInverseModuloCanon' rather than hiding it; the other four module laws
(@lawModuleSmulOne@, @lawModuleSmulMul@, @lawModuleSmulDistribModule@, @lawModuleSmulDistribRing@)
hold strictly and are witnessed for @ColourDelta@ in "Properties.RefinementCarriers".

Additive: imports the abstraction + both carriers; re-pins nothing, emits no golden vector.
-}
-- COMPARTMENT: PURE-SPEC-WALL | tag:none
module SixFour.Spec.RefinementCarriers
  ( -- * The VALUE carrier wired to @RModule ℤ@
    canonColourDelta
  , lawColourModuleInverseModuloCanon
  , lawColourModuleActsAsRecolour
    -- * The octant carrier wired to @ReversibleLift@ (its @liftF@ IS @liftOct@)
  , OctLeaf8(..)
  , octBandToPair
  , pairToOctBand
  , lawOctLeafLiftIsLiftOct
  , lawOctLeafOverridesDefault
    -- * The POLICY carrier bridged to the transport group (induced, not identical)
  , lawIndexDeltaRealizesTransport
  ) where

import Data.List (dropWhileEnd)

import SixFour.Spec.RefinementSystem
  ( RModule(..), ReversibleLift(..), liftVec )
import SixFour.Spec.HierarchicalDelta
  ( ColourDelta(..), applyValueDelta, applyDelta, deltaBetween )
import SixFour.Spec.ConstructionEncoder
  ( Construction(..), QColour, buildPixels )
import SixFour.Spec.OctreeCell
  ( V8(..), OctBand(..), liftOct, unliftOct )
import SixFour.Spec.TransportGroup
  ( Transport, tapply )

-- ============================================================================
-- The VALUE carrier: ColourDelta as a real RModule ℤ (instance in HierarchicalDelta)
-- ============================================================================

-- | The canonical (normal) form of a 'ColourDelta': drop the redundant trailing all-zero slots
-- that the ragged zero-padding representation allows. Two deltas with the same normal form act
-- identically as recolours; this is the equivalence the ℤ-module additive-inverse law respects.
canonColourDelta :: ColourDelta -> ColourDelta
canonColourDelta = ColourDelta . dropWhileEnd (== (0,0,0)) . unColourDelta

-- | The ℤ-module additive-inverse law for 'ColourDelta', stated MODULO 'canonColourDelta': a
-- recolour composed with its module negation is the no-op delta. The normalization is load-bearing
-- and honest — @madd x (mneg x)@ is a run of zeros of length @|x|@, equal to @mzero@ as a recolour
-- but not under the derived @Eq@ on the ragged list. Teeth: a clamped\/saturating add would leave
-- an over-range slot unrecoverable, so the canonicalized result would not be the no-op.
lawColourModuleInverseModuloCanon :: [QColour] -> Bool
lawColourModuleInverseModuloCanon xs =
  let x = ColourDelta xs
  in canonColourDelta (madd x (mneg x)) == canonColourDelta mzero

-- | THE governing law: the ABSTRACT module operations act as concrete recolours at the
-- 'applyValueDelta' call site. Module addition @madd@ is composition of recolours (applying the
-- summed delta equals applying one then the other), and the scalar action @smul 2@ is self-addition
-- (@madd d d@). This is what "the abstraction governs the call site" means: the @RModule@ methods
-- are not a parallel algebra, they compute the same palette displacement the shipped path does.
-- Compared in fused 'buildPixels' space (the gauge-correct comparison), never slot-by-slot.
lawColourModuleActsAsRecolour :: Bool
lawColourModuleActsAsRecolour =
  let c  = Construction 1 [(10,20,30),(40,50,60)] [0,1,0,1]
      d1 = ColourDelta [(1,0,0),(0,2,0)]
      d2 = ColourDelta [(0,0,3),(5,0,0)]
  in buildPixels (applyValueDelta (madd d1 d2) c)
       == buildPixels (applyValueDelta d1 (applyValueDelta d2 c))
     && buildPixels (applyValueDelta (smul (2 :: Integer) d1) c)
       == buildPixels (applyValueDelta (madd d1 d1) c)

-- ============================================================================
-- The octant carrier: OctLeaf8 as a real ReversibleLift whose liftF IS liftOct
-- ============================================================================

-- | The shipped @2×2×2@ octant leaf as a 'ReversibleLift' carrier: eight scalar children, branching
-- @b = 8@. Unlike 'SixFour.Spec.RefinementSystem.Dyad8' (which inherits the generic prefix-difference
-- scheme), this carrier OVERRIDES 'liftF'\/'unliftF' to route through the real averaging octant
-- S-transform 'SixFour.Spec.OctreeCell.liftOct', so the abstraction governs the actual lift.
newtype OctLeaf8 = OctLeaf8 (V8 Int) deriving (Eq, Show)

-- | Read an 'OctBand' (1 coarse + 7 detail) as the abstract @(coarse, detail)@ pair.
octBandToPair :: OctBand -> (Integer, [Integer])
octBandToPair (OctBand c (d1,d2,d3,d4,d5,d6,d7)) =
  (fromIntegral c, map fromIntegral [d1,d2,d3,d4,d5,d6,d7])

-- | Rebuild an 'OctBand' from an abstract @(coarse, detail)@ pair (pads\/truncates the detail to
-- the seven sub-bands, keeping the conversion total on generated inputs).
pairToOctBand :: (Integer, [Integer]) -> OctBand
pairToOctBand (c, ds) =
  case map fromIntegral (take 7 (ds ++ repeat 0)) of
    (d1:d2:d3:d4:d5:d6:d7:_) -> OctBand (fromIntegral c) (d1,d2,d3,d4,d5,d6,d7)
    _                        -> OctBand (fromIntegral c) (0,0,0,0,0,0,0)

instance ReversibleLift OctLeaf8 where
  liftBranching _ = 8
  toVec (OctLeaf8 (V8 a b c d e f g h)) = map fromIntegral [a,b,c,d,e,f,g,h]
  fromVec xs = case map fromIntegral (take 8 (xs ++ repeat 0)) of
    (a:b:c:d:e:f:g:h:_) -> OctLeaf8 (V8 a b c d e f g h)
    _                   -> OctLeaf8 (V8 0 0 0 0 0 0 0 0)
  liftF  (OctLeaf8 v) = octBandToPair (liftOct v)
  unliftF p           = OctLeaf8 (unliftOct (pairToOctBand p))

-- | The governing law: the carrier's @liftF@ IS the real 'liftOct' (read as a coarse\/detail pair),
-- and it round-trips through @unliftF@. So the @ReversibleLift@ interface now names the shipped
-- octant bijection, not a generic stand-in.
lawOctLeafLiftIsLiftOct :: V8 Int -> Bool
lawOctLeafLiftIsLiftOct v =
  liftF (OctLeaf8 v) == octBandToPair (liftOct v)
  && unliftF (liftF (OctLeaf8 v)) == OctLeaf8 v

-- | The "governs, not parallels" witness: 'OctLeaf8' genuinely OVERRIDES the class default — for a
-- non-smooth octant the averaging S-transform 'liftF' differs from the generic prefix-difference
-- 'liftVec' over the same voxels, yet remains a faithful bijection. (They agree only on constant
-- octants, where both produce zero detail.)
lawOctLeafOverridesDefault :: Bool
lawOctLeafOverridesDefault =
  let x = OctLeaf8 (V8 0 8 0 0 0 0 0 0)
  in liftF x /= liftVec (toVec x)
     && unliftF (liftF x) == x

-- ============================================================================
-- The POLICY carrier: IndexDelta bridged to the transport group (INDUCED action)
-- ============================================================================

-- | The policy-side bridge. Unlike the VALUE channel (one shared @RModule@ interface), the two
-- policy representations are NOT the same type: "SixFour.Spec.TransportGroup" @Transport@ is a
-- slot-VALUE permutation applied uniformly, while "SixFour.Spec.HierarchicalDelta" @IndexDelta@ is a
-- POSITIONAL relabel keyed by voxel with provenance. They relate by an INDUCED homomorphism: a slot
-- transport @sigma@ acting on a frame @idx@ is exactly reproduced by the positional 'IndexDelta'
-- data-manufactured from @(idx, tapply sigma idx)@. So the abstraction governs the policy carrier on
-- any frame, via the induced action — not by pretending the two carriers are one instance (which
-- would be a type-mismatched abstraction). Teeth: an 'applyDelta' that ignored provenance or a
-- 'deltaBetween' that dropped moved voxels would fail to reproduce @tapply sigma idx@.
lawIndexDeltaRealizesTransport :: Transport -> [Int] -> Bool
lawIndexDeltaRealizesTransport sigma idx =
  let moved = tapply sigma idx
  in applyDelta (deltaBetween idx moved) idx == moved
