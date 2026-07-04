module Properties.PaletteKinetics (tests) where

import Test.Tasty
import Test.Tasty.QuickCheck

import SixFour.Spec.PaletteKinetics

-- A small 4x4 frame (flat, padded by the laws).
genFrame :: Gen [Integer]
genFrame = vectorOf 16 (choose (-500, 500))

-- A short fine stream of 4x4 frames.
genStream :: Gen [[Integer]]
genStream = vectorOf 6 genFrame

-- Small nonnegative value-counts (a bin histogram fragment).
genCounts :: Gen [Integer]
genCounts = vectorOf 3 (choose (0, 7))

tests :: TestTree
tests = testGroup "PaletteKinetics (256 particles: position, mass, velocity; entropy = exact W)"
  [ testGroup "The base: 256 slots ordered by (x,y)"
      [ testProperty "slot <-> bin is a bijection [0,255] <-> 16x16" $
          once lawSlotIsXYOrder
      ]

  , testGroup "Kinetics (exact, from linearity)"
      [ testProperty "mass is conserved under pooling (the sums carrier)" $
          forAll genFrame lawMassPoolsExactly
      , testProperty "velocity commutes with spatial pooling: pool(delta) == delta(pool)" $
          forAll genStream lawVelocityCommutesWithPooling
      , testProperty "KEYSTONE: coarse velocity = pooled (1,2,1)-smoothed fine velocity" $
          forAll genStream lawCoarseVelocityIsBinomialSmoothing
      ]

  , testGroup "Entropy as exact microstate counting (W Integer, H = log W never landed)"
      [ testProperty "certainty is mass concentration: W == 1 iff one value holds all mass" $
          forAll (vectorOf 6 (choose (-20, 20))) lawCertainMassHasOneMicrostate
      , testProperty "maximum entropy is the balanced split (m <= 24, exhaustive)" $
          once lawMaxEntropyIsBalancedSplit
      , testProperty "KEYSTONE: chain rule = integer factorization W(fine) == W(coarse) * prod W(within)" $
          forAll genCounts $ \a -> forAll genCounts $ \b -> lawMicrostatesChainRule a b
      , testProperty "data processing as divisibility: W(coarse) | W(fine), quotient exact" $
          forAll genCounts $ \a -> forAll genCounts $ \b -> lawCoarseningNeverIncreasesW a b
      ]
  ]
