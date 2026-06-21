module Properties.CarrierL (tests) where

import Test.Tasty
import Test.Tasty.QuickCheck

import SixFour.Spec.OctreeCell (V8(..), Detail)
import SixFour.Spec.CarrierL

genInt :: Gen Int
genInt = choose (-65536, 65536)

genV8 :: Gen (V8 Int)
genV8 = V8 <$> genInt <*> genInt <*> genInt <*> genInt
           <*> genInt <*> genInt <*> genInt <*> genInt

genDetail :: Gen Detail
genDetail = (,,,,,,) <$> genInt <*> genInt <*> genInt <*> genInt <*> genInt <*> genInt <*> genInt

tests :: TestTree
tests = testGroup "CarrierL (L carries the signal; A/B search is the perturbation L re-balances)"
  [ testProperty "L is the coarse/DC carrier (lBalance = ocCoarse . liftOct)" $
      forAll genV8 lawCarrierIsDC

  , testProperty "A/B = 0 reconstructs the pure-L floor (constant octant)" $
      forAll genInt lawZeroSearchIsCarrierFloor

  , testProperty "L re-balances: the carrier is invariant to the search detail" $
      forAll genInt $ \c -> forAll genDetail $ \d1 -> forAll genDetail $ \d2 ->
        lawCarrierInvariantToSearch c d1 d2

  , testProperty "a flat carrier (constant octant) has zero search detail" $
      forAll genInt lawSearchIsZeroOnConstant
  ]
