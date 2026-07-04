module Properties.MixSKI (tests) where

import Test.Tasty
import Test.Tasty.QuickCheck

import SixFour.Spec.MixSKI

genVolume :: Gen [Integer]
genVolume = vectorOf (8 * 8 * 8) (choose (0, 255))

genDepths :: Gen [Int]
genDepths = vectorOf 8 (choose (0, 2))

tests :: TestTree
tests = testGroup "MixSKI (what SKI says: K,I canonical; the mix is the section; the gene lives on S)"
  [ testGroup "The mix never leaves the K-chain"
      [ testProperty "depth pulls are wash composites; washes compose along the chain (exact Q)" $
          forAll genVolume lawSectionFactorsThroughChain
      ]

  , testGroup "S carries all the freedom; K certifies it carries nothing else"
      [ testProperty "all mixes are K-indistinguishable: coarse marginals invariant under mixing" $
          forAll genDepths $ \ds -> forAll genVolume (lawMixesShareCoarseViews ds)
      , testProperty "the section space carries 3^8 distinguishable outputs (witness, every region)" $
          once lawMixesAreDistinguishable
      ]
  ]
