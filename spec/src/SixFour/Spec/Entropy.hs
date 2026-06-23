{-# LANGUAGE ScopedTypeVariables #-}

{- |
Module      : SixFour.Spec.Entropy
Description : The capture's information analysis — RGBT pool weights + per-frame↔global scope cost.

Phase 0 of the cube-ladder workflow (@docs/SIXFOUR-CUBE-LADDER-GAP-ANALYSIS.md@ §7): the
measurement that replaces two taste calls with information. It is __pure composition__ of
already-proven primitives — no new math:

  * 'SixFour.Spec.Diversity.gaussianColorEntropy' — @½ln((2πe)³|Σ|)@, the differential entropy of
    a palette's Gaussian fit (and 'SixFour.Spec.Diversity.effectiveDim', the participation ratio).
  * 'SixFour.Spec.Diversity.weightedCovariance' / 'SixFour.Spec.Diversity.covTrace' — the per-axis
    variances the channel weights come from.
  * 'SixFour.Spec.Sinkhorn.sinkhornDivergence' — the discrete-OT cost of reconstructing one frame
    from another palette (the debiased Sinkhorn divergence).

== Q2 — the RGBT pool weights ('rgbtWeights')

The 64→16 temporal distill pools each RGBT quartet (4 frames → 1). HOW MUCH to weight each
information axis should follow how much each CARRIES. The four axes are the three OKLab colour
axes @L, a, b@ plus time @T@:

  * @σ²_L, σ²_a, σ²_b@ — the diagonal of the pooled-capture covariance (colour spread per axis).
  * @σ²_T@ — the temporal spread: the trace of the covariance of the 64 per-frame centroids
    (how much the scene's average colour moves over time).

The weight of an axis is the __softmax of its marginal differential entropy__
@h_i = ½ln(2πe σ²_i)@, which simplifies exactly to the __standard-deviation share__
@w_i = σ_i / Σ_j σ_j@ (since @softmax(½ln(2πe σ²)) ∝ σ@). So the weights are entropy-derived,
non-negative, and sum to 1 — a high-information axis is preserved more by the quartet pool.

== Q3 — the scope cost ('scopeCost', 'scopeVerdict')

The cost of shipping ONE global palette instead of 64 per-frame palettes is the information the
per-frame palettes hold that one global palette cannot. Measure it directly:

>  scopeCost(global, frames) = mean over frames of  S_ε(global, frame)

with @S_ε@ the Sinkhorn divergence (each frame and the global palette taken as uniform discrete
measures). Small ⇒ the global palette reconstructs every frame well (low inter-frame divergence)
⇒ ship __global__ (one 768-byte table, smaller file, identical look). Large ⇒ frames need their
own gamut ⇒ ship __per-frame__. 'scopeVerdict' applies the threshold 'defaultScopeTau' (the
perceptual / dither-noise floor — below it the loss is invisible, so the cheaper scope is free).

This module decides; it does not render. The shipped collapse stays the Q16 maximin in
"SixFour.Spec.Collapse"; the temporal pool it feeds is "SixFour.Spec.GroupRGBT" / the planned
@Spec.TemporalPool@.
-}
-- COMPARTMENT: MLX-MODEL | tag:MacTag | STRADDLER
module SixFour.Spec.Entropy
  ( -- * Q2 — RGBT pool weights
    RGBTWeights(..)
  , rgbtWeights
    -- * Q3 — per-frame ↔ global scope
  , Scope(..)
  , scopeCostWith
  , scopeCost
  , defaultScopeTau
  , scopeVerdict
    -- * Whole-capture report
  , EntropyReport(..)
  , analyzeCapture
    -- * Laws (predicates; QuickCheck'd in Properties.Entropy)
  , lawWeightsNonNegative
  , lawWeightsSumToOne
  , lawScopeCostNonNegative
  , lawScopeCostZeroOnIdenticalFrames
  , lawScopeVerdictThreshold
  ) where

import Data.List (foldl')

import SixFour.Spec.Color     (OKLab(..))
import SixFour.Spec.Diversity (weightedCovariance, covTrace, gaussianColorEntropy, effectiveDim)
import SixFour.Spec.Sinkhorn  (SinkhornParams, defaultSinkhornParams, sinkhornDivergence)

-- ============================================================================
-- Q2 — the RGBT pool weights
-- ============================================================================

-- | The four information-axis weights for the RGBT quartet pool: the three OKLab colour axes
-- @(wL, wa, wb)@ plus time @wT@. Non-negative and sum to 1 ('lawWeightsSumToOne').
data RGBTWeights = RGBTWeights
  { wL :: !Double
  , wA :: !Double
  , wB :: !Double
  , wT :: !Double
  } deriving (Eq, Show)

-- | Per-frame centroid (mean OKLab of a frame's palette). Origin for an empty frame.
frameMean :: [OKLab] -> OKLab
frameMean [] = OKLab 0 0 0
frameMean cs =
  let n              = fromIntegral (length cs) :: Double
      (sl, sa, sb)   = foldl' (\(l, a, b) (OKLab l' a' b') -> (l + l', a + a', b + b')) (0, 0, 0) cs
  in OKLab (sl / n) (sa / n) (sb / n)

-- | The RGBT pool weights of a capture (its list of per-frame palettes). Each axis weight is the
-- standard-deviation share @σ_i / Σ_j σ_j@ — the softmax of the per-axis marginal differential
-- entropy. Colour-axis variances come from the pooled covariance diagonal; the temporal variance
-- is the trace of the covariance of the per-frame centroids. A degenerate (zero-spread) capture
-- falls back to uniform @(¼,¼,¼,¼)@.
rgbtWeights :: [[OKLab]] -> RGBTWeights
rgbtWeights frames =
  let pooled            = concat frames
      (sll, _, _, saa, _, sbb) = weightedCovariance [ (c, 1) | c <- pooled ]
      centroids         = [ frameMean f | f <- frames, not (null f) ]
      sigT2             = covTrace (weightedCovariance [ (c, 1) | c <- centroids ])
      sds               = map (sqrt . max 0) [sll, saa, sbb, sigT2]
      z                 = sum sds
  in case sds of
       [dl, da, db, dt]
         | z > 0     -> RGBTWeights (dl / z) (da / z) (db / z) (dt / z)
       _             -> RGBTWeights 0.25 0.25 0.25 0.25

-- ============================================================================
-- Q3 — per-frame ↔ global scope
-- ============================================================================

-- | Which palette scope a tier should ship under.
data Scope = PerFrame | Global
  deriving (Eq, Show)

-- | Mean Sinkhorn divergence between a candidate global palette and each frame's palette (both as
-- uniform discrete measures), under the given Sinkhorn parameters. The information a single global
-- table fails to capture. Non-negative; zero when every frame already equals the global palette.
scopeCostWith :: SinkhornParams -> [OKLab] -> [[OKLab]] -> Double
scopeCostWith p global frames =
  let g     = [ (c, 1) | c <- global ]
      costs = [ sinkhornDivergence p g [ (c, 1) | c <- f ] | f <- frames, not (null f) ]
  in if null costs then 0 else sum costs / fromIntegral (length costs)

-- | 'scopeCostWith' at 'SixFour.Spec.Sinkhorn.defaultSinkhornParams'.
scopeCost :: [OKLab] -> [[OKLab]] -> Double
scopeCost = scopeCostWith defaultSinkhornParams

-- | The scope-cost threshold below which a global palette is "free" (its reconstruction loss is
-- below the perceptual / 8-bit-dither floor). Squared-OKLab units; a conservative default the
-- trainer/UX can tune. @1/255 ≈ 3.9e-3@ per channel ⇒ a squared budget around @5e-5@.
defaultScopeTau :: Double
defaultScopeTau = 5e-5

-- | Decide scope: 'Global' iff the scope cost is within the perceptual threshold, else 'PerFrame'.
scopeVerdict :: Double -> Double -> Scope
scopeVerdict tau cost = if cost <= tau then Global else PerFrame

-- ============================================================================
-- Whole-capture report
-- ============================================================================

-- | A capture's information summary: the joint colour entropy and effective dimensionality of the
-- pooled gamut, the RGBT pool weights, the scope cost, and the scope verdict at 'defaultScopeTau'.
data EntropyReport = EntropyReport
  { erColorEntropy :: !Double       -- ^ @½ln((2πe)³|Σ|)@ of the pooled capture.
  , erEffectiveDim :: !Double       -- ^ participation ratio ∈ [0,3] (live colour dimensions).
  , erWeights      :: !RGBTWeights  -- ^ the RGBT quartet-pool weights (Q2).
  , erScopeCost    :: !Double       -- ^ mean Sinkhorn fidelity, global vs frames (Q3).
  , erScope        :: !Scope        -- ^ 'scopeVerdict' at 'defaultScopeTau'.
  } deriving (Eq, Show)

-- | Analyse a capture: its per-frame palettes plus a candidate global palette (e.g. the maximin
-- 'SixFour.Spec.Collapse.farthestPointCollapse'). Produces the full 'EntropyReport'.
analyzeCapture :: [OKLab] -> [[OKLab]] -> EntropyReport
analyzeCapture global frames =
  let pooled = concat frames
      cost   = scopeCost global frames
  in EntropyReport
       { erColorEntropy = gaussianColorEntropy pooled [ 1 | _ <- pooled ]
       , erEffectiveDim = effectiveDim [ (c, 1) | c <- pooled ]
       , erWeights      = rgbtWeights frames
       , erScopeCost    = cost
       , erScope        = scopeVerdict defaultScopeTau cost
       }

-- ============================================================================
-- Laws (predicates; QuickCheck'd in Properties.Entropy)
-- ============================================================================

-- | Every RGBT weight is non-negative.
lawWeightsNonNegative :: [[OKLab]] -> Bool
lawWeightsNonNegative frames =
  let RGBTWeights l a b t = rgbtWeights frames
  in l >= 0 && a >= 0 && b >= 0 && t >= 0

-- | The RGBT weights sum to 1 (a probability distribution over the four axes).
lawWeightsSumToOne :: [[OKLab]] -> Bool
lawWeightsSumToOne frames =
  let RGBTWeights l a b t = rgbtWeights frames
  in abs (l + a + b + t - 1) < 1e-9

-- | The scope cost is non-negative (a mean of non-negative Sinkhorn divergences), within
-- finite-iteration slack.
lawScopeCostNonNegative :: [OKLab] -> [[OKLab]] -> Bool
lawScopeCostNonNegative global frames =
  null global || scopeCost global frames >= -1e-6

-- | The scope cost is EXACTLY zero when every frame's palette IS the global palette: each term is
-- a Sinkhorn self-divergence (exactly 0), so their mean is 0. The reachable floor.
lawScopeCostZeroOnIdenticalFrames :: [OKLab] -> Int -> Bool
lawScopeCostZeroOnIdenticalFrames global n =
  null global || n <= 0
    || scopeCost global (replicate n global) == 0

-- | 'scopeVerdict' respects its threshold: 'Global' exactly when @cost ≤ τ@.
lawScopeVerdictThreshold :: Double -> Double -> Bool
lawScopeVerdictThreshold tau cost =
  (scopeVerdict tau cost == Global) == (cost <= tau)
