module Properties.VoxelReduce (tests) where

import Test.Tasty
import Test.Tasty.QuickCheck

import SixFour.Spec.VoxelReduce

genVal :: Gen Int
genVal = choose (-1000, 1000)

genOKLab :: Gen (Int, Int, Int)
genOKLab = (,,) <$> genVal <*> genVal <*> genVal

-- (levels, side, frames) with side and frames small multiples of 2^levels, so the round-trip
-- reference is cheap.
genDims :: Gen (Int, Int, Int)
genDims = do
  levels <- choose (0, 2)
  let m = 2 ^ levels
  sk <- choose (1, 3)
  fk <- choose (1, 3)
  pure (levels, m * sk, m * fk)

genCube :: Int -> Int -> Gen [[(Int, Int, Int)]]
genCube side frames = vectorOf frames (vectorOf (side * side) genOKLab)

-- A FIXED 4³ cube (side=4 → 16 positions, frames=4) — the cross-language round-trip anchor.
goldenCube :: [[(Int, Int, Int)]]
goldenCube =
  [ [ ( (i * 7 + f * 13) `mod` 200 - 100
      , (i * 5 + f * 3 ) `mod` 200 - 100
      , (i * 11 + f * 2) `mod` 200 - 100 )
    | i <- [0 .. 15] ]
  | f <- [0 .. 3] ]

tests :: TestTree
tests = testGroup "VoxelReduce (joint spatio-temporal (2×2)×(2×2)→1, 64³ <-> 16³ reversible)"
  [ testProperty "BIJECTIVE (EXACT): voxelExpand . voxelReduce = id within captured resolution" $
      forAll genDims $ \(levels, side, frames) ->
        forAll (genCube side frames) (lawVoxelReduceBijective levels side frames)

  , testProperty "substrate shape = (frames/2^levels) frames × (side/2^levels)²" $
      forAll genDims $ \(levels, side, frames) ->
        forAll (genCube side frames) (lawVoxelSubstrateShape levels side frames)

  , testProperty "deterministic (pure integer construction)" $
      forAll genDims $ \(levels, side, frames) ->
        forAll (genCube side frames) $ \cube ->
          lawVoxelReduceDeterministic levels side cube

  , testProperty "GOLDEN: round-trip recovers the fixed 4³ cube exactly (levels=1)" $
      once (voxelExpand 1 4 (voxelReduce 1 4 goldenCube) == goldenCube)

  , testProperty "GOLDEN: round-trip recovers the fixed 4³ cube exactly (levels=2)" $
      once (voxelExpand 2 4 (voxelReduce 2 4 goldenCube) == goldenCube)
  ]
