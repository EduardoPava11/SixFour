module Properties.DetailPredictor (tests) where

import Test.Tasty
import Test.Tasty.QuickCheck

import SixFour.Spec.OctreeCell (Detail)
import SixFour.Spec.DetailPredictor

-- Coarse Q16 values in a realistic range (a few thousand ULPs).
genV :: Gen Int
genV = choose (-8000, 8000)

-- A 7-band detail; bands span enough range that the off-floor guard fires.
genDetail :: Gen Detail
genDetail =
  let genB = choose (-20000, 20000)
  in (,,,,,,) <$> genB <*> genB <*> genB <*> genB <*> genB <*> genB <*> genB

-- A param vector sized to the deployed shape (small magnitude keeps the squared loss
-- well-scaled for the finite-difference check).
genParams :: Gen [Double]
genParams = vectorOf (paramCount defaultPredictorShape) (choose (-0.5, 0.5))

tests :: TestTree
tests = testGroup "DetailPredictor (learned f : coarse -> detail; zeroParams == floor by arithmetic)"
  [ testProperty "KEYSTONE: zeroParams == the floor BY ARITHMETIC (4 teeth: floor / non-constant / step-decreases / differs-from-floor)" $
      forAll genV $ \v -> forAll genDetail $ \tgt -> lawZeroParamsIsFloorArithmetic v tgt

  , testProperty "backprop: analytic gradient == central finite difference of bandLoss" $
      forAll genParams $ \ps -> forAll genV $ \v -> forAll genDetail $ \tgt ->
        lawPredictorGradientFiniteDiff ps v tgt

  , testProperty "self-similar reuse: f depends only on (theta, v) and both rungs are 2 levels" $
      forAll genParams $ \ps -> forAll genV (lawReusesOnBothRungs ps)
  ]
