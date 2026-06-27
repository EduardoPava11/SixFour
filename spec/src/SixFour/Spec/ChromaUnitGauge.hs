{- |
Module      : SixFour.Spec.ChromaUnitGauge
Description : The ℤ[i]-UNITS-ARE-LOAD-BEARING bridge: the Gaussian unit group @ℤ[i]* = {1, i, −1, −i}@ acts on the OKLab chroma plane EXACTLY as the model's bit-exact quarter-turn gauge "SixFour.Spec.ChromaRotation" @rotateQuarter@ — the operation the nudge-gesture consumer "SixFour.Spec.DetentNudge" @stepDelta@ actually computes. So the four Gaussian units are not a decorative algebraic fact ("SixFour.Spec.RefinementSystem" @lawGaussianUnitsAreQuarterTurns@ names them only internally); they are the GROUP STRUCTURE of a chroma operation the model already performs, identified through a REAL typed consumer.

This is the honest, NON-FORCED way to make the @ℤ[i]@ units load-bearing (the owner's anti-jargon line):
not a rename of "rotate by 90°", but a proven IDENTITY between two independently-defined maps that were
never connected —

  * "SixFour.Spec.RefinementSystem" defines @units :: [Gaussian] = [1, i, −1, −i]@ and the ring multiply
    @rmul@; "SixFour.Spec.GaussianChroma" shows @rmul i@ sends chroma @(a,b) ↦ (−b,a)@. This is the
    ALGEBRA side (the unit group of the Gaussian integers, @ℤ[i]* ≅ C4@).
  * "SixFour.Spec.ChromaRotation" independently defines the bit-exact integer quarter-turn
    @rotateQuarter q@ (sign swaps, order 4) — the CONSUMED side: "SixFour.Spec.DetentNudge" @stepDelta@
    rotates the unit nudge increment by @rotateQuarter@, and the canonical-form dedup @canonicalQuarter@
    gauges looks by the four quarter-turns.
  * THE BRIDGE ('lawGaussianUnitActsAsQuarterTurn'): the @q@-th Gaussian unit @units !! q@, acting by
    @rmul@ on packed chroma, equals @rotateQuarter q@ for EVERY chroma point. So multiplying by a
    @ℤ[i]@ unit IS the model's quarter-turn. The unit group and the @C4@ gauge are the SAME group, with
    @ℤ[i]@-unit multiply ↔ index addition mod 4 ↔ quarter-turn composition ('lawUnitGroupIsoQuarterTurn').

The consumer tie ('lawCanonicalQuarterIsUnitOrbit') makes it concrete: the model's @canonicalQuarter@
gauge-fix (the dedup "SixFour.Spec.ChromaRotation" @lawCanonicalChromaGaugeFixed@ rests on) is exactly the
ORBIT of a palette under the @ℤ[i]@ unit-group action. So the algebra is not parallel to the model — it
IS the model's chroma gauge group.

The teeth are real, not decorative ('lawNonUnitIsNotAQuarterTurn'): a NON-unit Gaussian (e.g. @1+i@,
norm 2) SCALES the chroma norm, so it equals NO @rotateQuarter q@ — the correspondence is special to the
norm-1 unit group, exactly the @ℤ[i]@ structure the model needs (a finite group of byte-exact isometries,
not an arbitrary multiply). Without this clause the bridge could be a vacuous "some multiply rotates".
Pure-spec, GHC-boot-only; laws QuickCheck'd in "Properties.ChromaUnitGauge". Emits no golden.
-}
-- COMPARTMENT: PURE-SPEC-WALL | tag:none
module SixFour.Spec.ChromaUnitGauge
  ( -- * The unit-group action on chroma, via the proven Gaussian multiply
    unitQuarterTurn
  , applyUnit
    -- * Laws
  , lawGaussianUnitActsAsQuarterTurn
  , lawUnitGroupIsoQuarterTurn
  , lawCanonicalQuarterIsUnitOrbit
  , lawNonUnitIsNotAQuarterTurn
  ) where

import SixFour.Spec.RefinementSystem (Gaussian(..), units, rmul)
import SixFour.Spec.GaussianChroma   (packChroma, unpackChroma, gaussNorm)
import SixFour.Spec.ChromaRotation   (rotateQuarter, canonicalQuarter)

-- | The four Gaussian units in canonical order @[1, i, −1, −i]@ (the "SixFour.Spec.RefinementSystem"
-- @units@ list specialised to @Gaussian@), indexed by their quarter-turn power @q ∈ {0,1,2,3}@.
gaussianUnits :: [Gaussian]
gaussianUnits = units

-- | Act on a chroma point by the @q@-th Gaussian unit, through the proven ring multiply: pack @(a,b)@
-- into @a + b·i@, multiply by @units !! (q mod 4)@, unpack. This is the ALGEBRA-side quarter-turn — the
-- bridge laws prove it equals the CONSUMED 'rotateQuarter' @q@.
unitQuarterTurn :: Int -> (Int, Int) -> (Int, Int)
unitQuarterTurn q ab = unpackChroma (rmul (gaussianUnits !! (q `mod` 4)) (packChroma ab))

-- | Act on a chroma point by a GIVEN Gaussian (unit or not), through the ring multiply. Used by the
-- teeth: a non-unit scales the norm and so cannot be any quarter-turn.
applyUnit :: Gaussian -> (Int, Int) -> (Int, Int)
applyUnit u ab = unpackChroma (rmul u (packChroma ab))

-- ---------------------------------------------------------------------------
-- Laws (QuickCheck'd in Properties.ChromaUnitGauge)
-- ---------------------------------------------------------------------------

-- | THE BRIDGE: multiplying chroma by the @q@-th @ℤ[i]@ unit (the algebra) equals the model's bit-exact
-- quarter-turn 'rotateQuarter' @q@ (the operation "SixFour.Spec.DetentNudge" @stepDelta@ consumes), for
-- EVERY chroma point and every @q@. So a Gaussian-unit multiply IS the model's chroma quarter-turn — the
-- typed consumer that makes the @ℤ[i]@ units load-bearing, not a rename. Teeth: 'lawNonUnitIsNotAQuarterTurn'
-- (only the norm-1 units land on a quarter-turn).
lawGaussianUnitActsAsQuarterTurn :: Int -> (Int, Int) -> Bool
lawGaussianUnitActsAsQuarterTurn q ab =
  unitQuarterTurn q ab == rotateQuarter q ab

-- | THE GROUP ISOMORPHISM @ℤ[i]* ≅ C4@: the @ℤ[i]@ unit multiply, index addition mod 4, and quarter-turn
-- COMPOSITION are the same group law. @units !! p · units !! q@ acts as @rotateQuarter (p+q)@, which is
-- 'rotateQuarter' @p@ then @q@ composed. So the Gaussian unit group is precisely the @C4@ chroma gauge —
-- four elements, cyclic, byte-exact. Teeth: a wrong index map would break composition on a generic chroma.
lawUnitGroupIsoQuarterTurn :: Int -> Int -> (Int, Int) -> Bool
lawUnitGroupIsoQuarterTurn p q ab =
     -- unit multiply ↔ index addition mod 4 (the group law transports)
     applyUnit (rmul (gaussianUnits !! (p `mod` 4)) (gaussianUnits !! (q `mod` 4))) ab
       == rotateQuarter (p + q) ab
     -- ...and that equals quarter-turn composition (rotate by q, then by p)
  && rotateQuarter (p + q) ab == rotateQuarter p (rotateQuarter q ab)

-- | THE CONSUMER TIE: the model's canonical-form dedup 'canonicalQuarter' (the gauge
-- "SixFour.Spec.ChromaRotation" @lawCanonicalChromaGaugeFixed@ rests on) is EXACTLY the orbit of a palette
-- under the @ℤ[i]@ unit-group action — the lexicographic maximum over the four unit images. So the chroma
-- gauge the model dedups by is the @ℤ[i]@ unit group, made concrete. Teeth: dropping a unit (a proper
-- subgroup) would change the orbit max on a generic palette, so all four units are needed.
lawCanonicalQuarterIsUnitOrbit :: [(Int, Int)] -> Bool
lawCanonicalQuarterIsUnitOrbit pal =
  canonicalQuarter pal == maximum [ map (unitQuarterTurn q) pal | q <- [0 .. 3] ]

-- | TEETH: a NON-unit Gaussian is NOT a quarter-turn. @1 + i@ has norm 2, so @rmul (1+i)@ SCALES the
-- chroma norm by 2 on any non-zero chroma — it cannot equal any 'rotateQuarter' @q@ (each preserves the
-- norm). This pins the correspondence to the norm-1 unit group: the @ℤ[i]@ UNITS specifically, not "some
-- multiply". Without it 'lawGaussianUnitActsAsQuarterTurn' could be read as a trivial existence claim.
lawNonUnitIsNotAQuarterTurn :: (Int, Int) -> Bool
lawNonUnitIsNotAQuarterTurn ab0 =
  let ab     = norm0 ab0
      onePi   = Gaussian (1, 1)                       -- 1 + i, a non-unit (norm 2)
      scaled  = applyUnit onePi ab
  in gaussNorm (packChroma scaled) == 2 * gaussNorm (packChroma ab)   -- norm doubled: it is a scale
     && all (\q -> scaled /= rotateQuarter q ab) [0 .. 3]              -- so it is no quarter-turn
  where
    -- force a non-zero chroma (else every map fixes the origin and the teeth would be vacuous)
    norm0 (a, b) = let a' = abs a `mod` 50 + 1; b' = abs b `mod` 50 in (a', b')
