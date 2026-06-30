module Properties.V21Field (tests) where

import Test.Tasty
import Test.Tasty.QuickCheck

import SixFour.Spec.V21Field

-- Q16-range integers, including negatives (the device regime).
genInt :: Gen Int
genInt = choose (-65536, 65536)

-- A short curve (length 1..12) of Q16 energies. Short keeps the @argmin@/delta laws fast while
-- still exercising ties and negatives.
genCurve :: Gen Curve
genCurve = do
  n  <- choose (1, 12)
  vectorOf n genInt

-- A pair of equal-length curve triples (a BinQ16 pair) plus an in-range level, so the opponent
-- delta law never indexes out of range.
genBinPairLevel :: Gen (BinQ16, BinQ16, Level)
genBinPairLevel = do
  n  <- choose (1, 12)
  let curve = vectorOf n genInt
  v1 <- BinQ16 <$> curve <*> curve <*> curve
  v2 <- BinQ16 <$> curve <*> curve <*> curve
  l  <- choose (0, n - 1)
  pure (v1, v2, l)

genOctant :: Gen [Int]
genOctant = vectorOf 8 genInt

-- A count histogram: 1..12 non-negative counts. Totals stay well under q16One, so the mass face
-- is strictly monotone in the count (the order-duality regime).
genCounts :: Gen [Int]
genCounts = do
  n <- choose (1, 12)
  vectorOf n (choose (0, 200))

tests :: TestTree
tests = testGroup "V21Field (pre-collapse curves -> GIF89a byte; byte-exact core)"
  [ testProperty "collapse is argmin energy at the lowest index" $
      forAll genCurve lawCollapseIsArgmin

  , testProperty "opponent commutes with the neighbour delta (encode-deltas licence)" $
      forAll genBinPairLevel (\(v1, v2, l) -> lawOpponentCommutesWithDelta v1 v2 l)

  , testProperty "x,y linear to each other; t weighted at the per-frame palette delta" $
      forAll genInt lawXyLinearTimeWeighted

  , testProperty "octant spine round-trips exactly (reuses OctreeCell): unlift . lift = id" $
      forAll genOctant lawOctantLiftReversible

  , testProperty "coarse is the floored-mean lineage, bounded in [min,max] (not a sum-DC)" $
      forAll genOctant lawOctantCoarseBounded

  , testProperty "S barred on the reversible floor (equal children -> zero residual band)" $
      forAll genInt lawSBarredOnFloor

  , testProperty "PonderNet read-depth is well-founded (halts on band bottom)" $
      once lawReadDepthWellFounded

  , -- golden pin: collapse of a fixed curve (cross-language reproducible). Min energy 2 at index 3.
    testProperty "golden: collapseQ16 [9,5,7,2,8,2] = 3 (lowest-index tie-break)" $
      once (collapseQ16 [9, 5, 7, 2, 8, 2] == 3)

  , -- golden pin: the opponent transform on a fixed colour, matching the V2 latent arithmetic.
    testProperty "golden: opponentI (200,50,10) = (260,150,230)" $
      once (opponentI (200, 50, 10) == (260, 150, 230))

  , testProperty "mass face IS the existing board algorithm (round-half-up Q16 goldens)" $
      once lawMassMatchesBoardAlgo

  , testProperty "collapse of the energy face is the histogram MODE (captured-bin curve model)" $
      forAll genCounts lawCollapseEnergyIsMode

  , testProperty "energy face and mass face are order-dual (argmin E = argmax p) in the Q16 regime" $
      forAll genCounts lawEnergyMassOrderDual

  , testProperty "make_bins accumulate: every fine sample counted once (total preserved)" $
      once lawHistTotalPreserved

  , testProperty "make_bins accumulate: each cell histogram sums to the decimation cell size" $
      once lawHistCellSumsToCellSize

  , testProperty "make_bins accumulate: a uniform fine cell collapses to a spike histogram" $
      once lawHistUniformIsSpike

  , testProperty "deploy round-trip: centering monotone (collapse unchanged) + int<->float seam exact" $
      forAll genCounts lawCenteredEnergyDeployRoundTrips

  , testProperty "encoder input withholds the mode: modeRelative pins argmin to relative-0" $
      forAll genCounts lawModeRelativeWithholdsMode

  , testProperty "non-redundant (witnessed): distinct GIF modes share one field input" $
      once lawModeIsNotAFunctionOfField

  , testProperty "field + GIF reconstruct the field: anchorAt mode (modeRelative e) = centeredEnergy e" $
      forAll genCounts lawFieldPlusGifReconstructs

  , testProperty "vector no-leak: held detail band not determined by the context modes (the GIF)" $
      once lawTargetNotDeterminedByGifModes
  ]
