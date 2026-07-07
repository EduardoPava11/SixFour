{- |
Module      : SixFour.Spec.LabTransition
Description : THE ONE-WAY VALVE — how LAB connects the color-time densities WITHOUT breaking them. The radiometric density accumulates and pools in LINEAR RGB (photons, where sums compose, "SixFour.Spec.ColorTime"); the gene / palette / look / user live in perceptual OKLab. The valve is the nonlinear conversion 'SixFour.Spec.Color.linearSRGBToOKLab' (cited, not rebuilt). This module pins the DISCIPLINE that keeps the two coherent: POOL ON THE RGB SIDE, LOOK ON THE LAB SIDE, and only the discrete/rational LINEAR hue group crosses the valve scale-equivariantly.

WHY POOL BEFORE THE VALVE. The valve is nonlinear, so it does NOT commute with pooling: for a strictly convex transfer (the OKLab-ish nonlinearity, Jensen), @mean(f xs) ≥ f(mean xs)@ with equality iff the window is constant ('lawValveNonlinearNeedsPoolFirst', the "SixFour.Spec.ColorTime" @lawLinearBeatsGamma@ re-stated as a valve law). Pooling in OKLab would integrate an ENCODED signal, not photons — the mid-gray trap. So color-time pooling stays radiometric and the conversion is applied AFTER, at the display/look boundary ("SixFour.Spec.RadiometricRealize").

WHAT CROSSES THE VALVE SCALE-EQUIVARIANTLY. The LINEAR hue group commutes with the linear pool, so it may be applied on EITHER side of the valve and agree: the S₃ RGB-axis permutation ('SixFour.Spec.OpponentDerivation' @swapRG@ / @cycleRGB@, = the Eisenstein-ω hue rotation on the A₂ plane) is pool-equivariant ('lawLinearHueCommutesWithPool') and preserves the DC/MASS @R+G+B@ ('lawS3PreservesMass', luma is the unique S₃-invariant) and the neutral axis ('lawGrayFixedByLinearHue'); the exact rational quarter-turn C₄ ('quarterTurn', the integer face of 'SixFour.Spec.ChromaRotation.rotateQuarter') likewise commutes ('lawQuarterTurnCommutesWithPool'). These are the discrete/rational elements — the same ones that make up the pool-equivariant part of the "SixFour.Spec.GeneDensity3D" hyperoctahedral @B₃ = (Z₂)³ ⋊ S₃@ (the @S₃@ quotient is exactly the hue that crosses).

THE LAYERING (exact valve + float look). Rational-angle hue (S₃ permutations, C₄ quarter-turns) is EXACT integer and pool-equivariant — the byte-exact valve. Arbitrary-angle OKLab rotation ('SixFour.Spec.ChromaRotation.rotateChroma') has irrational @cos/sin@, so it is FLOAT guidance applied POST-pool that must re-enter the Zig Q16 floor before GIF bytes (the two agree at the right angles, @ChromaRotation.lawFloatMatchesQuarterAtRightAngle@). 'lawLinearHueVsNonlinearValve' witnesses the split in one predicate: the linear op commutes with the pool, the nonlinear one strictly does not. Pure-spec, exact @Integer@/@Rational@; the Float valve itself lives in "SixFour.Spec.Color".
-}
-- COMPARTMENT: PURE-SPEC-WALL | tag:none
module SixFour.Spec.LabTransition
  ( -- * The linear-side pool and the exact hue that crosses the valve
    poolRGB
  , poolAB
  , quarterTurn
    -- * Laws — the valve discipline
  , lawS3PreservesMass
  , lawLinearHueCommutesWithPool
  , lawGrayFixedByLinearHue
  , lawQuarterTurnCommutesWithPool
  , lawValveNonlinearNeedsPoolFirst
  , lawLinearHueVsNonlinearValve
  ) where

import SixFour.Spec.OpponentDerivation (swapRG, cycleRGB, lumaOf)
import SixFour.Spec.ColorTime (meanOfSquares, squareOfMean)

-- | The LINEAR-side density pool: componentwise SUM of RGB pixels (the mass carrier — sums
-- compose only here). Pooling happens BEFORE the valve, never in OKLab.
poolRGB :: [(Integer, Integer, Integer)] -> (Integer, Integer, Integer)
poolRGB = foldr (\(r, g, b) (ar, ag, ab) -> (ar + r, ag + g, ab + b)) (0, 0, 0)

