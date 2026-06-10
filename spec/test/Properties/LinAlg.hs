module Properties.LinAlg (tests) where

import Test.Tasty
import Test.Tasty.QuickCheck
import Test.QuickCheck
import qualified Data.Vector.Unboxed as U
import Data.Maybe (fromJust)

import SixFour.Spec.LinAlg

genDim :: Gen Int
genDim = choose (1, 5)

genMatrix :: Int -> Int -> Gen Matrix
genMatrix r c = do
  xs <- vectorOf (r * c) (choose (-2, 2))
  pure (fromJust (mkMatrix r c (U.fromList xs)))

genVecN :: Int -> Gen (U.Vector Double)
genVecN n = U.fromList <$> vectorOf n (choose (-2, 2))

tol :: Double
tol = 1e-9

vecClose :: U.Vector Double -> U.Vector Double -> Bool
vecClose a b = U.length a == U.length b && U.and (U.zipWith (\x y -> abs (x - y) <= tol) a b)

-- The informal laws Spec.LinAlg's header names ("matVecMul is linear; transpose .
-- transpose = id"), now formalised — LinAlg backs the σ-pair decoder via SigmaPairHead.
tests :: TestTree
tests = testGroup "LinAlg (matrix algebra backing the σ-pair decoder)"
  [ testProperty "transpose is an involution (transpose . transpose = id)" $
      forAll genDim $ \r -> forAll genDim $ \c ->
        forAll (genMatrix r c) $ \m ->
          matToList (transpose (transpose m)) == matToList m

  , testProperty "matVecMul is additive: M(x+y) = Mx + My" $
      forAll genDim $ \r -> forAll genDim $ \c ->
        forAll (genMatrix r c) $ \m ->
          forAll (genVecN c) $ \x -> forAll (genVecN c) $ \y ->
            vecClose (matVecMul m (U.zipWith (+) x y))
                     (U.zipWith (+) (matVecMul m x) (matVecMul m y))

  , testProperty "matVecMul is homogeneous: M(s·x) = s·(Mx)" $
      forAll genDim $ \r -> forAll genDim $ \c ->
        forAll (genMatrix r c) $ \m ->
          forAll (genVecN c) $ \x -> forAll (choose (-3, 3)) $ \s ->
            vecClose (matVecMul m (U.map (* s) x))
                     (U.map (* s) (matVecMul m x))
  ]
