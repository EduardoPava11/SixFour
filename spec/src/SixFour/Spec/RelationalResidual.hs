{- |
Module      : SixFour.Spec.RelationalResidual
Description : The residual as a RELATIONAL MEMORY UNIT — a voxel becomes a 6D point @(L,a,b,x,y,t)@ with a distance @d6@, so pixels in different regions are comparable; the learned head emits the @7 bands x {x,y} = 14@ position residual the deterministic lift cannot give (L,t are the carrier pair, held out).

The pivot (2026-06-22): today a voxel stores only colour @(L,a,b)@ (Q16) and its
position @(x,y,t)@ is the IMPLICIT octant-Morton array index
("SixFour.Spec.CubeTensor" @channelOf _ DimX = Nothing@). So position is not a value
you can take a DISTANCE on across regions. This module makes the 6D point and its
distance first-class:

  * 'P6' — the comparable point @(L,a,b,x,y,t)@.
  * 'd6' — the relational distance (Q16 L1). THE load-bearing new object: it is what
    turns the residual into a relational MEMORY (a key you can place against any other
    octant), because position is now a carried VALUE, not an index that only supports
    same-array arithmetic.

The colour<->position pairing is the EXISTING "SixFour.Spec.Dim6" involution @phi6@
(@a<->x@, @b<->y@, @L<->t@; the @Phi@ functor of "SixFour.Spec.XYTLabDuality"). Under it
the carriers are exactly @{L,t}@ ('isUniversal') and the searches are @{a,b,x,y}@. So of
the octant's @1 coarse + 7 detail@ ("SixFour.Spec.OctreeCell" @liftOct@), the LEARNED
position residual is @7 detail bands x 2 search-position channels {x,y} = 14@ ints per
octant ('relationalResidualLen'): L is the deterministic carrier
("SixFour.Spec.CarrierL" @ocCoarse == lBalance@), and its @phi6@-partner @t@ is therefore
ALSO a free carrier. That 14 is exactly the user's "@16 - 2 = 14@" once "byte" is read as
"band slot": 8 octant slots, the coarse carrier removed, the 7 detail bands paired to
their @{x,y}@ search-position lanes.

The @+/-1@ quantum is one step in a search axis; 'd6' of two points one step apart is 1.

GHC-boot-only. Additive: reuses @Dim6@\/@phi6@, @OctreeCell@ (the 7-band count),
@CarrierL@ (the carrier identity). Laws QuickCheck'd in "Properties.RelationalResidual".
-}
module SixFour.Spec.RelationalResidual
  ( -- * The comparable 6D point + its relational distance
    P6(..)
  , d6
  , nudge
    -- * The residual budget (carriers held out)
  , residualBands
  , searchPositionChannels
  , relationalResidualLen
    -- * Laws (QuickCheck'd in @Properties.RelationalResidual@)
  , lawPhi6PairsColourWithPosition
  , lawCarriersAreLandT
  , lawResidualIsFourteen
  , lawD6NonNegative
  , lawD6Symmetric
  , lawD6IdentityOfIndiscernibles
  , lawD6TriangleInequality
  , lawUnitQuantumIsOneStep
  ) where

import SixFour.Spec.Dim6 (Dim6(..), phi6, isUniversal, isSearch)

-- | The comparable point: @(L,a,b,x,y,t)@ in Q16 integer units. Colour @(L,a,b)@ is
-- stored today; position @(x,y,t)@ is lifted from the implicit Morton index into a real
-- value so distance is computable across regions.
data P6 = P6
  { p6L :: !Int, p6A :: !Int, p6B :: !Int
  , p6X :: !Int, p6Y :: !Int, p6T :: !Int
  } deriving (Eq, Show)

-- | The six coordinates in axis order (@L,a,b,x,y,t@).
coords :: P6 -> [Int]
coords (P6 l a b x y t) = [l, a, b, x, y, t]

-- | The RELATIONAL DISTANCE: Q16 L1 over the 6D point. Symmetric, non-negative, zero iff
-- equal, triangle-respecting (a genuine metric) — so the residual is a memory KEY any two
-- octants can be compared by, not an index. Equal weights: the @+/-1@ quantum is one unit
-- on any axis.
d6 :: P6 -> P6 -> Int
d6 p q = sum (zipWith (\a b -> abs (a - b)) (coords p) (coords q))

-- | Move a single axis by @delta@ (the @+/-1@ gesture; via @phi6@ a nudge on search
-- colour @a@ is the same step as on position @x@).
nudge :: Dim6 -> Int -> P6 -> P6
nudge DimL d p = p { p6L = p6L p + d }
nudge DimA d p = p { p6A = p6A p + d }
nudge DimB d p = p { p6B = p6B p + d }
nudge DimX d p = p { p6X = p6X p + d }
nudge DimY d p = p { p6Y = p6Y p + d }
nudge DimT d p = p { p6T = p6T p + d }

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
-- Laws (predicates; QuickCheck'd in Properties.RelationalResidual)
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
