{-# OPTIONS_GHC -Wno-orphans #-}
module Properties.Trade (tests) where

import Test.Tasty
import Test.Tasty.QuickCheck

import SixFour.Spec.Trade

-- Generators build trades through the real state machine, so only reachable states are exercised.
instance Arbitrary GeneId where
  arbitrary = GeneId <$> choose (0, 5)

instance Arbitrary CreatorId where
  arbitrary = CreatorId <$> choose (0, 4)

instance Arbitrary Trade where
  arbitrary = do
    p     <- arbitrary
    offer <- arbitrary
    want  <- arbitrary                 -- Maybe GeneId; Nothing = open listing
    e     <- choose (0, 10)
    let t0 = propose p offer want e
    settle <- choose (0, 3 :: Int)
    case settle of
      1 -> pure (decline t0)
      2 -> pure (expire t0)
      3 -> do c <- arbitrary `suchThat` (/= p)   -- a distinct counterparty
              g <- arbitrary
              pure (accept c g t0)
      _ -> pure t0                                -- left open (Proposed)

tests :: TestTree
tests = testGroup "Trade (the swap-economy ledger — hybrid grant semantics)"
  [ testProperty "grant is non-destructive: holdings are monotone under append" $
      \led t who -> lawHoldingsMonotone led t who
  , testProperty "only a Proposed trade settles (accept/decline/expire inert otherwise)" $
      \t g who -> lawOnlyProposedSettles t g who
  , testProperty "you cannot accept your own proposal" $
      \t g -> lawNoSelfAccept t g
  , testProperty "a trade that never reaches Accepted grants nothing" $
      lawUnsettledGrantsNothing
  , testProperty "reliability is a probability in [0,1]" $
      \led who -> lawReliabilityUnit led who
  ]
