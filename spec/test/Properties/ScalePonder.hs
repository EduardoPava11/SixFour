module Properties.ScalePonder (tests) where

import Test.Tasty
import Test.Tasty.QuickCheck

import SixFour.Spec.ScalePonder

genInt :: Gen Int
genInt = choose (-65536, 65536)

genDepthXs :: Gen (Int, [Int])
genDepthXs = do
  d  <- elements [0, 1, 2]
  xs <- vectorOf (8 ^ d) genInt
  pure (d, xs)

tests :: TestTree
tests = testGroup "ScalePonder (per-scale halting replaces the scalar PonderNet halt)"
  [ testProperty "refine-all is the exact reversible floor (full compute = identity)" $
      forAll genDepthXs (uncurry lawRefineAllIsLossless)

  , testProperty "scalar halt is a contiguous prefix (the retired single stop-depth)" $
      forAll ((,) <$> choose (0, 6) <*> choose (0, 6)) (uncurry lawScalarHaltIsContiguous)

  , testProperty "non-contiguous ponder beats any scalar cutoff (strictly more expressive)" $
      once lawPonderExceedsScalarHalt
  ]
