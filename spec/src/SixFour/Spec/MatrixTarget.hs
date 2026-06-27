{- |
Module      : SixFour.Spec.MatrixTarget
Description : The HOLISTIC target object of the full-matrix H-JEPA: the whole 9-channel ChannelProduct matrix at the held scale/frame, predicted in one shot (never a masked pair). RANK-1 HONEST: "SixFour.Spec.ChannelProduct" @lawComparisonIsSeparable@ makes the matrix rank 1, so its real degrees of freedom are the SIX-dimensional P6 generator @(colorVec, spaceVec)@, not nine free numbers. The holism is therefore the value-by-content COUPLING (you must read colour and space jointly), not extra DOF — and the loss is measured on the full matrix (so the off-diagonal chroma-by-space cells count), NOT just the L row.

KEYSTONE 'lawMatrixLossSeesOffDiagonal': a prediction that differs from the target ONLY in chroma is
INVISIBLE to the L-row loss ('lRowLoss', the L-anchored model's view) but VISIBLE to the full matrix
loss ('matrixSqLoss'). So fitting the whole matrix forces learning chroma, which the L-anchored target
could ignore (the formal core of the band-at-floor result). 'lawGeneratorIsSixNotNine' keeps the
rank-1 honesty explicit. Builds on "SixFour.Spec.ChannelProduct" + "SixFour.Spec.HeldOutTarget";
pure-spec, emits no golden.
-}
-- COMPARTMENT: PURE-SPEC-WALL | tag:none
module SixFour.Spec.MatrixTarget
  ( targetMatrix
  , matrixSqLoss
  , lRowLoss
  , lawMatrixTargetIsRank1
  , lawGeneratorIsSixNotNine
  , lawTargetIsFullMatrixNotMaskedPair
  , lawMatrixLossSeesOffDiagonal
  ) where

import SixFour.Spec.DualCube       (P6(..))
import SixFour.Spec.XYTLabDuality  (Chroma(L))
import SixFour.Spec.ChannelProduct
  ( compareMatrix, comparePair, colorVec, spaceVec
  , lawComparisonIsSeparable, lawComparisonIsOuterProduct )

-- | The held target: the full 9-channel comparison matrix of the held object.
targetMatrix :: P6 -> [[Integer]]
targetMatrix = compareMatrix

-- | The holistic loss: summed squared error over ALL nine matrix cells (so the off-diagonal
-- chroma-by-space comparisons are part of the objective, not just the L row).
matrixSqLoss :: P6 -> P6 -> Integer
matrixSqLoss predP tgtP =
  sum [ (a - b) * (a - b)
      | (ra, rb) <- zip (compareMatrix predP) (compareMatrix tgtP)
      , (a, b)   <- zip ra rb ]

-- | The L-ANCHORED loss for contrast: squared error over only the @L@ row of comparisons (what a
-- model that anchors on L would minimize). Blind to chroma differences.
lRowLoss :: P6 -> P6 -> Integer
lRowLoss predP tgtP =
  sum [ (comparePair predP (L, s) - comparePair tgtP (L, s)) ^ (2 :: Int)
      | s <- [minBound .. maxBound] ]

-- | The target matrix is RANK 1 (separable value x content) — reuses
-- "SixFour.Spec.ChannelProduct" @lawComparisonIsSeparable@. The honesty anchor for the loss design.
lawMatrixTargetIsRank1 :: P6 -> Bool
lawMatrixTargetIsRank1 = lawComparisonIsSeparable

-- | The real degrees of freedom are SIX (the P6 generator: 3 colour + 3 space), and those six
-- determine all nine matrix cells (the outer product). So "full matrix" is value x content coupling,
-- not nine free numbers.
lawGeneratorIsSixNotNine :: P6 -> Bool
lawGeneratorIsSixNotNine p =
  length (colorVec p) + length (spaceVec p) == 6
  && lawComparisonIsOuterProduct p

-- | The target is the WHOLE nine-cell matrix, predicted in one shot, not one masked pair.
lawTargetIsFullMatrixNotMaskedPair :: P6 -> Bool
lawTargetIsFullMatrixNotMaskedPair p = length (concat (targetMatrix p)) == 9

-- | THE KEYSTONE: a prediction differing from the target ONLY in chroma @(a,b)@ is invisible to the
-- L-row loss (zero) but visible to the full matrix loss (positive). So the holistic matrix objective
-- forces learning chroma that the L-anchored objective could leave at the floor.
lawMatrixLossSeesOffDiagonal :: Bool
lawMatrixLossSeesOffDiagonal =
  let tgtP  = P6 5 1 2 3 4 6
      predP = P6 5 9 8 3 4 6      -- same L, x, y, t; chroma a, b differ
  in lRowLoss predP tgtP == 0 && matrixSqLoss predP tgtP > 0
