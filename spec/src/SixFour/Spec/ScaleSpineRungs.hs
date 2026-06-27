{- |
Module      : SixFour.Spec.ScaleSpineRungs
Description : The binding keystone of the Held-Out Full-Matrix H-JEPA: the model has exactly TWO held-out rungs, the SCALE rung (super-res, 64³→256³, Invented) and the TIME rung (temporal, frame t→t+1, Held), which are precisely the two held axes of "SixFour.Spec.HeldOutTarget". Both rungs predict the same holistic object (the full cell-aggregate matrix of "SixFour.Spec.MatrixTarget", scored on the aggregate per "SixFour.Spec.NudgeRankTheorem"), and both run the SAME two-level self-similar octant operator (the twiceness, "SixFour.Spec.SelfSimilarReconstruct" @levelsPerStep@). This ties the held-out target, the matrix object, and the RungPivot spine into one model rather than three loose pieces.

'lawTwoRungsAreTheTwoHeldAxes' (the rungs map onto Scale + Time), 'lawRungTargetIsCellAggregate'
(both score the aggregate, not per-voxel), 'lawBothRungsSelfSimilar' (both are the 2-level twiceness).
Additive, pure-spec, emits no golden.
-}
-- COMPARTMENT: MLX-MODEL | tag:MacTag
module SixFour.Spec.ScaleSpineRungs
  ( HeldRung(..)
  , rungHeldAxis
  , rungIsInvented
  , lawTwoRungsAreTheTwoHeldAxes
  , lawRungTargetIsCellAggregate
  , lawBothRungsSelfSimilar
  , lawScaleInventedTimeHeld
  ) where

import SixFour.Spec.HeldOutTarget          (HeldAxis(..))
import SixFour.Spec.NudgeRankTheorem        (lawHeldOutLossIsCellAggregateNotPerVoxel)
import SixFour.Spec.SelfSimilarReconstruct  (levelsPerStep)

-- | The two H-JEPA rungs, each a held-out direction predicting the full matrix.
data HeldRung = ScaleRung | TimeRung deriving (Eq, Show, Enum, Bounded)

-- | The held axis each rung lives on: the SCALE rung holds out scale (the 256³ detail), the TIME rung
-- holds out time (frame t+1).
rungHeldAxis :: HeldRung -> HeldAxis
rungHeldAxis ScaleRung = Scale
rungHeldAxis TimeRung  = Time

-- | Whether the rung INVENTS (beyond capture) or HOLDS (within capture): the SCALE rung invents the
-- 256³ super-res detail; the TIME rung holds the exact next captured frame.
rungIsInvented :: HeldRung -> Bool
rungIsInvented ScaleRung = True
rungIsInvented TimeRung  = False

-- ---------------------------------------------------------------------------
-- Laws
-- ---------------------------------------------------------------------------

-- | The two rungs ARE exactly the two held axes (Scale and Time): the H-JEPA hierarchy has no third
-- direction, and each held axis is a rung.
lawTwoRungsAreTheTwoHeldAxes :: Bool
lawTwoRungsAreTheTwoHeldAxes =
  map rungHeldAxis [minBound .. maxBound] == [Scale, Time]
  && ([minBound .. maxBound] :: [HeldAxis]) == [Scale, Time]

-- | Both rungs score the holistic CELL-AGGREGATE matrix target, not a per-voxel rank-1 view (delegates
-- "SixFour.Spec.NudgeRankTheorem" -- a chroma-by-space mispairing must cost the loss).
lawRungTargetIsCellAggregate :: Bool
lawRungTargetIsCellAggregate = lawHeldOutLossIsCellAggregateNotPerVoxel

-- | Both rungs run the SAME two-level self-similar octant operator (the twiceness): one reconstruct
-- engine, two directions.
lawBothRungsSelfSimilar :: Bool
lawBothRungsSelfSimilar = levelsPerStep == 2

-- | The Held/Invented split: the SCALE rung invents (beyond capture, 256³), the TIME rung holds (the
-- exact next captured frame). Aligns with RungPivot's Down=Held / Up=Invented vocabulary.
lawScaleInventedTimeHeld :: Bool
lawScaleInventedTimeHeld = rungIsInvented ScaleRung && not (rungIsInvented TimeRung)
