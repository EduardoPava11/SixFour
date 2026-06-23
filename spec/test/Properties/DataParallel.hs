module Properties.DataParallel (tests) where

import Test.Tasty
import Test.Tasty.QuickCheck

import SixFour.Spec.DataParallel

tests :: TestTree
tests = testGroup "DataParallel (the 4th compartment wall: GPU data-parallel boundary + determinism class)"
  [ testProperty "a PixelMap is elementwise (no GPU schedule can change the result)" $
      forAll (listOf (choose (-1000, 1000))) lawPixelMapIsElementwise
  , testProperty "an Exact integer reduction is order-invariant (any thread order = same byte)" $
      forAll (listOf (choose (-1000000, 1000000))) lawExactIntReduceIsOrderInvariant
  , testProperty "a Tol class declares a non-negative ULP tolerance" $
      forAll (choose (-1000, 1000)) lawTolDeclaresNonNegTolerance
  , testProperty "Exact and Tol are disjoint (a float reduce cannot masquerade as bit-exact)" $
      forAll (choose (-1000, 1000)) lawExactNeverFloatReduce
  ]
