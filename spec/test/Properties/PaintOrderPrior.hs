module Properties.PaintOrderPrior (tests) where

import Data.List (elemIndex)

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

-- Random valid order and permutation over n cells (small regime, all cells painted).
genSized :: Gen (Int, TouchOrder, Perm, CellBudget)
genSized = do
  n <- choose (2, 6)
  order <- shuffle [0 .. n-1]
  pperm <- shuffle [0 .. n-1]
  pure (n, order, pperm, touchedBudget n)

-- | The REALISTIC regime the audit (2026-07-03, finding G5) showed was never tested:
-- n past BOTH rank boundaries (ceilingRank = 7 packets saturate to 0, paletteDepth = 8
-- flips the keystone's strict arm to its order-preserving tie arm), with a MIXED budget.
-- The touch order lists exactly the painted cells (first-touch order derives from the
-- paint, so a cell in the order with zero budget is an inconsistent state, not a test
-- case); the remaining cells are untouched: zero budget AND absent from the order.
genRealistic :: Gen (Int, TouchOrder, Perm, CellBudget)
genRealistic = do
  n <- choose (10, 16)
  -- Biased into the boundary regime: ~90% of orders are longer than paletteDepth
  -- (k >= 9, exercising the tie arm and packet saturation), with k <= n-1 so at
  -- least one genuinely untouched cell always exists; ~10% stay short for contrast.
  k <- frequency [(9, choose (9, n-1)), (1, choose (2, 8))]
  cells <- shuffle [0 .. n-1]
  let painted = take k cells
  order <- shuffle painted
  pperm <- shuffle [0 .. k-1]
  vals  <- vectorOf k (choose (1, 9))
  let bud = [ [ maybe 0 (vals !!) (elemIndex c painted) ] | c <- [0 .. n-1] ]
  pure (n, order, pperm, bud)

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

  , testProperty "NON-VACUITY AT SCALE: magnitude-only FAILS with ranks past the paletteDepth boundary (n=10)" $
      once (not (lawPaintOrderTracksRankUnderPermutation packetsMagnitudeOnly
                   [0..9] (reverse [0..9]) (touchedBudget 10)))

  , testProperty "KEYSTONE holds for the correct policy over random valid (order, perm)" $
      forAll genSized $ \(_,order,pperm,bud) ->
        lawPaintOrderTracksRankUnderPermutation packetsAboveFloor order pperm bud

  , testProperty "KEYSTONE holds in the REALISTIC regime (n 9..16, mixed budgets, ranks past 7 and 8)" $
      checkCoverage $ forAll genRealistic $ \(n,order,pperm,bud) ->
        cover 80 (length order > 8) "orders with ranks past the paletteDepth tie boundary" $
        cover 80 (n > length order) "budgets with genuinely untouched cells" $
        lawPaintOrderTracksRankUnderPermutation packetsAboveFloor order pperm bud

  , testProperty "CEILING SATURATION: every painted cell at rank >= 7 deploys exactly 0 packets (tie at the floor)" $
      forAll genRealistic $ \(_,order,_,bud) ->
        and [ packetsAboveFloor bud order c == 0
            | (r, c) <- zip [0 ..] order, r >= ceilingRank ]

  , testProperty "earlier touch reads >= depth (composes with lawLowerHaltRefinesMore)" $
      forAll (choose (1,6) >>= \n -> shuffle [0..n-1]) lawEarlierTouchReadsDeeper

  , testProperty "earlier touch reads >= depth PAST the ladder boundaries (n 9..16)" $
      forAll (choose (9,16) >>= \n -> shuffle [0..n-1]) lawEarlierTouchReadsDeeper

  , testProperty "packets are conserved under permutation (reallocated, never inflated)" $
      forAll genSized $ \(_,order,pperm,bud) -> lawPacketBudgetConserved order pperm bud

  , testProperty "packets are conserved under permutation in the REALISTIC regime" $
      forAll genRealistic $ \(_,order,pperm,bud) -> lawPacketBudgetConserved order pperm bud

  , testProperty "an untouched cell halts at the floor (lambda_p=1.0, 0 packets)" $
      once (lawUnpaintedHaltsAtFloor [0,1,2] 999 (touchedBudget 3))

  , testProperty "EVERY cell outside the touch order halts at the floor (quantified over mixed budgets)" $
      forAll genRealistic $ \(n,order,_,bud) ->
        and [ lawUnpaintedHaltsAtFloor order c bud
            | c <- [0 .. n-1], c `notElem` order ]
  ]
