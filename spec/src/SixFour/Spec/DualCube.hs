{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE FlexibleInstances #-}
{- |
Module      : SixFour.Spec.DualCube
Description : The PIVOT off L-anchoring: the colour cube @(L,a,b)@ and the space cube @(x,y,t)@ as TWO copies of ONE @ℤ ⊕ ℤ[i]@ module (a real BALANCE axis + a Gaussian SEARCH plane), EXCHANGED by the φ6 involution. Because φ6 is a module AUTOMORPHISM that carries the colour cube onto the space cube, neither cube is algebraically privileged: anchoring on L (the colour balance) is the exact φ6-image of anchoring on t (the space balance), so the L-anchor is arbitrary, not canonical. This replaces the asymmetric @{L,t}@-carrier / @{a,b,x,y}@-search story (see "SixFour.Spec.CarrierL", "SixFour.Spec.RelationalMemory") with a SYMMETRIC dual-cube carrier.

Built on "SixFour.Spec.XYTLabDuality" (the axis-level functor φ: @x↦a, y↦b, t↦L@) and the
@ℤ[i]@ chroma ring of "SixFour.Spec.GaussianChroma" (a cube's search plane is one Gaussian integer;
the colour plane is @a+b·i@, the space plane is @x+y·i@). Each cube is a 'GColourDelta'
(@balance : ℤ@, @plane : ℤ[i]@), an @RModule ℤ@. The two lenses appear as the two factors:
DISCRETE GEOMETRY scores the real balance axis (the @ℓ¹@ lattice norm), ALGEBRAIC NUMBER THEORY
scores the Gaussian search plane (the @ℤ[i]@ field norm).

KEYSTONE 'lawCubesExchangedByPhi6': @colorCube (phi6 p) == spaceCube p@ and vice versa, so the two
cubes are dual. 'lawPhi6IsModuleAutomorphism' makes φ6 a genuine symmetry of the @ℤ⁶@ module, which
is the precise sense in which there is NO PRIVILEGED CARRIER. Pure-spec, emits no golden.
-}
-- COMPARTMENT: PURE-SPEC-WALL | tag:none
module SixFour.Spec.DualCube
  ( -- * The full 6D point and its two cube readings
    P6(..)
  , CubeKind(..)
  , colorCube
  , spaceCube
  , readCube
    -- * The φ6 duality (point-level), realizing XYTLabDuality's axis functor
  , phi6
    -- * Laws
  , lawPhi6Involution
  , lawCubesExchangedByPhi6
  , lawPhi6IsModuleAutomorphism
  , lawNoPrivilegedCarrier
  , lawBalanceRealSearchGaussian
  , lawPhi6MatchesAxisDuality
  ) where

import SixFour.Spec.RefinementSystem (Gaussian(..), RModule(..))
import SixFour.Spec.GaussianChroma   (GColourDelta(..), gaussNorm)
import SixFour.Spec.MetricLattice    (NormP(..), norm)
import SixFour.Spec.XYTLabDuality    (Axis(..), Chroma(..), phi)

-- | A full 6D relational point @(L,a,b,x,y,t)@. Its two cube readings (colour and space) are the
-- two halves the φ6 duality swaps.
data P6 = P6 { pL :: Integer, pA :: Integer, pB :: Integer
             , pX :: Integer, pY :: Integer, pT :: Integer }
  deriving (Eq, Show)

-- | The @ℤ⁶@ module structure (the cube carrier is a free ℤ-module of rank 6).
instance RModule Integer P6 where
  mzero = P6 0 0 0 0 0 0
  madd (P6 l a b x y t) (P6 l' a' b' x' y' t') =
    P6 (l + l') (a + a') (b + b') (x + x') (y + y') (t + t')
  mneg (P6 l a b x y t) = P6 (negate l) (negate a) (negate b) (negate x) (negate y) (negate t)
  smul k (P6 l a b x y t) = P6 (k * l) (k * a) (k * b) (k * x) (k * y) (k * t)

-- | Which cube a point is read as. φ6 swaps these.
data CubeKind = ColorCube | SpaceCube deriving (Eq, Show, Enum, Bounded)

-- | The COLOUR cube reading: balance @L@ (the real axis), search plane @a + b·i@ (the @ℤ[i]@ plane).
colorCube :: P6 -> GColourDelta
colorCube p = GColourDelta (pL p) (Gaussian (pA p, pB p))

-- | The SPACE cube reading: balance @t@ (the real axis), search plane @x + y·i@ (the @ℤ[i]@ plane).
-- Structurally IDENTICAL to 'colorCube' (same @ℤ ⊕ ℤ[i]@ type) — that sameness is the whole point.
spaceCube :: P6 -> GColourDelta
spaceCube p = GColourDelta (pT p) (Gaussian (pX p, pY p))

-- | Read a point as the requested cube.
readCube :: CubeKind -> P6 -> GColourDelta
readCube ColorCube = colorCube
readCube SpaceCube = spaceCube

-- | The φ6 duality at the POINT level: swap the colour and space triples per the axis functor
-- (@L↔t@, @a↔x@, @b↔y@). An involution. Realizes "SixFour.Spec.XYTLabDuality" @phi@ on values.
phi6 :: P6 -> P6
phi6 (P6 l a b x y t) = P6 t x y a b l

-- ---------------------------------------------------------------------------
-- Laws
-- ---------------------------------------------------------------------------

-- | φ6 is an involution: applying it twice is the identity (the duality is its own inverse).
lawPhi6Involution :: P6 -> Bool
lawPhi6Involution p = phi6 (phi6 p) == p

-- | THE KEYSTONE: the two cubes are EXCHANGED by φ6 — reading the φ6-image as colour gives the
-- original's space cube, and vice versa. So the colour and space cubes are genuinely dual, not
-- independent. This is the structural pivot off "L is the carrier": L (colour balance) and t
-- (space balance) are φ6-images of each other.
lawCubesExchangedByPhi6 :: P6 -> Bool
lawCubesExchangedByPhi6 p =
  colorCube (phi6 p) == spaceCube p && spaceCube (phi6 p) == colorCube p

-- | φ6 is a ℤ-module AUTOMORPHISM of @ℤ⁶@: it commutes with module addition and the scalar action.
-- This is the precise sense in which the duality is a SYMMETRY of the carrier, so neither cube can
-- be the canonical anchor (a symmetry cannot prefer one of two exchanged things).
lawPhi6IsModuleAutomorphism :: P6 -> P6 -> Integer -> Bool
lawPhi6IsModuleAutomorphism p q k =
  phi6 (madd p q) == madd (phi6 p) (phi6 q)
  && phi6 (smul k p) == smul k (phi6 p)
  && phi6 (mzero :: P6) == mzero

-- | NO PRIVILEGED CARRIER: the colour balance axis (L) and the space balance axis (t) are carried
-- onto each other by the φ6 automorphism, so privileging either as "the" anchor is arbitrary. The
-- balance of @colorCube p@ equals the balance of @spaceCube (phi6 p)@ (and symmetrically). Teeth: a
-- design that hard-codes L as the only carrier breaks this exchange.
lawNoPrivilegedCarrier :: P6 -> Bool
lawNoPrivilegedCarrier p =
  let GColourDelta colBal _ = colorCube p
      GColourDelta spcBal _ = spaceCube (phi6 p)
  in colBal == spcBal                         -- L of colour == t-after-φ6 == the same value
     && gcL (colorCube p) == pL p
     && gcL (spaceCube p) == pT p             -- the two balances are distinct axes, exchanged by φ6

-- | The two lenses, per cube: the BALANCE is a real ℤ axis (DISCRETE GEOMETRY, scored by the @ℓ¹@
-- lattice norm) and the SEARCH is a Gaussian @ℤ[i]@ plane (ALGEBRAIC NUMBER THEORY, scored by the
-- field norm @a²+b²@). So a cube = (lattice axis) ⊕ (Gaussian plane).
lawBalanceRealSearchGaussian :: P6 -> Bool
lawBalanceRealSearchGaussian p =
  let GColourDelta bal plane = colorCube p
  in norm L1 [bal] == abs (pL p)
     && gaussNorm plane == pA p * pA p + pB p * pB p

-- | The point-level φ6 realizes "SixFour.Spec.XYTLabDuality"'s axis functor exactly: the balance
-- axes pair @t ≅ L@ and the search axes pair @x ≅ a@, @y ≅ b@. Grounds this module in the existing
-- duality rather than re-asserting it.
lawPhi6MatchesAxisDuality :: Bool
lawPhi6MatchesAxisDuality =
  phi T == L && phi X == A && phi Y == B
