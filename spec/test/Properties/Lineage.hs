{-# OPTIONS_GHC -Wno-orphans #-}
module Properties.Lineage (tests) where

import Control.Monad (forM)
import Test.Tasty
import Test.Tasty.QuickCheck

import SixFour.Spec.Lineage
import SixFour.Spec.Trade (GeneId(..))
import Properties.Trade ()          -- reuse Arbitrary CreatorId / GeneId

-- A genealogy generated as a genuine DAG: gene i's parents are drawn only from {0 .. i-1}, so a
-- cycle is impossible (matching content-addressed provenance, where a child hashes over its parents).
newtype Dag = Dag Genealogy deriving Show

instance Arbitrary Dag where
  arbitrary = do
    n    <- choose (0, 12)
    tags <- forM [0 .. n - 1] $ \i -> do
      ps <- sublistOf (map GeneId [0 .. i - 1])
      cr <- arbitrary
      ep <- choose (0, 20)
      pure (GeneTag (GeneId i) cr ps ep)
    pure (Dag tags)

tests :: TestTree
tests = testGroup "Lineage (the content-addressed gene genealogy DAG)"
  [ testProperty "an origin has no ancestors" $
      \(Dag g) -> lawOriginHasNoAncestors g
  , testProperty "ancestry and descent are dual" $
      \(Dag g) -> lawAncestorDescendantDual g
  , testProperty "acyclic: no gene is its own ancestor" $
      \(Dag g) -> lawAcyclicNoSelfAncestor g
  , testProperty "an origin sits at generation 0" $
      \(Dag g) -> lawGenerationOriginZero g
  , testProperty "generation strictly exceeds every parent" $
      \(Dag g) -> lawGenerationExceedsParents g
  , testProperty "influence is the descendant count" $
      \(Dag g) -> lawInfluenceIsDescendantCount g
  ]
