module Properties.LocalPonder (tests) where

import Test.Tasty
import Test.Tasty.QuickCheck

import SixFour.Spec.LocalPonder

-- A small octree depth so 8^d cubes stay tiny (d in {0,1,2}).
genCube :: Gen (Int, [Int])
genCube = do
  d  <- elements [0, 1, 2]
  xs <- vectorOf (8 ^ d) (choose (-200, 200))
  pure (d, xs)

genPonder :: Gen [Bool]
genPonder = listOf arbitrary

tests :: TestTree
tests = testGroup "LocalPonder (per-octant adaptive deltas; bits-track-residual via DetailEntropy)"
  [ testProperty "all-True local mask is the exact reversible floor" $
      forAll genCube $ \(d, xs) -> lawRefineAllLocalIsLossless d xs

  , testProperty "per-level Ponder lifted == applyPonder (uniform special case faithful)" $
      forAll genCube $ \(d, xs) -> forAll genPonder $ \ps -> lawLevelUniformSubsumed d xs ps

  , testProperty "per-octant mask keeping one sibling, dropping another is unreachable by any per-level mask" $
      once lawLocalExceedsLevel

  , testProperty "halting a varied level zeroes its coded-bit budget (measured saving)" $
      once lawHaltingALevelZeroesItsBits
  ]
