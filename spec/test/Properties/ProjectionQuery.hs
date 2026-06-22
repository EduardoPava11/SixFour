module Properties.ProjectionQuery (tests) where

import Test.Tasty
import Test.Tasty.QuickCheck

import SixFour.Spec.CubeTensor       (CubeTensor(..))
import SixFour.Spec.ProjectionOrdering (allOrderings, orderingHash)
import SixFour.Spec.ProjectionQuery

genI :: Gen Int
genI = choose (-(2^(16 :: Int)), 2^(16 :: Int))

genStore :: Gen GeneStoreSpec
genStore = do
  d <- elements [0, 1]
  let n = 8 ^ d
  ct <- CubeTensor d <$> vectorOf n genI <*> vectorOf n genI <*> vectorOf n genI
  pure (GeneStoreSpec ct)

tests :: TestTree
tests = testGroup "ProjectionQuery (RAG read-as-projections)"
  [ testProperty "RAG correctness: two ordering-keys decode to the SAME object" $
      forAll genStore $ \s ->
        forAll (elements allOrderings) $ \p ->
          forAll (elements allOrderings) $ \p' -> lawQueryReadConsistency s p p'
  , testProperty "the hash key resolves to the right genome" $
      forAll genStore $ \s ->
        forAll (elements allOrderings) $ \o -> lawHashKeyResolves s o
  , testProperty "unknown keys resolve to Nothing (lock not vacuous)" $
      forAll genStore $ \s -> forAll (choose (minBound, maxBound)) $ \h ->
        lawHashKeyRejectsUnknown s h
  , testProperty "L carrier band fixed across every query" $
      forAll genStore $ \s ->
        forAll (elements allOrderings) $ \p ->
          forAll (elements allOrderings) $ \p' -> lawCarrierFixedAcrossQueries s p p'
  , testProperty "query vocabulary is exactly the two XOR diagonals" $
      forAll genStore lawQueryVocabularyIsTwo
  ]
