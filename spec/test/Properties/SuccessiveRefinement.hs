module Properties.SuccessiveRefinement (tests) where

import Test.Tasty
import Test.Tasty.QuickCheck

import SixFour.Spec.SuccessiveRefinement

genInt :: Gen Int
genInt = choose (-65536, 65536)

-- A valid cut (k levels) on a depth-d cube (d in {0,1,2}) with a sized cube.
genCut :: Gen (Int, Int, [Int])
genCut = do
  d  <- elements [0, 1, 2]
  k  <- choose (0, d)
  xs <- vectorOf (8 ^ d) genInt
  pure (k, d, xs)

genDepthXs :: Gen (Int, [Int])
genDepthXs = do
  d  <- elements [0, 1, 2]
  xs <- vectorOf (8 ^ d) genInt
  pure (d, xs)

tests :: TestTree
tests = testGroup "SuccessiveRefinement (16^3 surfaced + remainder held; Equitz-Cover)"
  [ testProperty "refine . split = id (the SR code loses nothing)" $
      forAll genCut (\(k, d, xs) -> lawRefineRoundTrip k d xs)

  , testProperty "Markov-by-pooling: surfaced depends only on coarse, not held detail" $
      forAll genCut (\(k, d, xs) -> lawMarkovByPooling k d xs)

  , testProperty "remainder budget = total dims - surfaced dims" $
      forAll genCut (\(k, d, xs) -> lawRemainderRateIsHeld k d xs)

  , testProperty "surfacing everything (cut 0) holds nothing" $
      forAll genDepthXs (uncurry lawFullSurfaceZeroRemainder)

  , -- golden: a 64-voxel cube cut 1 level holds 56 detail dims (64 - 8)
    testProperty "golden: remainderRate (split 1 2 [0..63]) = 56" $
      once (remainderRate (split 1 2 [0 .. 63]) == 56)
  ]
