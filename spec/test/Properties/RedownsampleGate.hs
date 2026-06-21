module Properties.RedownsampleGate (tests) where

import Test.Tasty
import Test.Tasty.QuickCheck

import SixFour.Spec.RedownsampleGate

genI :: Gen Int
genI = choose (-256, 256)

-- a fine cube of depth d (8^d voxels) plus a valid (k, d) gate pair
genGate :: Gen (Int, Int, [Int])
genGate = do
  d  <- elements [1, 2]
  k  <- choose (1, d)
  xs <- vectorOf (8 ^ d) genI
  pure (k, d, xs)

tests :: TestTree
tests = testGroup "RedownsampleGate (coarse-band RSI gate: rejects drift, ignores invented detail — H2)"
  [ testProperty "positive: a faithful reconstruction passes the gate" $
      forAll genGate (\(k, d, xs) -> lawRedownsampleConsistency k d xs)

  , testProperty "not-impossible: invented detail (same coarse) still passes" $
      forAll genGate (\(k, d, xs) -> lawGateIgnoresInventedDetail k d xs)

  , testProperty "not-vacuous: a drifted coarse band is REJECTED (teeth)" $
      forAll genGate (\(k, d, xs) -> lawGateRejectsCoarseDrift k d xs)
  ]
