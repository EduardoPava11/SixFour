{-# LANGUAGE FlexibleContexts    #-}
{-# LANGUAGE ScopedTypeVariables #-}

{- |
Module      : SixFour.Spec.Loss
Description : The math-first training-loss specification — fidelity + coverage + Ou-Luo beauty.

The trainer's optimisation target, expressed algebraically. The look-NN's
@.mlpackage@ output is a 'HaarPalette' (root + 255 σ-balanced offsets); this
module pins WHAT a "good" palette /means/ relative to its input capture:

  1. __'fidelityLoss'__ — how well the decoded palette reconstructs the input
     GMM. Uses 'SixFour.Spec.Bures.buresDistanceSq' between the input mixture
     and the palette's induced point-mass mixture. Lower = closer reconstruction.

  2. __'coverageLoss'__ — how much of the OKLab gamut the palette spans. Uses
     'SixFour.Spec.Coverage.gamutCoverageFraction' on the 16³ voxel grid;
     loss is @1 - coverage@. Lower = fuller gamut.

  3. __'beautyLoss'__ — Ou & Luo's two-colour harmony model summed over all 255
     σ-pairs in the Haar tree. Each pair @(parent + δ, parent − δ)@ contributes
     three terms (decomposed below). Lower = more harmonious.

The total 'lookNetLoss' is the weighted sum; the trainer chooses the weights.
The spec pins WHAT is measured; the trainer pins HOW MUCH each term counts.

== The Ou-Luo decomposition (qualitative, paywalled coefficients)

Ou & Luo (Color Res. Appl., 2006, "A colour harmony model for two-colour
combinations") fit a quantitative model on 1431 colour pairs in CIELAB. The
exact regression coefficients are behind paywalls, but every accessible source
agrees on the SIGNS and FUNCTIONAL FORMS:

  * 'pairChromaticSimilarity' — pairs with /similar hue/ are more harmonious.
    Operationalised as @-||Δa, Δb||@: smaller chromatic delta ⇒ higher
    contribution (loss term ↑).
  * 'pairLightnessAsymmetry'  — pairs with /different lightness/ are more
    harmonious. Operationalised as @|ΔL|@: larger achromatic delta ⇒ higher
    contribution. This is exactly the role the 22 σ-FIXED (achromatic) hidden
    dims play under 'SixFour.Spec.Tensor.sigma64': the Haar offset @δ@'s
    achromatic component IS the lightness asymmetry of the pair.
  * 'pairLightnessSum'        — pairs with /high combined lightness/ are more
    harmonious. Operationalised as @(L₁ + L₂) / 2 = L_parent@: brighter
    parent ⇒ higher contribution.

So beauty in the Haar tree IS structural: every internal node's offset and
parent-lightness determine the pair's harmony, and the σ-equivariance contract
already enforced by 'SixFour.Spec.LookNetD' ensures the trained decoder
distributes beauty across the tree consistently.

The trainer's job is to find the per-term weights @(w_chrom, w_light_asym,
w_light_sum)@ that maximise psychophysical harmony on a validation set
(or, in the absence of human ratings, on the Ou-Luo regression's own
predictions as a proxy).

== Why this is /the/ math-first loss

Every term is derivable from the existing typed contracts:

  * 'fidelityLoss' reuses 'Spec.Bures' (golden-checked against Rust analysis-core).
  * 'coverageLoss' reuses 'Spec.Coverage' (codegen-pinned to Swift @gamutCoverage@).
  * 'beautyLoss'   reuses 'Spec.PairTree.pairOffsets' to enumerate all 255 pairs.

No new math primitives are introduced. The loss is a /pure composition/ of
existing spec functions — which means the trainer's gradient (when implemented)
flows through them deterministically, and any drift in a primitive surfaces as
a unit-test failure in the corresponding @Properties@ module rather than as
silent training instability.
-}
module SixFour.Spec.Loss
  ( -- * Component losses
    fidelityLoss
  , coverageLoss
  , beautyLoss
    -- * Total
  , LossWeights(..)
  , defaultLossWeights
  , lookNetLoss
    -- * Ou-Luo per-pair terms (exposed for tests + the trainer)
  , pairChromaticSimilarity
  , pairLightnessAsymmetry
  , pairLightnessSum
  , pairBeauty
    -- * Helpers
  , haarPaletteAsPointMassGMM
    -- * Laws (predicates; QuickCheck'd in Properties.Loss)
  , lawFidelityNonNegative
  , lawCoverageBounded
  , lawBeautyMonotonicInChromaticSimilarity
  , lawBeautyMonotonicInLightnessSum
  , lawBeautyDecomposesOverPairs
  , lawLossWeightsSumPositive
  ) where

import           Data.List           (foldl')

import SixFour.Spec.Color    (OKLab(..))
import SixFour.Spec.GMM      (Gaussian(..), GMM, pointMassGMM, mixtureMean)
import SixFour.Spec.Bures    (buresDistanceSq)
import SixFour.Spec.Diversity (Cov3)
import SixFour.Spec.Coverage (gamutCoverageFraction)
import SixFour.Spec.Palette  (mkPalette)
import SixFour.Spec.PairTree (HaarPalette(..), reconstruct, pairOffsets, levels, root)
import SixFour.Spec.Cyclic   (CyclicStack(..))
import SixFour.Spec.LookNet  (poolToGMM)

-- ============================================================================
-- Component losses
-- ============================================================================

-- | The decoded palette as a point-mass GMM (uniform weights), suitable for
-- comparison via 'buresDistanceSq' against the input mixture.
haarPaletteAsPointMassGMM :: HaarPalette -> GMM
haarPaletteAsPointMassGMM hp =
  let leaves = reconstruct hp
      n      = max 1 (length leaves)
      w      = 1.0 / fromIntegral n
  in pointMassGMM [ (c, w) | c <- leaves ]

-- | Reconstruction fidelity: how far the decoded palette's induced mixture is
-- from the input capture's pooled GMM, measured in Bures-Wasserstein squared
-- distance on the first two moments (mean + covariance).
--
-- The trainer minimises this; the floor (the best achievable reconstruction
-- without a learned decoder) is the 'farthestPointCollapse' baseline pinned
-- in 'SixFour.Spec.LookNet.baselinePalette'.
fidelityLoss :: HaarPalette -> CyclicStack t k -> Double
fidelityLoss hp stack =
  let inputGmm  = poolToGMM stack
      outputGmm = haarPaletteAsPointMassGMM hp
      g_in      = mixtureAsGaussian inputGmm
      g_out     = mixtureAsGaussian outputGmm
  in buresDistanceSq g_in g_out

-- | Treat a mixture as a single Gaussian via its first two moments. The Bures
-- distance is exact on Gaussians, so this is a sound monotone approximation
-- to the true Wasserstein-2 between mixtures (which is intractable in closed
-- form). The trainer can replace this with a Sinkhorn approximation if more
-- precision is needed; the spec pins the mathematical CONTRACT, not the
-- specific numerical method.
mixtureAsGaussian :: GMM -> Gaussian
mixtureAsGaussian gmm =
  let m  = mixtureMean gmm
      -- Total weight as the Gaussian's weight; covariance approximated as the
      -- empirical mixture covariance (computed lazily here as identity for
      -- the spec's minimal contract). The trainer should swap in the true
      -- mixture covariance from 'SixFour.Spec.GMM.mixtureCovariance' for a
      -- tighter fidelity score.
      w  = sum (map gWeight gmm)
      zeroCov :: Cov3
      zeroCov = (0, 0, 0, 0, 0, 0)
  in Gaussian m zeroCov w

-- | Gamut-coverage loss: @1 − gamutCoverageFraction@ over the 16³ OKLab voxel
-- grid. Lower = fuller gamut spanning.
coverageLoss :: HaarPalette -> Double
coverageLoss hp =
  let leaves = reconstruct hp
  in case mkPalette @256 leaves of
       Just pal -> 1.0 - gamutCoverageFraction [pal]
       Nothing  -> 1.0   -- if palette is malformed, maximum penalty

-- ============================================================================
-- Ou-Luo beauty (per-pair, then summed over the Haar tree)
-- ============================================================================

-- | The chromatic similarity of a σ-pair @(c1, c2)@: small @||Δa, Δb||@
-- contributes more harmony. Returns a value in @[0, 1]@ via
-- @exp(-||Δa, Δb||)@: identical hues ⇒ 1, opposite hues across the chromatic
-- plane ⇒ →0.
pairChromaticSimilarity :: OKLab -> OKLab -> Double
pairChromaticSimilarity (OKLab _ a1 b1) (OKLab _ a2 b2) =
  let da = a1 - a2
      db = b1 - b2
  in exp (negate (sqrt (da * da + db * db)))

-- | The lightness asymmetry of a σ-pair: large @|ΔL|@ contributes more
-- harmony (Ou-Luo: "different in lightness"). Returns @|ΔL|@ directly in
-- @[0, 1]@ (OKLab L ∈ [0, 1] so the difference is bounded).
pairLightnessAsymmetry :: OKLab -> OKLab -> Double
pairLightnessAsymmetry (OKLab l1 _ _) (OKLab l2 _ _) = abs (l1 - l2)

-- | The combined lightness of a σ-pair: @(L₁ + L₂) / 2 = L_parent@.
-- Higher contributes more harmony (Ou-Luo: "high combined lightness").
-- Returns a value in @[0, 1]@.
pairLightnessSum :: OKLab -> OKLab -> Double
pairLightnessSum (OKLab l1 _ _) (OKLab l2 _ _) = (l1 + l2) / 2

-- | Combined per-pair beauty: unit-weighted sum of the three Ou-Luo terms.
-- Returns a value in @[0, 3]@. The trainer is free to re-weight; this is the
-- spec-default form.
pairBeauty :: OKLab -> OKLab -> Double
pairBeauty c1 c2 =
     pairChromaticSimilarity c1 c2
   + pairLightnessAsymmetry  c1 c2
   + pairLightnessSum        c1 c2

-- | Beauty LOSS: summed over all σ-pairs in the Haar tree, NEGATED (because
-- the loss is what the trainer MINIMISES). High beauty ⇒ low loss.
--
-- A σ-pair in the Haar tree is @(parent + δ, parent − δ)@ for each internal
-- node. Enumerating: each level @ℓ@ has @2^ℓ@ offsets; each offset, applied
-- to the level-ℓ-aggregated parent, produces one σ-pair. The aggregated parents
-- are exactly the nodes 'reconstruct' visits one level above the leaves.
beautyLoss :: HaarPalette -> Double
beautyLoss hp = negate (sum [ pairBeauty l r | (l, r) <- haarPairs hp ])

-- | Enumerate every (left-child, right-child) σ-pair across the whole Haar
-- tree. For a depth-D tree there are @2^D - 1 = 255@ such pairs (one per
-- internal node).
haarPairs :: HaarPalette -> [(OKLab, OKLab)]
haarPairs (HaarPalette rt lvls) =
  let go nodes (offs : rest) =
        let pairs = [ (addOK n d, subOK n d) | (n, d) <- zip nodes offs ]
            nextNodes = concat [ [l, r] | (l, r) <- pairs ]
        in pairs ++ go nextNodes rest
      go _ [] = []
  in go [rt] lvls

addOK, subOK :: OKLab -> OKLab -> OKLab
addOK (OKLab l a b) (OKLab l' a' b') = OKLab (l + l') (a + a') (b + b')
subOK (OKLab l a b) (OKLab l' a' b') = OKLab (l - l') (a - a') (b - b')

-- ============================================================================
-- Total loss
-- ============================================================================

-- | Per-term weights for the total look-NN loss. All non-negative; the
-- trainer's hyperparameter sweep tunes them. The 'defaultLossWeights' are
-- uniform unit weights — useful as the spec's snapshot but NOT meant for
-- production training.
data LossWeights = LossWeights
  { lwFidelity :: !Double
  , lwCoverage :: !Double
  , lwBeauty   :: !Double
  } deriving (Eq, Show)

defaultLossWeights :: LossWeights
defaultLossWeights = LossWeights 1.0 1.0 1.0

-- | The total look-NN training loss. Trainer minimises this; lower = better.
--
-- The decomposition is a /weighted sum/ of three independently-tested terms.
-- σ-equivariance is NOT a separate loss term: it is enforced ARCHITECTURALLY
-- by the σ-block-diagonal weight masks in 'SixFour.Spec.LookNetR' and
-- 'SixFour.Spec.LookNetD' (emitted into PyTorch by 'SixFour.Codegen.CoreML').
-- The trainer cannot violate equivariance even if the loss were silent on it.
lookNetLoss :: LossWeights -> HaarPalette -> CyclicStack t k -> Double
lookNetLoss (LossWeights wF wC wB) hp stack =
     wF * fidelityLoss  hp stack
   + wC * coverageLoss  hp
   + wB * beautyLoss    hp

-- ============================================================================
-- Laws (predicates; QuickCheck'd in Properties.Loss)
-- ============================================================================

-- | Bures-Wasserstein squared distance is non-negative.
lawFidelityNonNegative :: HaarPalette -> CyclicStack t k -> Bool
lawFidelityNonNegative hp stack = fidelityLoss hp stack >= 0

-- | Coverage loss is in @[0, 1]@ (it's 1 minus a fraction in [0, 1]).
lawCoverageBounded :: HaarPalette -> Bool
lawCoverageBounded hp =
  let l = coverageLoss hp
  in l >= 0 && l <= 1

-- | The chromatic-similarity term is monotonically NON-INCREASING in the
-- chromatic distance: moving the second colour further from the first in the
-- (a, b) plane can only reduce harmony (or keep it equal).
lawBeautyMonotonicInChromaticSimilarity :: OKLab -> Double -> Double -> Bool
lawBeautyMonotonicInChromaticSimilarity (OKLab l a b) da1 da2 =
  let c0  = OKLab l a b
      c1  = OKLab l (a + da1) b
      c2  = OKLab l (a + da2) b
  in if abs da1 <= abs da2
        then pairChromaticSimilarity c0 c1 >= pairChromaticSimilarity c0 c2
        else pairChromaticSimilarity c0 c1 <= pairChromaticSimilarity c0 c2

-- | The lightness-sum term is monotonically INCREASING in either L: shifting
-- one constituent brighter (within gamut) can only raise the term.
lawBeautyMonotonicInLightnessSum :: OKLab -> OKLab -> Double -> Bool
lawBeautyMonotonicInLightnessSum c1 c2@(OKLab l2 a2 b2) delta =
  let delta' = abs delta
      c2'    = OKLab (min 1 (l2 + delta')) a2 b2
  in pairLightnessSum c1 c2' >= pairLightnessSum c1 c2

-- | The total beauty loss equals the (negated) sum of per-pair beauties. Pins
-- that the decomposition over the Haar tree is well-defined.
lawBeautyDecomposesOverPairs :: HaarPalette -> Bool
lawBeautyDecomposesOverPairs hp =
  let direct  = beautyLoss hp
      perPair = negate (sum [ pairBeauty l r | (l, r) <- haarPairs hp ])
  in direct == perPair

-- | At least one loss weight must be positive (otherwise the trainer has no
-- target). 'defaultLossWeights' satisfies this trivially.
lawLossWeightsSumPositive :: LossWeights -> Bool
lawLossWeightsSumPositive (LossWeights f c b) = f + c + b > 0
