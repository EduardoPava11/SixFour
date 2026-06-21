module Properties.SameObjectJEPA (tests) where

import Test.Tasty
import Test.Tasty.QuickCheck

import SixFour.Spec.ProjectionOrdering (allOrderings)
import SixFour.Spec.SameObjectInvariance (Cube(..))
import SixFour.Spec.SameObjectJEPA

genI :: Gen Int
genI = choose (-256, 256)

genCube :: Gen (Int, Cube)
genCube = do
  d <- elements [0, 1]
  let n = 8 ^ d
  c <- Cube <$> vectorOf n genI <*> vectorOf n genI <*> vectorOf n genI
  pure (d, c)

tests :: TestTree
tests = testGroup "SameObjectJEPA (the JEPA objective: predict the sibling projection)"
  [ testProperty "OBJECTIVE: predicting the target from the context recovers it exactly" $
      forAll genCube $ \(d, c) ->
        forAll (elements allOrderings) $ \pc ->
          forAll (elements allOrderings) $ \pt -> lawJepaPredictsTarget d pc pt c

  , testProperty "context and target are co-projections of the SAME object" $
      forAll genCube $ \(d, c) ->
        forAll (elements allOrderings) $ \pc ->
          forAll (elements allOrderings) $ \pt -> lawJepaSameObject d pc pt c

  , testProperty "the context faithfully encodes the source cube" $
      forAll genCube $ \(d, c) ->
        forAll (elements allOrderings) $ \pc ->
          forAll (elements allOrderings) $ \pt -> lawJepaContextIsCube d pc pt c
  ]
