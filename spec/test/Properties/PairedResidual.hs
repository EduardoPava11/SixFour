module Properties.PairedResidual (tests) where

import Data.List (nubBy)
import Data.Function (on)
import Test.Tasty
import Test.Tasty.QuickCheck

import SixFour.Spec.OctreeCell (Detail)
import SixFour.Spec.PairedResidual

genI :: Gen Int
genI = choose (-256, 256)

genDetail :: Gen Detail
genDetail = (,,,,,,) <$> genI <*> genI <*> genI <*> genI <*> genI <*> genI <*> genI

genBook :: Gen ResidualBook
genBook = mkResidualBook <$> listOf ((,) <$> genI <*> genDetail)

-- key/value pairs with DISTINCT keys (so list-lookup matches Map.fromList last-wins)
genDistinctKVs :: Gen [(Int, Detail)]
genDistinctKVs = nubBy ((==) `on` fst) <$> listOf ((,) <$> genI <*> genDetail)

-- a coarse cube of length 8^d (d in {0,1})
genCube :: Gen (Int, [Int])
genCube = do
  d <- elements [0, 1]
  xs <- vectorOf (8 ^ d) genI
  pure (d, xs)

tests :: TestTree
tests = testGroup "PairedResidual (capture-anchored value-keyed super-res; residual = token)"
  [ testProperty "KEYSTONE: the 256^3 re-pools to exactly the 64^3 (capture-anchored, any book)" $
      forAll genCube $ \(d, c) -> forAll genBook $ \b -> lawPairedRepoolsToCoarse d b c

  , testProperty "teeth: two different books over the same coarse both pass (residual in null space)" $
      forAll genCube $ \(d, c) -> forAll genBook $ \b1 -> forAll genBook $ \b2 ->
        lawDistinctBooksSameCoarse d b1 b2 c

  , testProperty "pure-value keying: same value => same residual" $
      forAll genBook $ \b -> forAll genI $ \u -> forAll genI $ \v -> lawResidualPureValue b u v

  , testProperty "the paired octant edge is reversible" $
      forAll genBook $ \b -> forAll genI (lawPairedReversible b)

  , testProperty "the residual IS the token: residualFor = codebook lookup (distinct keys)" $
      forAll genDistinctKVs $ \kvs -> forAll genI (lawResidualIsToken kvs)

  , testProperty "unseen value => the zero floor (zero-genome==floor)" $
      forAll genDistinctKVs $ \kvs -> forAll genI (lawUnseenKeyIsFloor kvs)

  , testProperty "self-similar two levels: pairedLift = liftKeyed twice, reaches x64" $
      forAll genCube $ \(d, c) -> forAll genBook $ \b -> lawTwoLevelsTo256 d b c
  ]
