module Properties.FidelityLadder (tests) where

import Test.Tasty
import Test.Tasty.QuickCheck

import SixFour.Spec.FidelityLadder

genFrames :: Gen [[Integer]]
genFrames = vectorOf 4 (vectorOf 16 (choose (0, 255)))

genVolume :: Gen [Integer]
genVolume = vectorOf (8 * 8 * 8) (choose (0, 255))

tests :: TestTree
tests = testGroup "FidelityLadder (mix the three views to high fidelity; cadence makes rungs commensurable)"
  [ testGroup "Each size is equivalent in data interpretation"
      [ testProperty "every rung's window totals the same mass (partition, not privilege)" $
          forAll genFrames lawRungsPartitionTheSameMass
      , testProperty "each coarse bin holds exactly 8x its child's mass (the seed's signal)" $
          forAll arbitrary lawCoarseBinIsEightChildren
      ]

  , testGroup "Refinement converges; mixing strictly beats paint"
      [ testProperty "KEYSTONE: SSE(d0) >= SSE(d1) >= SSE(d2) == 0, exact over Q" $
          forAll genVolume lawDeeperIsCloser
      , testProperty "a witnessed mix render exists that no paint mask can produce" $
          once lawMixesStrictlyExtendPaint
      ]
  ]
