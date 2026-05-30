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

  3. __'beautyLoss'__ — an /Ou-Luo-inspired/ heuristic summed over all 255
     σ-pairs in the Haar tree. Each pair @(parent + δ, parent − δ)@ contributes
     three terms (decomposed below). Lower = more harmonious. NOTE: the published
     Ou-Luo paper (Color Res. Appl., 2006) fits a regression model on 1431
     human-rated CIELAB pairs; the actual regression coefficients are paywalled
     and not reproduced here. The forms below are the qualitative claims
     (similar hue ↑ harmony; different lightness ↑ harmony; high combined
     lightness ↑ harmony) operationalised as the simplest monotone proxies
     for each. The trainer must FIT the per-term weights against either a real
     human-harmony validation set or a published Ou-Luo proxy.

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
    -- * PonderNet halting loss (the λ_ℓ regulariser the trainer optimises)
  , haltingDistribution
  , geometricPrior
  , defaultHaltLambdaP
  , haltingLoss
    -- * Helpers
  , haarPaletteAsPointMassGMM
    -- * Leaf-list cores (the port-facing surface — the MLX trainer mirrors these)
  , leavesAsPointMassGMM
  , fidelityLossLeaves
  , coverageLossLeaves
  , beautyLossLeaves
  , lookNetLossLeaves
  , sigmaPairLeaves'
    -- * Laws (predicates; QuickCheck'd in Properties.Loss)
  , lawFidelityNonNegative
  , lawCoverageBounded
  , lawBeautyMonotonicInChromaticSimilarity
  , lawBeautyMonotonicInLightnessSum
  , lawBeautyDecomposesOverPairs
  , lawLossWeightsSumPositive
  , lawFidelityLeavesAgreesWithHaar
  , lawBeautyLeavesAgreesWithPairs
  , lawHaltingDistributionSumsToOne
  , lawHaltingLossNonNegative
  , lawHaltingLossZeroAtPrior
  ) where

