-- COMPARTMENT: MLX-MODEL | tag:MacTag
{- |
Module      : SixFour.Spec.RelationalMemory
Description : The I-JEPA RELATIONAL MEMORY UNIT — the d6 metric (the attention ground-distance / memory KEY) + the 14-int residual budget + the memory laws, split OUT of "SixFour.Spec.RelationalResidual" into the cohesive MLX-MODEL compartment. The SUBSTRATE it rides on (the @P6@ point, @nudge@, the @safeNudge@ domain guard) STAYS in the Zig floor; this is the LEARNED-side memory that rides above it.

Destructive compartment pivot (STEP 4): @RelationalResidual@ was a STRADDLER — it mixed the
bit-exact Zig-floor substrate (@P6@, @nudge@, @safeNudge@ = the @RC_OUT_OF_RANGE@ domain guard)
with the I-JEPA position MEMORY (@d6@, the 14-int residual, the metric laws). This module takes
the MEMORY half into MLX-MODEL beside "SixFour.Spec.LargeJepaHead" + "SixFour.Spec.JepaMemory";
the substrate half stays in the now-cohesive Zig-floor "SixFour.Spec.RelationalResidual". The
dependency direction is natural: the learned memory IMPORTS the substrate point + move.

The memory budget here is pinned + carried by "SixFour.Spec.JepaMemory" (@relationalResidualLen
== 14@ bound to the 77-param trained carrier); this module owns the definitions, JepaMemory owns
the accounting. GHC-boot-only. Laws QuickCheck'd in "Properties.RelationalMemory".
-}
module SixFour.Spec.RelationalMemory
  ( -- * The relational distance (the memory KEY)
    d6
  , dColour
    -- * The residual budget (carriers held out)
  , residualBands
  , searchPositionChannels
  , relationalResidualLen
    -- * Laws (QuickCheck'd in @Properties.RelationalMemory@)
  , lawPhi6PairsColourWithPosition
  , lawCarriersAreLandT
  , lawResidualIsFourteen
  , lawD6NonNegative
  , lawD6Symmetric
  , lawD6IdentityOfIndiscernibles
  , lawD6TriangleInequality
  , lawUnitQuantumIsOneStep
  , lawPositionDistinguishesSameColour
  ) where

import SixFour.Spec.Dim6 (Dim6(..), phi6, isUniversal, isSearch)
import SixFour.Spec.RelationalResidual (P6(..), p6Coords, nudge)

-- | THE RELATIONAL DISTANCE: Q16 L1 over the 6D point. Symmetric, non-negative, zero iff
-- equal, triangle-respecting (a genuine metric) — so the residual is a memory KEY any two
-- octants can be compared by, not an index. Equal weights: the @+/-1@ quantum is one unit
-- on any axis. (The attention ground-distance the large head's @d6Bias@ scales.)
d6 :: P6 -> P6 -> Int
d6 p q = sum (zipWith (\a b -> abs (a - b)) (p6Coords p) (p6Coords q))

-- | The COLOUR-ONLY distance (Q16 L1 over just @(L,a,b)@) — what a position-blind
-- representation can see. Contrast with 'd6': this is what the model was limited to before
-- position became a carried value.
dColour :: P6 -> P6 -> Int
dColour (P6 l a b _ _ _) (P6 l' a' b' _ _ _) = abs (l - l') + abs (a - a') + abs (b - b')

-- | The octant's detail-band count — @7@ ("SixFour.Spec.OctreeCell" @liftOct@ = 1 coarse
-- + 7 detail).
residualBands :: Int
residualBands = 7

-- | The number of SEARCH position channels the learned head emits — @{x,y} = 2@. The
-- carriers @{L,t}@ are held out (deterministic floor), so they are NOT emitted.
searchPositionChannels :: Int
searchPositionChannels = 2

-- | The learned RELATIONAL RESIDUAL length: @7 bands x 2 search-position channels = 14@
-- ints per octant. This is the user's "@16 - 2 = 14@": 8 octant slots, the coarse carrier
-- removed, the 7 detail bands paired to their @{x,y}@ lanes (L,t carriers held out).
relationalResidualLen :: Int
relationalResidualLen = residualBands * searchPositionChannels

-- ============================================================================
-- Laws (predicates; QuickCheck'd in Properties.RelationalMemory)
-- ============================================================================

-- | THE pairing that grounds "the natural relationship of L,a,b,x,y,t": @phi6@ pairs each
-- colour axis with its position axis — @a<->x@, @b<->y@, @L<->t@. Teeth: a wrong pairing
-- (e.g. @a<->y@) fails. Delegates "SixFour.Spec.Dim6" @phi6@.
lawPhi6PairsColourWithPosition :: Bool
lawPhi6PairsColourWithPosition =
     phi6 DimA == DimX && phi6 DimX == DimA
  && phi6 DimB == DimY && phi6 DimY == DimB
  && phi6 DimL == DimT && phi6 DimT == DimL

-- | The carrier pair is exactly @{L,t}@ (the @phi6@-paired universals); the searches are
-- exactly @{a,b,x,y}@. This is WHY the learned residual excludes 2 of the 6 axes: L is the
-- deterministic carrier and its partner t rides free. Teeth: marking a search axis
-- universal (or vice versa) fails. Delegates @isUniversal@\/@isSearch@.
lawCarriersAreLandT :: Bool
lawCarriersAreLandT =
     and [ isUniversal a | a <- [DimL, DimT] ]
  && not (or [ isUniversal a | a <- [DimA, DimB, DimX, DimY] ])
  && and [ isSearch a | a <- [DimA, DimB, DimX, DimY] ]
  && isUniversal (phi6 DimL)   -- the partner of a carrier is a carrier (t)

-- | The learned residual is @14@ ints per octant: @7 detail bands x 2 search-position
-- channels {x,y}@, with the carrier pair @{L,t}@ held out. This is the user's
-- "@16 - 2 = 14@" made exact. Teeth: emitting the carrier lanes (would be 21) or dropping
-- a band fails.
lawResidualIsFourteen :: Bool
lawResidualIsFourteen =
     relationalResidualLen == 14
  && relationalResidualLen == residualBands * searchPositionChannels
  && searchPositionChannels == length [ a | a <- [DimX, DimY], isSearch a ]

-- | 'd6' is non-negative (a distance).
lawD6NonNegative :: P6 -> P6 -> Bool
lawD6NonNegative p q = d6 p q >= 0

-- | 'd6' is symmetric.
lawD6Symmetric :: P6 -> P6 -> Bool
lawD6Symmetric p q = d6 p q == d6 q p

-- | 'd6' is zero IFF the points are equal (identity of indiscernibles) — so the residual
-- is a faithful key: distinct 6D points are never confused.
lawD6IdentityOfIndiscernibles :: P6 -> P6 -> Bool
lawD6IdentityOfIndiscernibles p q = (d6 p q == 0) == (p == q)

-- | 'd6' respects the triangle inequality — the property that makes it a usable metric for
-- relating octants (nearest-neighbour, clustering).
lawD6TriangleInequality :: P6 -> P6 -> P6 -> Bool
lawD6TriangleInequality p q r = d6 p r <= d6 p q + d6 q r

-- | The @+/-1@ quantum: a one-unit nudge on ANY axis is distance exactly 1 — so "the user
-- moves a +/-1 unit" is a well-defined unit step, and via @phi6@ the same step on the
-- paired position axis. Teeth: a non-unit metric weight fails.
lawUnitQuantumIsOneStep :: Dim6 -> P6 -> Bool
lawUnitQuantumIsOneStep ax p = d6 p (nudge ax 1 p) == 1 && d6 p (nudge ax (-1) p) == 1

-- | THE I-JEPA position-conditioning theorem: position carries DISTINGUISHING information
-- that colour alone (and the old implicit array index) cannot. Two voxels with the SAME
-- colour @(L,a,b)@ but different position @(x,y,t)@ are INVISIBLE to a colour-only distance
-- (@dColour == 0@) yet DISTINCT under @d6@ (@d6 == 0@ iff their positions also match). This
-- is why the relational residual IS the I-JEPA positional embedding: it lets the predictor
-- be conditioned on WHERE it predicts. Teeth: a position-blind metric (or dropping x,y,t
-- from @d6@) collapses the two and fails the second conjunct.
lawPositionDistinguishesSameColour :: P6 -> P6 -> Bool
lawPositionDistinguishesSameColour p q =
  let q' = q { p6L = p6L p, p6A = p6A p, p6B = p6B p }   -- force the SAME colour as p
      samePos = p6X p == p6X q' && p6Y p == p6Y q' && p6T p == p6T q'
  in dColour p q' == 0                                    -- colour-only is blind to position
     && (d6 p q' == 0) == samePos                         -- d6 sees it: zero IFF positions match too
