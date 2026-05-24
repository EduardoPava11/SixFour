{- |
Module      : SixFour.Spec.Pipeline
Description : End-to-end Stage A ; Stage B composition for one capture burst.

The pipeline takes @T@ frames, runs Stage A on each, then merges via
Stage B. The output carries the 'Surjective256' witness, so any
downstream encoder can rely on "all @K@ palette entries are used"
without re-checking.
-}
module SixFour.Spec.Pipeline
  ( SixFourPipeline(..)
  , defaultPipeline
  , runPipeline
  , PipelineInput(..)
  , PipelineOutput(..)
  ) where

import GHC.TypeLits (Nat, KnownNat)

import SixFour.Spec.StageA
import SixFour.Spec.StageB

-- | Composed pipeline: a Stage A and a Stage B.
data SixFourPipeline (t :: Nat) (h :: Nat) (w :: Nat) (k :: Nat) = SixFourPipeline
  { pipelineStageA :: !(StageA h w k)
  , pipelineStageB :: !(StageB t h w k)
  }

-- | @T@ frames (length-@T@ list); types check the per-frame shape.
data PipelineInput (t :: Nat) (h :: Nat) (w :: Nat) (k :: Nat) = PipelineInput
  { piFrames :: ![Frame h w]
  }

-- | Final per-burst output: global palette, global indices, witness.
type PipelineOutput = StageBOutput

-- | The reference pipeline: variance-cut Stage A + Sinkhorn-balanced Stage B.
defaultPipeline
  :: forall t h w k. (KnownNat t, KnownNat h, KnownNat w, KnownNat k)
  => SixFourPipeline t h w k
defaultPipeline =
  SixFourPipeline
    { pipelineStageA = varianceCutReference
    , pipelineStageB = sinkhornReference defaultSinkhornParams
    }

runPipeline
  :: forall t h w k. (KnownNat t, KnownNat h, KnownNat w, KnownNat k)
  => SixFourPipeline t h w k
  -> PipelineInput t h w k
  -> PipelineOutput t h w k
runPipeline (SixFourPipeline sA sB) (PipelineInput frames) =
  let perFrame = map (runStageA sA) frames
      (pals, ixs) = unzip perFrame
  in runStageB sB (StageBInput pals ixs)
