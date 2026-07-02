{-# OPTIONS_GHC -Wno-orphans #-}
module Properties.DerivationLog (tests) where

import Test.Tasty
import Test.Tasty.QuickCheck

import SixFour.Spec.DerivationLog
import Properties.Trade ()          -- reuse Arbitrary CreatorId / GeneId
import Properties.GeneHash ()       -- reuse Arbitrary MintOp

-- A self-contained derivation event: small payload, a few absolute parent ids, a creator and epoch.
instance Arbitrary DerivationEvent where
  arbitrary = DerivationEvent
    <$> resize 6 (listOf arbitrary)   -- payload
    <*> resize 4 (listOf arbitrary)   -- parents (absolute GeneIds)
    <*> arbitrary                     -- creator
    <*> choose (0, 20)                -- epoch
  shrink (DerivationEvent pay ps cr ep) =
    [ DerivationEvent pay' ps cr ep | pay' <- shrink pay ] ++
    [ DerivationEvent pay ps' cr ep | ps'  <- shrink ps ]

tests :: TestTree
tests = testGroup "DerivationLog (genealogy as an order-independent fold of an append-only log)"
  [ testProperty "an event's id self-verifies (= geneHash of its content)" $
      \e -> lawEventIdSelfVerifying e
  , testProperty "an event's tag commits to its own parents" $
      \e -> lawEventTagCommitsToParents e
  , testProperty "idempotent: repeating the whole log changes nothing (G-Set)" $
      \l -> lawGenealogyIdempotent l
  , testProperty "order-independent: reversing the log changes nothing" $
      \l -> lawGenealogyReverseInvariant l
  , testProperty "SEC: invariant under an arbitrary permutation of the log" $
      \l -> forAll (shuffle l) $ \l' -> genealogyOf l' == genealogyOf l
  , testProperty "monotone: appending events never removes a gene" $
      \l extra -> lawGenealogyMonotone l extra
  , testProperty "THEOREM: a causally-complete log folds to an acyclic genealogy" $
      \ops -> lawReconstructedGenealogyAcyclic ops
  , testProperty "the log faithfully carries the DAG (same ids as direct construction)" $
      \ops -> lawLogFaithful ops
  ]
