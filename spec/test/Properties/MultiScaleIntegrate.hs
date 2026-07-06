module Properties.MultiScaleIntegrate (tests) where

import Test.Tasty
import Test.Tasty.QuickCheck

import SixFour.Spec.MultiScaleIntegrate

-- A raw 10-bit sub-exposure stream: nCells × nSubslices samples (over-range
-- values exercise the clamp).
genStream :: Gen [Integer]
genStream = vectorOf (nCells * nSubslices) (choose (0, 2047))

tests :: TestTree
tests = testGroup "MultiScaleIntegrate (assemble the 3 independent volumes; disjoint = physically honest)"
  [ testProperty "KEYSTONE: the 3 volumes conserve the raw photons (each counted once)" $
      forAll genStream lawConservesPhotons
  , testProperty "a scale's volume uses ONLY the photons it owns (independence)" $
      forAll genStream $ \xs s sc -> lawVolumeUsesOnlyOwnedPhotons xs s sc
  , testProperty "the owner schedule is a well-formed disjoint cover" $
      once lawScheduleCoversAllScales
  , testProperty "10-bit × 3 absorbed exactly (ceiling stream → ownedCount·1023)" $
      once lawIntegrate10BitAbsorbed
  , testProperty "device-max per-cell accumulation fits the i64 carrier" $
      once lawIntegrateCarrierWidthSuffices
  ]
