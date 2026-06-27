module Properties.DualCube (tests) where

import Test.Tasty
import Test.Tasty.QuickCheck

import SixFour.Spec.DualCube

genI :: Gen Integer
genI = choose (-100, 100)

genP6 :: Gen P6
genP6 = P6 <$> genI <*> genI <*> genI <*> genI <*> genI <*> genI

tests :: TestTree
tests = testGroup "DualCube (the colour/space duality pivot: no privileged carrier)"
  [ testProperty "phi6 is an involution" $ forAll genP6 lawPhi6Involution
  , testProperty "KEYSTONE: colour and space cubes are exchanged by phi6" $
      forAll genP6 lawCubesExchangedByPhi6
  , testProperty "phi6 is a Z-module automorphism (a symmetry of the carrier)" $
      forAll genP6 $ \p -> forAll genP6 $ \q -> forAll genI $ \k ->
        lawPhi6IsModuleAutomorphism p q k
  , testProperty "no privileged carrier (L and t balances are exchanged, not preferred)" $
      forAll genP6 lawNoPrivilegedCarrier
  , testProperty "balance = real Z axis (geometry); search = Z[i] plane (number theory)" $
      forAll genP6 lawBalanceRealSearchGaussian
  , testProperty "phi6 realizes the XYTLabDuality axis functor (t~L, x~a, y~b)"
      lawPhi6MatchesAxisDuality
  ]
