module Properties.Export (tests) where

import Test.Tasty
import Test.Tasty.QuickCheck
import Test.QuickCheck

import SixFour.Spec.Export

-- A full side×side grid of distinct-ish Int cells, side ∈ 1..6, factor ∈ 1..4.
genCase :: Gen (Int, Int, [Int])
genCase = do
  side   <- choose (1, 6)
  factor <- choose (1, 4)
  cells  <- vectorOf (side * side) (choose (0, 9))
  pure (factor, side, cells)

tests :: TestTree
tests = testGroup "Export (64→256 index replication, 1→4×4)"
  [ testProperty "output length = (factor·side)²" $
      forAll genCase $ \(f, s, c) -> lawReplicateLength f s c

  , testProperty "replication preserves the used-index set (no new/lost index → opacity)" $
      forAll genCase $ \(f, s, c) -> lawReplicatePreservesUsedSet f s c

  , testProperty "each index's population scales by factor²" $
      forAll genCase $ \(f, s, c) -> lawReplicateCountsScale f s c

  , testProperty "shipping constants: factor=4, source=64, output=256" $
      once $ (upscaleFactor === 4) .&&. (sourceSide === 64) .&&. (outputSide === 256)

  , testProperty "golden: replicate2D 2 2 [10,20,30,40] → 4×4 blocks" $
      once $ replicate2D 2 2 ([10, 20, 30, 40] :: [Int])
               === [ 10, 10, 20, 20
                   , 10, 10, 20, 20
                   , 30, 30, 40, 40
                   , 30, 30, 40, 40 ]
  ]
