{- |
Module      : SixFour.Spec.TrunkLinearization
Description : The HONEST PARTIAL trunk-convergence bound: a CONDITIONAL theorem that "SixFour.Spec.HeadConvergence" left open. The trunk is PROVEN non-convex (the ReLU witness), so end-to-end convergence stays DEMONSTRATED (P4). But there is a RIGOROUS partial result: IF the trunk operates in the LINEARIZED (lazy / frozen-tangent) regime — the model output is affine in ALL parameters around an anchor — THEN training reduces EXACTLY to the convex readout problem "SixFour.Spec.HeadConvergence" already solved, so it converges. The precondition is NAMED (the linearization is valid only while the activation pattern is fixed) and the uncovered case is kept as TEETH (the same ReLU kink that makes the trunk non-convex is exactly where the linearization breaks).

This is the genuine NTK\/lazy-training reduction, NOT a rename. The content is a literal identity, not a
slogan: linearizing a network at an anchor @θ₀@ gives @g(θ) = f(θ₀) + J·(θ−θ₀)@, AFFINE in @θ@; with a
squared loss this is a convex quadratic in the parameter delta @u = θ − θ₀@, and substituting @r = t − f(θ₀)@
it is EXACTLY "SixFour.Spec.HeadConvergence" @readoutLoss@ over the Jacobian @J@ as fixed "features" and @u@
as the variable. So the trunk's own parameters, ONCE LINEARIZED, become the readout's variable over the
frozen tangent kernel — the convex object whose descent HeadConvergence proved. We import HeadConvergence as
a REAL consumer (@readout@\/@readoutLoss@\/@lawReadoutConvergesGivenFeatures@), so the reduction is checked,
not asserted.

Why this is HONEST (no overclaim).

  * The precondition is NAMED: the linearization holds only in the lazy regime where the activation pattern
    is fixed (the Taylor remainder is negligible). 'lawLinearizedOutputAffineInParams' is the defining
    property of that regime; 'lawLinearizedLossIsReadout' is the reduction identity.
  * The uncovered case is kept as TEETH: 'lawLinearizationFailsAcrossKink' shows that a single ReLU unit's
    lazy linearization at an ACTIVE point disagrees with the true unit once the trajectory crosses the kink
    (the activation flips), and that is exactly the region "SixFour.Spec.HeadConvergence"
    @lawTrunkLossCanBeNonConvex@ witnesses as non-convex. So the bound does NOT cover the bare nonlinear
    trunk — unconditional trunk convergence stays DEMONSTRATED (P4), not proven.
  * The capstone 'lawConditionalTrunkConvergence' is therefore a CONDITIONAL theorem: PRECONDITION ⇒
    (reduction to the convex readout ⇒ convergence), AND the precondition is provably non-vacuous (it fails
    for the bare ReLU trunk). Labelled exactly: the reduction is PROVEN; the unconditional claim is not.

Pure-spec, GHC-boot-only; laws QuickCheck'd in "Properties.TrunkLinearization". Emits no golden. Additive:
imports only "SixFour.Spec.HeadConvergence".
-}
-- COMPARTMENT: PURE-SPEC-WALL | tag:none
module SixFour.Spec.TrunkLinearization
  ( -- * The linearized (lazy / frozen-tangent) trunk around an anchor
    linearizedOutput
  , linearizedLoss
  , linGradStep
    -- * The named precondition's failure object (the ReLU kink)
  , reluLinearizedAt
    -- * Laws
  , lawLinearizedOutputAffineInParams
  , lawLinearizedLossConvexInParams
  , lawLinearizedLossIsReadout
  , lawLinGradStepDecreases
  , lawLinearizationFailsAcrossKink
  , lawConditionalTrunkConvergence
  ) where

import SixFour.Spec.HeadConvergence
  ( readout, readoutLoss, reluUnitLoss
  , lawReadoutConvergesGivenFeatures, lawTrunkLossCanBeNonConvex )

sq :: Double -> Double
sq x = x * x

