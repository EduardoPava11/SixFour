module Properties.PaintOrderPrior (tests) where

import Test.Tasty
import Test.Tasty.QuickCheck

import SixFour.Spec.CellNudge (CellBudget)
import SixFour.Spec.PaintOrderPrior

-- Deliberately-WRONG magnitude-only policy: reads the CellBudget, discards the order.
-- This is exactly what the permutation-pair keystone must structurally forbid.
packetsMagnitudeOnly :: CellBudget -> TouchOrder -> CellIx -> Int
packetsMagnitudeOnly bud _order c
  | c < 0 || c >= length bud = 0
  | otherwise                = min ceilingRank (sum (bud !! c))

-- A touched budget over n cells (each cell carries a unit budget => cellTouchedInBudget True).
touchedBudget :: Int -> CellBudget
touchedBudget n = replicate n [1]

-- Random valid order and permutation over n cells.
genSized :: Gen (Int, TouchOrder, Perm, CellBudget)
genSized = do
  n <- choose (2, 6)
  order <- shuffle [0 .. n-1]
  pperm <- shuffle [0 .. n-1]
  pure (n, order, pperm, touchedBudget n)

tests :: TestTree
tests = testGroup "PaintOrderPrior (paint order seeds the halting prior; magnitude-only is forbidden)"
  [ testProperty "A7 ceiling is 7 and paletteDepth is 8 (rung ladder constants)" $
      once (ceilingRank == 7)

  , testProperty "swap witness: order [0,1] vs [1,0] gives SWAPPED depths (correct policy)" $
      once ( packetsAboveFloor (touchedBudget 2) [0,1] 0 > packetsAboveFloor (touchedBudget 2) [0,1] 1
           && packetsAboveFloor (touchedBudget 2) [1,0] 1 > packetsAboveFloor (touchedBudget 2) [1,0] 0 )

  , testProperty "KEYSTONE: the correct rank policy tracks permuted rank (deterministic witness)" $
      once (lawPaintOrderTracksRankUnderPermutation packetsAboveFloor [0,1,2,3] [3,2,1,0] (touchedBudget 4))

  , testProperty "NON-VACUITY: the magnitude-only policy FAILS the permutation keystone" $
      once (not (lawPaintOrderTracksRankUnderPermutation packetsMagnitudeOnly [0,1,2,3] [3,2,1,0] (touchedBudget 4)))

  , testProperty "KEYSTONE holds for the correct policy over random valid (order, perm)" $
      forAll genSized $ \(_,order,pperm,bud) ->
        lawPaintOrderTracksRankUnderPermutation packetsAboveFloor order pperm bud

  , testProperty "earlier touch reads >= depth (composes with lawLowerHaltRefinesMore)" $
      forAll (choose (1,6) >>= \n -> shuffle [0..n-1]) lawEarlierTouchReadsDeeper

  , testProperty "packets are conserved under permutation (reallocated, never inflated)" $
      forAll genSized $ \(_,order,pperm,bud) -> lawPacketBudgetConserved order pperm bud

  , testProperty "an untouched cell halts at the floor (lambda_p=1.0, 0 packets)" $
      once (lawUnpaintedHaltsAtFloor [0,1,2] 999 (touchedBudget 3))
  ]
