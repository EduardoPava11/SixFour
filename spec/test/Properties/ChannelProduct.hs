module Properties.ChannelProduct (tests) where

import Test.Tasty
import Test.Tasty.QuickCheck

import SixFour.Spec.DualCube (P6(..))
import SixFour.Spec.ChannelProduct

genI :: Gen Integer
genI = choose (-50, 50)

genP6 :: Gen P6
genP6 = P6 <$> genI <*> genI <*> genI <*> genI <*> genI <*> genI

tests :: TestTree
tests = testGroup "ChannelProduct (all 9 colour x space comparisons = GIF89a = attention)"
  [ testProperty "exactly 9 free channels, all distinct" lawNineFreeChannels
  , testProperty "comparison matrix is the outer product (attention q (x) k)" $
      forAll genP6 lawComparisonIsOuterProduct
  , testProperty "GIF89a separability: matrix is rank 1 (value x content)" $
      forAll genP6 lawComparisonIsSeparable
  , testProperty "DualCube diagonal = the phi6-fixed cells" lawDiagonalIsPhi6Fixed
  , testProperty "search:search block = Z[i] Gaussian product of the two planes" $
      forAll genP6 lawSearchBlockIsGaussianProduct
  , testProperty "KEYSTONE: all-channels see the chroma difference the L-anchor is blind to"
      lawAllChannelsSeeWhatLAnchorMisses
  ]
