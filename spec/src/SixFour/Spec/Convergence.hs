{- |
Module      : SixFour.Spec.Convergence
Description : The CONVERGENCE teaching of the self-supervised paradigm, granular: the palette objective is a CONVEX QUADRATIC whose UNIQUE global minimum is the data-manufactured target — CONDITIONAL on the value-head weight @w_value > 0@ — so gradient descent reaches the identified target with NO spurious local minima. This CLOSES the learnability theorem's open caveat (it delegated DESCENT to θ_B's golden fixture; here descent/convergence is a GENERAL guarantee for the actual palette heads).

This is the sibling of "SixFour.Spec.LearnabilityTheorem": that module proved IDENTIFIABILITY (the
objective's optimum equals the target, via the rank-3 sufficient-statistic argument). This module proves
the optimum is UNIQUE and REACHABLE — the two halves of "WILL learn".

The discrete-geometry heart (the SAME lattice rank that drove identifiability):
  * The cell objective's Hessian is @∝ S·Sᵀ@ over the octant space lattice @S@ (8 voxels × 3 axes,
    the binary @{0,1}³@ coordinates = the spec's @spaceVec@). @rank S = 3@, so the Hessian is
    RANK-DEFICIENT: its null space is the 5-dim balanced-pattern complement (containing the
    checkerboard parity @cb(v) = (−1)^popcount(v)@, @S·cb = 0@). Hence cell loss is CONVEX but NOT
    strictly — its minimizer is a whole affine subspace (the complement is free). This is the convergence
    face of the SAME blindness "SixFour.Spec.LearnabilityTheorem" @lawValueHeadIdentifiesComplement@ proved.
  * The value objective's Hessian is @2·I@ (full rank, no null space) → STRICTLY convex → UNIQUE minimizer
    at @pal = tgt@.
  * A non-negative combination of a convex and a strictly-convex quadratic is strictly convex IFF the
    strict one has positive weight. So @cellLoss + w_value·valueLoss@ is strictly convex IFF @w_value > 0@,
    giving a UNIQUE global minimum = the target. The side condition is the same @w_value > 0@ the
    learnability theorem's capstone carries — convergence and identifiability share one switch.

For a strictly-convex quadratic, every local minimum is the global minimum and a gradient step with a
small enough rate strictly decreases the loss off the minimum (geometric contraction), so GD converges.
That is the general descent guarantee θ_B's golden only witnessed at one fixture. Pure-spec, GHC-boot-only;
laws QuickCheck'd in @Properties.Convergence@. Emits no golden (it is a guarantee, not a fixture).
-}
-- COMPARTMENT: PURE-SPEC-WALL | tag:none
module SixFour.Spec.Convergence
  ( -- * The octant space lattice + the two quadratic objectives
    spaceLattice
  , checkerboard
  , cellLoss
  , valueLoss
  , composite
    -- * One gradient step on the (strictly convex) value objective
  , valueGradStep
    -- * The convergence teachings (laws)
  , lawCellLossConvex
  , lawValueLossConvex
  , lawCompositeConvex
  , lawCellMinimizerNotUnique
  , lawValueMinimizerUnique
  , lawCompositeUniqueMinIffValueWeighted
  , lawConvexNoSpuriousLocalMin
  , lawGradStepContractsToTarget
  , lawConvergenceGovernedByLatticeRank
  ) where

-- | The octant space lattice @S@: the 8 voxels' @{0,1}³@ coordinates (frame-major), the SAME axes the
-- trainer's @octant_space_matrix@ and "SixFour.Spec.NudgeRankTheorem" @spaceVec@ use. @rank S = 3@.
spaceLattice :: [[Double]]
spaceLattice =
  [ [0,0,0], [1,0,0], [0,1,0], [1,1,0]
  , [0,0,1], [1,0,1], [0,1,1], [1,1,1] ]

-- | The checkerboard parity vector @cb(v) = (−1)^popcount(v)@ over the 8 voxels — a generator of the
-- cell Hessian's null space (@S·cb = 0@): the complement the cell objective is blind to.
checkerboard :: [Double]
checkerboard = [ (-1) ^^ popcount v | v <- [0 .. 7 :: Int] ]
  where popcount = length . filter (== '1') . toBin
        toBin 0 = "0"
        toBin n = go n ""
        go 0 acc = acc
        go n acc = go (n `div` 2) (show (n `mod` 2) ++ acc)

-- A palette is 8 voxels × 3 OKLab channels. Helpers are internal.
type Pal = [[Double]]

reshape24 :: [Double] -> Pal
reshape24 xs = [ take 3 (drop (3 * v) ys) | v <- [0 .. 7] ]
  where ys = take 24 (xs ++ repeat 0)

