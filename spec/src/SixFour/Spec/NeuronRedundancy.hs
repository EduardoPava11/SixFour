{- |
Module      : SixFour.Spec.NeuronRedundancy
Description : REDUNDANCY of the intermediate-latent neuron outputs — the WITHIN-ONE-LATENT VICReg covariance (decorrelation) term on the non-surfaced level (the 32³ of a 64³→[32³]→16³ rung, the 128³ of 64³→[128³]→256³). One view only; the CROSS-view 32³:128³ objective is a separate pairing (cross-prediction + this term as its covariance guard). Self-supervised pressure on the one representation the net controls; must be measured in LATENT space, before surfacing.

A RUNG is the @(2×2):(2×2)→1 + residual@ transform between two /real/ levels, passing
through an INTERMEDIATE that never surfaces:

  * rung A: @64³ → [32³] → 16³ + residual@
  * rung B: @256³ → [128³] → 64³ + residual@   (self-similar — same operator,
    "SixFour.Spec.MaskedBandPrediction" @lawMaskedReusesOnBothRungs@)

The endpoints (@64³@, @16³@) are FIXED by the data; the intermediate (@32³@, @128³@) is the
ONLY level the network is free to organise. It is not "real" — it lives as a latent
NEURON-OUTPUT representation, never a committed cube. So it is exactly where the
self-supervised objective of /efficient coding/ applies: minimise the REDUNDANCY of the
neuron outputs, so each neuron carries information no other neuron already carries.

== The measure (VICReg covariance / decorrelation — one view, not cross-view Barlow)

Over a batch of samples, each a vector of neuron outputs, form the per-neuron columns and
their Pearson cross-correlations. 'crossRedundancy' is the sum of squared OFF-DIAGONAL
correlations — zero iff the neurons are pairwise decorrelated (the identity
cross-correlation matrix Barlow Twins drives toward; VICReg's covariance term is the same
idea). This is information-theoretic redundancy's second-order surrogate; the per-band
Shannon view lives in "SixFour.Spec.DetailEntropy".

  * 'lawIdenticalNeuronsAreFullyRedundant' — two neurons with identical (varying) outputs
    correlate at 1, contributing ≈ 1 to the redundancy. Teeth: a measure blind to
    duplicate neurons fails.
  * 'lawDecorrelatedNeuronsZeroRedundancy' — orthogonal zero-mean neurons contribute ≈ 0.
    Teeth: a measure that flagged decorrelated neurons as redundant fails.
  * 'lawRedundancyMeasuredInLatent' — surfacing (the @reenterQ16@ crossing) can DESTROY the
    redundancy signal: a sub-quantum-correlated batch reads as redundant in latent space but
    collapses once rounded to integers. So redundancy MUST be read on the intermediate
    latent, before surfacing — the same sub-quantum argument as
    "SixFour.Spec.DeferredSurfacing". Teeth: a measure taken post-surfacing would miss it.

Additive: a self-contained second-order statistic over @[[Double]]@ neuron batches; the
only repo coupling is "SixFour.Spec.ByteCarrier" (the surfacing seam, for the latent-vs-
surfaced law). Re-pins NOTHING; GHC-boot-only. Laws QuickCheck'd in
"Properties.NeuronRedundancy".
-}
-- COMPARTMENT: MLX-MODEL | tag:MacTag
module SixFour.Spec.NeuronRedundancy
  ( -- * The intermediate-latent neuron batch
    NeuronBatch
  , neuronColumns
  , validBatch
    -- * Second-order statistics
  , meanOf
  , varianceOf
  , correlationOf
    -- * The redundancy measure
  , crossRedundancy
  , surfaceColumn
    -- * Laws (QuickCheck'd in @Properties.NeuronRedundancy@)
  , lawRedundancyNonNegative
  , lawIdenticalNeuronsAreFullyRedundant
  , lawDecorrelatedNeuronsZeroRedundancy
  , lawRedundancyMeasuredInLatent
  ) where

import Data.List (transpose)

import SixFour.Spec.ByteCarrier (mkLatent, reenterQ16, toByte)

-- | A batch of intermediate-latent samples: outer list = samples, inner list = the neuron
-- outputs of that sample (the @32³@\/@128³@ coefficients). Rectangular when well-formed.
type NeuronBatch = [[Double]]

-- | The per-NEURON columns of a batch (transpose): each column is one neuron's outputs
-- across the whole batch — the series the cross-correlation is computed over.
neuronColumns :: NeuronBatch -> [[Double]]
neuronColumns = transpose

-- | A batch is well-formed for the measure: at least two samples (so variance is defined)
-- and rectangular (every sample has the same neuron count, at least one).
validBatch :: NeuronBatch -> Bool
validBatch rows =
     length rows >= 2
  && not (null (head rows))
  && all ((== length (head rows)) . length) rows

-- | The mean of a series (0 for the empty series).
meanOf :: [Double] -> Double
meanOf [] = 0
meanOf xs = sum xs / fromIntegral (length xs)

-- | The (population) variance of a series.
varianceOf :: [Double] -> Double
varianceOf xs =
  let m = meanOf xs
  in meanOf [ (x - m) * (x - m) | x <- xs ]

-- | The Pearson correlation of two series. A constant series (zero variance) carries no
-- information and is treated as decorrelated from everything (correlation 0), so it adds
-- no redundancy rather than dividing by zero.
correlationOf :: [Double] -> [Double] -> Double
correlationOf xs ys =
  let mx = meanOf xs
      my = meanOf ys
      cov = meanOf (zipWith (\x y -> (x - mx) * (y - my)) xs ys)
      vx = varianceOf xs
      vy = varianceOf ys
  in if vx <= 0 || vy <= 0 then 0 else cov / sqrt (vx * vy)

-- | THE redundancy measure: the sum of squared OFF-DIAGONAL cross-correlations of the
-- neuron columns (each unordered pair once). Zero iff the neurons are pairwise
-- decorrelated — the identity cross-correlation matrix Barlow Twins minimises toward. This
-- is the self-supervised efficiency pressure on the intermediate latent.
crossRedundancy :: NeuronBatch -> Double
crossRedundancy batch =
  let cols = neuronColumns batch
      n    = length cols
  in sum [ let c = correlationOf (cols !! i) (cols !! j) in c * c
         | i <- [0 .. n - 1], j <- [i + 1 .. n - 1] ]

-- | Surface a latent neuron column through the single sanctioned @reenterQ16@ crossing
-- ("SixFour.Spec.ByteCarrier") — the integer the level WOULD commit to if it were made
-- real. Used only to witness that redundancy must be read BEFORE this crossing
-- ('lawRedundancyMeasuredInLatent'); the intermediate latent is never actually surfaced.
surfaceColumn :: [Double] -> [Double]
surfaceColumn = map (fromIntegral . toByte . reenterQ16 . mkLatent)

-- ============================================================================
-- Laws (predicates; QuickCheck'd in Properties.NeuronRedundancy)
-- ============================================================================

-- | Redundancy is a sum of squares, hence never negative.
lawRedundancyNonNegative :: NeuronBatch -> Bool
lawRedundancyNonNegative batch = crossRedundancy batch >= -1e-12

-- | TEETH: two neurons with IDENTICAL (and varying) outputs correlate at 1, so the batch's
-- redundancy is at least ≈ 1 — duplicate neurons are maximally redundant. Witness: a
-- two-neuron batch whose columns are the same varying series.
lawIdenticalNeuronsAreFullyRedundant :: Bool
lawIdenticalNeuronsAreFullyRedundant =
  let batch = [[1, 1], [2, 2], [3, 3], [4, 4]]   -- col0 == col1 == [1,2,3,4]
  in crossRedundancy batch >= 1 - 1e-9

-- | TEETH: two ORTHOGONAL zero-mean neurons contribute ≈ 0 redundancy — decorrelated
-- neurons are not redundant. Witness: columns @[1,-1,1,-1]@ and @[1,1,-1,-1]@ (zero mean,
-- zero covariance).
lawDecorrelatedNeuronsZeroRedundancy :: Bool
lawDecorrelatedNeuronsZeroRedundancy =
  let batch = [[1, 1], [-1, 1], [1, -1], [-1, -1]]  -- col0=[1,-1,1,-1], col1=[1,1,-1,-1]
  in crossRedundancy batch <= 1e-9

-- | The measure must be read on the INTERMEDIATE LATENT, before surfacing. A batch whose
-- neurons are correlated only at SUB-QUANTUM scale reads as fully redundant in latent space
-- but collapses to zero once each value is surfaced through @reenterQ16@ (all round to the
-- same byte ⇒ constant columns ⇒ no correlation). So redundancy measured AFTER surfacing
-- would miss it. Teeth: the continuous redundancy strictly exceeds the surfaced one — the
-- same sub-quantum argument as "SixFour.Spec.DeferredSurfacing".
lawRedundancyMeasuredInLatent :: Bool
lawRedundancyMeasuredInLatent =
  let ulp     = 1 / 65536
      col     = [0.1 * ulp, 0.2 * ulp, 0.3 * ulp, 0.4 * ulp]   -- sub-ULP, varying
      batch   = [ [a, a] | a <- col ]                          -- two identical latent neurons
      surfaced = transpose (map surfaceColumn (transpose batch))
  in crossRedundancy batch > crossRedundancy surfaced + 0.5     -- latent ≈1, surfaced ≈0
