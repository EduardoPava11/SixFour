module Properties.NudgeRankTheorem (tests) where

import Test.Tasty
import Test.Tasty.QuickCheck

import SixFour.Spec.NudgeRankTheorem

tests :: TestTree
tests = testGroup "NudgeRankTheorem (rank / collapse / residual-reuse — three hypotheses as theorems)"
  [ testGroup "H1 RANK"
    [ testProperty "single voxel comparison matrix is rank <= 1 (all 2x2 minors 0)"
        lawSingleVoxelRank1
    , testProperty "cell aggregate reaches full rank 3 (det != 0, 9 independent entries)"
        lawCellAggregateReachesRank3
    , testProperty "9 channels independent at the CELL, degenerate at the VOXEL"
        lawNineIndependentAtCellNotVoxel
    , testProperty "held-out loss must be the cell-aggregate, not per-voxel rank-1"
        lawHeldOutLossIsCellAggregateNotPerVoxel
    ]
  , testGroup "H2 COLLAPSE"
    [ testProperty "octant axes ARE space-time (liftQuad x2 + sLift factorization)"
        lawOctantAxesAreSpaceTime
    , testProperty "colour is the lifted value (three independent liftOct passes)"
        lawColourIsTheLiftedValue
    , testProperty "two levels collapse space-time /4, colour rides through lossless"
        lawTwoLevelsCollapseSpaceTimeNotColour
    , testProperty "BOTH levels mixed space-time (refutes one-spatial-one-temporal)"
        lawBothLevelsAreMixedSpaceTime
    , testProperty "value/collapsed split is a phi6 GAUGE (refutes intrinsic colour)"
        lawValueSplitIsPhi6Gauge
    ]
  , testGroup "H3 RESIDUAL REUSE"
    [ testProperty "down and up residual are the SAME type + SAME operator"
        lawResidualTypeScaleInvariant
    , testProperty "residual is A7 = ker Sigma at every level"
        lawResidualIsA7AtEveryLevel
    , testProperty "down residual is a legit conditioning seed (richer than zero floor)"
        lawDownResidualConditionsUpInvention
    , testProperty "BOUNDARY: down residual is NOT up ground truth (refutes copy)"
        lawDownResidualIsNotUpGroundTruth
    ]
  ]
