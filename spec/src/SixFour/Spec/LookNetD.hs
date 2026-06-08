{-# LANGUAGE FlexibleContexts    #-}
{-# LANGUAGE ScopedTypeVariables #-}

{- |
Module      : SixFour.Spec.LookNetD
Description : L5 σ-pair tree decoder — per-level Haar heads, σ-block-diagonal weights, σ₃₈₄ output action.

The decoder turns the 64-D hidden context into the 384 'SixFour.Spec.SigmaPairHead.SigmaPairTree'
coefficients (root + 127 σ-balanced offsets in OKLab, a depth-7 binary Haar
pyramid generating 128 @c_i@ generators), which the L6 reconstruction step
('reconstructSigmaPair') then expands into the 256-OKLab σ-pair palette
@[c_0, σ(c_0), c_1, σ(c_1), …]@.

This is the SigmaPairHead pivot (NOTES 2026-05-28): the tensor measurement
(the now-retired @Quad4Fit@ experiment; see docs/SIXFOUR-BURES-DISCRETE-CORRECTION.md §0)
showed a free 768-coefficient Haar decoder fits
σ-symmetric palettes no better than random ones, so the decoder is reduced to
the 384-DOF σ-symmetric subspace exactly — the lowest Haar level is dropped
(depth 8 → depth 7) and the 256 leaves become 128 algebraically-paired
generators. See "SixFour.Spec.SigmaPairHead".

== The output's σ-action: σ₃₈₄

Every Haar coefficient is an OKLab triple @(L, a, b)@. σ on each triple is
@(L,a,b) ↦ (L,−a,−b)@. So the σ-action on the flat 384-D output vector is the
fixed diagonal involution

>   σ₃₈₄ = diag(1, -1, -1, 1, -1, -1, …)   -- the triple (1, -1, -1) repeated 128 times.

This is 'PairTree.sigmaReflect' lifted point-wise to the 128-triple flat layout.

== The per-head weight mask: same block-diagonal forcing as L4

A decoder head @h_ℓ : ℝ^{64} → ℝ^{levelDof[ℓ]}@ is σ-equivariant iff
@h_ℓ · sigma64 = σ_out[ℓ] · h_ℓ@, which forces each weight @W[i,j]@ to be zero
whenever @sigma64Mask[j] ≠ sigma768Mask[i]@. Same algebraic constraint as L4
('SixFour.Spec.LookNetR.sigmaBlockDiagonalMask'), now lifted across heads of
different output sizes.

For one OKLab triple in the output: 1 achromatic dim takes from the 22
achromatic hidden dims (22 free weights); 2 chromatic dims each take from the
42 chromatic hidden dims (84 free weights). Per triple: 22 + 84 = 106 free, vs
the naive 3·64 = 192. Per the 128 generator triples: 128·22 + 256·42 = 13568
free, vs naive 384·64 = 24576. Pruning ratio @13568/24576 ≈ 0.552@ — the same
~45% that the σ-equivariance constraint extracts in L4. ('decoderPruningRatio'.)

== The reference baseline

'decoderReference' is the ZERO decoder: every output coefficient is 0. The
resulting 'HaarPalette' is the neutral grey palette (256 copies of (0,0,0)).
Trivially σ-equivariant (the zero map commutes with everything); a total
reference the trainer is a controlled deviation from. Same philosophy as
'SixFour.Spec.LookNetR.coreReferenceFull' and 'SixFour.Spec.LookNet.baselinePalette'.

== Why the per-level head structure matters

The 7 generator levels are @[3, 6, 12, 24, 48, 96, 192]@ — geometrically
doubling. Level 0 has 1 generator (the coarsest split); level 6 has 64
generators (the finest detail), so the depth-7 pyramid emits 128 @c_i@
generators in total. The decoder /could/ be one big 64 → 384 dense matrix, but
the per-level decomposition exposes the multiresolution structure the Haar tree
encodes — and lets the trainer apply a per-level weight schedule (e.g. the φ
golden-decay hypothesis from 'SixFour.Spec.PairTree.goldenDecay'). The spec
pins the head sizes; the trainer specializes weights per level.
-}
module SixFour.Spec.LookNetD
  ( -- * Structural constants
    decoderOutputDim
  , rootDim
  , decoderLevelDims
  , numTriples
  , decoderTreeDepth
    -- * Output type
  , DecoderOutput(..)
  , toHaarPalette
  , flattenHaar
  , reconstructSigmaPair
  , decoderReference
  , decoderFromRecursion
    -- * σ₃₈₄ — the OKLab-triple-wise σ on the flat 384-D output
  , sigmaDecoderMask
  , sigmaDecoder
    -- * Per-head pruning accounting
  , headFreeParams
  , decoderFreeParams
  , decoderNaiveParams
  , decoderPruningRatio
    -- * Laws
  , lawSigmaDecoderInvolution
  , lawSigmaDecoderOrthogonal
  , lawSigmaDecoderMatchesPerTriple
  , lawDecoderRefIsZero
  , lawDecoderRefSigmaEquivariance
  , lawDecoderPruningArithmetic
  , lawHaarFlattenRoundTrip
  , lawDecoderFromRecursionMatchesZero
  , lawReconstructSigmaPairLeaves
  ) where

import qualified Data.Vector.Unboxed as U

import SixFour.Spec.Color    (OKLab(..))
import SixFour.Spec.PairTree (HaarPalette(..), wellFormed)
import SixFour.Spec.SigmaPairHead
  ( SigmaPairTree(..), reconstructPaired
  , sigmaPairDepth, sigmaPairDegreesOfFreedom, sigmaPairLeaves )
import SixFour.Spec.Tensor   (Tensor1(..), hiddenAchromaticDim, hiddenRedGreenDim, hiddenBlueYellowDim)
import SixFour.Spec.LookNetE (HiddenContext(..))
import SixFour.Spec.LookNetR (SharedBlock, runRecursion, sharedReferenceBlock)

-- =============================================================================
-- Structural constants
-- =============================================================================

-- | The flat decoder output dim: 'sigmaPairDegreesOfFreedom' = 384 (root + 127
-- offsets, each as an OKLab triple) — the σ-symmetric subspace dimension.
decoderOutputDim :: Int
decoderOutputDim = sigmaPairDegreesOfFreedom

-- | The root takes 3 dims (one OKLab triple). The remaining 381 dims are the
-- per-level offsets of the depth-7 generator pyramid.
rootDim :: Int
rootDim = 3

-- | Depth of the underlying generator Haar tree (= 'sigmaPairDepth' = 7).
decoderTreeDepth :: Int
decoderTreeDepth = sigmaPairDepth

-- | One head per generator Haar level, output dim @3·2^(ℓ-1)@ for level @ℓ@.
-- Plus the root head (3 dims). Total: @3 + 3·(1+2+…+64) = 3·128 = 384@.
decoderLevelDims :: [Int]
decoderLevelDims = rootDim : [ 3 * 2 ^ (l - 1) | l <- [1 .. decoderTreeDepth] ]
                   -- [3, 3, 6, 12, 24, 48, 96, 192] = 8 heads

-- | Number of OKLab generator triples in the flat output:
-- @decoderOutputDim / 3 = 128@ (the @c_i@; the 256-leaf palette is their
-- σ-pair interleave, see 'reconstructSigmaPair').
numTriples :: Int
numTriples = decoderOutputDim `div` 3

-- =============================================================================
-- Output type
-- =============================================================================

-- | The decoder's raw flat output — 384 reals, /not/ yet a SigmaPairTree. The
-- 'toHaarPalette' destructor slices the flat vector into a depth-7 generator
-- 'HaarPalette' (the @c_i@); 'reconstructSigmaPair' then σ-pair-interleaves it
-- into the 256-leaf palette.
newtype DecoderOutput = DecoderOutput { unDecoderOutput :: Tensor1 384 Double }
  deriving (Eq, Show)

-- | Slice the 384-D flat output into the depth-7 generator 'HaarPalette': first
-- 3 reals = root (one OKLab), then offsets for levels 0..('decoderTreeDepth'-1),
-- each level taking @3 · 2^level@ reals (1, 2, 4, …, 64 OKLab offsets).
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
  in HaarPalette rt (go 3 [0 .. decoderTreeDepth - 1])

-- | L6 reconstruction: the depth-7 'SigmaPairTree' generator pyramid expands
-- into the 256-leaf σ-pair palette @[c_0, σ(c_0), c_1, σ(c_1), …]@ via
-- 'SixFour.Spec.SigmaPairHead.reconstructPaired'. This is the deterministic
-- decoder→palette step (Pipeline L6); its image lies in the σ-symmetric
-- eigenspace by construction.
reconstructSigmaPair :: DecoderOutput -> [OKLab]
reconstructSigmaPair = reconstructPaired . SigmaPairTree . toHaarPalette

-- | The reference decoder: zero output, hence the neutral-grey SigmaPairTree
-- (root = (0,0,0), every offset = (0,0,0); 'reconstructSigmaPair' yields 256
-- copies of (0,0,0)). Total, σ-equivariant trivially (the zero map commutes
-- with σ₃₈₄).
decoderReference :: HiddenContext -> DecoderOutput
decoderReference _ = DecoderOutput (Tensor1 (U.replicate 384 0.0))

-- | The exact left-inverse of 'toHaarPalette': flatten a depth-7 generator
-- 'HaarPalette' (root + per-level offsets, top-down) into the 384-D flat
-- layout. Order: root triple, then level 0's 1 offset, level 1's 2 offsets, …
-- level 6's 64 offsets — each as @[L, a, b]@. For a well-formed
-- depth-'decoderTreeDepth' palette this is the byte-exact inverse of
-- 'toHaarPalette' ('lawHaarFlattenRoundTrip').
flattenHaar :: HaarPalette -> DecoderOutput
flattenHaar (HaarPalette rt lvls) =
  let triple (OKLab l a b) = [l, a, b]
      flat = concatMap triple (rt : concat lvls)
  in DecoderOutput (Tensor1 (U.fromList flat))

-- | The decoder expressed as the Mixture-of-Recursions over the Haar tree
-- ("SixFour.Spec.LookNetR".'runRecursion'): the root reads the initial context,
-- and Haar level @ℓ@ reads the context after @ℓ+1@ shared-block refinements, so
-- deeper recursion feeds finer detail. The /reference/ shared block emits zeros
-- (identity refine, zero offsets), so this equals 'decoderReference' on every
-- input ('lawDecoderFromRecursionMatchesZero'); the trained decoder supplies
-- σ-block-diagonal per-level heads. Output byte-layout is identical to
-- 'decoderReference' (via 'flattenHaar' / 'toHaarPalette' order).
decoderFromRecursion :: SharedBlock -> HiddenContext -> DecoderOutput
decoderFromRecursion blk ctx0 =
  let contexts = runRecursion blk ctx0                 -- length coreDepth + 1 (>= decoderTreeDepth+1)
      rt       = referenceRoot (head contexts)
      lvls     = [ referenceLevelEmit l (contexts !! (l + 1))
                 | l <- [0 .. decoderTreeDepth - 1] ]
  in flattenHaar (HaarPalette rt lvls)
  where
    -- Reference emission heads: the zero map. The trained decoder replaces these
    -- with σ-block-diagonal Linear heads (one per level, per the per-head pruning
    -- accounting below); the spec pins the structure, not the weights.
    referenceRoot :: HiddenContext -> OKLab
    referenceRoot _ = OKLab 0 0 0
    referenceLevelEmit :: Int -> HiddenContext -> [OKLab]
    referenceLevelEmit lvl _ = replicate (2 ^ lvl) (OKLab 0 0 0)

-- =============================================================================
-- σ₃₈₄ — the OKLab-triple-wise σ on the flat decoder output
-- =============================================================================

-- | The σ-mask on the 384-D flat output. For each OKLab triple (L, a, b),
-- L is σ-fixed, (a, b) are σ-negated. So the mask repeats @[False, True, True]@
-- 128 times. Total length: 384.
sigmaDecoderMask :: [Bool]
sigmaDecoderMask = concat (replicate numTriples [False, True, True])

-- | σ on the flat decoder output: per-channel sign flip where 'sigmaDecoderMask'
-- says True. Equivalent to applying 'PairTree.sigmaReflect' to each OKLab
-- triple in the flat layout. Fixed diagonal orthogonal involution.
sigmaDecoder :: DecoderOutput -> DecoderOutput
sigmaDecoder (DecoderOutput (Tensor1 v)) =
  let ms = U.fromList [ if b then (-1 :: Double) else 1 | b <- sigmaDecoderMask ]
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

-- | σ₃₈₄ is an involution: @σ₃₈₄ ∘ σ₃₈₄ ≡ id@. Exact.
lawSigmaDecoderInvolution :: DecoderOutput -> Bool
lawSigmaDecoderInvolution o =
  let DecoderOutput (Tensor1 a) = sigmaDecoder (sigmaDecoder o)
      DecoderOutput (Tensor1 b) = o
  in U.length a == U.length b && U.and (U.zipWith (==) a b)

-- | σ₃₈₄ is orthogonal: preserves Euclidean norm.
lawSigmaDecoderOrthogonal :: DecoderOutput -> Bool
lawSigmaDecoderOrthogonal o =
  let normSq (DecoderOutput (Tensor1 v)) = U.sum (U.map (\x -> x * x) v)
  in normSq o == normSq (sigmaDecoder o)

-- | σ₃₈₄ acts as per-triple OKLab σ: for every i in [0, 128), the i-th triple
-- of the σ₃₈₄-applied vector equals 'PairTree.sigmaReflect' of the i-th input triple.
lawSigmaDecoderMatchesPerTriple :: DecoderOutput -> Bool
lawSigmaDecoderMatchesPerTriple (DecoderOutput (Tensor1 v)) =
  let DecoderOutput (Tensor1 v') = sigmaDecoder (DecoderOutput (Tensor1 v))
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
  in U.length v == 384 && U.all (== 0.0) v

-- | The reference decoder (= 0 map) is σ-equivariant: @0 ∘ σ = σ ∘ 0 = 0@.
-- Trivial (the zero map commutes with everything); pins the base case.
lawDecoderRefSigmaEquivariance :: HiddenContext -> Bool
lawDecoderRefSigmaEquivariance x =
  let DecoderOutput (Tensor1 a) = decoderReference x
      DecoderOutput (Tensor1 b) = sigmaDecoder (decoderReference x)
  in U.length a == U.length b && U.and (U.zipWith (==) a b)

-- | The pruning arithmetic: total free params = 128 generator triples × 106 per
-- triple = 13568; naive = 384·64 = 24576; ratio = 13568/24576 ≈ 0.552. Pinned
-- as a snapshot so if any of the upstream dims drift, this fails.
lawDecoderPruningArithmetic :: Bool
lawDecoderPruningArithmetic =
     decoderOutputDim   == 384
  && numTriples         == 128
  && decoderFreeParams  == numTriples * 106   -- 13568
  && decoderNaiveParams == 384 * 64           -- 24576
  && decoderFreeParams  == 13568
  && decoderNaiveParams == 24576
  && abs (decoderPruningRatio - 13568 / 24576) < 1e-12

-- | 'flattenHaar' is the exact left-inverse of 'toHaarPalette' for well-formed
-- depth-'decoderTreeDepth' palettes: @toHaarPalette (flattenHaar hp) == hp@.
-- EXACT (no arithmetic — the same 'Double's are sliced out and reassembled), so
-- the recursion-driven decoder produces the same flat 384 layout the flat
-- decoder does. Guards on well-formedness + correct depth (other shapes don't
-- fit 384).
lawHaarFlattenRoundTrip :: HaarPalette -> Bool
lawHaarFlattenRoundTrip hp =
  length (levels hp) /= decoderTreeDepth || not (wellFormed hp)
  || toHaarPalette (flattenHaar hp) == hp

-- | L6 reconstruction yields exactly 'sigmaPairLeaves' (= 256) OKLab leaves on
-- the zero decoder output (a neutral-grey σ-pair palette). Pins the
-- decoder→palette leaf count.
lawReconstructSigmaPairLeaves :: HiddenContext -> Bool
lawReconstructSigmaPairLeaves x =
  length (reconstructSigmaPair (decoderReference x)) == sigmaPairLeaves

-- | The recursion-driven decoder with the reference shared block equals the zero
-- decoder, on every input. Pins that the Mixture-of-Recursions restructuring
-- preserves the reference contract (and hence 'lawLookNetReferenceIsZero').
lawDecoderFromRecursionMatchesZero :: HiddenContext -> Bool
lawDecoderFromRecursionMatchesZero x =
  let DecoderOutput (Tensor1 a) = decoderFromRecursion sharedReferenceBlock x
      DecoderOutput (Tensor1 b) = decoderReference x
  in U.length a == U.length b && U.and (U.zipWith (==) a b)
