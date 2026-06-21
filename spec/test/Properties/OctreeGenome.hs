module Properties.OctreeGenome (tests) where

import Test.Tasty
import Test.Tasty.QuickCheck

import SixFour.Spec.OctreeGenome

genInt :: Gen Int
genInt = choose (-65536, 65536)

genDepthXs :: Gen (Int, [Int])
genDepthXs = do
  d  <- elements [0, 1, 2]
  xs <- vectorOf (octreeLeafCount d) genInt
  pure (d, xs)

tests :: TestTree
tests = testGroup "OctreeGenome (bijective octant code; law-pinned counts; zero-genome=floor)"
  [ testProperty "genome round-trips: paletteOf . genomeOf = id" $
      forAll genDepthXs (uncurry lawGenomeRoundTrip)

  , testProperty "leaf count = 8^d" $
      forAll (choose (0, 6)) lawLeafCount

  , testProperty "node count = geometric sum 8^0+...+8^(d-1) = (8^d-1)/7" $
      forAll (choose (0, 6)) lawNodeCountGeometric

  , testProperty "distilling a constant cube has zero detail" $
      forAll ((,) <$> choose (0, 3) <*> genInt) (uncurry lawConstantHasZeroDetail)

  , testProperty "zero-genome == floor: zero detail reconstructs the constant" $
      forAll ((,) <$> choose (0, 3) <*> genInt) (uncurry lawZeroGenomeIsFloor)

  , -- golden pin: octree dims at depth 2 (the rung-gap shape)
    testProperty "golden: octreeLeafCount 2 = 64, octreeNodeCount 2 = 9" $
      once (octreeLeafCount 2 == 64 && octreeNodeCount 2 == 9)
  ]
