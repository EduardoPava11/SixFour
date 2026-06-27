{- |
Module      : SixFour.Spec.VarianceFloorGuard
Description : The collapse guard for the full-matrix H-JEPA: a VICReg per-FACTOR variance hinge on the two comparison factors (the colour vector q and the space vector k of "SixFour.Spec.ChannelProduct"). Because the held-out target is data-manufactured (no EMA), the only collapse risk is the never-surfaced mid-latent going constant; this guard makes each factor carry variance across voxels or pays a penalty, so neither the colour nor the space factor can collapse to a point (which would make the cell-aggregate matrix degenerate again).

The hinge is @max(0, γ − √(var + ε))@ per factor (the std hinge, not the variance, so the gradient does
not vanish at collapse). The COMBINED guard penalizes a collapse in EITHER factor
('lawEitherCollapseTripsGuard'): a flat colour factor OR a flat space factor trips it, full variance in
both clears it. Tested AT THE BOUNDARY ('lawHingeAtBoundary': fires exactly when the std is below γ),
because capacity is not information. Pure-spec (Double, off the byte-exact path), emits no golden.
-}
-- COMPARTMENT: MLX-MODEL | tag:MacTag
module SixFour.Spec.VarianceFloorGuard
  ( factorVariance
  , varianceHinge
  , combinedGuard
  , lawFlatFactorPenalised
  , lawVariedFactorPasses
  , lawHingeAtBoundary
  , lawEitherCollapseTripsGuard
  ) where

-- | The population variance of a factor's per-voxel values across the cell.
factorVariance :: [Double] -> Double
factorVariance [] = 0
factorVariance xs =
  let n = fromIntegral (length xs)
      m = sum xs / n
  in sum [ (x - m) * (x - m) | x <- xs ] / n

-- | The VICReg STD hinge for one factor: @max(0, γ − √(var + ε))@. Penalizes a low-variance factor;
-- zero once the std clears γ. Std (not variance) so the gradient is non-vanishing at collapse.
varianceHinge :: Double -> [Double] -> Double
varianceHinge gamma xs = max 0 (gamma - sqrt (factorVariance xs + 1e-4))

-- | The combined guard over both comparison factors (colour q and space k): the sum of their hinges.
-- Zero iff BOTH carry variance; positive if either collapses.
combinedGuard :: [Double] -> [Double] -> Double
combinedGuard q k = varianceHinge 1.0 q + varianceHinge 1.0 k

-- ---------------------------------------------------------------------------
-- Laws
-- ---------------------------------------------------------------------------

-- | A FLAT (constant) factor trips the hinge: zero variance, std ~ 0, hinge ~ γ. Collapse is caught.
lawFlatFactorPenalised :: Bool
lawFlatFactorPenalised = varianceHinge 1.0 (replicate 8 5.0) > 0.5

-- | A high-variance factor PASSES (hinge ~ 0): once the std clears γ there is no penalty.
lawVariedFactorPasses :: Bool
lawVariedFactorPasses = varianceHinge 1.0 [0, 10, 0, 10, 0, 10, 0, 10] < 1e-9

-- | The hinge fires exactly at the BOUNDARY: a factor whose std is below γ is penalized, one above is
-- not. Teeth: a hinge keyed on variance (not std) or off by a square would mis-locate the boundary.
lawHingeAtBoundary :: Bool
lawHingeAtBoundary =
  let g = 2.0
  in varianceHinge g [0, 1, 0, 1, 0, 1, 0, 1] > 0      -- std 0.5 < 2: fires
     && varianceHinge g [0, 10, 0, 10, 0, 10, 0, 10] < 1e-9   -- std 5 > 2: clears

-- | THE guard: a collapse in EITHER factor trips it. Both factors varied: guard 0. Colour collapsed:
-- guard fires. Space collapsed: guard fires. So neither comparison factor can go constant.
lawEitherCollapseTripsGuard :: Bool
lawEitherCollapseTripsGuard =
  let varied = [0, 10, 0, 10, 0, 10, 0, 10]
      flat   = replicate 8 5.0
  in combinedGuard varied varied < 1e-9
     && combinedGuard flat varied > 0.5
     && combinedGuard varied flat > 0.5
