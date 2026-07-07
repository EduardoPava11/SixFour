module Properties.HaltDepth (tests) where

import Test.Tasty
import Test.Tasty.QuickCheck

import SixFour.Spec.HaltDepth

genOrder :: Gen Int
genOrder = choose (-2, 8)

genDepth :: Gen Int
genDepth = choose (-1, 4)   -- out-of-range too, to exercise the clamp

genOrders :: Gen [Int]
genOrders = choose (0, 24) >>= \n -> vectorOf n genOrder

genCoeffs :: Gen [Integer]
genCoeffs = choose (0, 8) >>= \n -> vectorOf n (choose (-32, 32))

tests :: TestTree
tests = testGroup "HaltDepth (certified order → render depth; motion buys detail, stillness keeps color-time)"
  [ testProperty "BOUNDED: haltDepth ∈ {0,1,2}" $ forAll genOrder lawHaltDepthBounded
  , testProperty "MONOTONE: a ≤ b ⇒ haltDepth a ≤ haltDepth b" $
      forAll genOrder $ \a -> forAll genOrder $ \b -> lawHaltDepthMonotone a b
  , testProperty "THRESHOLDS: −1/0/1→0, 2→1, ≥3→2" $ once lawHaltDepthThresholds
  , testProperty "UNCERTIFIED (order<0) is coarsest" $ forAll genOrder lawUncertifiedIsCoarsest
  , testProperty "depth drives the exact RenderSelect block side 4/2^d" $
      forAll genOrder lawDepthDrivesValidBlock
  , testProperty "user brush can only REFINE (finest-wins max)" $
      forAll genDepth $ \u -> forAll genOrder $ \o -> lawUserCanOnlyRefine u o
  , testProperty "mergeDepth is a semilattice (idem/comm/assoc)" $
      forAll genDepth $ \a -> forAll genDepth $ \b -> forAll genDepth $ \c -> lawMergeSemilattice a b c
  , testProperty "ALL-FINE: all order≥3 ⇒ all depth-2 (= identity on V64)" $
      forAll genOrders lawAllHighIsAllFine
  , testProperty "ALL-STATIC: all order≤1 ⇒ all depth-0 (max color-time)" $
      forAll genOrders lawAllStaticIsAllCoarse
  , testProperty "TRADEOFF: more motion order ⇒ ≤ color-time" $
      forAll genOrder $ \a -> forAll genOrder $ \b -> lawMotionSpendsColorTime a b
  , testProperty "composes with certifiedOrder, stays in {0,1,2}" $
      forAll (choose (1, 5)) $ \cap -> forAll genCoeffs $ \f -> lawDepthOfCertifiedBounded cap f
  ]
