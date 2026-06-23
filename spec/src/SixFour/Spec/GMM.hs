{- |
Module      : SixFour.Spec.GMM
Description : The continuous OKLab Gaussian-mixture substrate — the look-NN's input.

A frame palette is not 256 named-category buckets; it is a **256-component Gaussian
mixture** in OKLab — one component @(μ_k, Σ_k, w_k)@ per cluster, exactly the
@(mean, covariance, count)@ the device already computes in
@SixFour/Palette/ClusterStatistics.swift@. This module is the deterministic
substrate that replaces the lossy 88-float category code (the Berlin–Kay
@categorize@ layer): it pools the per-frame mixtures into one capture measure and
exposes the fixed-width per-component **token** the set-encoder consumes.

Why continuous, not categorical: OKLab is already perceptual (Euclidean distance ≈
perceptual difference, Ottosson 2020), so discretising it into 11 named bins discards
the very structure the collapse needs. The categories came from the colour-*naming*
literature (lexicon compression for communication, Zaslavsky 2018) — a different
problem from palette-collapse fidelity. See @spec/LOOK_NN.md@ §2 (redesigned).

The mixture's first two moments use the **law of total covariance**
@Σ = Σ wᵢ Σᵢ  (within)  +  Σ wᵢ (μᵢ−μ)(μᵢ−μ)ᵀ  (between)@; for point-mass components
(Σᵢ = 0) this reduces to 'SixFour.Spec.Diversity.weightedCovariance' — the
cross-check law in @Properties.GMM@.
-}
-- COMPARTMENT: METAL-GPU | tag:none | STRADDLER
module SixFour.Spec.GMM
  ( -- * The mixture
    Gaussian(..)
  , GMM
    -- * Tokens (the NN's per-component input)
  , gmmTokenDim
  , gaussianToken
  , gmmTokens
    -- * Construction
  , pointMass
  , pointMassGMM
  , normalizeGMM
  , poolGMM
    -- * Moments (permutation-invariant summaries)
  , totalWeight
  , mixtureMean
  , mixtureCovariance
  ) where

import Data.List (foldl')

import SixFour.Spec.Color     (OKLab(..))
import SixFour.Spec.Diversity (Cov3)

-- | One mixture component: an OKLab mean, a 3×3 OKLab covariance (the cluster's
-- spread, 'Cov3'), and a non-negative population weight.
data Gaussian = Gaussian
  { gMean   :: !OKLab
  , gCov    :: !Cov3
  , gWeight :: !Double
  } deriving (Eq, Show)

-- | A Gaussian mixture model — the continuous representation of a palette (or, after
-- pooling, of a whole capture). Order is irrelevant (a mixture is a multiset of
-- components); every exported summary is permutation-invariant.
type GMM = [Gaussian]

-- | Per-component token width fed to the set encoder: @μ(3) + Σ(6 upper-triangle) +
-- w(1) = 10@. (Replaces the old @categoryCodeDim = 88@.)
gmmTokenDim :: Int
gmmTokenDim = 10

-- | A component as its flat 10-float token @[μL,μa,μb, ΣLL,ΣLa,ΣLb,Σaa,Σab,Σbb, w]@.
gaussianToken :: Gaussian -> [Double]
gaussianToken (Gaussian (OKLab l a b) (sll, sla, slb, saa, sab, sbb) w) =
  [l, a, b, sll, sla, slb, saa, sab, sbb, w]

-- | The whole mixture as a token set (length @= |mixture|@, each row 'gmmTokenDim').
gmmTokens :: GMM -> [[Double]]
gmmTokens = map gaussianToken

zeroCov :: Cov3
zeroCov = (0, 0, 0, 0, 0, 0)

-- | A degenerate (zero-covariance) component — a point mass at @c@ with weight @w@.
-- Lifts a bare @(colour, weight)@ candidate into the mixture; real device input
-- carries the cluster covariance instead.
pointMass :: OKLab -> Double -> Gaussian
pointMass c w = Gaussian c zeroCov w

-- | Lift a bare weighted-candidate cloud to a point-mass mixture.
pointMassGMM :: [(OKLab, Double)] -> GMM
pointMassGMM = map (uncurry pointMass)

-- | Total component weight.
totalWeight :: GMM -> Double
totalWeight = sum . map gWeight

-- | Renormalise the weights to sum to 1 (no-op when total weight is non-positive).
normalizeGMM :: GMM -> GMM
normalizeGMM gm =
  let s = totalWeight gm
  in if s <= 0 then gm else [ g { gWeight = gWeight g / s } | g <- gm ]

-- | L1 Pool: merge the @T@ per-frame mixtures into one capture mixture and
-- renormalise. A mixture-of-mixtures with renormalised weights is again a mixture —
-- the pooled measure whose Wasserstein barycenter the look-NN collapses.
poolGMM :: [GMM] -> GMM
poolGMM = normalizeGMM . concat

-- | Mixture mean @μ = Σ pᵢ μᵢ@ (with @pᵢ = wᵢ / Σw@). Permutation-invariant.
mixtureMean :: GMM -> OKLab
mixtureMean gm =
  let s = totalWeight gm
  in if s <= 0
       then OKLab 0 0 0
       else
         let (al, aa, ab) =
               foldl' (\(xl, xa, xb) (Gaussian (OKLab l a b) _ w) ->
                         (xl + w * l, xa + w * a, xb + w * b)) (0, 0, 0) gm
         in OKLab (al / s) (aa / s) (ab / s)

-- | Mixture covariance by the **law of total covariance**: within-component spread
-- @Σ pᵢ Σᵢ@ plus between-component spread @Σ pᵢ (μᵢ−μ)(μᵢ−μ)ᵀ@. For point-mass
-- components this is the pure between term — equal to
-- 'SixFour.Spec.Diversity.weightedCovariance' (the @Properties.GMM@ cross-check).
mixtureCovariance :: GMM -> Cov3
mixtureCovariance gm =
  let s = totalWeight gm
  in if s <= 0
       then zeroCov
       else
         let OKLab ml ma mb = mixtureMean gm
             step (qll, qla, qlb, qaa, qab, qbb)
                  (Gaussian (OKLab l a b) (cll, cla, clb, caa, cab, cbb) w) =
               let p  = w / s
                   dl = l - ml; da = a - ma; db = b - mb
               in ( qll + p * (cll + dl * dl)
                  , qla + p * (cla + dl * da)
                  , qlb + p * (clb + dl * db)
                  , qaa + p * (caa + da * da)
                  , qab + p * (cab + da * db)
                  , qbb + p * (cbb + db * db) )
         in foldl' step zeroCov gm
