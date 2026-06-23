{- |
Module      : SixFour.Spec.XYTLabDuality
Description : The [x,y,t] ≅ [L,a,b] duality — a Φ-twisted Balance ⊣ Search split (L≅t universal, a≅x b≅y searches).

The user's keystone: position and colour are DUAL. The positional axes @[x,y,t]@
correspond to the colour axes @[a,b,L]@ under an involutive duality functor @Φ@
(@x↦a@, @y↦b@, @t↦L@), and that correspondence splits each cube into two factors
of different character:

  * a __universal / balance__ factor @t ≅ L@ — the DC / coarse axis, /acted on/
    toward a unique optimum (the L white-balance + dynamic-range operator), never
    searched. ('universalAxis', 'universalChroma'.)
  * a __search__ factor @(x,y) ≅ (a,b)@ — the directions the A/B picks /destabilize/
    and search over.

@Φ@ preserves this split ('lawPhiPreservesUniversal'). The split itself is the
@Balance ⊣ Search@ adjunction, realised concretely by the reversible Haar lifting
of "SixFour.Spec.RGBTLift": 'balance' is the coarse/DC left adjoint, 'search' the
detail right adjoint, and the adjunction UNIT is the exact round-trip
@unliftQuad . liftQuad = id@ ('lawAdjunctionUnit').

GHC-boot-only. Laws are exported predicates, QuickCheck'd in @Properties.XYTLabDuality@.
-}
-- COMPARTMENT: PURE-SPEC-WALL | tag:none
module SixFour.Spec.XYTLabDuality
  ( -- * The dual axis labels
    Axis(..)
  , Chroma(..)
    -- * The duality functor Φ
  , phi
  , phiInv
    -- * The universal / search split
  , universalAxis
  , universalChroma
    -- * Balance ⊣ Search (grounded in the reversible Haar split)
  , balance
  , search
    -- * Laws (QuickCheck'd in @Properties.XYTLabDuality@)
  , lawPhiInvolution
  , lawPhiPreservesUniversal
  , lawUniversalIsTL
  , lawAdjunctionUnit
  ) where

import SixFour.Spec.RGBTLift (Quad, liftQuad, unliftQuad)

-- | The positional axes of the @(x,y,t)@ index cube.
data Axis = X | Y | T deriving (Eq, Show, Enum, Bounded)

-- | The OKLab colour axes (a = R−G, b = (R+G)−B, L = lightness).
data Chroma = A | B | L deriving (Eq, Show, Enum, Bounded)

-- | The duality functor on axes: @x↦a@, @y↦b@, @t↦L@ (position ↦ colour).
phi :: Axis -> Chroma
phi X = A
phi Y = B
phi T = L

-- | Its inverse: @a↦x@, @b↦y@, @L↦t@.
phiInv :: Chroma -> Axis
phiInv A = X
phiInv B = Y
phiInv L = T

-- | An axis is UNIVERSAL (the balance/DC axis) iff it is @t@; @x@,@y@ are SEARCH axes.
universalAxis :: Axis -> Bool
universalAxis T = True
universalAxis _ = False

-- | A colour axis is UNIVERSAL iff it is @L@; @a@,@b@ are SEARCH axes.
universalChroma :: Chroma -> Bool
universalChroma L = True
universalChroma _ = False

-- | Balance (left adjoint): collapse a 2×2 cell to its coarse/DC value — the
-- universal factor (the @R = LL@ band of "SixFour.Spec.RGBTLift").
balance :: Quad -> Int
balance q = let (r, _, _, _) = liftQuad q in r

-- | Search (right adjoint): the detail sub-bands — the section the A/B picks move.
search :: Quad -> (Int, Int, Int)
search q = let (_, g, b, t) = liftQuad q in (g, b, t)

-- | Φ is an involution / bijection: @phiInv . phi = id@.
lawPhiInvolution :: Axis -> Bool
lawPhiInvolution ax = phiInv (phi ax) == ax

-- | Φ maps the universal/search split to itself: an axis is universal iff its
-- colour-dual is — i.e. @L≅t@ universal, @a≅x@ and @b≅y@ searches.
lawPhiPreservesUniversal :: Axis -> Bool
lawPhiPreservesUniversal ax = universalAxis ax == universalChroma (phi ax)

-- | The universal factor is exactly @{t} ↔ {L}@.
lawUniversalIsTL :: Bool
lawUniversalIsTL =
     filter universalAxis   [minBound .. maxBound] == [T]
  && filter universalChroma [minBound .. maxBound] == [L]
  && phi T == L

-- | The @Balance ⊣ Search@ adjunction's UNIT is the reversible Haar split: the
-- cell is recovered exactly from @(balance, search)@ — @unliftQuad . liftQuad = id@
-- (the triangle identity made exact; cf. @RGBTLift.lawLiftUnliftExact@).
lawAdjunctionUnit :: Quad -> Bool
lawAdjunctionUnit q = unliftQuad (liftQuad q) == q
