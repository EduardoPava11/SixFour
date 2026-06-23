{- |
Module      : SixFour.Spec.Coverage
Description : Gamut-coverage metric — the data-driven yardstick for the
              per-frame-palette diversity objective.

The per-frame palette exists to capture a wide variety of true OKLab colour;
a NN collapses the per-frame variation. So the quantity every capture decision
is judged by — seed A/B, Wu+KM vs farthest-point — is **gamut coverage**: how
much of OKLab the burst's centroids occupy, NOT reconstruction MSE.

Coverage voxelises OKLab into @coverageBinsPerAxis³@ cells and counts the
distinct cells the palettes' entries occupy (union across frames — per-frame
variation is the point, not a defect). @coverageBinsPerAxis@ is emitted to
Swift + Python so the app, this oracle, and the trainer score coverage on the
identical grid; @okLabBin@ is the bit-mirrored binning the Swift
`ClusterStatisticsOps.gamutCoverage` must match (same arithmetic, clamped,
truncation == floor for the non-negative working range).

Laws (see @Properties.Coverage@): fraction ∈ [0,1]; occupied ≤ total; monotone
under union; @S_K@ gauge-invariant (palette reorder); a single-colour palette
occupies exactly one bin; bin indices stay in @[0, n)@.
-}
-- COMPARTMENT: METAL-GPU | tag:none | STRADDLER
module SixFour.Spec.Coverage
  ( coverageBinsPerAxis
  , okLabBin
  , occupiedBins
  , gamutCoverageFraction
  ) where

import qualified Data.Set    as Set
import qualified Data.Vector as V

import SixFour.Spec.Color   (OKLab(..))
import SixFour.Spec.Palette (Palette(..))

-- | Bins per OKLab axis for the coverage grid: 16³ = 4096 cells.
coverageBinsPerAxis :: Int
coverageBinsPerAxis = 16

-- | OKLab → integer voxel @(iL, ia, ib) ∈ [0, n)³@. @L@ binned over @[0,1]@;
-- @a, b@ over @[-0.5, 0.5]@ (the OKLab working range), clamped. The Swift
-- `binL`/`binAB` MUST match: @floor@ equals Swift's @Int(·)@ truncation here
-- because every argument is non-negative after the @+0.5@ shift.
okLabBin :: OKLab -> (Int, Int, Int)
okLabBin (OKLab l a b) = (binL l, binAB a, binAB b)
  where
    n = coverageBinsPerAxis
    clamp i = max 0 (min (n - 1) i)
    binL  v = clamp (floor (v * fromIntegral n))
    binAB v = clamp (floor ((v + 0.5) * fromIntegral n))

-- | Distinct occupied voxels across a list of palettes (union of all entries).
occupiedBins :: [Palette k] -> Int
occupiedBins pals = Set.size $ Set.fromList
  [ okLabBin c | Palette v <- pals, c <- V.toList v ]

-- | Occupied fraction ∈ [0,1]: occupied voxels / @coverageBinsPerAxis³@.
gamutCoverageFraction :: [Palette k] -> Double
gamutCoverageFraction pals =
  fromIntegral (occupiedBins pals) / fromIntegral (coverageBinsPerAxis ^ (3 :: Int))
