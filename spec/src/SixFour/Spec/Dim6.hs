{- |
Module      : SixFour.Spec.Dim6
Description : The 6-axis alphabet (L,A,B,x,y,t) every projection-ordering permutes — one FLAT set spanning the colour/position boundary, with the Phi-twist as an involution.

The frontier (1a) is: the SAME 64³ object encoded as an ORDERED SET OF PROJECTIONS
of its six dimensions into the recursive octant ladder. Before an "ordering" can be a
type, the six dims need to be ONE flat alphabet. "SixFour.Spec.XYTLabDuality" keeps
them as TWO split 3-sets (@Axis = X|Y|T@, @Chroma = A|B|L@) joined by the functor Φ;
this module unifies them so a single permutation can range over all six.

'phi6' is the @x↔a, y↔b, t↔L@ twist (the duality Φ lifted to one set), and it is its
own inverse ('lawPhi6Involution'). 'isUniversal' marks the @L,t@ axes (the
universal\/balance carrier — frontier 1b) that the encoding condition will pin to the
coarse\/DC lane; the other four are the search axes.

Subset-enum (nullary constructors) is the precise type: the guarantee needed is a
FINITE CLOSED enumeration, and @Enum@\/@Bounded@ give the permutation\/coverage checks
for free. No payload, no DataKinds — type-level perms over a fixed 6-set would be pure
ceremony.
-}
module SixFour.Spec.Dim6
  ( Dim6(..)
  , allDims
  , phi6
  , isUniversal
  , isSearch
    -- * Laws (QuickCheck'd in @Properties.Dim6@)
  , lawDim6Finite
  , lawPhi6Involution
  , lawPhi6AgreesWithDuality
  , lawUniversalIsLT
  ) where

import Data.List (nub)

-- | The six dimensions of the cube as ONE flat alphabet: lightness, the two chroma
-- search axes, and the three space-time axes.
data Dim6 = DimL | DimA | DimB | DimX | DimY | DimT
  deriving (Eq, Ord, Show, Enum, Bounded)

-- | All six dims, in declaration order (the @Enum@\/@Bounded@ enumeration).
allDims :: [Dim6]
allDims = [minBound .. maxBound]

-- | The Φ-twist as an endo-permutation of the flat alphabet: @x↔a@, @y↔b@, @t↔L@.
-- It is its own inverse. (The single-set lift of "SixFour.Spec.XYTLabDuality"'s Φ.)
phi6 :: Dim6 -> Dim6
phi6 DimX = DimA
phi6 DimA = DimX
phi6 DimY = DimB
phi6 DimB = DimY
phi6 DimT = DimL
phi6 DimL = DimT

-- | The UNIVERSAL\/balance carrier axes (@L@ and its space-time partner @t@) — the
-- signal carrier (frontier 1b); the encoding condition pins these to the coarse\/DC lane.
isUniversal :: Dim6 -> Bool
isUniversal DimL = True
isUniversal DimT = True
isUniversal _    = False

-- | The SEARCH\/destabilize axes (everything that is not universal): @A,B@ and their
-- space partners @x,y@.
isSearch :: Dim6 -> Bool
isSearch = not . isUniversal

-- ============================================================================
-- Laws (predicates; QuickCheck'd in Properties.Dim6)
-- ============================================================================

-- | The alphabet is finite and closed: exactly six distinct inhabitants. This is
-- what makes "covers all dims" / "is a permutation" decidable downstream.
lawDim6Finite :: Bool
lawDim6Finite = length allDims == 6 && length (nub allDims) == 6

-- | The Φ-twist is an involution: @phi6 . phi6 == id@ on every dim.
lawPhi6Involution :: Dim6 -> Bool
lawPhi6Involution d = phi6 (phi6 d) == d

-- | Φ encodes the duality @x↦a, y↦b, t↦L@ (and back) — the same pairing
-- "SixFour.Spec.XYTLabDuality" fixes, here on the flat alphabet.
lawPhi6AgreesWithDuality :: Bool
lawPhi6AgreesWithDuality =
  phi6 DimX == DimA && phi6 DimY == DimB && phi6 DimT == DimL
    && phi6 DimA == DimX && phi6 DimB == DimY && phi6 DimL == DimT

-- | The universal carrier is exactly @{L,t}@, and Φ maps one universal axis to the
-- other (it never turns a carrier into a search axis): the carrier set is Φ-closed.
lawUniversalIsLT :: Dim6 -> Bool
lawUniversalIsLT d = isUniversal d == (d == DimL || d == DimT)
                     && isUniversal (phi6 d) == isUniversal d
