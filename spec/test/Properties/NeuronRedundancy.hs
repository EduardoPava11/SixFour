module Properties.NeuronRedundancy (tests) where

import Test.Tasty
import Test.Tasty.QuickCheck

import SixFour.Spec.NeuronRedundancy

-- a rectangular neuron batch: s samples (>=2) x n neurons (>=1)
genBatch :: Gen NeuronBatch
genBatch = do
  s <- choose (2, 8)
  n <- choose (1, 6)
  vectorOf s (vectorOf n (choose (-10.0, 10.0)))

tests :: TestTree
tests = testGroup "NeuronRedundancy (Barlow-Twins redundancy of the intermediate-latent neuron outputs)"
  [ testProperty "redundancy is non-negative (a sum of squares)" $
      forAll genBatch lawRedundancyNonNegative
  , testProperty "TEETH: identical neurons are maximally redundant (corr=1)" $
      once lawIdenticalNeuronsAreFullyRedundant
  , testProperty "TEETH: decorrelated neurons carry zero redundancy" $
      once lawDecorrelatedNeuronsZeroRedundancy
  , testProperty "redundancy must be read in LATENT space (surfacing destroys it)" $
      once lawRedundancyMeasuredInLatent
  ]
