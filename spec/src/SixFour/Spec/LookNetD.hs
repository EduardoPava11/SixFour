{-# LANGUAGE FlexibleContexts    #-}
{-# LANGUAGE ScopedTypeVariables #-}

{- |
Module      : SixFour.Spec.LookNetD
Description : L5 tree decoder — per-level Haar heads, σ-block-diagonal weights, σ₇₆₈ output action.

The decoder turns the 64-D hidden context into 768 Haar coefficients (root +
255 σ-balanced offsets in OKLab), which "SixFour.Spec.PairTree.reconstruct"
then expands into the 256-OKLab palette.

== The output's σ-action: σ₇₆₈

Every Haar coefficient is an OKLab triple @(L, a, b)@. σ on each triple is
@(L,a,b) ↦ (L,−a,−b)@. So the σ-action on the flat 768-D output vector is the
fixed diagonal involution

>   σ₇₆₈ = diag(1, -1, -1, 1, -1, -1, …)   -- the triple (1, -1, -1) repeated 256 times.

This is 'PairTree.sigmaReflect' lifted point-wise to the 256-triple flat layout.

== The per-head weight mask: same block-diagonal forcing as L4

A decoder head @h_ℓ : ℝ^{64} → ℝ^{levelDof[ℓ]}@ is σ-equivariant iff
@h_ℓ · sigma64 = σ_out[ℓ] · h_ℓ@, which forces each weight @W[i,j]@ to be zero
whenever @sigma64Mask[j] ≠ sigma768Mask[i]@. Same algebraic constraint as L4
('SixFour.Spec.LookNetR.sigmaBlockDiagonalMask'), now lifted across heads of
different output sizes.

For one OKLab triple in the output: 1 achromatic dim takes from the 22
achromatic hidden dims (22 free weights); 2 chromatic dims each take from the
42 chromatic hidden dims (84 free weights). Per triple: 22 + 84 = 106 free, vs
the naive 3·64 = 192. Per the full 256 triples: 256·22 + 512·42 = 27136 free,
vs naive 768·64 = 49152. Pruning ratio @27136/49152 ≈ 0.552@ — the same ~45%
that the σ-equivariance constraint extracts in L4. ('symmetryPruningRatio'.)

== The reference baseline

'decoderReference' is the ZERO decoder: every output coefficient is 0. The
resulting 'HaarPalette' is the neutral grey palette (256 copies of (0,0,0)).
Trivially σ-equivariant (the zero map commutes with everything); a total
reference the trainer is a controlled deviation from. Same philosophy as
'SixFour.Spec.LookNetR.coreReferenceFull' and 'SixFour.Spec.LookNet.baselinePalette'.

== Why the per-level head structure matters

The 8 levels of 'PairTree.levelDof' are @[3, 6, 12, 24, 48, 96, 192, 384]@ —
geometrically doubling. Level 0 has 1 σ-pair (the coarsest split); level 7 has
128 σ-pairs (the finest detail). The decoder /could/ be one big 64 → 768 dense
matrix, but the per-level decomposition exposes the multiresolution structure
the Haar tree encodes — and lets the trainer apply a per-level weight schedule
(e.g. the φ golden-decay hypothesis from 'SixFour.Spec.PairTree.goldenDecay').
The spec pins the head sizes; the trainer specializes weights per level.
-}
module SixFour.Spec.LookNetD
  ( -- * Structural constants
    decoderOutputDim
  , rootDim
  , decoderLevelDims
  , numTriples
    -- * Output type
  , DecoderOutput(..)
  , toHaarPalette
  , decoderReference
    -- * σ₇₆₈ — the OKLab-triple-wise σ on the flat 768-D output
  , sigma768Mask
  , sigma768
    -- * Per-head pruning accounting
  , headFreeParams
  , decoderFreeParams
  , decoderNaiveParams
  , decoderPruningRatio
    -- * Laws
  , lawSigma768Involution
  , lawSigma768Orthogonal
  , lawSigma768MatchesPerTriple
  , lawDecoderRefIsZero
  , lawDecoderRefSigmaEquivariance
  , lawDecoderPruningArithmetic
  ) where

import qualified Data.Vector.Unboxed as U

import SixFour.Spec.Color    (OKLab(..))
import SixFour.Spec.PairTree (HaarPalette(..), degreesOfFreedom, levelDof, paletteDepth)
import SixFour.Spec.Tensor   (Tensor1(..), hiddenAchromaticDim, hiddenRedGreenDim, hiddenBlueYellowDim)
import SixFour.Spec.LookNetE (HiddenContext(..))

-- =============================================================================
-- Structural constants
-- =============================================================================

-- | The flat decoder output dim: 'degreesOfFreedom' = 768 (root + 255 offsets,
-- each as an OKLab triple).
decoderOutputDim :: Int
decoderOutputDim = degreesOfFreedom

-- | The root takes 3 dims (one OKLab triple). The remaining 765 dims are the
-- per-level offsets, summing to 'sum levelDof'.
rootDim :: Int
rootDim = 3

-- | One head per Haar level, output dim @3·2^(ℓ-1)@ for level @ℓ@. Plus the
-- root head (3 dims). Total: @3 + sum levelDof = 768@.
decoderLevelDims :: [Int]
decoderLevelDims = rootDim : levelDof   -- [3, 3, 6, 12, 24, 48, 96, 192, 384] = 9 heads

-- | Number of OKLab triples in the flat output: @decoderOutputDim / 3 = 256@.
-- (= 'PairTree.numLeaves'.)
numTriples :: Int
numTriples = decoderOutputDim `div` 3

-- =============================================================================
-- Output type
-- =============================================================================

-- | The decoder's raw flat output — 768 reals, /not/ yet a HaarPalette. The
-- 'toHaarPalette' destructor slices the flat vector into root + per-level
-- offset lists matching the well-formedness constraint of "SixFour.Spec.PairTree".
newtype DecoderOutput = DecoderOutput { unDecoderOutput :: Tensor1 768 Double }
  deriving (Eq, Show)

-- | Slice the 768-D flat output into a 'HaarPalette': first 3 reals = root
-- (one OKLab), then offsets for levels 0..(paletteDepth-1), each level taking
-- @3 · 2^level@ reals (1, 2, 4, …, 128 OKLab offsets respectively).
toHaarPalette :: DecoderOutput -> HaarPalette
toHaarPalette (DecoderOutput (Tensor1 v)) =
  let oklabAt off = OKLab (v U.! off) (v U.! (off + 1)) (v U.! (off + 2))
      rt          = oklabAt 0
      go lvlOffs (l : ls) =
        let n     = 2 ^ l
            offs  = [ oklabAt (lvlOffs + 3 * i) | i <- [0 .. n - 1] ]
            next  = lvlOffs + 3 * n
        in offs : go next ls
      go _ [] = []
  in HaarPalette rt (go 3 [0 .. paletteDepth - 1])

-- | The reference decoder: zero output, hence the neutral-grey HaarPalette
-- (root = (0,0,0), every offset = (0,0,0); 'reconstruct' yields 256 copies of (0,0,0)).
-- Total, σ-equivariant trivially (the zero map commutes with σ₇₆₈).
decoderReference :: HiddenContext -> DecoderOutput
decoderReference _ = DecoderOutput (Tensor1 (U.replicate 768 0.0))

-- =============================================================================
-- σ₇₆₈ — the OKLab-triple-wise σ on the flat decoder output
-- =============================================================================

-- | The σ-mask on the 768-D flat output. For each OKLab triple (L, a, b),
-- L is σ-fixed, (a, b) are σ-negated. So the mask repeats @[False, True, True]@
-- 256 times. Total length: 768.
sigma768Mask :: [Bool]
sigma768Mask = concat (replicate numTriples [False, True, True])

-- | σ on the flat decoder output: per-channel sign flip where 'sigma768Mask'
-- says True. Equivalent to applying 'PairTree.sigmaReflect' to each OKLab
-- triple in the flat layout. Fixed diagonal orthogonal involution.
sigma768 :: DecoderOutput -> DecoderOutput
sigma768 (DecoderOutput (Tensor1 v)) =
  let ms = U.fromList [ if b then (-1 :: Double) else 1 | b <- sigma768Mask ]
  in DecoderOutput (Tensor1 (U.zipWith (*) v ms))

-- =============================================================================
-- Pruning accounting
-- =============================================================================

-- | Free parameter count for a single decoder head of output dim @d@ (number
-- of OKLab triples = d/3). Each triple contributes 1 achromatic output dim
-- (22 free weights from the achromatic input block) + 2 chromatic output dims
-- (42 free weights each). Per triple: 22 + 84 = 106 free; per head:
-- @(d/3) · 106@.
--
-- Pre: @d `mod` 3 == 0@.
headFreeParams :: Int -> Int
headFreeParams d =
  let triples = d `div` 3
  in triples * (1 * hiddenAchromaticDim + 2 * chromaticDim)
  where
    chromaticDim = hiddenRedGreenDim + hiddenBlueYellowDim   -- 21 + 21 = 42

-- | Total free parameters across all decoder heads.
decoderFreeParams :: Int
decoderFreeParams = sum (map headFreeParams decoderLevelDims)

-- | Naive parameter count if no σ structure were enforced: @768 · 64@.
decoderNaiveParams :: Int
decoderNaiveParams = decoderOutputDim * (hiddenAchromaticDim + 2 * (hiddenRedGreenDim))   -- = 768 · 64

-- | Pruning ratio for the full decoder (free / naive).
decoderPruningRatio :: Double
decoderPruningRatio =
  fromIntegral decoderFreeParams / fromIntegral decoderNaiveParams

-- =============================================================================
-- Laws
-- =============================================================================

-- | σ₇₆₈ is an involution: @σ₇₆₈ ∘ σ₇₆₈ ≡ id@. Exact.
lawSigma768Involution :: DecoderOutput -> Bool
lawSigma768Involution o =
  let DecoderOutput (Tensor1 a) = sigma768 (sigma768 o)
      DecoderOutput (Tensor1 b) = o
  in U.length a == U.length b && U.and (U.zipWith (==) a b)

-- | σ₇₆₈ is orthogonal: preserves Euclidean norm.
lawSigma768Orthogonal :: DecoderOutput -> Bool
lawSigma768Orthogonal o =
  let normSq (DecoderOutput (Tensor1 v)) = U.sum (U.map (\x -> x * x) v)
  in normSq o == normSq (sigma768 o)

-- | σ₇₆₈ acts as per-triple OKLab σ: for every i in [0, 256), the i-th triple
-- of the σ₇₆₈-applied vector equals 'PairTree.sigmaReflect' of the i-th input triple.
lawSigma768MatchesPerTriple :: DecoderOutput -> Bool
lawSigma768MatchesPerTriple (DecoderOutput (Tensor1 v)) =
  let DecoderOutput (Tensor1 v') = sigma768 (DecoderOutput (Tensor1 v))
      triple  k = (v  U.! (3 * k), v  U.! (3 * k + 1), v  U.! (3 * k + 2))
      tripleF k = (v' U.! (3 * k), v' U.! (3 * k + 1), v' U.! (3 * k + 2))
      check k =
        let (l, a, b)    = triple  k
            (l', a', b') = tripleF k
        in l == l' && a' == negate a && b' == negate b
  in all check [0 .. numTriples - 1]

-- | The reference decoder is identically zero on every input.
lawDecoderRefIsZero :: HiddenContext -> Bool
lawDecoderRefIsZero x =
  let DecoderOutput (Tensor1 v) = decoderReference x
  in U.length v == 768 && U.all (== 0.0) v

-- | The reference decoder (= 0 map) is σ-equivariant: @0 ∘ σ = σ ∘ 0 = 0@.
-- Trivial (the zero map commutes with everything); pins the base case.
lawDecoderRefSigmaEquivariance :: HiddenContext -> Bool
lawDecoderRefSigmaEquivariance x =
  let DecoderOutput (Tensor1 a) = decoderReference x
      DecoderOutput (Tensor1 b) = sigma768 (decoderReference x)
  in U.length a == U.length b && U.and (U.zipWith (==) a b)

-- | The pruning arithmetic: total free params = 256 triples × 106 per triple =
-- 27136; naive = 768·64 = 49152; ratio = 27136/49152 ≈ 0.552. Pinned as a
-- snapshot so if any of the upstream dims drift, this fails.
lawDecoderPruningArithmetic :: Bool
lawDecoderPruningArithmetic =
     decoderOutputDim   == 768
  && numTriples         == 256
  && decoderFreeParams  == numTriples * 106   -- 27136
  && decoderNaiveParams == 768 * 64           -- 49152
  && decoderFreeParams  == 27136
  && decoderNaiveParams == 49152
  && abs (decoderPruningRatio - 27136 / 49152) < 1e-12
