module Properties.Affiliation (tests) where

import Test.Tasty
import Test.Tasty.QuickCheck

import SixFour.Spec.Affiliation
import Properties.Trade ()          -- reuse Arbitrary Trade / CreatorId (⇒ Arbitrary Ledger)

tests :: TestTree
tests = testGroup "Affiliation (guilds as trade-graph components)"
  [ testProperty "the trade graph is symmetric" $
      \led -> lawGraphSymmetric led
  , testProperty "guilds partition the active traders" $
      \led -> lawAffiliationPartitions led
  , testProperty "every active trader has a guild" $
      \led -> lawEveryActiveHasGuild led
  , testProperty "trade partners share a guild" $
      \led -> lawPartnersShareGuild led
  ]
