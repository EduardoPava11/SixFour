module Properties.Dim6 (tests) where

import Test.Tasty
import Test.Tasty.QuickCheck

import SixFour.Spec.Dim6

genDim :: Gen Dim6
genDim = elements allDims

tests :: TestTree
tests = testGroup "Dim6 (the 6-axis alphabet; Phi-twist involution)"
  [ testProperty "the alphabet is finite and closed: exactly 6 distinct inhabitants" $
      once lawDim6Finite

  , testProperty "Phi-twist is an involution: phi6 . phi6 = id" $
      forAll genDim lawPhi6Involution

  , testProperty "Phi encodes x<->a, y<->b, t<->L (agrees with XYTLabDuality)" $
      once lawPhi6AgreesWithDuality

  , testProperty "the universal carrier is exactly {L,t} and is Phi-closed" $
      forAll genDim lawUniversalIsLT
  ]
