module Properties.LedgerCRDT (tests) where

import Test.Tasty
import Test.Tasty.QuickCheck

import SixFour.Spec.LedgerCRDT
import Properties.Trade ()          -- reuse Arbitrary Trade / CreatorId / GeneId
                                    -- (Arbitrary (Set a) comes from QuickCheck itself)

tests :: TestTree
tests = testGroup "LedgerCRDT (the trade ledger is a Grow-only-Set CvRDT ⇒ Strong Eventual Consistency)"
  [ testProperty "join is commutative" $
      \a b -> lawMergeCommutative a b
  , testProperty "join is associative" $
      \a b c -> lawMergeAssociative a b c
  , testProperty "join is idempotent" $
      \a -> lawMergeIdempotent a
  , testProperty "bottom is the join identity" $
      \a -> lawBottomIdentity a
  , testProperty "stateOf is a homomorphism (Ledger,++) → (Grants,merge)" $
      \a b -> lawStateHomomorphism a b
  , testProperty "the empty ledger folds to bottom" $
      lawStateEmptyIsBottom
  , testProperty "monotone: appending trades never shrinks state" $
      \a b -> lawStateMonotone a b
  , testProperty "duplicate delivery is harmless (G-Set idempotence)" $
      \l -> lawLedgerIdempotent l
  , testProperty "SEC: element-equal ledgers hold identical state" $
      \a b -> lawStrongEventualConsistency a b
  , testProperty "SEC (constructive): shuffled + duplicated ledger converges" $
      \l -> forAll (shuffle (l ++ l)) $ \l' -> stateOf l' == stateOf l
  , testProperty "the shipped holdings fold is a slice of the CvRDT state" $
      \l who -> lawHoldingsFromState l who
  ]
