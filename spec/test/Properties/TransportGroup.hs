module Properties.TransportGroup (tests) where

import Test.Tasty
import Test.Tasty.QuickCheck
import Test.QuickCheck (shuffle)

import SixFour.Spec.TransportGroup

-- A valid transport (a permutation of [0..k-1], k in [1,6]) plus an index map over those slots.
genPermK :: Gen (Transport, Int)
genPermK = do
  k <- choose (1, 6)
  p <- shuffle [0 .. k - 1]
  pure (p, k)

genMap :: Int -> Gen [Int]
genMap k = do
  m <- choose (0, 8)
  vectorOf m (choose (0, max 0 (k - 1)))

tests :: TestTree
tests = testGroup "TransportGroup (IndexDelta: a NON-ABELIAN transport group; chaining, not addition)"
  [ testGroup "tapply is a group action on the index set"
      [ testProperty "identity acts trivially" $
          forAll (genPermK >>= \(_, k) -> genMap k) lawTransportActionIdentity
      , testProperty "homomorphism: tapply (a∘b) = tapply a . tapply b" $
          forAll genPermK $ \(a, _) -> forAll genPermK $ \(b, _) -> forAll (genMap 6) $ \m ->
            lawTransportActionHomomorphism a b m
      , testProperty "every transport is invertible (tinv a ∘ a acts as id)" $
          forAll genPermK $ \(a, k) -> forAll (genMap k) $ \m -> lawTransportInverse a m
      , testProperty "tbetween x y carries x to y (data manufacture)" $
          forAll genPermK $ \(s, k) -> forAll (genMap k) $ \x ->
            lawTransportBetweenManufactures s x
      ]

  , testGroup "The policy channel is NOT the value channel"
      [ testProperty "NON-ABELIAN: a∘b ≠ b∘a" $ once lawTransportNonAbelian
      , testProperty "composition is CHAINING, not addition ([2,0,1] ≠ [2,4,0])" $
          once lawCompositionIsChainingNotAddition
      ]
  ]
