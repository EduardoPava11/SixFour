{-# LANGUAGE FlexibleContexts    #-}
{-# LANGUAGE ScopedTypeVariables #-}

{- |
Module      : SixFour.Spec.LookNetR
Description : L4 recursive core — 8 unrolled residual blocks with σ-block-diagonal weights.

The /core/ of the look-NN. Eight residual blocks @x ↦ x + φ_n(x)@ amortize the
Wasserstein-2 / Bures barycenter iteration into a fixed-depth network (the
@maxPonderDepth = 8@ ceiling, tied to the Haar pairing depth).

== The σ-equivariance constraint forces a block-diagonal weight matrix

The L4 input AND output is the 64-D 'HiddenContext' from "SixFour.Spec.LookNetE".
Both sides carry the same σ-action: 'SixFour.Spec.Tensor.sigma64' (the Hurvich-Jameson
22+21+21 decomposition — 22 achromatic dims σ-fixed, 42 chromatic dims σ-negated).

An L4 block @x ↦ x + W·x@ (linear, no nonlinearity for the spec; the trainer adds
GELU between two such Ws) is σ-equivariant iff:

>   W · sigma64 = sigma64 · W                     [equivariance condition]
>   ⇔ W · diag(s) = diag(s) · W      where s = ±1 per the sigma64Mask
>   ⇔ W[i,j] · s[j] = s[i] · W[i,j]
>   ⇔ W[i,j] = 0  whenever s[i] ≠ s[j]            [block-diagonal forcing]

So @W@ MUST be **block-diagonal** in the achromatic/chromatic partition:

>   W = ⎡ W_AA      0   ⎤      A = achromatic block (22×22)
>       ⎣  0     W_CC   ⎦      C = chromatic   block (42×42)

The achromatic block is 22×22 = 484 free parameters; the chromatic block is
42×42 = 1764 free parameters. Total per W: 2248. The "naive dense" 64×64 W
would have 4096 — so σ-equivariance prunes **45%** of parameters /by symmetry/,
not by training. This is an exact analogue of the parameter sharing in
group-equivariant CNNs (Cohen & Welling 2016, Lengyel 2023).

== The mask is exposed for the codegen path

'sigmaBlockDiagonalMask' returns the 64×64 bit-matrix where 1 = "weight is free
to learn" and 0 = "weight must be exactly zero." 'SixFour.Codegen.CoreML' (when
it lands) will multiply this mask into every L4 weight tensor at codegen time so
the trained `.mlpackage` cannot violate the constraint at inference.

== The reference baseline

'coreReferenceBlock' is the IDENTITY block — @step x = x + 0@. It satisfies σ-equivariance
trivially (the zero matrix commutes with everything) and gives a total reference
the trainer is a controlled deviation from. The /full/ reference core
'coreReferenceFull' is 8 unrolled identity blocks, hence still the identity. This
is mathematically interesting: the spec says the core IS the identity until trained,
matching the Pipeline.hs philosophy of "deterministic boundary, learned middle."

== The /halting/ structure ("ponder")

Adaptive-depth recursion (Graves ACT / Mixture-of-Recursions) is rejected for
the on-device path: variable-depth control flow is CPU-only in CoreML's MIL and
breaks the SoA zero-copy story. Instead, halting is AMORTIZED at training time:
each block has a learned scalar @h_n ∈ [0,1]@; the cumulative halting product
@∏ (1 - h_n)@ multiplies each block's contribution. At inference, all 8 blocks
ALWAYS run (the unroll is exact), so there is no control flow — the halting is
already baked into the weights via training. 'haltingWeightSlot' just declares
the scalar dimension; the spec doesn't model the training dynamics.
-}
module SixFour.Spec.LookNetR
  ( -- * Core structure
    coreDepth
  , haltingWeightSlot
    -- * The block + its σ-correct mask
  , CoreBlock(..)
  , coreReferenceBlock
  , coreReferenceFull
  , sigmaBlockDiagonalMask
  , freeParameterCount
  , naiveParameterCount
  , symmetryPruningRatio
    -- * σ-action on the boundary (re-exported for composition)
  , sigmaCoreContext
    -- * Laws (predicates; QuickCheck'd in Properties.LookNetR)
  , lawCoreRefSigmaEquivariance
  , lawCoreRefIsIdentity
  , lawBlockDiagonalMaskRespectsSigma
  , lawSymmetryPruningRatio
  ) where

import qualified Data.Vector.Unboxed as U

import SixFour.Spec.Tensor   (Tensor1(..), sigma64Mask)
import SixFour.Spec.LookNetE (HiddenContext(..), sigmaHiddenContext)

-- =============================================================================
-- Structural constants
-- =============================================================================

-- | The L4 core depth — 8 unrolled residual blocks. Tied to 'SixFour.Spec.PairTree.paletteDepth'
-- (the Haar pairing depth): one barycenter-iteration step per Haar level is the
-- natural ceiling. Fixed at the type-and-value level for static-shape ANE compatibility.
coreDepth :: Int
coreDepth = 8

-- | Per-block halting scalar. The trainer learns one @h_n ∈ [0,1]@ per block;
-- the cumulative halting product @∏ (1 - h_n)@ amortizes adaptive depth into
-- the per-block weights. At inference this is a constant baked into the .mlpackage.
haltingWeightSlot :: Int
haltingWeightSlot = 1

-- =============================================================================
-- The block (algebraic specification, no learned weights)
-- =============================================================================

-- | An L4 residual block @x ↦ x + φ(x)@. The reference spec carries no weights;
-- 'coreReferenceBlock' is the identity (@φ = 0@). The trained core supplies
-- weights that satisfy the σ-block-diagonal constraint
-- ('sigmaBlockDiagonalMask') by construction.
data CoreBlock = CoreBlock
  { cbResidual :: !(HiddenContext -> HiddenContext)
    -- ^ the @φ@ map; for the reference spec, @const (HiddenContext zeros)@.
  , cbHalting  :: !Double
    -- ^ the learned halting scalar @h ∈ [0,1]@; the reference uses @0@
    -- (no halting — full contribution from every block).
  }

-- | The identity reference block: @φ = 0@, no halting, output ≡ input.
coreReferenceBlock :: CoreBlock
coreReferenceBlock = CoreBlock
  { cbResidual = \(HiddenContext (Tensor1 _)) ->
      HiddenContext (Tensor1 (U.replicate 64 0.0))
  , cbHalting  = 0
  }

-- | Apply one block: @x' = x + (1 - h) · φ(x)@. With the reference block this
-- reduces to @x' = x@ (identity); with a trained block, this is the standard
-- residual update with the amortized halting weight.
applyBlock :: CoreBlock -> HiddenContext -> HiddenContext
applyBlock (CoreBlock phi h) ctx@(HiddenContext (Tensor1 x)) =
  let HiddenContext (Tensor1 dx) = phi ctx
      scale = 1 - h
      x'    = U.zipWith (\xi di -> xi + scale * di) x dx
  in HiddenContext (Tensor1 x')

-- | The full reference core: 8 unrolled identity blocks. Identity ∘ identity =
-- identity, so 'coreReferenceFull' is the identity on 'HiddenContext'. The
-- trained core is a controlled deviation; its σ-equivariance is the composition
-- of 8 σ-equivariant block instances.
coreReferenceFull :: HiddenContext -> HiddenContext
coreReferenceFull = foldr (.) id (replicate coreDepth (applyBlock coreReferenceBlock))

-- =============================================================================
-- The σ-block-diagonal constraint
-- =============================================================================

-- | The 64×64 binary mask where @1@ = "this weight is FREE to learn" and @0@ =
-- "this weight MUST be exactly zero for σ-equivariance." Computed by the rule
-- @mask[i,j] = (sigma64Mask[i] == sigma64Mask[j])@: a weight is free iff its
-- input and output dims belong to the same σ-class (both achromatic or both
-- chromatic). Cross-class weights would couple σ-fixed dims to σ-negated dims,
-- which breaks the equivariance condition @W·σ = σ·W@.
--
-- Stored row-major: index @(i * 64 + j)@.
sigmaBlockDiagonalMask :: U.Vector Int
sigmaBlockDiagonalMask =
  let s = sigma64Mask
  in U.generate (64 * 64) (\k ->
       let i = k `div` 64
           j = k `mod` 64
       in if (s !! i) == (s !! j) then 1 else 0)

-- | The number of FREE parameters per σ-block-diagonal 64×64 weight matrix:
-- @22² + 42² = 484 + 1764 = 2248@. This is what the trainer actually fits per
-- block W (× 2 W matrices per block × 8 blocks = 35968 total L4 parameters,
-- vs the naive 65536 if no σ structure were enforced).
freeParameterCount :: Int
freeParameterCount = U.sum sigmaBlockDiagonalMask

-- | The naive parameter count for a dense 64×64 weight: @64² = 4096@.
naiveParameterCount :: Int
naiveParameterCount = 64 * 64

-- | The symmetry-pruning ratio: @freeParameterCount / naiveParameterCount@.
-- For the Hurvich-Jameson 22+42 split this is @2248/4096 ≈ 0.549@ — the
-- σ-equivariance constraint /forces/ ~45% of weights to zero by symmetry, not
-- by training. (Compare to L1/L2/L∞ weight sparsity, which is achieved by
-- regularization; this is achieved by structure.)
symmetryPruningRatio :: Double
symmetryPruningRatio =
  fromIntegral freeParameterCount / fromIntegral naiveParameterCount

-- =============================================================================
-- σ-action on the hidden context (re-export of LookNetE.sigmaHiddenContext)
-- =============================================================================

-- | σ on the 64-D core context. Just re-exports 'sigmaHiddenContext' from
-- "SixFour.Spec.LookNetE" with a name local to L4. Same fixed diagonal
-- involution; the equivariance condition is @core ∘ σ = σ ∘ core@.
sigmaCoreContext :: HiddenContext -> HiddenContext
sigmaCoreContext = sigmaHiddenContext

-- =============================================================================
-- Laws
-- =============================================================================

-- | The reference core (identity) is σ-equivariant: @id ∘ σ = σ ∘ id@. Exact.
-- This is the trivial base case; the trained core inherits equivariance from
-- the per-block σ-block-diagonal weight constraint.
lawCoreRefSigmaEquivariance :: HiddenContext -> Bool
lawCoreRefSigmaEquivariance x =
  let HiddenContext (Tensor1 a) = coreReferenceFull (sigmaCoreContext x)
      HiddenContext (Tensor1 b) = sigmaCoreContext (coreReferenceFull x)
  in U.length a == U.length b && U.and (U.zipWith (==) a b)

-- | The reference core IS the identity: @coreReferenceFull x ≡ x@ for all x.
-- Pins the "deterministic boundary, learned middle" philosophy: the spec
-- doesn't compute anything; it only declares the dimensional + symmetry contract
-- that the trained core must satisfy.
lawCoreRefIsIdentity :: HiddenContext -> Bool
lawCoreRefIsIdentity x@(HiddenContext (Tensor1 v)) =
  let HiddenContext (Tensor1 y) = coreReferenceFull x
  in U.length v == U.length y && U.and (U.zipWith (==) v y)

-- | The block-diagonal mask respects σ: every position @(i,j)@ with
-- @mask[i,j] = 1@ has @sigma64Mask[i] == sigma64Mask[j]@. The contrapositive
-- (mask=0 ⇒ classes differ) is also asserted. This is the algebraic
-- correctness criterion for 'sigmaBlockDiagonalMask'.
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

-- | The pruning ratio is exactly @(22² + 42²) / 64² = 2248/4096@. This is a
-- snapshot of the parameter-count arithmetic — if any of the structural
-- constants drift, this law catches it.
lawSymmetryPruningRatio :: Bool
lawSymmetryPruningRatio =
     freeParameterCount  == 22 * 22 + 42 * 42
  && naiveParameterCount == 64 * 64
  && freeParameterCount  == 2248
  && naiveParameterCount == 4096
  && abs (symmetryPruningRatio - 2248 / 4096) < 1e-12
