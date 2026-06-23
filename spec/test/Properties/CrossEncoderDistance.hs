module Properties.CrossEncoderDistance (tests) where

import Test.Tasty
import Test.Tasty.QuickCheck

import SixFour.Spec.SameObjectInvariance (Cube(..))
import SixFour.Spec.GifDualView          (GifObject(..))
import SixFour.Spec.RelationalResidual   (P6(..))
import SixFour.Spec.CrossEncoderDistance

-- | GIF object with a SMALL colour range so the distinct-colour count straddles the budget
-- (exercising both the lossless and the lossy branch of palettizeBudget).
genGifObject :: Gen GifObject
genGifObject = do
  d <- choose (0, 2)
  let n = 8 ^ d
  cl <- vectorOf n (choose (0, 3))
  ca <- vectorOf n (choose (0, 3))
  cb <- vectorOf n (choose (0, 3))
  pure (GifObject d (Cube cl ca cb))

genBudget :: Gen Int
genBudget = choose (1, 6)

genP6 :: Gen P6
genP6 = P6 <$> c <*> c <*> c <*> c <*> c <*> c where c = choose (-50, 50)

tests :: TestTree
tests = testGroup "CrossEncoderDistance (the d6 distance between the two semantics)"
  [ testProperty "per-axis distortions sum to the total d6 distortion" $
      forAll genBudget $ \k -> forAll genGifObject $ \g -> lawPerAxisDistortionSumsToTotal k g
  , testProperty "distortion == 0 iff palettizable within budget" $
      forAll genBudget $ \k -> forAll genGifObject $ \g -> lawDistortionZeroIffLossless k g
  , testProperty "the cloud distance is a pseudometric (delegates d6)" $
      forAll (listOf genP6) $ \ps -> forAll (listOf genP6) $ \qs -> forAll (listOf genP6) $ \rs ->
        lawDistortionIsPseudometric ps qs rs
  ]
