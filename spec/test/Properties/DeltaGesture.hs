module Properties.DeltaGesture (tests) where

import Test.Tasty
import Test.Tasty.QuickCheck

import SixFour.Spec.ConstructionEncoder (QColour)
import SixFour.Spec.DeltaGesture

genQColours :: Gen [QColour]
genQColours = do
  k <- choose (0, 6)
  vectorOf k ((,,) <$> choose (-3000, 3000) <*> choose (-3000, 3000) <*> choose (-3000, 3000))

genIndex :: Gen [Int]
genIndex = do
  k <- choose (0, 8)
  vectorOf k (choose (0, 15))

tests :: TestTree
tests = testGroup "DeltaGesture (the two drag verbs: colour drags ADD, index drags COMPOSE)"
  [ testProperty "colour STACK = sum (the abelian ℤ-module add)" $
      forAll genQColours $ \pal -> forAll genQColours $ \d1 -> forAll genQColours $ \d2 ->
        lawColourDragAdds pal d1 d2
  , testProperty "colour STACK is commutative (order-free, elastic)" $
      forAll genQColours $ \d1 -> forAll genQColours $ \d2 -> lawColourDragCommutes d1 d2
  , testProperty "index CHAIN = apply in sequence (transport composition)" $
      forAll genIndex $ \b -> forAll genIndex $ \m -> forAll genIndex $ \t ->
        lawIndexDragComposes b m t
  , testProperty "index CHAIN order matters (non-abelian; no stack verb)" $
      once lawIndexDragOrderMatters
  ]
