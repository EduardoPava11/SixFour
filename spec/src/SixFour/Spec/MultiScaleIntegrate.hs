{- |
Module      : SixFour.Spec.MultiScaleIntegrate
Description : THE INTEGRATOR — assemble the three INDEPENDENT volumes (V16/V32/V64) from the raw laddered capture, and prove the independence is PHYSICAL: each scale integrates a DISJOINT set of the sub-exposures (an @owner@ schedule partitions every photon to exactly one scale), so no photon is shared and no scale's volume is a function of another's. This strengthens "SixFour.Spec.MultiScaleCapture" from "not derivable" to "fully independent by conservation", and produces exactly the volumes "SixFour.Spec.RenderSelect" consumes.

WHY DISJOINT (the physical honesty): a photon is absorbed once — it cannot be in both a short and a long exposure. So the interleaved exposure ladder must ALLOCATE the sub-exposures, each to one scale (here a round-robin @owner@; the device uses the real interleaving pattern, any total assignment works). The integrator then SUMS each scale's owned sub-exposures into its volume in the wide (i64) carrier.

THE THEOREMS:
  * 'lawConservesPhotons' (KEYSTONE — disjoint = physically honest): summing the three scales' volumes recovers the total raw photons, per cell — every photon counted EXACTLY once. No sharing (would double-count), no loss.
  * 'lawVolumeUsesOnlyOwnedPhotons' (independence): a scale's volume is invariant to any photon a DIFFERENT scale owns — perturbing scale B's sub-exposures never moves scale A's volume. Full independence, stronger than mere non-derivability.
  * 'lawScheduleCoversAllScales': the schedule is a well-formed disjoint cover — every scale owns at least one sub-exposure, and their union is the whole stream.
  * 'lawIntegrate10BitAbsorbed': 10-bit × 3 preserved exactly — a ceiling stream integrates to @ownedCount · 1023@ per channel, three channels independent, no truncation.
  * 'lawIntegrateCarrierWidthSuffices': the widest per-cell accumulation fits the i64 carrier (the width contract the Zig kernel honors).

Model: @photons cell s@ is the raw 10-bit sub-exposure at (cell = bin×channel, sub-slice s); @volume scale cell@ sums the sub-slices that scale OWNS. The Zig twin is @Native/src/multiscale_integrate.zig@ (s4_multiscale_integrate).
-}
-- COMPARTMENT: PURE-SPEC-WALL | tag:none
module SixFour.Spec.MultiScaleIntegrate
  ( -- * The raw stream, the disjoint schedule, and the integrator
    nScales
  , nSubslices
  , nCells
  , owner
  , photons
  , volume
  , ownedCount
    -- * Laws
  , lawConservesPhotons
  , lawVolumeUsesOnlyOwnedPhotons
  , lawScheduleCoversAllScales
  , lawIntegrate10BitAbsorbed
  , lawIntegrateCarrierWidthSuffices
  ) where

import Data.List (nub)

import SixFour.Spec.MultiScaleCapture (tenBitMax)

-- | The three scales (0 = coarse/16³, 1 = mid/32³, 2 = fine/64³).
nScales :: Int
nScales = 3

-- | Sub-exposures on the finest temporal grid (the raw stream length per cell).
nSubslices :: Int
nSubslices = 12

-- | Cells in the mini model = bins × channels (here 3, one per R/G/B, to exercise
-- channel independence).
nCells :: Int
nCells = 3

-- | THE SCHEDULE: which scale OWNS each sub-exposure. A round-robin partition —
-- every sub-slice to exactly one scale, all three covered. The device supplies
-- its real interleaving; any total assignment is a valid disjoint cover.
owner :: Int -> Int
owner s = s `mod` nScales

-- | The raw 10-bit sub-exposure at @(cell, sub-slice)@, from a flat
-- @nCells × nSubslices@ list (clamped to the 10-bit ceiling; out of range = 0).
photons :: [Integer] -> Int -> Int -> Integer
photons xs cell s
  | cell < 0 || cell >= nCells || s < 0 || s >= nSubslices = 0
  | otherwise = clamp (padded !! (cell * nSubslices + s))
  where
    padded = take (nCells * nSubslices) (xs ++ repeat 0)
    clamp v = max 0 (min tenBitMax v)

