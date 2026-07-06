module Properties.MultiScaleCapture (tests) where

import Test.Tasty
import Test.Tasty.QuickCheck

import SixFour.Spec.MultiScaleCapture

-- A random 10-bit × 3 world: chans × subslices samples, each in 0..tenBitMax
-- (over-range values exercise worldFromList's clamp).
genWorld :: Gen [Integer]
genWorld = vectorOf (chans * fastFrames * subPerFast) (choose (0, tenBitMax))

tests :: TestTree
tests = testGroup "MultiScaleCapture (the independence contract: 16³/32³/64³ are independent world reads)"
  [ testGroup "Shared time axis (one clock, nested cadence)"
      [ testProperty "the 4:2:1 windows nest exactly (slow = ∪ fast = ∪ mid)" $
          once lawSharedTimeIsNested
      ]

  , testGroup "Not derivable (the coarse read is its own measurement)"
      [ testProperty "slow − pooled-fast == dead-time photons, exactly (keystone)" $
          forAll genWorld lawSlowMinusPoolIsDeadTime
      , testProperty "a gap-emitting world makes slow ≠ pool(fast)" $
          once lawScalesAreNotDerivable
      , testProperty "same fast read, different slow read ⇒ H(coarse | fine) > 0" $
          once lawIndependentScalesAddInformation
      ]

  , testGroup "Full 10-bit × 3 absorbed, and the u64 carrier contract"
      [ testProperty "ceiling world round-trips as exact integer sums, 3 channels independent" $
          once lawTenBitAbsorbed
      , testProperty "device-max per-channel accumulation fits u64 (Zig width contract)" $
          once lawCarrierWidthSuffices
      ]
  ]
