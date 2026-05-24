{- |
Module      : SixFour.Spec.Net
Description : The NN-organ slot contract — currently only @metric@.

A single slot has a *trainer* in this repo and a *consumer* on-device:

  * @NetSlotMetric@ — a 3×3 PSD distance learned by
    @trainer/train_metric.py@, encoded as the 6 upper-triangle floats
    of @M = L Lᵀ@, loaded by @SixFour/Organs/MetricOrgan.swift@.

Previous revisions reserved 'NetSlotMerger' (a learned Stage B replacement)
and 'NetSlotEmbedder' (a post-pipeline look encoder). Both were dropped:
no trainer in this repo emits files for them and no consumer reads them.
Per the project rule \"no stubs — fully working and tested code only\",
the slots return when their trainers do.

The on-device estimator @θ̂@ (@spec/MATH.md §5@) is acknowledged in MATH.md
as a future workstream; it has no slot here because it has no producer.
-}
module SixFour.Spec.Net
  ( NetSlot(..)
  , NetIO(..)
  , slotMetricDims
  , metricPSDUpperTriangleCount
  ) where

-- | Tag for which slot a model targets. Sized to what exists today.
data NetSlot
  = NetSlotMetric    -- ^ Stage A perceptual distance
  deriving (Eq, Show, Read, Enum, Bounded)

-- | Generic NN I/O signature.
data NetIO = NetIO
  { netInputDim    :: !Int
  , netOutputDim   :: !Int
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
  , netDescription = "Stage-A learned PSD metric (3x3 M = L Lᵀ via Cholesky; 6 upper-triangle floats)"
  }
