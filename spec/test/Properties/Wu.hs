module Properties.Wu (tests) where

import Test.Tasty
import Test.Tasty.QuickCheck
import Test.QuickCheck

import qualified Data.Vector         as V
import qualified Data.Vector.Unboxed as U

import SixFour.Spec.Color   (OKLab(..))
import SixFour.Spec.StageA
import SixFour.Spec.Palette (Palette(..))
import SixFour.Spec.Indices (IndexTensor(..))

-- Use very small frames so QuickCheck is fast: H = W = 4, K = 8.

type H = 4
type W = 4
type K = 8

genFrame :: Gen (Frame H W)
genFrame = do
  let n = 4 * 4 :: Int
  xs <- vectorOf n $ do
    l <- choose (0, 1)
    a <- choose (-0.4, 0.4)
    b <- choose (-0.4, 0.4)
    pure (OKLab l a b)
  pure (Frame (V.fromList xs))

tests :: TestTree
tests = testGroup "StageA / variance-cut reference"
  [ testProperty "output palette has exactly K entries" $
      forAll genFrame $ \fr ->
        let (Palette pv, _) = runStageA (varianceCutReference @H @W @K) fr
        in V.length pv == 8
  , testProperty "output indices have exactly H*W entries, all in [0, K-1]" $
      forAll genFrame $ \fr ->
        let (_, IndexTensor iv) = runStageA (varianceCutReference @H @W @K) fr
        in U.length iv == 16
           && U.all (\i -> i >= 0 && i < 8) iv
  ]