-- | THE INTEGRATOR: a scale's volume at a cell = the exact i64 sum of the
-- sub-exposures that scale OWNS. Disjoint by @owner@, so the three volumes are
-- built from disjoint photons.
volume :: [Integer] -> Int -> Int -> Integer
volume xs scale cell = sum [ photons xs cell s | s <- [0 .. nSubslices - 1], owner s == scale ]

-- | How many sub-slices a scale owns (its integration length).
ownedCount :: Int -> Int
ownedCount scale = length [ s | s <- [0 .. nSubslices - 1], owner s == scale ]

allScales :: [Int]
allScales = [0 .. nScales - 1]

allCells :: [Int]
allCells = [0 .. nCells - 1]

-- | LAW (KEYSTONE — conservation, i.e. disjoint photons): the three scales'
-- volumes sum, per cell, to the total raw photons — every sub-exposure counted
-- EXACTLY once. Sharing would double-count (sum too high); loss would undercount.
-- Physical honesty: a photon lands in one scale, and all of them land somewhere.
lawConservesPhotons :: [Integer] -> Bool
lawConservesPhotons xs =
  and [ sum [ volume xs scale cell | scale <- allScales ]
          == sum [ photons xs cell s | s <- [0 .. nSubslices - 1] ]
      | cell <- allCells ]

-- | LAW (independence): a scale's volume depends ONLY on the sub-exposures it
-- owns. Perturbing a photon a DIFFERENT scale owns leaves this scale's whole
-- volume byte-identical — full independence, not just non-derivability.
lawVolumeUsesOnlyOwnedPhotons :: [Integer] -> Int -> Int -> Bool
lawVolumeUsesOnlyOwnedPhotons xs sRaw scaleRaw =
  owner s0 == scale
    || and [ volume xs scale cell == volume bumped scale cell | cell <- allCells ]
  where
    s0 = abs sRaw `mod` nSubslices
    scale = abs scaleRaw `mod` nScales
    -- bump the photon at sub-slice s0 (owned by owner s0) across every cell.
    bumped = [ x + (if (i `mod` nSubslices) == s0 then 100 else 0) | (i, x) <- zip [0 ..] padded ]
    padded = take (nCells * nSubslices) (xs ++ repeat 0)

-- | LAW (well-formed disjoint cover): every scale owns at least one sub-exposure,
-- and the owners over the whole stream are exactly the scales — a partition, no
-- gap, no overlap.
lawScheduleCoversAllScales :: Bool
lawScheduleCoversAllScales =
  nub (map owner [0 .. nSubslices - 1]) == allScales
    && all (\sc -> ownedCount sc >= 1) allScales

-- | LAW (full 10-bit × 3 absorbed): a stream at the 10-bit ceiling integrates to
-- the EXACT product @ownedCount · tenBitMax@ per scale, in every cell (channel),
-- with no truncation — the three channels stay independent.
lawIntegrate10BitAbsorbed :: Bool
lawIntegrate10BitAbsorbed =
  and [ volume ceil scale cell == fromIntegral (ownedCount scale) * tenBitMax
      | scale <- allScales, cell <- allCells ]
  where ceil = replicate (nCells * nSubslices) tenBitMax

-- | LAW (the carrier-width contract for Zig): the widest per-cell accumulation on
-- the real device — the coarsest 4×4 spatial bin integrating the full 64-frame
-- long exposure at the 10-bit ceiling — fits with vast headroom in the i64
-- carrier. This is the bound the kernel must honor so no 10-bit is lost.
lawIntegrateCarrierWidthSuffices :: Bool
lawIntegrateCarrierWidthSuffices = deviceMaxPerCell < 2 ^ (63 :: Int)
  where
    coarseSpatialBin = 4 * 4 :: Int
    deviceSubslices  = 64 :: Int
    deviceMaxPerCell = fromIntegral (coarseSpatialBin * deviceSubslices) * tenBitMax
