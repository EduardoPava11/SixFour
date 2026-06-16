{-# LANGUAGE FlexibleContexts    #-}
{-# LANGUAGE ScopedTypeVariables #-}

{- |
Module      : SixFour.Spec.LookNetR
Description : L4 recursive core — ONE weight-shared block applied over 8 Haar levels (Mixture-of-Recursions) with σ-invariant halting.

The /core/ of the look-NN. A SINGLE weight-shared block @g@ (the @sbRefine@ map)
is applied recursively, once per Haar pairing level @ℓ = 0..coreDepth-1@
(Universal-Transformer / Mixture-of-Recursions style — one set of weights reused
@coreDepth@ times, not @coreDepth@ distinct blocks). Each application amortizes
one Wasserstein-2 / Bures barycenter-iteration step; the @maxPonderDepth = 8@
ceiling is tied to 'SixFour.Spec.PairTree.paletteDepth' (one recursion per Haar
level). 'runRecursion' exposes the SEQUENCE of per-step contexts so the decoder's
level-ℓ head ('SixFour.Spec.LookNetD.decoderFromRecursion') can read the context
after ℓ refinements — coarse Haar levels read shallow contexts, fine levels read
deep ones.

== The σ-equivariance constraint forces a block-diagonal weight matrix

The L4 input AND output is the 64-D 'HiddenContext' from "SixFour.Spec.LookNetE".
Both sides carry the same σ-action: 'SixFour.Spec.Tensor.sigma64' (the Hurvich-Jameson
22+21+21 decomposition — 22 achromatic dims σ-fixed, 42 chromatic dims σ-negated).

A refine step @x ↦ x + W·x@ (the trainer puts tanh between two such Ws) is
σ-equivariant iff:

>   W · sigma64 = sigma64 · W                     [equivariance condition]
>   ⇔ W[i,j] = 0  whenever s[i] ≠ s[j]            [block-diagonal forcing]

So @W@ MUST be **block-diagonal** in the achromatic/chromatic partition: a 22×22
achromatic block (484 free) + a 42×42 chromatic block (1764 free) = 2248 free,
vs the naive 4096 — σ-equivariance prunes **45%** of parameters /by symmetry/,
not by training (group-equivariant CNNs, Cohen & Welling 2016; Lengyel 2023).
Because the block is SHARED across all recursion steps, this 2248-free matrix is
fit once and reused 8×.

== The /halting/ structure ("ponder") — Mixture-of-Recursions over Haar levels

This is the redesign's heart. The shared block carries a halting head @sbHalt@
producing @λ_ℓ ∈ [0,1]@ per recursion step (PonderNet / MoR per-token routing,
where the "tokens" are the 8 Haar levels). The φ self-similar coefficient decay
('SixFour.Spec.PairTree.goldenDecay') makes this principled: coarse levels carry
SIGNAL (large offsets), fine levels carry NOISE (offsets shrinking by 1/φ per
level), so adaptive depth = adaptive wavelet truncation — halt early on the fine
(noise) levels, ponder on the coarse (signal) levels.

DESIGN VALIDATION (2025–2026 literature, adversarially verified): reuse-one-block-
@N@× with adaptive halting is the right family for a tiny net. Mixture-of-Recursions
(Bae et al., NeurIPS 2025) "reuses a shared stack of layers across recursion steps to
achieve parameter efficiency, while lightweight routers dynamically assign different
recursion depths"; at equal FLOPs and SMALLER model sizes it improves accuracy and
throughput. Controlled looped-LM experiments in the 1M–40M-parameter regime — the
closest published scale to this net's ~115K — find the advantage "stems not from
increased knowledge capacity, but from superior knowledge MANIPULATION" (Zhu et al.,
2025): i.e. the gain is from /computation reuse/, exactly what a 2248-free block reused
8× buys. Caveat: those models halt PER-TOKEN; this core halts PER-GIF (the σ-invariant
@λ_ℓ@ schedule below), so the endorsement is at the mechanism level, not the granularity.

CRITICAL σ-CONSTRAINT: @λ_ℓ@ must be **σ-INVARIANT** — sign-flipping the chroma
channels (red↔green, blue↔yellow) must NOT change how many levels we generate.
'sigmaInvariantFeatures' projects the context onto @(‖achromatic‖², ‖chromatic‖²)@,
which is σ-invariant /exactly/: σ only flips signs within the chromatic block, and
@(−x)² = x²@. The halting head reads ONLY these two scalars
('haltingFromFeatures'), so σ-invariance is true by construction
('lawHaltingSigmaInvariance', proved with @==@, no tolerance).

== Inference contract: hard static unroll

The /spec reference/ and the on-device forward pass run all @coreDepth@ steps
(static unroll, control-flow-free — friendly to a hand-written Metal/Swift
forward pass and to the dormant CoreML/ANE fallback). @sbHalt@ and the per-level
halt schedule are exposed for the /trainer's/ soft-PonderNet objective (the
expected-output marginalization over halt step), but the shipped contract — and
the golden vectors — are the hard unroll. The trainer must distill/evaluate
against the hard unroll.

== The reference baseline

'sharedReferenceBlock' is the IDENTITY refine (@sbRefine = id@) with never-halt
(@sbHalt = const 0@). 'coreReferenceFull' = the final context after
@coreDepth@ identity refinements = the identity on 'HiddenContext'. A total
reference the trainer is a controlled deviation from — matching the Pipeline.hs
philosophy of "deterministic boundary, learned middle."
-}
module SixFour.Spec.LookNetR
  ( -- * Core structure
    coreDepth
  , haltingWeightSlot
  , sharedBlockCount
    -- * The shared recursive block (Mixture-of-Recursions)
  , SharedBlock(..)
  , sharedReferenceBlock
  , runRecursion
  , recursionFinalContext
  , coreReferenceFull
    -- * σ-invariant halting head
  , sigmaInvariantFeatures
  , haltingFromFeatures
    -- * The σ-correct weight mask + pruning accounting
  , sigmaBlockDiagonalMask
  , freeParameterCount
  , naiveParameterCount
  , symmetryPruningRatio
    -- * σ-action on the boundary (re-exported for composition)
  , sigmaCoreContext
    -- * Laws (predicates; QuickCheck'd in Properties.LookNetR)
  , lawCoreRefSigmaEquivariance
  , lawCoreRefIsIdentity
  , lawRecursionSigmaEquivariance
  , lawHaltingSigmaInvariance
  , lawBlockDiagonalMaskRespectsSigma
  , lawSymmetryPruningRatio
  , lawSharedBlockReuse
  ) where

import qualified Data.Vector.Unboxed as U

import SixFour.Spec.Tensor   (Tensor1(..), sigma64Mask, hiddenAchromaticDim)
import SixFour.Spec.LookNetE (HiddenContext(..), sigmaHiddenContext)

-- =============================================================================
-- Structural constants
-- =============================================================================

-- | The L4 recursion depth — the shared block is applied 8 times, once per Haar
-- pairing level. Tied to 'SixFour.Spec.PairTree.paletteDepth' (= 'maxPonderDepth'):
-- one barycenter-iteration step per Haar level is the natural ceiling. Fixed at
-- the value level for static-shape ANE/Metal compatibility.
coreDepth :: Int
coreDepth = 8

-- | Halting-scalar dimension: one @λ_ℓ ∈ [0,1]@ per recursion step.
haltingWeightSlot :: Int
haltingWeightSlot = 1

-- | The number of distinct weight-bearing blocks: exactly ONE (the shared block
-- @g@), reused 'coreDepth' times. This is the Mixture-of-Recursions invariant —
-- contrast the retired design's 8 distinct blocks. ('lawSharedBlockReuse'.)
sharedBlockCount :: Int
sharedBlockCount = 1

-- =============================================================================
-- The shared recursive block (algebraic specification, no learned weights)
-- =============================================================================

-- | The ONE weight-shared block reused across all 'coreDepth' recursion steps.
-- The reference carries no weights: 'sbRefine' is the identity and 'sbHalt'
-- never halts. The trained block supplies a 'sbRefine' that satisfies the
-- σ-block-diagonal constraint ('sigmaBlockDiagonalMask') by construction, and a
-- 'sbHalt' that factors through 'sigmaInvariantFeatures' (σ-invariant by
-- construction).
data SharedBlock = SharedBlock
  { sbRefine :: !(HiddenContext -> HiddenContext)
    -- ^ the σ-equivariant context update applied at every recursion step;
    -- reference = 'id'.
  , sbHalt   :: !(HiddenContext -> Double)
    -- ^ the σ-INVARIANT halting head @λ_ℓ ∈ [0,1]@; reference = @const 0@
    -- (never halt — every level runs). MUST factor through
    -- 'sigmaInvariantFeatures' to stay σ-invariant.
  }

-- | The identity reference block: @sbRefine = id@, @sbHalt = const 0@.
sharedReferenceBlock :: SharedBlock
sharedReferenceBlock = SharedBlock
  { sbRefine = id
  , sbHalt   = haltingFromFeatures (const 0)
  }

-- | The sequence of per-step contexts: @[ctx₀, ctx₁, …, ctx_coreDepth]@, where
-- @ctxₙ@ is the context after @n@ applications of 'sbRefine'. Length
-- @coreDepth + 1@. The decoder reads @ctx₀@ for the root and @ctx_{ℓ+1}@ for
-- Haar level @ℓ@, so deeper recursion feeds finer detail.
runRecursion :: SharedBlock -> HiddenContext -> [HiddenContext]
runRecursion blk = take (coreDepth + 1) . iterate (sbRefine blk)

-- | The final context after all 'coreDepth' refinements (= @step \@L4Core@).
recursionFinalContext :: SharedBlock -> HiddenContext -> HiddenContext
recursionFinalContext blk = last . runRecursion blk

-- | The full reference core = the final context under the identity block =
-- the identity on 'HiddenContext' (@iterate id x@ is constant, so the last
-- element is @x@). The trained core is a controlled deviation; its
-- σ-equivariance is 'lawRecursionSigmaEquivariance'.
coreReferenceFull :: HiddenContext -> HiddenContext
coreReferenceFull = recursionFinalContext sharedReferenceBlock

-- =============================================================================
-- σ-invariant halting head
-- =============================================================================

-- | The σ-INVARIANT summary the halting head is allowed to read:
-- @(‖achromatic block‖², ‖chromatic block‖²)@. The achromatic block is the
-- first 'hiddenAchromaticDim' (22) coordinates (σ-fixed); the chromatic block is
-- the remaining 42 (σ-negated). Both are sums of squares over a σ-class, so they
-- are unchanged under 'sigmaHiddenContext' EXACTLY (negation then squaring is
-- bit-identical in 'Double'). See 'lawHaltingSigmaInvariance'.
sigmaInvariantFeatures :: HiddenContext -> (Double, Double)
sigmaInvariantFeatures (HiddenContext (Tensor1 v)) =
  let (achroma, chroma) = U.splitAt hiddenAchromaticDim v   -- 22 | 42
  in (U.sum (U.map sq achroma), U.sum (U.map sq chroma))
  where sq x = x * x

-- | Build a halting head from a function of the σ-invariant features. Any head
-- so constructed is σ-invariant by composition. The reference uses
-- @const 0@ (never halt); the trainer supplies a small MLP @(Double, Double) ->
-- Double@ (with a final sigmoid to land in @[0,1]@).
haltingFromFeatures :: ((Double, Double) -> Double) -> HiddenContext -> Double
haltingFromFeatures f = f . sigmaInvariantFeatures

-- =============================================================================
-- The σ-block-diagonal constraint
-- =============================================================================

-- | The 64×64 binary mask where @1@ = "this weight is FREE to learn" and @0@ =
-- "this weight MUST be exactly zero for σ-equivariance." Computed by the rule
-- @mask[i,j] = (sigma64Mask[i] == sigma64Mask[j])@: a weight is free iff its
-- input and output dims belong to the same σ-class. Stored row-major
-- (@i * 64 + j@). Applied to the SHARED block's weights at codegen time.
sigmaBlockDiagonalMask :: U.Vector Int
sigmaBlockDiagonalMask =
  let s = sigma64Mask
  in U.generate (64 * 64) (\k ->
       let i = k `div` 64
           j = k `mod` 64
       in if (s !! i) == (s !! j) then 1 else 0)

-- | The number of FREE parameters per σ-block-diagonal 64×64 weight matrix:
-- @22² + 42² = 484 + 1764 = 2248@ (fit once, reused 'coreDepth' times).
freeParameterCount :: Int
freeParameterCount = U.sum sigmaBlockDiagonalMask

-- | The naive parameter count for a dense 64×64 weight: @64² = 4096@.
naiveParameterCount :: Int
naiveParameterCount = 64 * 64

-- | The symmetry-pruning ratio @freeParameterCount / naiveParameterCount ≈ 0.549@
-- — σ-equivariance /forces/ ~45% of weights to zero by structure, not training.
symmetryPruningRatio :: Double
symmetryPruningRatio =
  fromIntegral freeParameterCount / fromIntegral naiveParameterCount

-- =============================================================================
-- σ-action on the hidden context (re-export of LookNetE.sigmaHiddenContext)
-- =============================================================================

-- | σ on the 64-D core context. Re-exports 'sigmaHiddenContext' with a name
-- local to L4. The equivariance condition is @core ∘ σ = σ ∘ core@.
sigmaCoreContext :: HiddenContext -> HiddenContext
sigmaCoreContext = sigmaHiddenContext

-- =============================================================================
-- Laws
-- =============================================================================

-- | The reference core (identity) is σ-equivariant: @id ∘ σ = σ ∘ id@. Exact.
lawCoreRefSigmaEquivariance :: HiddenContext -> Bool
lawCoreRefSigmaEquivariance x =
  let HiddenContext (Tensor1 a) = coreReferenceFull (sigmaCoreContext x)
      HiddenContext (Tensor1 b) = sigmaCoreContext (coreReferenceFull x)
  in U.length a == U.length b && U.and (U.zipWith (==) a b)

-- | The reference core IS the identity: @coreReferenceFull x ≡ x@ for all x.
lawCoreRefIsIdentity :: HiddenContext -> Bool
lawCoreRefIsIdentity x@(HiddenContext (Tensor1 v)) =
  let HiddenContext (Tensor1 y) = coreReferenceFull x
  in U.length v == U.length y && U.and (U.zipWith (==) v y)

-- | INDUCTIVE recursion σ-equivariance: if the shared block's 'sbRefine' is
-- σ-equivariant, then applying it @n@ times stays σ-equivariant, for every
-- @n ∈ [0, coreDepth]@. This is the law that lets one σ-equivariant block
-- witness the whole recursion (the trainer's obligation). Tested on the
-- reference ('sbRefine = id', exact); the @tol@ argument mirrors
-- 'SixFour.Spec.PairTree.lawReconstructAnalyzeRoundTrip' for the trained case,
-- where FP reassociation compounds across the @n@ steps.
lawRecursionSigmaEquivariance :: Double -> HiddenContext -> Bool
lawRecursionSigmaEquivariance tol x =
  all equivAt [0 .. coreDepth]
  where
    g        = sbRefine sharedReferenceBlock
    applyN n = foldr (.) id (replicate n g)
    equivAt n =
      let HiddenContext (Tensor1 a) = applyN n (sigmaCoreContext x)
          HiddenContext (Tensor1 b) = sigmaCoreContext (applyN n x)
      in U.length a == U.length b
         && U.and (U.zipWith (\p q -> abs (p - q) <= tol) a b)

-- | The halting head is σ-INVARIANT, EXACTLY: 'sigmaInvariantFeatures' is
-- unchanged under σ (squares kill the chromatic sign flip), and hence so is any
-- 'haltingFromFeatures'-built head — including the reference. Asserted with
-- @==@ (no tolerance): a strictly stronger guarantee than the equivariance laws.
lawHaltingSigmaInvariance :: HiddenContext -> Bool
lawHaltingSigmaInvariance x =
     sigmaInvariantFeatures (sigmaCoreContext x) == sigmaInvariantFeatures x
  && sbHalt sharedReferenceBlock (sigmaCoreContext x)
     == sbHalt sharedReferenceBlock x

-- | The block-diagonal mask respects σ: @mask[i,j] = 1 ⇔ sigma64Mask[i] == sigma64Mask[j]@.
lawBlockDiagonalMaskRespectsSigma :: Bool
lawBlockDiagonalMaskRespectsSigma =
  let s = sigma64Mask
      check k =
        let i = k `div` 64
            j = k `mod` 64
            m = sigmaBlockDiagonalMask U.! k
            sameClass = (s !! i) == (s !! j)
        in (m == 1) == sameClass
  in all check [0 .. 64 * 64 - 1]

-- | The pruning ratio is exactly @(22² + 42²) / 64² = 2248/4096@.
lawSymmetryPruningRatio :: Bool
lawSymmetryPruningRatio =
     freeParameterCount  == 22 * 22 + 42 * 42
  && naiveParameterCount == 64 * 64
  && freeParameterCount  == 2248
  && naiveParameterCount == 4096
  && abs (symmetryPruningRatio - 2248 / 4096) < 1e-12

-- | The Mixture-of-Recursions invariant: exactly ONE shared block, reused
-- 'coreDepth' = 8 times. 'runRecursion' produces @coreDepth + 1@ contexts (the
-- initial context plus one per reuse).
lawSharedBlockReuse :: HiddenContext -> Bool
lawSharedBlockReuse x =
     sharedBlockCount == 1
  && coreDepth == 8
  && length (runRecursion sharedReferenceBlock x) == coreDepth + 1
