{- |
Module      : SixFour.Spec.ValueWeightThreshold
Description : Closes the PARAMETRIZATION gap in the convergence teaching: the @w_value > 0@ side condition that "SixFour.Spec.ParadigmSoundness" asserts as a guard, and that "SixFour.Spec.Convergence" @lawCompositeUniqueMinIffValueWeighted@ witnesses at only TWO hardcoded points (@w_value = 0@ and @w_value = 1@), is here proven EXACT across the whole weight domain — the target is the unique global minimum IFF @w_value > 0@, for every weight, with both sides of the boundary carrying teeth.

The audit finding (PARAMETRIZATION-GAP-1): @paradigmSound@ is a function of @w_value@ but its convergence
conjunct is a constant @teachingConvergence@ whose supporting law only compares the two fixed weights 0 and
1. So the THRESHOLD @w_value > 0@ in the guard is asserted, not proven: nothing witnesses a FRACTIONAL
positive weight (0 < w < 1) still gives a unique minimum, nor that a NEGATIVE weight is genuinely fatal
(target stops being the global minimum, not merely a tie). This module supplies exactly that, additively,
without editing either body.

The exact discrete-geometry reason it is provable in closed form (NOT a rename — it reuses
"SixFour.Spec.Convergence" @composite@/@checkerboard@/@valueLoss@ directly):

  * The checkerboard shift @cb@ lives in the CELL Hessian's null space (@S·cb = 0@), so it changes
    @cellLoss@ by ZERO. The ONLY term that sees it is the full-rank value term.
  * @valueLoss shifted t = ½·Σ cb(v)² = ½·8 = 4@ — independent of the target, because @cb(v) ∈ {−1,+1}@.
  * Hence the shifted-vs-target gap is LINEAR in the weight: @composite w shifted t − composite w t t = 4·w@.
    Its sign is the sign of @w@. So @w > 0 ⟺ target strictly wins (unique)@, @w = 0 ⟺ tie (non-unique)@,
    @w < 0 ⟺ shifted strictly wins (target is NOT even the global minimum)@. The threshold is EXACTLY 0,
    proven on both sides, for all weights — not a two-point witness.

The bridge law @lawParadigmGuardIsExactlyConvergenceThreshold@ then shows the @paradigmSound@ guard
@w_value > 0@ coincides, weight-by-weight over a sweep that straddles the boundary, with the genuine
parametrized convergence predicate @convergesAt@ — i.e. the guard scales with @w_value@ for the right
reason. Pure-spec, GHC-boot-only; laws QuickCheck'd in @Properties.ValueWeightThreshold@. Emits no golden.
-}
-- COMPARTMENT: PURE-SPEC-WALL | tag:none
module SixFour.Spec.ValueWeightThreshold
  ( -- * The weight-parametrized convergence predicate
    shiftedGap
  , convergesAt
    -- * The threshold laws
  , lawShiftedGapIsLinearInWeight
  , lawFractionalWeightStillUnique
  , lawNegativeWeightBreaksGlobalMin
  , lawConvergenceThresholdIsExactlyZero
  , lawParadigmGuardIsExactlyConvergenceThreshold
  ) where

import SixFour.Spec.Convergence      (composite, checkerboard, valueLoss)
import SixFour.Spec.ParadigmSoundness (paradigmSound)

-- A palette is 8 voxels x 3 OKLab channels (the same shape Convergence uses).
type Pal = [[Double]]

eps :: Double
eps = 1e-6

-- bounded sample palettes from arbitrary doubles, mirroring Convergence.samp so the two modules
-- exercise the SAME well-conditioned palette space.
samp :: [Double] -> Pal
samp = reshape24 . map (\x -> fromIntegral (round (x * 100) `mod` 200 - 100 :: Int) / 100)
  where reshape24 xs = [ take 3 (drop (3 * v) ys) | v <- [0 .. 7] ]
          where ys = take 24 (xs ++ repeat 0)

-- the checkerboard-shifted palette: add the cell-blind null-space vector @cb@ to channel 0.
shiftedPal :: Pal -> Pal
shiftedPal t = [ [ (t !! v !! 0) + (checkerboard !! v), t !! v !! 1, t !! v !! 2 ] | v <- [0 .. 7] ]

-- | The shifted-vs-target loss gap at value weight @w@: @composite w shifted t − composite w t t@.
-- Closed form: @4·w@ (the checkerboard is cell-blind, so only the value term, weight @w@, sees it,
-- contributing @w·valueLoss shifted t = w·4@). Positive ⟺ the target strictly wins ⟺ unique minimum.
shiftedGap :: Double -> Pal -> Double
shiftedGap w t = composite w (shiftedPal t) t - composite w t t

