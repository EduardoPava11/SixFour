module Properties.ByteCarrier (tests) where

import Test.Tasty
import Test.Tasty.QuickCheck

import SixFour.Spec.ByteCarrier

genD :: Gen Double
genD = choose (-1000, 1000)

tests :: TestTree
tests = testGroup "ByteCarrier (typed device-byte vs Mac-float boundary; leak = compile error)"
  [ testProperty "a float reaches a byte ONLY via reenterQ16 (= quantizeQ16)" $
      forAll genD lawByteOnlyFromQ16

  , testProperty "a value on the Q16 floor is a re-entry fixpoint (zero-genome==floor)" $
      forAll (choose (-1000000, 1000000)) lawReentryIsFloor

  , testProperty "the device carrier round-trips: toByte . q16 = id" $
      forAll (choose (-1000000, 1000000)) lawDeviceRoundTrips

    -- NOTE: `toByte someLatent` is a TYPE ERROR (no exported Latent -> Int), which is
    -- the real guarantee; it cannot be expressed as a runtime property.
  ]
