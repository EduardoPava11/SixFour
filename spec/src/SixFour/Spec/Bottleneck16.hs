{- |
Module      : SixFour.Spec.Bottleneck16
Description : The 16³ = 4096-bin OKLab histogram as a typed probability simplex.

The same grid that 'SixFour.Spec.Coverage' uses for the gamut-coverage metric is
promoted here to a first-class internal representation: the capture's empirical
OKLab distribution over 4096 voxels. Bin indices are linearised as
@iL·256 + ia·16 + ib@ (the natural row-major order over @(iL, ia, ib) ∈ [0,16)³@).

This is the L1' stage of the proposed bottleneck-16 redesign: a histogram
representation that lives on the SAME grid as the coverage objective, so
@gamutCoverageFraction ≡ #{i : H i > 0} / 4096@ by construction. Pairs with
'SixFour.Spec.SigmaDecomp' for the σ-eigenspace split @H = H_sym + H_asym@.

The 'Histogram4096' constructor is exported for friend modules
(SigmaDecomp, Quad4) that prove the simplex invariant by math; external callers
should use the smart constructors ('histogramFromOKLabs', 'histogramFromPalette',
'uniformHistogram', or 'mkHistogramFromSimplex') instead.

Laws (see @Properties.Bottleneck16@): mass-preservation; non-negativity;
@binToCoords ∘ binIndex = id@; binning agrees with 'Spec.Coverage.okLabBin';
coverage compatibility (#non-zero bins of a palette's histogram recovers
'Spec.Coverage.occupiedBins').
-}
module SixFour.Spec.Bottleneck16
  ( -- * The branded 4096-bin histogram
    Histogram4096(..)
  , numBins
  , numBinsPerAxis
    -- * Bin coordinates
  , binIndex
  , binToCoords
  , okLabBinIndex
    -- * Smart constructors
  , histogramFromOKLabs
  , histogramFromPalette
  , uniformHistogram
  , mkHistogramFromSimplex
    -- * Laws
  , lawMassPreservation
  , lawNonNegative
  , lawBinIndexRoundTrip
  , lawCoverageCompatibility
  ) where

import qualified Data.Set            as Set
import qualified Data.Vector         as V
import qualified Data.Vector.Unboxed as U
import           Data.Vector.Unboxed (Vector)

import SixFour.Spec.Color    (OKLab(..))
import SixFour.Spec.Coverage (coverageBinsPerAxis, okLabBin)
import SixFour.Spec.Palette  (Palette(..))

-- | Bins per OKLab axis. Pinned to 'SixFour.Spec.Coverage.coverageBinsPerAxis' = 16
-- so the bottleneck representation lives on the same grid the coverage metric scores.
numBinsPerAxis :: Int
numBinsPerAxis = coverageBinsPerAxis

-- | Total bins = @numBinsPerAxis³@ = 4096.
numBins :: Int
numBins = numBinsPerAxis * numBinsPerAxis * numBinsPerAxis

-- | A branded 4096-vector on the probability simplex: @Σᵢ H i = 1@, @H i ≥ 0@.
-- Constructor exported only for friend modules that prove the simplex invariant
-- by math (see 'SixFour.Spec.SigmaDecomp.symPart'); external callers should use
-- the smart constructors below.
newtype Histogram4096 = Histogram4096 { unHistogram :: Vector Double }
  deriving (Eq, Show)

-- | Linearise voxel coords @(iL, ia, ib) ∈ [0,16)³@ into a flat bin index ∈ [0,4096).
binIndex :: (Int, Int, Int) -> Int
binIndex (iL, ia, ib) =
  iL * (numBinsPerAxis * numBinsPerAxis) + ia * numBinsPerAxis + ib

-- | Inverse of 'binIndex': flat index ∈ [0,4096) → @(iL, ia, ib) ∈ [0,16)³@.
binToCoords :: Int -> (Int, Int, Int)
binToCoords i =
  let n  = numBinsPerAxis
      ib = i `mod` n
      r  = i `div` n
      ia = r `mod` n
      iL = r `div` n
  in (iL, ia, ib)

-- | Bin index of an OKLab colour through 'SixFour.Spec.Coverage.okLabBin', then
-- linearised. The single source of truth for "which voxel a colour lands in".
okLabBinIndex :: OKLab -> Int
okLabBinIndex = binIndex . okLabBin

-- | Build a histogram from a list of OKLab samples (empirical normalised count).
-- Empty list yields the uniform histogram so the brand always holds.
histogramFromOKLabs :: [OKLab] -> Histogram4096
histogramFromOKLabs []  = uniformHistogram
histogramFromOKLabs xs  =
  let n      = numBins
      idxs   = [ (okLabBinIndex c, 1.0 :: Double) | c <- xs ]
      counts = U.accum (+) (U.replicate n 0.0) idxs
      total  = U.sum counts
  in if total <= 0
       then uniformHistogram
       else Histogram4096 (U.map (/ total) counts)

-- | Build a histogram from a palette (one count per entry, then normalise).
histogramFromPalette :: Palette k -> Histogram4096
histogramFromPalette (Palette v) = histogramFromOKLabs (V.toList v)

-- | The uniform histogram: every bin = 1/4096. The trivial σ-symmetric baseline.
uniformHistogram :: Histogram4096
uniformHistogram =
  Histogram4096 (U.replicate numBins (1.0 / fromIntegral numBins))

-- | Checked promotion of a raw simplex vector to a 'Histogram4096'. Returns
-- 'Nothing' if the length, non-negativity, or mass-1 invariant fails.
mkHistogramFromSimplex :: Double -> Vector Double -> Maybe Histogram4096
mkHistogramFromSimplex tol v
  | U.length v /= numBins      = Nothing
  | not (U.all (>= 0) v)       = Nothing
  | abs (U.sum v - 1.0) > tol  = Nothing
  | otherwise                  = Just (Histogram4096 v)

-- * Laws

-- | Total mass is 1 (within tolerance).
lawMassPreservation :: Double -> Histogram4096 -> Bool
lawMassPreservation tol (Histogram4096 v) = abs (U.sum v - 1.0) <= tol

-- | Every bin is non-negative.
lawNonNegative :: Histogram4096 -> Bool
lawNonNegative (Histogram4096 v) = U.all (>= 0) v

-- | @binToCoords ∘ binIndex = id@ on @[0,16)³@.
lawBinIndexRoundTrip :: (Int, Int, Int) -> Bool
lawBinIndexRoundTrip (iL, ia, ib) =
  let n = numBinsPerAxis
  in not (iL >= 0 && iL < n && ia >= 0 && ia < n && ib >= 0 && ib < n) ||
     binToCoords (binIndex (iL, ia, ib)) == (iL, ia, ib)

-- | Counting non-zero bins of a palette's histogram equals
-- 'SixFour.Spec.Coverage.occupiedBins' on a single palette — so the bottleneck
-- refines the coverage metric rather than replacing it.
lawCoverageCompatibility :: Palette k -> Bool
lawCoverageCompatibility pal@(Palette v) =
  let Histogram4096 h = histogramFromPalette pal
      nonZero         = U.length (U.filter (> 0) h)
      occByCoverage   = Set.size (Set.fromList [ okLabBinIndex c | c <- V.toList v ])
  in nonZero == occByCoverage