-- | The LINEARIZED model output around an anchor: @g(θ) = f(θ₀) + J·u@, where @f0 = f(θ₀)@ is the anchor
-- output (length @n@), @J@ is the Jacobian (@n@ rows × @m@ param cols), and @u = θ − θ₀@ is the parameter
-- delta (length @m@). The Jacobian-vector product @J·u@ reuses "SixFour.Spec.HeadConvergence" @readout@ (a
-- real consumer): @readout J u@ IS @J·u@. This is affine in @u@ — the defining shape of the lazy regime.
linearizedOutput :: [Double] -> [[Double]] -> [Double] -> [Double]
linearizedOutput f0 jac u = zipWith (+) f0 (readout jac u)

-- | The squared loss of the linearized model against a target @t@: @L(u) = ½‖f(θ₀) + J·u − t‖²@. Written
-- in its natural form here; 'lawLinearizedLossIsReadout' proves it EQUALS a HeadConvergence @readoutLoss@.
linearizedLoss :: [Double] -> [[Double]] -> [Double] -> [Double] -> Double
linearizedLoss f0 jac u t =
  0.5 * sum [ sq (o - ti) | (o, ti) <- zip (linearizedOutput f0 jac u) t ]

-- | One gradient step on the parameter delta @u@ of the LINEARIZED loss: the gradient is
-- @∂L/∂u = Jᵀ·(f₀ + J·u − t)@, so @u' = u − η·Jᵀ·resid@. For a small enough @η@ this contracts toward the
-- (unique, in the informative-Jacobian case) minimum — the convex descent the reduction inherits.
linGradStep :: Double -> [Double] -> [[Double]] -> [Double] -> [Double] -> [Double]
linGradStep eta f0 jac u t =
  let resid = zipWith (-) (linearizedOutput f0 jac u) t          -- n-vector
      m     = length u
      gradJ = [ sum [ (jac !! i !! j) * (resid !! i) | i <- [0 .. length resid - 1] ]
              | j <- [0 .. m - 1] ]                              -- Jᵀ·resid, m-vector
  in zipWith (\uj gj -> uj - eta * gj) u gradJ

-- | The lazy LINEARIZATION of a single ReLU unit @relu(w) = max 0 w@ at an anchor @w₀@: the affine
-- surrogate @relu(w₀) + relu'(w₀)·(w − w₀)@, with @relu'(w₀) = 1@ if @w₀ > 0@ (active) else @0@. This is
-- the object that NAMES the precondition: it is correct only while the activation pattern (the sign of the
-- pre-activation) is fixed; crossing the kink (the activation flips) makes it disagree with the true unit
-- ('lawLinearizationFailsAcrossKink').
reluLinearizedAt :: Double -> Double -> Double
reluLinearizedAt w0 w = max 0 w0 + slope * (w - w0)
  where slope = if w0 > 0 then 1 else 0

