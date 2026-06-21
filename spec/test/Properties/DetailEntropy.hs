module Properties.DetailEntropy (tests) where

import Test.Tasty
import Test.Tasty.QuickCheck

import SixFour.Spec.OctreeCell    (Detail)
import SixFour.Spec.DetailEntropy

-- Small integer coefficients so histograms have repeats (so entropy is exercised,
-- not just the all-distinct degenerate case).
genCoeffs :: Gen [Int]
genCoeffs = listOf (choose (-4, 4))

genDetail :: Gen Detail
genDetail =
  let g = choose (-50, 50)
  in (,,,,,,) <$> g <*> g <*> g <*> g <*> g <*> g <*> g

tests :: TestTree
tests = testGroup "DetailEntropy (integer-histogram Shannon entropy over octant detail bands)"
  [ testProperty "entropy is non-negative" $
      forAll genCoeffs lawEntropyNonNegative

  , testProperty "entropy == 0 IFF at most one distinct symbol (flat band = 0 bits)" $
      forAll genCoeffs lawEntropyZeroIffSingleSymbol

  , testProperty "entropy is MAXIMISED at uniform: n distinct symbols == log2 n bits" $
      forAll genCoeffs lawEntropyMaxAtUniform

  , testProperty "entropy <= log2 K (the max-entropy ceiling)" $
      forAll genCoeffs lawEntropyUpperBound

  , testProperty "OPERATIONAL: a skewed distribution costs STRICTLY fewer bits than uniform" $
      forAll genCoeffs lawSkewedStrictlyBelowUniform

  , testProperty "constant detail list = zero coded bits (flat-residual floor)" $
      forAll genDetail $ \d -> forAll (choose (0, 7)) $ \n -> lawConstantDetailZeroBits d n

  , testProperty "per-band reading differs from pooling all 7 bands (fixed witness)" $
      once lawPerBandDiffersFromPooled
  ]
