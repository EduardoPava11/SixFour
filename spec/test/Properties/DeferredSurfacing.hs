module Properties.DeferredSurfacing (tests) where

import Test.Tasty
import Test.Tasty.QuickCheck

import SixFour.Spec.OctreeGenome (octreeLeafCount)
import SixFour.Spec.DeferredSurfacing

-- a Q16-ish coarse value cube of the right length for a small depth
genCapture :: Int -> Gen [Int]
genCapture d = vectorOf (octreeLeafCount d) (choose (-32768, 32768))

tests :: TestTree
tests = testGroup "DeferredSurfacing (rung-1 latent search; surface 16³+residual after rung 2)"
  [ testProperty "KEYSTONE: deferring the surface crossing preserves sub-quantum latent distinctions" $
      forAll (choose (0, 1000000)) lawDeferredSurfacingPreservesSubQuantum
  , testProperty "the first rung is a latent search (score separates what surfacing collapses)" $
      forAll (choose (0, 1000000)) lawFirstRungIsLatentSearch
  , testProperty "surfacing comes once, after BOTH rungs (no early surface)" $
      once lawSurfaceComesAfterBothRungs
  , testProperty "once surfaced, the 16³+residual reconstructs EXACTLY" $
      forAll (choose (0, 2)) $ \d ->
        forAll (choose (0, d)) $ \k ->
          forAll (genCapture d) $ \cap -> lawSurfacedOutputIsExact k d cap
  , testProperty "one θ_B drives the latent search across BOTH rungs before the single commit" $
      forAll (vectorOf paramCountBForTest (choose (-2.0, 2.0))) $ \ps ->
        forAll (choose (0, 65536)) $ \v -> lawSearchReusesBothRungs ps v
  ]
  where
    -- the 63-param width of MaskedBandPrediction's θ_B (kept local to avoid an extra import)
    paramCountBForTest = 63
