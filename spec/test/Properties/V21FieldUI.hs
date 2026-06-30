module Properties.V21FieldUI (tests) where

import Test.Tasty
import Test.Tasty.QuickCheck

import SixFour.Spec.V21FieldUI

-- A region with small coordinates, so 'sane' yields a small box and 'budgetCells' stays fast (the
-- recursion floor is one voxel, so a small region bounds the leaf count).
genRegion :: Gen Region
genRegion = do
  let axis = do lo <- choose (0, 7); ext <- choose (0, 7); pure (lo, lo + ext)
  Region <$> axis <*> axis <*> axis

-- A modest cell budget (includes 0 and 1, the recursion edges).
genBudget :: Gen Int
genBudget = choose (0, 96)

-- A count histogram (1..10 non-negative counts), the 'disagree' domain.
genCounts :: Gen [Int]
genCounts = do
  n <- choose (1, 10)
  vectorOf n (choose (0, 50))

-- A widget set: 0..6 widgets, each a (saliency, mortonKey) pair.
genWidgets :: Gen [(Int, Int)]
genWidgets = do
  k <- choose (0, 6)
  vectorOf k ((,) <$> choose (0, 100) <*> choose (0, 4095))

-- A total budget that comfortably clears the opposition floor for up to 6 widgets (6*5/2 = 15), plus
-- some small values so the infeasible fallback is also exercised.
genWidgetTotal :: Gen Int
genWidgetTotal = oneof [choose (0, 12), choose (15, 200)]

tests :: TestTree
tests = testGroup "V21FieldUI (the cell-count layer: budget + widget opposition)"
  [ testProperty "apportion conserves the budget at a single split" $
      forAll genBudget $ \t -> forAll (listOf (choose (0, 20))) (lawApportionConserves t)

  , testProperty "budgetCells conserves: every cell lands in exactly one plot" $
      forAll genRegion $ \r -> forAll genBudget (lawBudgetConserves r)

  , testProperty "budgetCells is grid-aligned: plots are aligned sub-regions with positive cells" $
      forAll genRegion $ \r -> forAll genBudget (lawBudgetGridAligned r)

  , testProperty "disagree is zero on a spike, positive on spread (saliency twin of UniformIsSpike)" $
      forAll genCounts lawDisagreeZeroOnSpike

  , testProperty "widget budget partitions: per-widget counts sum to the total" $
      forAll genWidgetTotal $ \t -> forAll genWidgets (lawWidgetBudgetPartitions t)

  , testProperty "widgets OPPOSE equal counts: feasible budget gives pairwise-distinct counts" $
      forAll genWidgetTotal $ \t -> forAll genWidgets (lawWidgetsOpposeEqualCounts t)

  , testProperty "opposition floor: distinct iff total >= k(k-1)/2; tight staircase at the floor" $
      once lawWidgetOppositionFloor

  , testProperty "saliency orders the budget: the most uncertain widget owns the most cells" $
      once lawWidgetSalienceOrders
  ]
