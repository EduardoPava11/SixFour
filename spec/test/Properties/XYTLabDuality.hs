module Properties.XYTLabDuality (tests) where

import Test.Tasty
import Test.Tasty.QuickCheck

import SixFour.Spec.XYTLabDuality

genAxis :: Gen Axis
genAxis = elements [X, Y, T]

genQuad :: Gen (Int, Int, Int, Int)
genQuad = (,,,) <$> g <*> g <*> g <*> g
  where g = choose (-65536, 65536)

tests :: TestTree
tests = testGroup "XYTLabDuality ([x,y,t] = [L,a,b]: Balance |- Search)"
  [ testProperty "Phi is an involution: phiInv . phi = id" $
      forAll genAxis lawPhiInvolution

  , testProperty "Phi preserves the universal/search split (L=t universal, a=x b=y search)" $
      forAll genAxis lawPhiPreservesUniversal

  , testProperty "the universal factor is exactly {t} <-> {L}" $
      once lawUniversalIsTL

  , testProperty "Balance |- Search unit = the reversible Haar split (unlift . lift = id)" $
      forAll genQuad lawAdjunctionUnit
  ]
