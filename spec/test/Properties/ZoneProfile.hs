module Properties.ZoneProfile (tests) where

import Test.Tasty
import Test.Tasty.QuickCheck
import qualified Data.Vector.Unboxed as U

import SixFour.Spec.ColorFixed (q16One)
import SixFour.Spec.ZoneProfile

-- A Q16 OKLab-ish triple: L in [0, q16One], a/b in [-q16One/4, q16One/4].
genPx :: Gen (Int, Int, Int)
genPx = do
  l <- choose (0, q16One)
  a <- choose (negate (q16One `div` 4), q16One `div` 4)
  b <- choose (negate (q16One `div` 4), q16One `div` 4)
  pure (l, a, b)

-- Center of zone z (mirrors the module-private formula) for the sample-at-center law.
center :: Int -> Int -> Int
center nz z = ((2 * z + 1) * q16One) `quot` (2 * nz)

tests :: TestTree
tests = testGroup "ZoneProfile"
  [ -- Sum-then-divide ⇒ the profile does not depend on input order. This is the
    -- gauge-invariance the Zig port must also have (it folds in array order, but
    -- the SUM is order-independent so the divided mean is too).
    testProperty "analyzeZoneProfileQ16 is permutation-invariant" $
      \pxs0 ->
        let pxs = map clampPx pxs0
        in analyzeZoneProfileQ16 pxs == analyzeZoneProfileQ16 (reverse pxs)

  , -- A palette confined to a single L-zone leaves every OTHER zone == global
    -- mean (the empty-zone fallback). Build colours all with tiny L (zone 0).
    testProperty "empty zones fall back to the global mean" $
      forAll (listOf1 genLowL) $ \pxs ->
        let zp = analyzeZoneProfileQ16 pxs
            nz = zpNumZones zp
            -- zones above 0 are empty here ⇒ must equal the global means
            allFallback v g = and [ (v U.! z) == g | z <- [1 .. nz - 1] ]
        in allFallback (zpMeanA zp) (zpGlobalA zp)
           && allFallback (zpMeanB zp) (zpGlobalB zp)
           && allFallback (zpMeanC zp) (zpGlobalC zp)

  , -- Sampling AT a zone center returns that zone's stored mean exactly (the
    -- interpolation knot passes through the data). Interior zones only.
    testProperty "sample at a zone center == that zone's stored mean" $
      forAll (listOf1 genPx) $ \pxs ->
        let zp = analyzeZoneProfileQ16 pxs
            nz = zpNumZones zp
            ok z = sampleZoneTargetQ16 zp (center nz z)
                     == (zpMeanA zp U.! z, zpMeanB zp U.! z, zpMeanC zp U.! z)
        in and [ ok z | z <- [0 .. nz - 1] ]

  , -- Below the first center / above the last, the target CLAMPS to the end zone
    -- (no extrapolation overshoot).
    testProperty "ends clamp: sample 0 == zone 0, sample q16One == last zone" $
      forAll (listOf1 genPx) $ \pxs ->
        let zp = analyzeZoneProfileQ16 pxs
            nz = zpNumZones zp
            lo = sampleZoneTargetQ16 zp 0
            hi = sampleZoneTargetQ16 zp q16One
        in lo == (zpMeanA zp U.! 0, zpMeanB zp U.! 0, zpMeanC zp U.! 0)
           && hi == (zpMeanA zp U.! (nz-1), zpMeanB zp U.! (nz-1), zpMeanC zp U.! (nz-1))

  , -- chromaQ16 is a genuine magnitude: on an axis it is the absolute component.
    testProperty "chromaQ16 a 0 == |a| and chromaQ16 0 b == |b|" $
      \a b -> chromaQ16 a 0 == abs a && chromaQ16 0 b == abs b
  ]
  where
    clampPx (l, a, b) =
      ( ((abs l) `mod` (q16One + 1))
      , ((a `mod` (q16One `div` 2)) )
      , ((b `mod` (q16One `div` 2)) ) )
    genLowL = do
      l <- choose (0, q16One `div` (2 * numZonesDefault))  -- inside zone 0
      a <- choose (negate (q16One `div` 4), q16One `div` 4)
      b <- choose (negate (q16One `div` 4), q16One `div` 4)
      pure (l, a, b)
