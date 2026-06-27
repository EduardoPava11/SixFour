module Properties.Recursion (tests) where

import Test.Tasty
import Test.Tasty.QuickCheck

import SixFour.Spec.Recursion

-- A short integer list (the seed for the sample-functor schemes).
genList :: Gen [Int]
genList = do
  n <- choose (0, 40)
  vectorOf n (choose (-1000, 1000))

tests :: TestTree
tests = testGroup "Recursion (the boot-only Fix/cata/ana/hylo/meta foundation)"
  [ testGroup "the combinators behave (pinned against a sample ListF functor)"
      [ testProperty "hylo fuses cata . ana (the fusion theorem)" $
          forAll genList lawHyloFusesCataAna
      , testProperty "ana then cata round-trips a list (cata toList . ana fromList == id)" $
          forAll genList lawCataAnaRoundTrip
      , testProperty "meta = fold-then-unfold: length n then descending [n..1]" $
          forAll genList lawMetaFoldThenUnfold
      ]
  ]
