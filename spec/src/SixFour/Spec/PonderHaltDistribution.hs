{- |
Module      : SixFour.Spec.PonderHaltDistribution
Description : The STRONG PonderNet, proper: a real geometric HALTING DISTRIBUTION over refinement steps (Banino et al. PonderNet), Σ p_halt = 1, with the training objective the EXPECTED matrix-loss over the halt distribution and a KL pull toward a geometric prior. This is the adaptive-depth engine the user's "SixFour.Spec.CellNudge" budget biases: a higher per-region budget LOWERS the halt probability there (refine more passes), so the painted nudge and the halting are one mechanism.

'haltDist' turns per-step halt probabilities @λ_n@ into the proper distribution
@p_n = λ_n · Π_{j<n}(1 − λ_j)@ with the leftover mass halting at the last step, so it sums to ONE by
construction ('lawHaltIsProperDistribution'). 'expectedLoss' is the convex combination
@Σ p_n L_n@ (the differentiable PonderNet objective, 'lawExpectedLossIsConvex'). 'geometricPrior'
is the truncated-geometric prior the run is regularized toward ('lawGeometricPriorSumsToOne'), and
'klDivergence' is zero at the prior itself ('lawKLZeroAtSelf'). The nudge tie: lowering the halt
probabilities (more budget) moves mass to LATER steps, i.e. more refinement
('lawLowerHaltRefinesMore'). Pure-spec (Double, off the byte-exact path), emits no golden.
-}
-- COMPARTMENT: MLX-MODEL | tag:MacTag
module SixFour.Spec.PonderHaltDistribution
  ( haltDist
  , expectedLoss
  , geometricPrior
  , klDivergence
  , expectedSteps
  , lawHaltIsProperDistribution
  , lawExpectedLossIsConvex
  , lawGeometricPriorSumsToOne
  , lawKLZeroAtSelf
  , lawLowerHaltRefinesMore
  ) where

clamp01 :: Double -> Double
clamp01 = max 0 . min 1

-- | The halt distribution from per-step halt probabilities: @p_n = λ_n · Π_{j<n}(1 − λ_j)@, with the
-- leftover probability mass halting at the final step. Sums to 1 by construction.
haltDist :: [Double] -> [Double]
haltDist = go 1.0 . map clamp01
  where
    go remain []       = [remain]                 -- all remaining mass halts at the last step
    go remain (l : ls) = (remain * l) : go (remain * (1 - l)) ls

-- | The PonderNet objective: the EXPECTED loss over the halt distribution, @Σ p_n L_n@ (a convex
-- combination of the per-step losses). Losses are padded/truncated to the distribution length.
expectedLoss :: [Double] -> [Double] -> Double
expectedLoss dist losses = sum (zipWith (*) dist (losses ++ repeat 0))

-- | The expected number of refinement steps under the distribution, @Σ n · p_n@ (the compute the
-- halting actually spends). The nudge raises this where the user paints budget.
expectedSteps :: [Double] -> Double
expectedSteps dist = sum (zipWith (\n p -> fromIntegral n * p) [1 :: Int ..] dist)

-- | The truncated-geometric prior over @n@ steps with halt rate @λ_p@: @prior_n = λ_p (1−λ_p)^{n−1}@,
-- the leftover at the last step. The KL regularizer pulls the learned distribution toward this.
geometricPrior :: Double -> Int -> [Double]
geometricPrior lp n = haltDist (replicate (max 0 (n - 1)) (clamp01 lp))

-- | KL divergence @Σ p log (p/q)@ (nats), guarded against zeros. Zero iff @p == q@.
klDivergence :: [Double] -> [Double] -> Double
klDivergence ps qs =
  sum [ if p <= 0 then 0 else p * log (p / max 1e-12 q) | (p, q) <- zip ps qs ]

-- ---------------------------------------------------------------------------
-- Laws
-- ---------------------------------------------------------------------------

-- | The halt distribution is PROPER: it sums to 1 for any per-step halt probabilities. Teeth: a
-- design that forgot the leftover-mass final step would sum to < 1 (mass leaks).
lawHaltIsProperDistribution :: [Double] -> Bool
lawHaltIsProperDistribution ls = abs (sum (haltDist ls) - 1) < 1e-9

-- | The expected loss is a CONVEX combination: it lies between the min and max per-step loss (the
-- halting cannot do better than the best step or worse than the worst). Teeth: a non-distribution
-- weighting could exceed the range.
lawExpectedLossIsConvex :: [Double] -> [Double] -> Bool
lawExpectedLossIsConvex ls lossesRaw =
  let dist   = haltDist ls
      n      = length dist
      losses = take n (map (\x -> fromIntegral (abs (round x :: Int)) :: Double) lossesRaw ++ repeat 0)
      e      = expectedLoss dist losses
  in null losses || (e >= minimum losses - 1e-9 && e <= maximum losses + 1e-9)

-- | The geometric prior is itself a proper distribution (sums to 1).
lawGeometricPriorSumsToOne :: Double -> Int -> Bool
lawGeometricPriorSumsToOne lp n0 =
  let n = 1 + (abs n0 `mod` 32)
  in abs (sum (geometricPrior lp n) - 1) < 1e-9

-- | KL is zero at the prior itself: a distribution has zero divergence from a copy of itself. Teeth:
-- a sign error or a missing log would make KL non-zero on equal inputs.
lawKLZeroAtSelf :: Double -> Int -> Bool
lawKLZeroAtSelf lp n0 =
  let n = 1 + (abs n0 `mod` 32)
      p = geometricPrior lp n
  in abs (klDivergence p p) < 1e-9

-- | THE NUDGE TIE: lowering the halt probabilities (more painted budget) refines MORE, i.e. raises the
-- expected number of steps. A uniformly lower halt rate stochastically delays halting. Teeth: a
-- monotonicity bug (budget that halts SOONER) fails.
lawLowerHaltRefinesMore :: Bool
lawLowerHaltRefinesMore =
  let high = replicate 6 0.6      -- eager to halt (little budget)
      low  = replicate 6 0.2      -- reluctant to halt (more budget) -> deeper refinement
  in expectedSteps (haltDist low) > expectedSteps (haltDist high)
