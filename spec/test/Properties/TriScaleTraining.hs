module Properties.TriScaleTraining (tests) where

import Test.Tasty
import Test.Tasty.QuickCheck

import SixFour.Spec.TriScaleTraining

genCounts :: Gen [Integer]
genCounts = vectorOf 4 (choose (-30, 30))

tests :: TestTree
tests = testGroup "TriScaleTraining (all three scales, at the appropriate information density)"
  [ testGroup "Density accounting (exact counts, no estimates)"
      [ testProperty "detail samples scale by exactly 8 per rung" $
          once lawDetailSamplesScaleByEight
      , testProperty "information-per-compute is rung-invariant (7 values per block, every rung)" $
          once lawInfoPerComputeIsRungInvariant
      , testProperty "training both transitions costs exactly 9/8 of the finest alone" $
          once lawTriScaleOverheadIsNineEighths
      ]

  , testGroup "No bit counted twice; skip what carries nothing"
      [ testProperty "KEYSTONE: the microstate chain rule telescopes across the two transitions" $
          forAll genCounts lawLadderTelescopesExactly
      , testProperty "a concentrated block's conditional factor is 1 (zero bits, skipped)" $
          forAll genCounts lawConcentratedTransitionIsFree
      ]
  ]
