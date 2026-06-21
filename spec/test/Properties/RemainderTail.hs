module Properties.RemainderTail (tests) where

import Test.Tasty
import Test.Tasty.QuickCheck

import SixFour.Spec.RemainderTail

genD :: Gen Double
genD = choose (-100, 100)

tests :: TestTree
tests = testGroup "RemainderTail (discrete-surfaced vs continuous-remainder split — B6/B1)"
  [ testProperty "surfaced layer is exact on the integer grid" $
      forAll (listOf (choose (-1000, 1000))) lawSurfacedExact

  , testProperty "continuous remainder reconstructs within eps" $
      forAll (listOf genD) lawTailWithinEps

  , testProperty "the continuous tail is NOT bit-exact (forbids 'lossless by construction')" $
      once lawTailNotExactWitness

  , testProperty "B1: losslessness needs the remainder (dropping it is strictly worse than eps)" $
      once lawLosslessNeedsRemainder

  , testProperty "the tail is one-shot, not autoregressed (no node depends on the tail)" $
      forAll (choose (0, 20)) lawTailNotAutoregressed

  , testProperty "the held remainder channel count is bounded (1 <= n <= cTail)" $
      once lawRemainderChannelsBounded
  ]