-- | The chroma-plane density pool (componentwise sum of @(a,b)@ pairs).
poolAB :: [(Integer, Integer)] -> (Integer, Integer)
poolAB = foldr (\(a, b) (aa, bb) -> (aa + a, bb + b)) (0, 0)

-- | The exact rational quarter-turn @(a,b) ↦ (−b, a)@ — the integer face of the C₄ that
-- 'SixFour.Spec.ChromaRotation.rotateQuarter' realizes in Q16. Rational, hence linear, hence
-- pool-equivariant.
quarterTurn :: (Integer, Integer) -> (Integer, Integer)
quarterTurn (a, b) = (negate b, a)

-- ─────────────────────────────────────────────────────────────────────────────
-- Laws
-- ─────────────────────────────────────────────────────────────────────────────

-- | The linear hue preserves the DC / MASS: @R+G+B@ (luma, the unique S₃-invariant) is fixed by
-- the S₃ RGB-axis permutations. The photon mass survives the hue op — it crosses the valve intact.
lawS3PreservesMass :: (Integer, Integer, Integer) -> Bool
lawS3PreservesMass p = lumaOf (swapRG p) == lumaOf p && lumaOf (cycleRGB p) == lumaOf p

-- | THE KEYSTONE: the linear hue (S₃ permutation) COMMUTES WITH POOLING — @pool ∘ map g = g ∘ pool@.
-- So S₃ may be applied on either side of the linear pool and agree: it crosses the valve
-- SCALE-EQUIVARIANTLY (the discrete hue the ladder can carry through 64/32/16).
lawLinearHueCommutesWithPool :: [(Integer, Integer, Integer)] -> Bool
lawLinearHueCommutesWithPool ps =
  poolRGB (map swapRG ps) == swapRG (poolRGB ps)
    && poolRGB (map cycleRGB ps) == cycleRGB (poolRGB ps)

-- | The neutral axis @R=G=B@ is fixed by the linear hue — gray crosses the valve unchanged (no
-- hue op can tint the DC).
lawGrayFixedByLinearHue :: Integer -> Bool
lawGrayFixedByLinearHue v = swapRG (v, v, v) == (v, v, v) && cycleRGB (v, v, v) == (v, v, v)

-- | The exact rational quarter-turn C₄ also commutes with pooling (linear in the @(a,b)@ plane) —
-- the other exact hue element that crosses the valve scale-equivariantly.
lawQuarterTurnCommutesWithPool :: [(Integer, Integer)] -> Bool
lawQuarterTurnCommutesWithPool ps = poolAB (map quarterTurn ps) == quarterTurn (poolAB ps)

-- | THE VALVE IS NONLINEAR ⇒ POOL FIRST: a strictly convex transfer (the OKLab-ish nonlinearity;
-- Jensen via "SixFour.Spec.ColorTime") does NOT commute with pooling — @mean(f xs) ≥ f(mean xs)@,
-- strict unless constant. So the density MUST be pooled on the LINEAR side, then converted; never
-- pooled in OKLab. (The gap is exactly the variance — the mid-gray trap.)
lawValveNonlinearNeedsPoolFirst :: [Rational] -> Bool
lawValveNonlinearNeedsPoolFirst xs = null xs || meanOfSquares xs >= squareOfMean xs

-- | THE LAYERING, witnessed in one predicate: on a non-constant window the LINEAR hue commutes
-- with the pool (crosses the valve, scale-equivariant) while the NONLINEAR valve strictly does not
-- (must be post-pool). This is "pool on RGB, look on LAB" made a theorem.
lawLinearHueVsNonlinearValve :: Bool
lawLinearHueVsNonlinearValve =
  poolRGB (map swapRG ps) == swapRG (poolRGB ps)   -- linear hue: commutes with the pool
    && meanOfSquares xs > squareOfMean xs           -- nonlinear valve: strictly does NOT
  where ps = [(1, 2, 3), (4, 5, 6)] :: [(Integer, Integer, Integer)]
        xs = [0, 1] :: [Rational]
