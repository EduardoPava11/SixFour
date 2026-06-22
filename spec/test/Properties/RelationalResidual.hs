module Properties.RelationalResidual (tests) where

import Test.Tasty
import Test.Tasty.QuickCheck

import SixFour.Spec.Dim6 (Dim6(..))
import SixFour.Spec.RelationalResidual

genI :: Gen Int
genI = choose (-32768, 32768)

genP6 :: Gen P6
genP6 = P6 <$> genI <*> genI <*> genI <*> genI <*> genI <*> genI

genAxis :: Gen Dim6
genAxis = elements [DimL, DimA, DimB, DimX, DimY, DimT]

tests :: TestTree
tests = testGroup "RelationalResidual (residual as relational memory: d6 metric + the 14 position residual)"
  [ testProperty "phi6 pairs colour with position (a<->x, b<->y, L<->t)" $
      once lawPhi6PairsColourWithPosition
  , testProperty "carriers are exactly {L,t}; searches {a,b,x,y}" $
      once lawCarriersAreLandT
  , testProperty "the learned residual is 14 (7 bands x {x,y}; L,t held out)" $
      once lawResidualIsFourteen
  , testProperty "d6 is non-negative" $
      forAll genP6 $ \p -> forAll genP6 $ \q -> lawD6NonNegative p q
  , testProperty "d6 is symmetric" $
      forAll genP6 $ \p -> forAll genP6 $ \q -> lawD6Symmetric p q
  , testProperty "d6 == 0 iff the points are equal" $
      forAll genP6 $ \p -> forAll genP6 $ \q -> lawD6IdentityOfIndiscernibles p q
  , testProperty "d6 respects the triangle inequality" $
      forAll genP6 $ \p -> forAll genP6 $ \q -> forAll genP6 $ \r -> lawD6TriangleInequality p q r
  , testProperty "the +/-1 quantum is one step on any axis" $
      forAll genAxis $ \ax -> forAll genP6 $ \p -> lawUnitQuantumIsOneStep ax p
  ]
