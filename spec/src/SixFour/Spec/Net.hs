{- |
Module      : SixFour.Spec.Net
Description : The NN-organ slot contract — @metric@ and @look@.

A single slot has a *trainer* in this repo and a *consumer* on-device:

  * @NetSlotMetric@ — a 3×3 PSD distance learned by
    @trainer/train_metric.py@, encoded as the 6 upper-triangle floats
    of @M = L Lᵀ@, loaded by @SixFour/Organs/MetricOrgan.swift@.

  * @NetSlotLook@ — the look-NN (E :> R :> D, σ-equivariant). Trained by the
    MLX path (@trainer/generated/look_net_mlx.py@), consumed on-device by the
    hand-written Swift/Zig forward pass (weights shipped via the deploy blob,
    @trainer/export_look_net_blob.py@). Maps a set of 10-D GMM tokens to the
    384 SigmaPairTree coefficients (= @SIGMA_PAIR_DOF@), reconstructed into the
    256-leaf σ-pair palette. The aux dims (@MODEL_DIM@, @CORE_DEPTH@,
    @SIGMA_PAIR_LEAVES@, @MAX_TOKENS@) pin the rest of the model shape.

Previous revisions reserved 'NetSlotMerger' (a learned Stage B replacement)
and 'NetSlotEmbedder' (a post-pipeline look encoder). Both were dropped:
no trainer in this repo emits files for them and no consumer reads them.
Per the project rule \"no stubs — fully working and tested code only\",
the slots return when their trainers do.

The on-device estimator @θ̂@ (@spec/MATH.md §5@) is acknowledged in MATH.md
as a future workstream; it has no slot here because it has no producer.
-}
-- COMPARTMENT: MLX-MODEL | tag:MacTag | STRADDLER
module SixFour.Spec.Net
  ( NetSlot(..)
  , NetIO(..)
  , slotMetricDims
  , slotLookDims
  , metricPSDUpperTriangleCount
  ) where

import SixFour.Spec.GMM          (gmmTokenDim)
import SixFour.Spec.Tensor       (hiddenDim)
import SixFour.Spec.Shape        (tVal, kVal)
import SixFour.Spec.LookNetR     (coreDepth)
import SixFour.Spec.SigmaPairHead (sigmaPairDegreesOfFreedom, sigmaPairLeaves)

-- | Tag for which slot a model targets. Sized to what exists today.
data NetSlot
  = NetSlotMetric    -- ^ Stage A perceptual distance
  | NetSlotLook      -- ^ The look-NN (tokens → σ-pair palette coefficients)
  deriving (Eq, Show, Read, Enum, Bounded)

-- | Generic NN I/O signature. @netAuxDims@ carries any extra named shape
-- constants a slot needs beyond the (input, output) pair — e.g. the look-NN's
-- @MODEL_DIM@ / @CORE_DEPTH@ / @SIGMA_PAIR_LEAVES@ / @MAX_TOKENS@. It is empty
-- for the simple per-layer / metric signatures.
data NetIO = NetIO
  { netInputDim    :: !Int
  , netOutputDim   :: !Int
  , netAuxDims     :: ![(String, Int)]
  , netDescription :: !String
  } deriving (Eq, Show)

-- | The 'NetSlotMetric' file is a 6-float vector — the upper triangle of
-- the 3×3 PSD matrix @M = L Lᵀ@. Loaded by 'MetricOrgan.swift' (which
-- reflects it into 'LearnedPSDMetric') and produced by
-- 'trainer/train_metric.py' (which trains @L@ via Cholesky parameterisation).
metricPSDUpperTriangleCount :: Int
metricPSDUpperTriangleCount = 6

-- | Per-frame metric polish: 6 PSD upper-triangle floats; consumed by
-- 'KMeansLab.run' through the generic 'DistanceMetric' specialisation.
slotMetricDims :: NetIO
slotMetricDims = NetIO
  { netInputDim    = metricPSDUpperTriangleCount
  , netOutputDim   = 0
  , netAuxDims     = []
  , netDescription = "Stage-A learned PSD metric (3x3 M = L Lᵀ via Cholesky; 6 upper-triangle floats)"
  }

-- | The look-NN slot: a set of @GMM_TOKEN_DIM=10@ tokens → @SIGMA_PAIR_DOF=384@
-- SigmaPairTree coefficients. The aux dims pin the rest of the model shape so
-- the registry fully describes what the MLX trainer emits and the hand-written
-- on-device forward pass loads (see 'trainer/export_look_net_blob.py').
slotLookDims :: NetIO
slotLookDims = NetIO
  { netInputDim    = gmmTokenDim                  -- 10
  , netOutputDim   = sigmaPairDegreesOfFreedom    -- 384 = SIGMA_PAIR_DOF
  , netAuxDims     =
      [ ("MODEL_DIM",         hiddenDim)          -- 64 (= modelDim; the σ-decomposition width)
      , ("CORE_DEPTH",        coreDepth)          -- 8
      , ("SIGMA_PAIR_LEAVES", sigmaPairLeaves)    -- 256 = K
      , ("MAX_TOKENS",        tVal * kVal)        -- 16384 = T·K = maxTokens
      ]
  , netDescription = "look-NN E:>R:>D: GMM_TOKEN_DIM tokens -> SIGMA_PAIR_DOF SigmaPairTree coeffs (sigma-equivariant; reconstructs 256-leaf palette)"
  }