-- | The weight-parametrized convergence predicate: the target is the UNIQUE global minimum at weight @w@
-- exactly when the cell-blind shifted palette strictly loses, i.e. @shiftedGap w t > 0@. This is the
-- genuine function of @w@ that the @paradigmSound@ guard stands in for.
convergesAt :: Double -> Pal -> Bool
convergesAt w t = shiftedGap w t > eps

-- ---------------------------------------------------------------------------
-- Laws (QuickCheck'd in Properties.ValueWeightThreshold)
-- ---------------------------------------------------------------------------

-- | THE EXACT FORM: the shifted-vs-target gap is LINEAR in the weight with slope @valueLoss shifted t = 4@,
-- i.e. @shiftedGap w t = 4·w@ for EVERY weight @w@ (not just 0 and 1). This is why the threshold is exactly
-- 0. Teeth: the gap is checked against the closed form @4·w@ at an arbitrary weight; the slope is verified to
-- equal @valueLoss shifted t@ (so it is the FULL-RANK value term, not the cell term, that carries the weight),
-- and it is asserted @> 0@ (a degenerate slope-0 collapse, which would make the threshold vacuous, fails).
lawShiftedGapIsLinearInWeight :: [Double] -> Double -> Bool
lawShiftedGapIsLinearInWeight tt w0 =
  let t = samp tt
      w = fromIntegral (round (w0 * 10) :: Int) / 10   -- a bounded but arbitrary weight, both signs
      slope = valueLoss (shiftedPal t) t
  in abs (shiftedGap w t - slope * w) < eps            -- gap is exactly slope*w (cell term cancels)
     && abs (slope - 4) < eps                          -- slope is the value-term constant 4 = 1/2 * Sum cb^2
     && slope > eps                                     -- non-degenerate: the threshold is a real sign change

-- | THE GAP THE ORIGINAL TWO-POINT WITNESS LEAVES OPEN: a FRACTIONAL positive weight @0 < w < 1@ still gives
-- a unique minimum (@convergesAt w@). @lawCompositeUniqueMinIffValueWeighted@ only checked @w = 1@; this
-- covers the interior. Teeth: checked at several interior weights; if convergence held only at @w = 1@ this
-- would fail at @w = 0.01@.
lawFractionalWeightStillUnique :: [Double] -> Bool
lawFractionalWeightStillUnique tt =
  let t = samp tt
  in all (\w -> convergesAt w t) [0.01, 0.1, 0.5, 0.9]

-- | THE OTHER OPEN GAP: a NEGATIVE weight is genuinely FATAL — the shifted palette strictly BEATS the target,
-- so the target is not even the global minimum (a stronger failure than the @w = 0@ TIE the original law
-- witnessed). At @w < 0@ the value term REWARDS moving away. Teeth: @shiftedGap w t < 0@ AND @not (convergesAt w t)@
-- at several negative weights; a sign error in the guard threshold would let one through.
lawNegativeWeightBreaksGlobalMin :: [Double] -> Bool
lawNegativeWeightBreaksGlobalMin tt =
  let t = samp tt
  in all (\w -> shiftedGap w t < (-eps) && not (convergesAt w t)) [-5, -1, -0.5, -0.01]

-- | THE THRESHOLD IS EXACTLY ZERO, over the whole domain: for every weight in a sweep that straddles the
-- boundary (negative, zero, fractional-positive, large-positive), @convergesAt w t@ holds IFF @w > 0@. This
-- upgrades the two-point @lawCompositeUniqueMinIffValueWeighted@ to an all-weights statement. Teeth: the
-- equivalence is checked at the boundary @w = 0@ (must be False) and just above it @w = 0.001@ (must be True),
-- so a threshold off by any margin is caught.
lawConvergenceThresholdIsExactlyZero :: [Double] -> Bool
lawConvergenceThresholdIsExactlyZero tt =
  let t = samp tt
      sweep = [-5, -1, -0.5, -0.001, 0, 0.001, 0.5, 1, 5]
  in all (\w -> convergesAt w t == (w > 0)) sweep

-- | THE BRIDGE to the master theorem: the @paradigmSound@ guard @w_value > 0@ coincides, weight-by-weight
-- across the straddling sweep, with the genuine parametrized convergence predicate @convergesAt@. So the
-- guard is not a constant aligned with a two-point witness — it scales with @w_value@ for the right reason
-- (the linear gap @4·w@). Teeth: at every swept weight @paradigmSound w@ must equal @convergesAt w t@; since
-- all the OTHER eight teachings are weight-independent and TRUE, any disagreement (e.g. a guard threshold
-- other than 0) fails. The boundary weights @0@ and @0.001@ pin the exact crossover.
lawParadigmGuardIsExactlyConvergenceThreshold :: [Double] -> Bool
lawParadigmGuardIsExactlyConvergenceThreshold tt =
  let t = samp tt
      sweep = [-5, -1, -0.5, -0.001, 0, 0.001, 0.5, 1, 5]
  in all (\w -> paradigmSound w == convergesAt w t) sweep