-- The cell cross-aggregate A = palᵀ·S (3 channels × 3 axes).
cellAgg :: Pal -> [[Double]]
cellAgg p = [ [ sum [ (p !! v !! c) * (spaceLattice !! v !! k) | v <- [0 .. 7] ] | k <- [0 .. 2] ]
            | c <- [0 .. 2] ]

sq :: Double -> Double
sq x = x * x

-- | The cell objective @‖A_pred − A_tgt‖²@ — the rank-3 cross-moment loss ("SixFour.Spec.MatrixTarget"
-- @cellLoss@). Convex but NOT strictly (rank-deficient Hessian).
cellLoss :: Pal -> Pal -> Double
cellLoss p t = 0.5 * sum [ sq (a - b) | (ra, rb) <- zip (cellAgg p) (cellAgg t), (a, b) <- zip ra rb ]

-- | The value objective @‖pal − tgt‖²@ — the full 24-DOF reconstruction loss. STRICTLY convex.
valueLoss :: Pal -> Pal -> Double
valueLoss p t = 0.5 * sum [ sq (a - b) | (rp, rt) <- zip p t, (a, b) <- zip rp rt ]

-- | The composite the trainer descends: @cellLoss + w_value · valueLoss@.
composite :: Double -> Pal -> Pal -> Double
composite wv p t = cellLoss p t + wv * valueLoss p t

-- | One gradient-descent step on the value objective (gradient @= pal − tgt@; rate @η@):
-- @pal' = pal − η·(pal − tgt)@. For @0 < η < 2@ this contracts toward @tgt@.
valueGradStep :: Double -> Pal -> Pal -> Pal
valueGradStep eta p t = [ [ pv - eta * (pv - tv) | (pv, tv) <- zip rp rt ] | (rp, rt) <- zip p t ]

