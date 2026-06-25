module Properties.TriScaleBench (tests) where

import Test.Tasty
import Test.Tasty.QuickCheck

import SixFour.Spec.TriScaleBench

-- A 4096-voxel "256³-analog" fine cube (distilled down to 64³ then 16³), and an integer tail bump.
genFine :: Gen [Int]
genFine = vectorOf 4096 (choose (0, 4096))

tests :: TestTree
tests = testGroup "TriScaleBench (a 16³ change is comparable to a 256³ change only at the coarse band)"
  [ testProperty "KEYSTONE: re-downsample 256³ recovers the 16³ seed (and 64³ capture), tail-blind" $
      forAll genFine lawSixteenComparableAtCoarseOnly
  , testProperty "the invented tail has NO coarse footprint (same 16³/64³, different 256³)" $
      forAll genFine $ \f -> forAll (choose (-50, 50)) $ \b1 -> forAll (choose (-50, 50)) $ \b2 ->
        lawTailHasNoCoarseFootprint f b1 b2
  ]