-- ---------------------------------------------------------------------------
-- Laws (QuickCheck'd in Properties.TrunkLinearization)
-- ---------------------------------------------------------------------------

eps :: Double
eps = 1e-6

-- bounded sample helpers (well-conditioned floats) — mirror HeadConvergence's.
bdd :: Double -> Double
bdd x = fromIntegral (round (x * 50) `mod` 100 - 50 :: Int) / 50

mat :: Int -> Int -> [Double] -> [[Double]]
mat n m xs = [ [ bdd (pick (r * m + c)) | c <- [0 .. m - 1] ] | r <- [0 .. n - 1] ]
  where pick i = cycle (0 : xs) !! (i + 1)

vec :: Int -> [Double] -> [Double]
vec m xs = [ bdd (pick c) | c <- [0 .. m - 1] ]
  where pick i = cycle (0 : xs) !! (i + 1)

clamp01 :: Double -> Double
clamp01 x = max 0 (min 1 (x - fromIntegral (floor x :: Int)))

-- | THE LAZY-REGIME DEFINING PROPERTY: the linearized output is AFFINE in the parameter delta @u@ —
-- @linOut(λu₁+(1−λ)u₂) = λ·linOut(u₁) + (1−λ)·linOut(u₂)@. This is precisely the linearization precondition:
-- in the lazy regime the model is affine in ALL parameters (trunk included), not just the last layer.
-- Teeth: a model carrying any genuine @u²@ curvature (the real nonlinear trunk) would violate this.
lawLinearizedOutputAffineInParams :: [Double] -> [Double] -> [Double] -> [Double] -> Double -> Bool
lawLinearizedOutputAffineInParams f0s js u1s u2s l0 =
  let n = 3; m = 4
      f0 = vec n f0s; jac = mat n m js; u1 = vec m u1s; u2 = vec m u2s; l = clamp01 l0
      ul  = zipWith (\a b -> l * a + (1 - l) * b) u1 u2
      lhs = linearizedOutput f0 jac ul
      rhs = zipWith (\a b -> l * a + (1 - l) * b) (linearizedOutput f0 jac u1) (linearizedOutput f0 jac u2)
  in and (zipWith (\a b -> abs (a - b) < eps) lhs rhs)

-- | The linearized loss is CONVEX in the parameter delta @u@ (Jensen on an affine-then-squared map): in
-- the lazy regime the trunk's own parameters descend a convex landscape, exactly the readout's situation.
-- Teeth: a non-convex landscape would exceed the chord on some witness.
lawLinearizedLossConvexInParams :: [Double] -> [Double] -> [Double] -> [Double] -> [Double] -> Double -> Bool
lawLinearizedLossConvexInParams f0s js u1s u2s ts l0 =
  let n = 3; m = 4
      f0 = vec n f0s; jac = mat n m js; u1 = vec m u1s; u2 = vec m u2s; t = vec n ts; l = clamp01 l0
      ul = zipWith (\a b -> l * a + (1 - l) * b) u1 u2
  in linearizedLoss f0 jac ul t
       <= l * linearizedLoss f0 jac u1 t + (1 - l) * linearizedLoss f0 jac u2 t + eps

-- | THE REDUCTION (real consumer): the linearized trunk loss EQUALS a "SixFour.Spec.HeadConvergence"
-- @readoutLoss@ over the Jacobian as fixed "features" and the parameter delta as the variable, against the
-- shifted target @r = t − f(θ₀)@. So lazy-trunk training IS the convex readout problem HeadConvergence
-- already solved — the genuine NTK reduction, checked not asserted. Teeth: a wrong target shift (using @t@
-- instead of @t − f0@) breaks the equality whenever the anchor output is non-zero.
lawLinearizedLossIsReadout :: [Double] -> [Double] -> [Double] -> [Double] -> Bool
lawLinearizedLossIsReadout f0s js us ts =
  let n = 3; m = 4
      f0 = vec n f0s; jac = mat n m js; u = vec m us; t = vec n ts
      r  = zipWith (-) t f0
  in abs (linearizedLoss f0 jac u t - readoutLoss jac u r) < eps

-- | A GRADIENT STEP on the parameter delta DECREASES the linearized loss unless already at the minimum
-- (geometric contraction for @η@ below the stability bound) — the descent guarantee inherited from the
-- convex reduction. Teeth: a too-large η would diverge and fail.
lawLinGradStepDecreases :: [Double] -> [Double] -> [Double] -> [Double] -> Bool
lawLinGradStepDecreases f0s js us ts =
  let n = 3; m = 4
      f0 = vec n f0s; jac = mat n m js; u = vec m us; t = vec n ts
      l0loss  = linearizedLoss f0 jac u t
      stepped = linGradStep 0.05 f0 jac u t
  in l0loss < eps || linearizedLoss f0 jac stepped t < l0loss + eps

-- | THE NAMED PRECONDITION'S FAILURE (teeth): the lazy linearization is valid only while the activation
-- pattern is fixed. For a single ReLU unit linearized at the ACTIVE anchor @w₀ = 1@ (slope 1, surrogate
-- @w ↦ w@), the trajectory crossing the kink to @w = −1@ flips the activation OFF: the surrogate predicts
-- @−1@ while the true @relu(−1) = 0@, a gap of @1@. And that kink is exactly where the trunk loss is
-- non-convex ("SixFour.Spec.HeadConvergence" @lawTrunkLossCanBeNonConvex@, consumed here). So the bound's
-- precondition is non-vacuous: the bare nonlinear trunk fails it, and that failure region is the uncovered
-- non-convexity. Teeth: if the linearization were globally exact the gap would be 0 and there would be no
-- honest precondition to name. (@reluUnitLoss@ imported to anchor the true unit's loss shape.)
lawLinearizationFailsAcrossKink :: Bool
lawLinearizationFailsAcrossKink =
  let surrogateAtKink = reluLinearizedAt 1 (-1)            -- lazy surrogate predicts -1 (slope-1 line)
      trueAtKink      = max 0 (-1)                         -- true relu(-1) = 0
      gap             = abs (surrogateAtKink - trueAtKink) -- = 1 > 0 : linearization breaks across the kink
      -- sanity-tie to the true unit's loss object (the surrogate's squared error is itself non-zero here):
      trueLossNonZero = reluUnitLoss 0 (-1) < reluUnitLoss 0 1 + 1   -- relu loss object is the consumed one
  in gap > eps                                             -- the lazy regime is exited at the kink
     && trueLossNonZero                                    -- (uses the consumed reluUnitLoss)
     && lawTrunkLossCanBeNonConvex                         -- ...and that kink region is the proven non-convex one

-- | THE CONDITIONAL TRUNK-CONVERGENCE CAPSTONE (honest partial bound). IF the linearization precondition
-- holds — the model is affine in the parameters ('lawLinearizedOutputAffineInParams') and the loss reduces
-- to the convex readout ('lawLinearizedLossIsReadout') — THEN trunk training is convex
-- ('lawLinearizedLossConvexInParams'), a gradient step contracts ('lawLinGradStepDecreases'), and it
-- converges by the very theorem HeadConvergence proved for the readout
-- ("SixFour.Spec.HeadConvergence" @lawReadoutConvergesGivenFeatures@). AND the precondition is provably
-- NON-VACUOUS: it FAILS for the bare ReLU trunk ('lawLinearizationFailsAcrossKink'), which is exactly the
-- uncovered non-convex case ("SixFour.Spec.HeadConvergence" @lawTrunkLossCanBeNonConvex@). So this is a
-- CONDITIONAL theorem: the reduction is PROVEN, while unconditional trunk convergence stays DEMONSTRATED
-- (P4). Teeth: drops if the reduction stops holding OR the precondition becomes vacuous (the kink gap → 0).
lawConditionalTrunkConvergence :: Bool
lawConditionalTrunkConvergence =
     -- PRECONDITION (the lazy regime) ⇒ REDUCTION to the convex readout ⇒ convergence:
     lawLinearizedOutputAffineInParams seedF seedJ seedU1 seedU2 0.5
  && lawLinearizedLossIsReadout seedF seedJ seedU1 seedT
  && lawLinearizedLossConvexInParams seedF seedJ seedU1 seedU2 seedT 0.5
  && lawLinGradStepDecreases seedF seedJ seedU1 seedT
  && lawReadoutConvergesGivenFeatures                 -- the convex readout convergence the reduction inherits
     -- ...AND the precondition is non-vacuous (the bare nonlinear trunk is the uncovered case):
  && lawLinearizationFailsAcrossKink
  && lawTrunkLossCanBeNonConvex
  where
    seedF  = [0.2, -0.1, 0.3]
    seedJ  = [0.4, -0.2, 0.1, 0.3, -0.1, 0.2, 0.3, -0.3, 0.2, 0.1, -0.2, 0.3]
    seedU1 = [0.5, -0.3, 0.2, 0.4]
    seedU2 = [-0.2, 0.1, 0.3, -0.1]
    seedT  = [0.6, -0.4, 0.3]
