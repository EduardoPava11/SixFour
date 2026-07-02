{-# OPTIONS_GHC -Wno-orphans #-}
module Properties.Governance (tests) where

import Test.Tasty
import Test.Tasty.QuickCheck

import SixFour.Spec.Governance
import Properties.Trade ()          -- reuse the Arbitrary CreatorId / GeneId instances

instance Arbitrary Grade where
  arbitrary = elements [minBound .. maxBound]

instance Arbitrary Member where
  arbitrary = do
    i  <- arbitrary
    p  <- choose (0, 20)
    te <- choose (0, 20)
    r  <- choose (0, 100 :: Int)
    gs <- arbitrary
    pure (Member i p te (fromIntegral r / 100) gs)

instance Arbitrary Constitution where
  arbitrary = oneof
    [ pure Meritocracy
    , pure Gerontocracy
    , pure MajorityJudgment
    , Monarchy <$> arbitrary
    ]

tests :: TestTree
tests = testGroup "Governance (constitutions as pure ranking functions)"
  [ testProperty "govern is a permutation of the roster" $
      \c ms -> lawGovernIsPermutation c ms
  , testProperty "the governed order is stable (idempotent)" $
      \c ms -> lawGovernIdempotentOrder c ms
  , testProperty "meritocracy ranks by non-increasing prestige" $
      lawMeritocracyRanksByPrestige
  , testProperty "gerontocracy ranks by non-increasing tenure" $
      lawGerontocracyRanksByTenure
  , testProperty "a monarch leads the roster whenever present" $
      \k ms -> lawMonarchLeads k ms
  , testProperty "the council never exceeds councilSize nor the roster" $
      \c ms -> lawCouncilBoundedBySize c ms
  , testProperty "majority-judgment ties are exactly equal grade multisets" $
      \a b -> lawMjTieClassesAreMultisets a b
  ]
