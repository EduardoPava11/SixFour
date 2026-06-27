{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE FlexibleInstances #-}
{- |
Module      : SixFour.Spec.GaussianChroma
Description : The Gaussian-chroma KNOB the capstone unlocked, carried toward the trainer: represent the two OKLab chroma axes @(a,b)@ as ONE Gaussian integer @a + b·i@ (lightness @L@ stays real), so a colour delta is @(L : ℤ, chroma : ℤ[i])@. This is a second 'SixFour.Spec.RefinementSystem.RModule' carrier built on the proven @CommutativeRing Gaussian@ instance — and it UNLOCKS an operation the two-independent-reals encoding has no single ring op for: complex MULTIPLICATION is a hue rotation of the chroma plane (multiply by the unit @i@ = an exact 90° quarter-turn, order 4, norm-preserving).

Why this is the knob "carried toward the trainer": a recolour parameterized over @ℤ[i]@ chroma gets a
structured, exactly-invertible HUE-ROTATION primitive for free — @rmul (a + b·i)@ scales and rotates
the chroma plane in one ring op, with the four Gaussian units @{1, i, -1, -i}@ giving the exact
quarter-turn hue rotations. Two scalar @a@,@b@ channels cannot express that as a single algebraic
operation. The re-encoding is FAITHFUL (addition agrees with componentwise real-pair addition,
'lawChromaAddAgreesWithRealPairs'), so nothing is lost relative to today's 'SixFour.Spec.HierarchicalDelta'
@ColourDelta@; what is GAINED is the multiplicative structure.

Note the contrast with @ColourDelta@'s wiring ("SixFour.Spec.RefinementCarriers"): @GColourDelta@ has
a FIXED shape (one @L@, one chroma), so its @RModule@ additive-inverse law holds STRICTLY (no
trailing-zero normalization needed). Additive: imports only the capstone ring/module; emits no golden.
-}
-- COMPARTMENT: PURE-SPEC-WALL | tag:none
module SixFour.Spec.GaussianChroma
  ( -- * The Gaussian-chroma colour delta (L real, chroma ∈ ℤ[i])
    GColourDelta(..)
  , packChroma
  , unpackChroma
    -- * The hue-rotation operator (the ℤ[i] payoff)
  , gaussI
  , gaussNorm
  , rotateChroma
    -- * Laws
  , lawChromaAddAgreesWithRealPairs
  , lawChromaUnitIsQuarterTurn
  , lawChromaUnitRotationPreservesNorm
  , lawChromaQuarterTurnOrderFour
  , lawChromaScaleByRealIsComponentwise
  ) where

import SixFour.Spec.RefinementSystem
  ( CommutativeRing(..), RModule(..), Gaussian(..) )

-- | A colour delta with the chroma plane carried as ONE Gaussian integer: @L@ is the real lightness
-- displacement, @chroma = a + b·i@ packs the two OKLab chroma axes. The value carrier of
-- "SixFour.Spec.RefinementCarriers" @ColourDelta@ re-encoded so the chroma axes share a ring.
data GColourDelta = GColourDelta { gcL :: Integer, gcChroma :: Gaussian }
  deriving (Eq, Show)

-- | Pack a real chroma pair @(a,b)@ into the Gaussian integer @a + b·i@.
packChroma :: (Int, Int) -> Gaussian
packChroma (a, b) = Gaussian (toInteger a, toInteger b)

-- | Unpack a Gaussian chroma back to the real pair @(a,b)@.
unpackChroma :: Gaussian -> (Int, Int)
unpackChroma (Gaussian (a, b)) = (fromInteger a, fromInteger b)

-- | The Gaussian unit @i@ — a quarter-turn of the chroma plane under 'rotateChroma'.
gaussI :: Gaussian
gaussI = Gaussian (0, 1)

-- | The (squared) norm @a² + b²@ of a Gaussian chroma — the squared chroma radius (preserved by
-- rotation, scaled by a non-unit multiply).
gaussNorm :: Gaussian -> Integer
gaussNorm (Gaussian (a, b)) = a * a + b * b

-- | Rotate\/scale the chroma plane by a Gaussian: @rmul u@ on the chroma component, @L@ untouched.
-- With @u = i@ this is a 90° hue rotation; with a general @a + b·i@ it scales by @√(a²+b²)@ and
-- rotates by its argument — a structured recolour the two-scalar encoding has no single op for.
rotateChroma :: Gaussian -> GColourDelta -> GColourDelta
rotateChroma u (GColourDelta l c) = GColourDelta l (rmul u c)

-- | The capstone 'RModule' instance over the Gaussian-chroma carrier: scale by an integer acts on
-- @L@ and (via @rmul (k + 0·i)@) on the chroma; deltas add componentwise; the inverse negates both.
-- A second, FIXED-shape witness of the value carrier (no ragged-length caveat ⇒ every module law,
-- including additive inverse, holds strictly).
instance RModule Integer GColourDelta where
  mzero = GColourDelta rzero rzero
  madd (GColourDelta l c) (GColourDelta l' c') = GColourDelta (radd l l') (radd c c')
  mneg (GColourDelta l c) = GColourDelta (rneg l) (rneg c)
  smul k (GColourDelta l c) = GColourDelta (rmul k l) (rmul (Gaussian (k, 0)) c)

-- ---------------------------------------------------------------------------
-- Laws (QuickCheck'd in Properties.GaussianChroma)
-- ---------------------------------------------------------------------------

-- | FAITHFULNESS: the @ℤ[i]@ re-encoding intertwines addition — adding packed chroma equals adding
-- the real pairs componentwise. So the Gaussian carrier loses nothing the two-real @ColourDelta@
-- had. Teeth: an encoding that coupled the axes under addition (anything but @a+c, b+d@) fails.
lawChromaAddAgreesWithRealPairs :: (Int, Int) -> (Int, Int) -> Bool
lawChromaAddAgreesWithRealPairs p@(a, b) q@(c, d) =
  unpackChroma (radd (packChroma p) (packChroma q)) == (a + c, b + d)

-- | THE payoff: multiplying chroma by the Gaussian unit @i@ is an exact 90° hue rotation
-- @(a,b) ↦ (-b, a)@ — a single ring op with no two-scalar-channel analogue. Teeth: any commutative
-- per-axis scaling gives @(a,b) ↦ (±a, ±b)@, never the cross @(-b, a)@.
lawChromaUnitIsQuarterTurn :: (Int, Int) -> Bool
lawChromaUnitIsQuarterTurn (a, b) =
  unpackChroma (rmul gaussI (packChroma (a, b))) == (-b, a)

-- | The quarter-turn is a ROTATION, not a scale: it preserves the chroma norm @a² + b²@ (the four
-- Gaussian units are exactly the norm-1 elements). Teeth: a non-unit multiply would scale the norm.
lawChromaUnitRotationPreservesNorm :: (Int, Int) -> Bool
lawChromaUnitRotationPreservesNorm (a, b) =
  let z = packChroma (a, b)
  in gaussNorm (rmul gaussI z) == gaussNorm z

-- | Hue rotation by @i@ has ORDER 4: four quarter-turns return the original chroma (@i⁴ = 1@). This
-- is the cyclic hue-rotation subgroup the trainer gets for free. Teeth: order-2 (@-1@) or any
-- non-unit fails to close after four steps for a generic chroma.
lawChromaQuarterTurnOrderFour :: (Int, Int) -> Bool
lawChromaQuarterTurnOrderFour (a, b) =
  let z   = packChroma (a, b)
      rot = rmul gaussI
  in rot (rot (rot (rot z))) == z

-- | The module scalar action over @GColourDelta@ acts componentwise: scaling by an integer @k@
-- scales @L@ and both chroma axes by @k@ (a real recolour gain), distinct from the hue ROTATION a
-- Gaussian multiply gives. Ties the carrier to "SixFour.Spec.RefinementSystem" @lawModuleSmul*@.
lawChromaScaleByRealIsComponentwise :: Integer -> Integer -> (Int, Int) -> Bool
lawChromaScaleByRealIsComponentwise k l (a, b) =
  let x = GColourDelta l (packChroma (a, b))
  in smul k x == GColourDelta (k * l) (Gaussian (k * toInteger a, k * toInteger b))
