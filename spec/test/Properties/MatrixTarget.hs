module Properties.MatrixTarget (tests) where

import Test.Tasty
import Test.Tasty.QuickCheck

import SixFour.Spec.DualCube (P6(..))
import SixFour.Spec.MatrixTarget

genI :: Gen Integer
genI = choose (-30, 30)

genP6 :: Gen P6
genP6 = P6 <$> genI <*> genI <*> genI <*> genI <*> genI <*> genI

tests :: TestTree
tests = testGroup "MatrixTarget (the holistic full-matrix target, rank-1 honest)"
  [ testProperty "target matrix is rank 1 (separable value x content)" $
      forAll genP6 lawMatrixTargetIsRank1
  , testProperty "generator is 6 DOF and determines all 9 cells" $
      forAll genP6 lawGeneratorIsSixNotNine
  , testProperty "target is the full 9-cell matrix, not a masked pair" $
      forAll genP6 lawTargetIsFullMatrixNotMaskedPair
  , testProperty "KEYSTONE: matrix loss sees the chroma the L-row loss is blind to"
      lawMatrixLossSeesOffDiagonal
  ]
