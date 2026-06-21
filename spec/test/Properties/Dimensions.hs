module Properties.Dimensions (tests) where

import Test.Tasty
import Test.Tasty.QuickCheck

import SixFour.Spec.Dimensions

genInt :: Gen Int
genInt = choose (-65536, 65536)

genCut :: Gen (Int, Int, [Int])
genCut = do
  d  <- elements [0, 1, 2]
  k  <- choose (0, d)
  xs <- vectorOf (8 ^ d) genInt
  pure (k, d, xs)

tests :: TestTree
tests = testGroup "Dimensions (rule of dimensions: traceable + conserved)"
  [ testProperty "dimension conserved: surfaced + held == input, exactly" $
      forAll genCut (\(k, d, xs) -> lawDimConserved k d xs)

  , testProperty "every manipulated axis is classified in the ledger" $
      once lawEveryAxisClassified
  ]
