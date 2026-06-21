module Properties.LBalanceOperator (tests) where

import Test.Tasty
import Test.Tasty.QuickCheck

import SixFour.Spec.OctreeCell (V8(..))
import SixFour.Spec.LBalanceOperator

genInt :: Gen Int
genInt = choose (-65536, 65536)

genV8 :: Gen (V8 Int)
genV8 = V8 <$> genInt <*> genInt <*> genInt <*> genInt
           <*> genInt <*> genInt <*> genInt <*> genInt

tests :: TestTree
tests = testGroup "LBalanceOperator (L = the coarse/DC universal balance)"
  [ testProperty "balance is gamut-closed: min children <= balance <= max children" $
      forAll genV8 lawBalanceInRange

  , testProperty "balance of a uniform octant is itself (the floor fixpoint)" $
      forAll genInt lawBalanceFixedOnConstant

  , testProperty "golden: balance (V8 10 20 30 44 10 20 30 44) = 26" $
      once lawBalanceGolden
  ]
