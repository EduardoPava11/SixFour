module Properties.SelfSimilarReconstruct (tests) where

import Test.Tasty
import Test.Tasty.QuickCheck

import SixFour.Spec.OctreeCell (Detail)
import SixFour.Spec.SelfSimilarReconstruct

genI :: Gen Int
genI = choose (-256, 256)

genDetail :: Gen Detail
genDetail = (,,,,,,) <$> genI <*> genI <*> genI <*> genI <*> genI <*> genI <*> genI

genBands :: Gen [[Detail]]
genBands = do
  nb <- choose (0, 2)
  vectorOf nb (do n <- choose (0, 4); vectorOf n genDetail)

genCut :: Gen (Int, Int, [Int])
genCut = do
  d  <- elements [0, 1, 2]
  k  <- choose (0, d)
  xs <- vectorOf (8 ^ d) genI
  pure (k, d, xs)

tests :: TestTree
tests = testGroup "SelfSimilarReconstruct (one octant operator twice; held-exact vs invented-continuous)"
  [ testProperty "same operator both rungs (source-agnostic) + levelsBetween==2 each" $
      forAll (vectorOf 8 genI) $ \coarse -> forAll genBands $ \det ->
        lawSameOperatorBothRungs coarse det

  , testProperty "16->64 within capture is bit-exact (delegates refine round-trip)" $
      forAll genCut (\(k, d, xs) -> lawWithinCaptureExact k d xs)

  , testProperty "64->256 invented detail is real (nonzero tail changes the output)" $
      forAll (vectorOf 8 genI) lawBeyondCaptureInvented

  , testProperty "zero latent tail = the deterministic zero-detail floor (zero-genome==floor)" $
      forAll (vectorOf 8 genI) lawZeroTailIsFloor
  ]