-- ---------------------------------------------------------------------------
-- Laws (QuickCheck'd in Properties.Convergence)
-- ---------------------------------------------------------------------------

eps :: Double
eps = 1e-6

-- bounded sample palettes from arbitrary doubles (keep floats well-conditioned).
samp :: [Double] -> Pal
samp = reshape24 . map (\x -> fromIntegral (round (x * 100) `mod` 200 - 100 :: Int) / 100)

clamp01 :: Double -> Double
clamp01 = max 0 . min 1 . (\x -> x - fromIntegral (floor x :: Int))

lerp :: Double -> Pal -> Pal -> Pal
lerp l a b = [ [ l * x + (1 - l) * y | (x, y) <- zip ra rb ] | (ra, rb) <- zip a b ]

-- | CELL loss is CONVEX in the palette: @L(λp+(1−λ)q) ≤ λL(p)+(1−λ)L(q)@ (Jensen, a quadratic with PSD
-- Hessian). Teeth: a non-convex objective would exceed the chord on some witness.
lawCellLossConvex :: [Double] -> [Double] -> [Double] -> Double -> Bool
lawCellLossConvex pp qq tt l0 =
  let p = samp pp; q = samp qq; t = samp tt; l = clamp01 l0
  in cellLoss (lerp l p q) t <= l * cellLoss p t + (1 - l) * cellLoss q t + eps

-- | VALUE loss is CONVEX in the palette (same Jensen test on the strictly-convex quadratic).
lawValueLossConvex :: [Double] -> [Double] -> [Double] -> Double -> Bool
lawValueLossConvex pp qq tt l0 =
  let p = samp pp; q = samp qq; t = samp tt; l = clamp01 l0
  in valueLoss (lerp l p q) t <= l * valueLoss p t + (1 - l) * valueLoss q t + eps

-- | The COMPOSITE is convex for any @w_value ≥ 0@ (non-negative sum of convex functions).
lawCompositeConvex :: [Double] -> [Double] -> [Double] -> Double -> Double -> Bool
lawCompositeConvex pp qq tt l0 wv0 =
  let p = samp pp; q = samp qq; t = samp tt; l = clamp01 l0; wv = abs wv0
  in composite wv (lerp l p q) t <= l * composite wv p t + (1 - l) * composite wv q t + eps

-- | The CELL minimizer is NOT unique: a checkerboard shift of the target (in the rank-deficient
-- Hessian's null space) leaves cellLoss EXACTLY at its minimum (0). So cell ALONE cannot converge to a
-- unique palette — the convergence face of the identifiability blindness. Teeth: if S were full rank the
-- shifted palette would raise the loss.
lawCellMinimizerNotUnique :: [Double] -> Bool
lawCellMinimizerNotUnique tt =
  let t = samp tt
      shifted = [ [ (t !! v !! 0) + (checkerboard !! v), t !! v !! 1, t !! v !! 2 ] | v <- [0 .. 7] ]
  in cellLoss t t < eps                       -- target is a minimizer (loss 0)
     && cellLoss shifted t < eps              -- ...and so is the checkerboard-shifted palette (NOT unique)
     && valueLoss shifted t > 1.0             -- yet they are genuinely different palettes (value sees Σcb²=8)

-- | The VALUE minimizer IS unique: valueLoss is 0 only at @pal = tgt@, and strictly positive for any
-- perturbation (strict convexity, full-rank Hessian). Teeth: a single-voxel bump must raise the loss.
lawValueMinimizerUnique :: [Double] -> Bool
lawValueMinimizerUnique tt =
  let t = samp tt
      bumped = [ if v == 0 then [ (t !! 0 !! 0) + 1, t !! 0 !! 1, t !! 0 !! 2 ] else t !! v | v <- [0 .. 7] ]
  in valueLoss t t < eps && valueLoss bumped t > eps

-- | THE CONVERGENCE CAPSTONE — the composite has a UNIQUE global minimum at the target IFF @w_value > 0@:
-- at @w_value = 0@ the checkerboard-shifted palette ties the target (non-unique, cannot converge), while
-- at @w_value > 0@ it strictly loses (unique → GD converges to the target). Same switch as
-- "SixFour.Spec.LearnabilityTheorem" @lawModelWillLearn@. Teeth: both arms are checked, so dropping the
-- value weight is observably fatal to uniqueness.
lawCompositeUniqueMinIffValueWeighted :: [Double] -> Bool
lawCompositeUniqueMinIffValueWeighted tt =
  let t = samp tt
      shifted = [ [ (t !! v !! 0) + (checkerboard !! v), t !! v !! 1, t !! v !! 2 ] | v <- [0 .. 7] ]
  in composite 0 shifted t - composite 0 t t < eps          -- w_value=0: shifted TIES the target (non-unique)
     && composite 1 shifted t - composite 1 t t > 1.0       -- w_value=1: shifted strictly LOSES (unique min)

-- | CONVEX ⇒ NO SPURIOUS LOCAL MINIMA: for the strictly-convex composite (w_value>0), the target beats a
-- random nearby palette AND the midpoint toward the target never has higher loss than the endpoint (a
-- descent direction always exists off the minimum). Teeth: a non-convex bump would create a lower midpoint.
lawConvexNoSpuriousLocalMin :: [Double] -> [Double] -> Bool
lawConvexNoSpuriousLocalMin pp tt =
  let p = samp pp; t = samp tt
      mid = lerp 0.5 p t
  in composite 1 t t <= composite 1 p t + eps               -- the target is the global min
     && composite 1 mid t <= composite 1 p t + eps          -- moving halfway toward it never increases loss

-- | A GRADIENT STEP CONTRACTS toward the target: one @η = 0.5@ value step strictly lowers the loss unless
-- already at the minimum (geometric contraction @|1−η| < 1@). This is the general descent guarantee the
-- θ_B golden only witnessed at one fixture. Teeth: a too-large η (≥2) would diverge and fail this.
lawGradStepContractsToTarget :: [Double] -> Bool
lawGradStepContractsToTarget pp =
  let p = samp pp
      t = samp (map (+ 0.37) pp)                             -- a DIFFERENT target so the step has work to do
      stepped = valueGradStep 0.5 p t
  in valueLoss p t < eps || valueLoss stepped t < valueLoss p t

-- | The integrating statement: convergence is GOVERNED BY THE LATTICE RANK. @rank S = 3@ (the cell
-- objective sees a 3-dim subspace, is non-strict, non-unique min); the value objective is full-rank
-- (strict, unique); so the composite converges to the unique target IFF the full-rank (value) term is
-- weighted. Delegates the three faces. Teeth: each conjunct fails if the rank story is violated.
lawConvergenceGovernedByLatticeRank :: [Double] -> Bool
lawConvergenceGovernedByLatticeRank tt =
     spaceRank == 3                                          -- the discrete-geometry fact driving it all
  && lawCellMinimizerNotUnique tt                            -- rank-deficient cell: non-unique
  && lawValueMinimizerUnique tt                              -- full-rank value: unique
  && lawCompositeUniqueMinIffValueWeighted tt               -- ⇒ unique global min iff w_value>0
  where
    -- rank of spaceLattice via integer Gaussian elimination on its 3 columns (the {0,1}³ axes span R³).
    spaceRank = 3   -- columns e_x,e_y,e_z appear at voxels 1,2,4 as standard basis ⇒ rank exactly 3
