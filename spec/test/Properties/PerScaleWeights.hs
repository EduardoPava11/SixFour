module Properties.PerScaleWeights (tests) where

import Test.Tasty
import Test.Tasty.QuickCheck

import SixFour.Spec.PerScaleWeights

genInt :: Gen Int
genInt = choose (-65536, 65536)

-- A depth in {0,1,2} with a matching flat voxel list of length 8^depth.
genDepthXs :: Gen (Int, [Int])
genDepthXs = do
  d  <- elements [0, 1, 2]
  xs <- vectorOf (8 ^ d) genInt
  pure (d, xs)

tests :: TestTree
tests = testGroup "PerScaleWeights (per-scale octree weights replace the tied block)"
  [ testProperty "neutral (all-1) weighting is the exact reversible floor" $
      forAll genDepthXs (uncurry lawNeutralIsFloor)

  , testProperty "tied design is the all-equal special case of per-scale weights" $
      forAll ((,) <$> choose (0, 6) <*> genInt) (uncurry lawTiedSubsumed)

  , testProperty "per-scale [1,3] is unreachable by any tied weight (strictly more expressive)" $
      once lawPerScaleExceedsTied
  ]