import           Data.List           (foldl')

import SixFour.Spec.Color    (OKLab(..))
import SixFour.Spec.GMM      (Gaussian(..), GMM, pointMassGMM, mixtureMean, mixtureCovariance)
import SixFour.Spec.Bures    (buresDistanceSq)
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

-- | A bare leaf list as a uniform-weight point-mass GMM — the leaf-list analogue
-- of 'haarPaletteAsPointMassGMM'. This is the port-facing form: the MLX/Swift
-- decoder emits a 256-leaf OKLab palette (via 'SixFour.Spec.LookNetD.reconstructSigmaPair'),
-- and the loss is computed on that list directly. No Haar-tree dependency, so a
-- port that has only the reconstructed leaves can mirror the loss byte-for-byte.
leavesAsPointMassGMM :: [OKLab] -> GMM
leavesAsPointMassGMM leaves =
  let n = max 1 (length leaves)
      w = 1.0 / fromIntegral n
  in pointMassGMM [ (c, w) | c <- leaves ]

-- | Fidelity loss on a bare leaf list against an already-pooled input GMM. The
-- leaf-list core 'fidelityLoss' delegates to. Both moment-match each mixture to
-- a single Gaussian and take the Bures-Wasserstein squared distance.
fidelityLossLeaves :: [OKLab] -> GMM -> Double
fidelityLossLeaves leaves inputGmm =
  let outputGmm = leavesAsPointMassGMM leaves
      g_in      = mixtureAsGaussian inputGmm
      g_out     = mixtureAsGaussian outputGmm
  in buresDistanceSq g_in g_out

-- | Coverage loss on a bare 256-leaf list: @1 − gamutCoverageFraction@. Mirrors
-- 'coverageLoss' but takes the reconstructed leaves directly.
coverageLossLeaves :: [OKLab] -> Double
coverageLossLeaves leaves =
  case mkPalette @256 leaves of
    Just pal -> 1.0 - gamutCoverageFraction [pal]
    Nothing  -> 1.0

-- | Beauty loss on a bare leaf list, enumerated over ADJACENT leaf pairs
-- @(leaves[2i], leaves[2i+1])@. On the σ-pair palette the decoder actually emits
-- (@[c0, σc0, c1, σc1, …]@, "SixFour.Spec.LookNetD.reconstructSigmaPair"), each
-- adjacent pair is exactly a σ-pair @(c, σc)@ — so this is the σ-pair beauty the
-- trainer optimises, and the form the MLX loss reproduces. Negated (minimise).
beautyLossLeaves :: [OKLab] -> Double
beautyLossLeaves leaves =
  negate (sum [ pairBeauty l r | (l, r) <- adjacentPairs leaves ])

-- | Adjacent-pair enumeration: @[(x0,x1),(x2,x3),…]@. A trailing odd element is
-- dropped (the decoder always emits an even count = 256).
adjacentPairs :: [OKLab] -> [(OKLab, OKLab)]
adjacentPairs (x : y : rest) = (x, y) : adjacentPairs rest
adjacentPairs _              = []

-- | The total look-NN loss on a bare leaf list + pre-pooled input GMM — the
-- port-facing total the MLX trainer minimises. Same weighted sum as 'lookNetLoss'
-- but over the leaf-list cores (no Haar tree). The golden vectors pin this form.
lookNetLossLeaves :: LossWeights -> [OKLab] -> GMM -> Double
lookNetLossLeaves (LossWeights wF wC wB) leaves inputGmm =
     wF * fidelityLossLeaves leaves inputGmm
   + wC * coverageLossLeaves leaves
   + wB * beautyLossLeaves   leaves

-- | The number of σ-pair palette leaves (= 256). Re-exported convenience so the
-- golden emitter and tests do not depend on "SixFour.Spec.SigmaPairHead" directly.
sigmaPairLeaves' :: Int
sigmaPairLeaves' = 256

-- | Reconstruction fidelity: how far the decoded palette's induced mixture is
-- from the input capture's pooled GMM, measured in Bures-Wasserstein squared
-- distance on the first two moments (mean + covariance).
--
-- The trainer minimises this; the floor (the best achievable reconstruction
-- without a learned decoder) is the 'farthestPointCollapse' baseline pinned
-- in 'SixFour.Spec.LookNet.baselinePalette'.
fidelityLoss :: HaarPalette -> CyclicStack t k -> Double
fidelityLoss hp stack = fidelityLossLeaves (reconstruct hp) (poolToGMM stack)

-- | Treat a mixture as a single Gaussian via its first two moments — the
-- 'mixtureMean' and 'mixtureCovariance' from "SixFour.Spec.GMM". The Bures
-- distance is exact on Gaussians; this approximation collapses each mixture
-- to its moment-matched Gaussian, so 'fidelityLoss' measures the Bures
-- distance between the moment-matched Gaussians — strictly weaker than the
-- true Wasserstein-2 between mixtures (which has no closed form in 3-D), but
-- structurally honest about both mean AND spread differences.
--
-- The trainer can replace this with a Sinkhorn approximation if tighter
-- bounds are needed; the spec pins the FUNCTIONAL CONTRACT (moment-matching),
-- not the specific approximation order.
mixtureAsGaussian :: GMM -> Gaussian
mixtureAsGaussian gmm =
  let m  = mixtureMean gmm
      c  = mixtureCovariance gmm
      w  = sum (map gWeight gmm)
  in Gaussian m c w

-- | Gamut-coverage loss: @1 − gamutCoverageFraction@ over the 16³ OKLab voxel
-- grid. Lower = fuller gamut spanning.
coverageLoss :: HaarPalette -> Double
coverageLoss = coverageLossLeaves . reconstruct

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
-- PonderNet halting loss
-- ============================================================================

-- The L4 core ('SixFour.Spec.LookNetR') produces a per-recursion-step σ-INVARIANT
-- halting scalar @λ_ℓ ∈ [0,1]@, one per Haar level. The forward pass computes
-- these (golden field @"halts"@) but nothing /trains/ them — the static unroll
-- runs all 'coreDepth' steps regardless. PonderNet (Banino et al., 2021) supplies
-- the missing training signal: turn the @λ_ℓ@ into a halting distribution and
-- regularise it towards a geometric prior, so the trainer learns to concentrate
-- compute on the coarse (signal) Haar levels and halt early on the fine (noise)
-- ones (the wavelet-truncation argument in "SixFour.Spec.LookNetR").

-- | The PonderNet halting distribution @p_n@ from the per-step halting scalars
-- @[λ_0, …, λ_{N-1}]@: @p_n = λ_n · ∏_{i<n}(1 − λ_i)@, with the LAST step forced
-- to absorb all remaining probability mass (@p_{N-1} = ∏_{i<N-1}(1 − λ_i)@) so
-- the distribution sums to exactly 1 over the static unroll's @N = coreDepth@
-- steps ('lawHaltingDistributionSumsToOne'). This is the standard PonderNet
-- "halt-or-continue" product, truncated at the hard-unroll depth.
haltingDistribution :: [Double] -> [Double]
haltingDistribution [] = []
haltingDistribution ls = go 1.0 ls
  where
    go remaining [_lastLambda]   = [remaining]          -- force the tail to absorb the rest
    go remaining (l : rest)      = (remaining * l) : go (remaining * (1 - l)) rest
    go _         []              = []

-- | The PonderNet geometric prior over @N@ steps with parameter @λ_p ∈ (0,1)@:
-- @g_n ∝ λ_p · (1 − λ_p)^n@, renormalised to sum to 1 over @n = 0..N-1@. A small
-- @λ_p@ favours pondering longer; a large @λ_p@ favours halting early.
geometricPrior :: Double -> Int -> [Double]
geometricPrior lambdaP n =
  let raw = [ lambdaP * (1 - lambdaP) ** fromIntegral k | k <- [0 .. n - 1] ]
      z   = sum raw
  in if z <= 0 then replicate n (1 / fromIntegral (max 1 n))
               else map (/ z) raw

-- | The spec-default geometric-prior parameter. @λ_p = 0.5@ centres the prior
-- mid-unroll (expected halt ≈ step 1 on the renormalised 8-step support) — a
-- neutral snapshot; the trainer tunes it. NOT meant for production training.
defaultHaltLambdaP :: Double
defaultHaltLambdaP = 0.5

-- | The PonderNet halting loss: the KL divergence @KL(p ‖ g)@ from the halting
-- distribution @p@ (from the @λ_ℓ@) to the geometric prior @g@ (parameter
-- 'defaultHaltLambdaP'). Non-negative ('lawHaltingLossNonNegative'); zero iff the
-- network halts exactly on the prior ('lawHaltingLossZeroAtPrior'). Terms with
-- @p_n = 0@ contribute 0 (the @0·log 0 = 0@ convention).
haltingLoss :: Double -> [Double] -> Double
haltingLoss lambdaP halts =
  let p = haltingDistribution halts
      g = geometricPrior lambdaP (length halts)
  in sum [ if pn <= 0 then 0 else pn * log (pn / gn) | (pn, gn) <- zip p g ]

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

-- | The leaf-list fidelity core agrees EXACTLY with the Haar-tree 'fidelityLoss':
-- both reconstruct the same leaves and compare the same moment-matched Gaussians.
-- This pins that the port-facing leaf form (what the MLX trainer + golden use) is
-- the same number as the original tree form — no drift between the two surfaces.
lawFidelityLeavesAgreesWithHaar :: HaarPalette -> CyclicStack t k -> Bool
lawFidelityLeavesAgreesWithHaar hp stack =
  fidelityLossLeaves (reconstruct hp) (poolToGMM stack) == fidelityLoss hp stack

-- | The leaf-list beauty core, enumerated over adjacent leaf pairs of a Haar
-- reconstruction, equals the Haar internal-node beauty: 'reconstruct' lays the
-- leaves out so that adjacent leaves @(2i, 2i+1)@ are exactly the children
-- @(parent+δ, parent−δ)@ of the deepest internal nodes — but the full Haar
-- 'beautyLoss' also sums the shallower internal nodes, so they are NOT equal in
-- general. What IS pinned: on the σ-pair palette every adjacent pair is a σ-pair,
-- so 'beautyLossLeaves' is well-defined and bounded by the per-pair beauty count.
lawBeautyLeavesAgreesWithPairs :: [OKLab] -> Bool
lawBeautyLeavesAgreesWithPairs leaves =
  let n      = length leaves
      direct = beautyLossLeaves leaves
      manual = negate (sum [ pairBeauty (leaves !! (2*i)) (leaves !! (2*i+1))
                           | i <- [0 .. n `div` 2 - 1] ])
  in direct == manual

-- | The halting distribution is a probability distribution: its terms sum to
-- exactly 1 over the static unroll (the tail step absorbs the remaining mass).
lawHaltingDistributionSumsToOne :: [Double] -> Bool
lawHaltingDistributionSumsToOne halts =
  let clamped = [ min 1 (max 0 l) | l <- halts ]
      p       = haltingDistribution clamped
  in null clamped || abs (sum p - 1) < 1e-9

-- | The KL halting loss is non-negative (Gibbs' inequality), for any clamped
-- @λ_ℓ@ list and any prior parameter @λ_p ∈ (0,1)@.
lawHaltingLossNonNegative :: Double -> [Double] -> Bool
lawHaltingLossNonNegative lambdaPRaw halts =
  let lambdaP = min 0.99 (max 0.01 lambdaPRaw)
      clamped = [ min 1 (max 0 l) | l <- halts ]
  in null clamped || haltingLoss lambdaP clamped >= -1e-9

-- | The KL halting loss is (numerically) zero when the network's halting
-- distribution IS the geometric prior. Constructs the @λ_ℓ@ that induce exactly
-- the prior (@λ_n = g_n / ∏_{i<n}(1 − λ_i)@) and checks @KL ≈ 0@.
lawHaltingLossZeroAtPrior :: Bool
lawHaltingLossZeroAtPrior =
  let n       = coreDepthLocal
      lambdaP = defaultHaltLambdaP
      g       = geometricPrior lambdaP n
      -- invert the product form: λ_n = g_n / remaining, remaining_{n+1} = remaining_n − g_n
      lambdas = inv 1.0 g
      inv _   []        = []
      inv rem' [_]      = [1.0]                     -- tail forced; value irrelevant
      inv rem' (gn:gs)  = (gn / rem') : inv (rem' - gn) gs
  in abs (haltingLoss lambdaP lambdas) < 1e-9
  where coreDepthLocal = 8
