module Properties.EventEncoding (tests) where

import Test.Tasty
import Test.Tasty.QuickCheck
import Data.Ratio ((%))

import SixFour.Spec.EventEncoding

-- Signals: exact rationals over a modest range, freely off-grid and negative (Hermite is
-- an identity for ALL reals, so recovery must hold there too).
genSig :: Gen Rational
genSig = do
  n <- choose (-4096, 4096) :: Gen Integer
  d <- choose (1, 256)      :: Gen Integer
  pure (n % d)

genT :: Gen Int
genT = choose (1, 64)

genK :: Gen Int
genK = choose (0, 8)

tests :: TestTree
tests = testGroup "EventEncoding (temporal dither: entropy ↑, signal captured by ∫ = color-time)"
  [ testProperty "HERMITE: Σᵢ ⌊s + i/T⌋ = ⌊T·s⌋ (entropy up, signal captured exactly)" $
      forAll genSig $ \s -> forAll genT $ \t -> lawHermiteDither s t
  , testProperty "RATE–DISTORTION: 0 ≤ s − decode < 1/T" $
      forAll genSig $ \s -> forAll genT $ \t -> lawDecodeRecoversSignal s t
  , testProperty "ADDED BITS: decode lands on the (1/T)-grid (denominator ∣ T)" $
      forAll genSig $ \s -> forAll genT $ \t -> lawDecodeOnFineGrid s t
  , testProperty "ENTROPY UP: off-grid ⇒ exactly two distinct codes (marginal H > 0)" $
      forAll genSig $ \s -> forAll (choose (2, 64)) $ \t -> lawEncodingRaisesEntropy s t
  , testProperty "LADDER: rung-k dither ⇒ 2^k-grid (k added bits)" $
      forAll genSig $ \s -> forAll genK $ \k -> lawLadderDitherBits s k
  ]
