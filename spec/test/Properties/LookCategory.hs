module Properties.LookCategory (tests) where

import Test.Tasty
import Test.Tasty.QuickCheck
import Test.QuickCheck

import SixFour.Spec.Color       (OKLab(..))
import SixFour.Spec.LookCategory

genOKLab :: Gen OKLab
genOKLab = OKLab <$> choose (0, 1) <*> choose (-0.4, 0.4) <*> choose (-0.4, 0.4)

-- | A fixed-dimension parameter / embedding vector in a bounded range (D = 8).
dim :: Int
dim = 8

genVec :: Gen [Double]
genVec = vectorOf dim (choose (-1, 1))

-- | A non-degenerate (winner, loser) pair: same dimension, guaranteed @w /= l@.
genPair :: Gen ([Double], [Double])
genPair = do
  w <- genVec
  l <- genVec `suchThat` (/= w)
  pure (w, l)

genRatePos :: Gen Double
genRatePos = choose (0.01, 1.0)

tests :: TestTree
tests = testGroup "LookCategory (look taxonomy + on-device push-pull learning)"
  [ testProperty "classify is total (always a real category)" $
      forAll genOKLab lawClassifyTotal

  , testProperty "each prototype classifies back to its own category" $
      once lawPrototypeSelfClassify

  , testProperty "category prototypes are pairwise distinct" $
      once lawCategoriesDistinct

  , testProperty "zero learning rate is the identity (no signal ⇒ no change)" $
      forAll genVec $ \theta -> forAll genPair (lawZeroRateIdentity theta)

  , testProperty "a positive step STRICTLY increases the preferred gap (push-pull learns)" $
      forAll genRatePos $ \rate ->
        forAll genVec $ \theta ->
          forAll genPair (lawStepIncreasesPreferredGap rate theta)

  , testProperty "training a batch is the fold of single steps" $
      forAll genRatePos $ \rate ->
        forAll genVec $ \theta ->
          forAll (listOf genPair) $ \pairs ->
            trainPairs rate pairs theta
              == foldl (\th p -> btGradStep rate th p) theta pairs
  ]
