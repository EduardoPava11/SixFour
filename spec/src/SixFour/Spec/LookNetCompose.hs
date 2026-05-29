{-# LANGUAGE AllowAmbiguousTypes #-}
{-# LANGUAGE FlexibleContexts    #-}
{-# LANGUAGE FlexibleInstances   #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE TypeFamilies        #-}
{-# LANGUAGE TypeOperators       #-}

{- |
Module      : SixFour.Spec.LookNetCompose
Description : Knit L3 → L4 → L5 into one typed pipeline + the end-to-end σ-equivariance theorem.

The /unification/ of the three learnable look-NN layers. Each of "SixFour.Spec.LookNetE"
(L3 encoder), "SixFour.Spec.LookNetR" (L4 recursive core), and "SixFour.Spec.LookNetD"
(L5 tree decoder) declares its own boundary types and reference baseline. This module
makes them 'SixFour.Spec.Pipeline.Stage' instances and composes them with the existing
@(:>)@ operator, so the entire learnable middle of the look-NN is a single typed
pipeline tag.

== The composition

>   LookNetPipeline = L5Decoder :> L4Core :> L3Encoder
>
>   In  LookNetPipeline = In  L3Encoder = GmmTokenSet
>   Out LookNetPipeline = Out L5Decoder = DecoderOutput

So the typed signature of the entire learnable look-NN is just
@GmmTokenSet -> DecoderOutput@ — the rest is structural decomposition the GHC
checker derives automatically from the three Stage instances.

== The σ-equivariance theorem

@lookNetSigmaTheorem@ is the analogue of "SixFour.Spec.Pipeline".@option4Theorem@
for the learnable middle. Its type signature says:

>   IF L3Encoder, L4Core, and L5Decoder are individually 'SigmaEquivariant',
>   AND the boundary types compose (which the typeclass also requires),
>   THEN @LookNetPipeline@ is 'SigmaEquivariant' end-to-end.

The proof is the typeability — if GHC accepts the signature, the theorem holds.
The body is @SigmaEquivariantDict@ — a zero-information runtime witness.

The per-layer SigmaEquivariant instances are declared HERE (not in LookNetE/R/D)
because the typeclass lives in "SixFour.Spec.Pipeline" and we deliberately kept
the layer modules free of that dependency to avoid module-graph entanglement.

== The reference baseline at the pipeline level

@lookNetReference@ composes the three reference baselines:

>   lookNetReference = decoderReference . coreReferenceFull . encoderReferenceShim
>                    = DecoderOutput (Tensor1 0)   -- always zero, for any input

This is the math-first statement of "the spec is a contract, not a computation":
the deterministic pipeline maps every input to the zero decoder output. The
trained pipeline is a controlled deviation; its σ-equivariance is exactly the
theorem this module proves typeable.
-}
module SixFour.Spec.LookNetCompose
  ( -- * Pipeline tag
    LookNetPipeline
    -- * The end-to-end σ-equivariance theorem
  , lookNetSigmaTheorem
    -- * Reference baseline (the zero map)
  , lookNetReference
    -- * Laws
  , lawPipelineComposes
  , lawLookNetReferenceIsZero
  ) where

import           Data.Proxy            (Proxy(..))
import qualified Data.Vector.Unboxed   as U

import SixFour.Spec.Pipeline
  ( Stage(..)
  , SigmaEquivariant(..)
  , (:>)
  , SigmaEquivariantDict(..)
  )
import SixFour.Spec.Tensor   (Tensor1(..))
import SixFour.Spec.LookNetE
  ( L3Encoder
  , GmmTokenSet(..)
  , HiddenContext(..)
  , encoderReference
  , sigmaGmmTokenSet
  , sigmaHiddenContext
  )
import SixFour.Spec.LookNetR
  ( coreReferenceFull
  , sigmaCoreContext
  )
import SixFour.Spec.LookNetD
  ( DecoderOutput(..)
  , decoderReference
  , sigmaDecoder
  )

-- =============================================================================
-- Stage tags for L4 and L5 (L3 already exists in LookNetE)
-- =============================================================================

-- | The L4 recursive core as a single Stage. ONE weight-shared block is reused
-- across 8 Haar-level recursion steps (Mixture-of-Recursions) internally; at the
-- pipeline level the core is one @HiddenContext -> HiddenContext@ map. Its
-- σ-equivariance is witnessed by
-- "SixFour.Spec.LookNetR".'SixFour.Spec.LookNetR.lawRecursionSigmaEquivariance'
-- (σ-equivariant shared block ⇒ N-fold recursion σ-equivariant).
data L4Core

-- | The L5 tree decoder as a single Stage.
data L5Decoder

-- =============================================================================
-- Stage instances (declared here to keep the layer modules free of the
-- Pipeline dependency, per their own docstrings)
-- =============================================================================

instance Stage L3Encoder where
  type In  L3Encoder = GmmTokenSet
  type Out L3Encoder = HiddenContext
  step = encoderReference

instance Stage L4Core where
  type In  L4Core = HiddenContext
  type Out L4Core = HiddenContext
  step = coreReferenceFull

instance Stage L5Decoder where
  type In  L5Decoder = HiddenContext
  type Out L5Decoder = DecoderOutput
  step = decoderReference

-- =============================================================================
-- SigmaEquivariant instances (the trainer's hard targets)
-- =============================================================================
--
-- Each layer's σ commutes with the layer (modulo FP reassociation; the
-- numerical verification lives in each layer's Properties module with its
-- own tolerance). The typeclass instance pins the algebraic claim; GHC
-- accepting the (:>) instance derivation is the type-level proof.

instance SigmaEquivariant L3Encoder where
  sigmaIn  = sigmaGmmTokenSet
  sigmaOut = sigmaHiddenContext

instance SigmaEquivariant L4Core where
  sigmaIn  = sigmaCoreContext
  sigmaOut = sigmaCoreContext

instance SigmaEquivariant L5Decoder where
  sigmaIn  = sigmaHiddenContext
  sigmaOut = sigmaDecoder

-- =============================================================================
-- The pipeline + the theorem
-- =============================================================================

-- | The full learnable look-NN as a typed pipeline. Reads right-to-left:
-- "encode tokens, then run the recursive core, then decode to Haar coefficients."
--
-- The composed 'Stage' instance:
--
-- >   In  LookNetPipeline = In  L3Encoder  = GmmTokenSet
-- >   Out LookNetPipeline = Out L5Decoder  = DecoderOutput
type LookNetPipeline = L5Decoder :> L4Core :> L3Encoder

-- | The end-to-end σ-equivariance theorem. If GHC accepts this signature,
-- @LookNetPipeline@ is 'SigmaEquivariant' end-to-end, because each Stage
-- instance is σ-equivariant and the boundary types align:
--
-- >   In  L4Core ~ Out L3Encoder = HiddenContext   ✓
-- >   In  L5Decoder ~ Out L4Core = HiddenContext   ✓
--
-- The body is the zero-information runtime witness 'SigmaEquivariantDict' —
-- the theorem is purely about typeability. (Mirrors
-- "SixFour.Spec.Pipeline".@option4Theorem@.)
--
-- The trainer's σ-equivariance obligation for the look-NN: produce per-layer
-- weights such that each layer's individual law
-- ('lawEncoderRefSigmaEquivariance', 'lawCoreRefSigmaEquivariance',
-- 'lawDecoderRefSigmaEquivariance') passes within FP tolerance. This theorem
-- guarantees that if each layer satisfies its own equivariance, the
-- composition does too — no separate end-to-end equivariance regularizer is
-- needed in the loss.
lookNetSigmaTheorem :: Proxy LookNetPipeline -> SigmaEquivariantDict LookNetPipeline
lookNetSigmaTheorem _ = SigmaEquivariantDict

-- =============================================================================
-- Reference baseline (the deterministic pipeline)
-- =============================================================================

-- | The reference pipeline: encode → identity-core → zero-decode. The
-- decoder always emits zeros, so the composition always returns the zero
-- DecoderOutput regardless of input. The /trained/ pipeline is a controlled
-- deviation from this floor.
lookNetReference :: GmmTokenSet -> DecoderOutput
lookNetReference = step @LookNetPipeline

-- =============================================================================
-- Laws
-- =============================================================================

-- | The composition typechecks (a runtime witness for the type-level proof).
-- True by construction — if this expression compiles, the law holds.
lawPipelineComposes :: Bool
lawPipelineComposes = case lookNetSigmaTheorem (Proxy :: Proxy LookNetPipeline) of
  SigmaEquivariantDict -> True

-- | The reference pipeline is the zero map for any input.
lawLookNetReferenceIsZero :: GmmTokenSet -> Bool
lawLookNetReferenceIsZero s =
  let DecoderOutput (Tensor1 v) = lookNetReference s
  in U.length v == 384 && U.all (== 0.0) v
