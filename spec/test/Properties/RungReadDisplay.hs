module Properties.RungReadDisplay (tests) where

import Test.Tasty
import Test.Tasty.QuickCheck

import SixFour.Spec.RungReadDisplay

-- The synthetic weave's mid-rung owned ticks over a 16-tick window: three
-- dwells starting at ticks 0/4/10, settle 2, two owned frames each — the
-- settle-2 fixture shape (owned ticks are SPARSE and scattered).
goldenOwnedTicks :: [Int]
goldenOwnedTicks = [2, 3, 6, 7, 12, 13]

-- Coded probe volumes: values name their own coordinates, so every probe is
-- hand-checkable. v16 side 2, v32 side 4, v64 side 8.
v16c, v32c, v64c :: (Int, Int, Int) -> Integer
v16c (x, y, t) = 100 + toInteger ((t * 2 + y) * 2 + x)
v32c (x, y, t) = 200 + toInteger ((t * 4 + y) * 4 + x)
v64c (x, y, t) = 1000 + toInteger ((t * 8 + y) * 8 + x)

-- The mixed golden field: region r at depth r mod 3 (all three depths hit).
goldenField :: Int -> Int
goldenField r = r `mod` 3

tests :: TestTree
tests = testGroup "RungReadDisplay (show a region from ITS OWN read: causal slice hold, exact realize counts, provenance gate, per-frame sampler)"
  [ -- Causal slice lookup ----------------------------------------------------
    testProperty "lawOwnedTickShowsOwnSlice: the i-th owned tick shows slice i (fresh reads win instantly)" $
      \xs i -> lawOwnedTickShowsOwnSlice xs i

  , testProperty "lawHoldIsCausal: the shown slice is the last arrival <= t; slice 0 before the first; monotone in t" $
      \xs t -> lawHoldIsCausal xs t

  , testProperty "goldenSliceForTick16: the pinned 16-tick hold table for the settle-2 fixture weave" $
      once (map (sliceForTick goldenOwnedTicks) [0 .. 15]
              == [0, 0, 0, 1, 1, 1, 2, 3, 3, 3, 3, 3, 4, 5, 5, 5])

  , testProperty "FOIL (non-vacuity): naive frame/2 indexing disagrees with the causal hold on the fixture" $
      once (map (sliceForTick goldenOwnedTicks) [0 .. 15]
              /= map (`div` 2) [0 .. 15])

    -- The realize pixel base -------------------------------------------------
  , testProperty "lawSliceCountMatchesProvenance: ladder slices are 1-tick, derived c16 is 4-tick; 256 and 4096 at area 64" $
      \a -> lawSliceCountMatchesProvenance a

  , testProperty "ticks-per-slice WITNESS: ladder 1, derived 4 (= fastPerSlow)" $
      once (ladderTicksPerSlice == 1 && derivedTicksPerSlice == 4)

    -- The shared clock -------------------------------------------------------
  , testProperty "lawTemporalQuantizeOnSharedClock: tq is the block start, never ahead of t; block sides = cadence ratios" $
      \d t -> lawTemporalQuantizeOnSharedClock d t

    -- The sampler gate -------------------------------------------------------
  , testProperty "lawSamplerMatchesRenderSelectWhenDense: the per-frame sampler == renderSelect on every voxel, any field" $
      \fld a b c -> lawSamplerMatchesRenderSelectWhenDense fld a b c

  , testProperty "golden sampler probes: hand-checked reads across all three depths on the coded volumes" $
      once (map (\(t, p) -> frameSample goldenField v16c v32c v64c t p)
              [ (0, (0, 0)), (0, (5, 0)), (2, (1, 5)), (1, (6, 6))
              , (6, (3, 2)), (7, (7, 3)), (5, (2, 7)), (4, (5, 4))
              , (3, (0, 0)) ]
              == [100, 202, 1169, 103, 253, 1479, 106, 242, 100])

    -- Provenance -------------------------------------------------------------
  , testProperty "lawDerivedNeverClaimsReads: c16-only = derived signature, never independent; all-empty is neither" $
      \c16 -> lawDerivedNeverClaimsReads c16
  ]
