module Properties.Bottleneck16 (tests) where

import Test.Tasty
import Test.Tasty.QuickCheck
import Test.QuickCheck

import qualified Data.Vector.Unboxed as U
import           Data.Maybe          (fromJust)

import SixFour.Spec.Color       (OKLab(..))
import SixFour.Spec.Palette     (Palette, mkPalette)
import SixFour.Spec.Coverage    (coverageBinsPerAxis, occupiedBins, gamutCoverageFraction)
import SixFour.Spec.Bottleneck16

type K = 8

genOKLab :: Gen OKLab
genOKLab = OKLab <$> choose (0, 1) <*> choose (-0.4, 0.4) <*> choose (-0.4, 0.4)

genPalette :: Gen (Palette K)
genPalette = fromJust . mkPalette @K <$> vectorOf 8 genOKLab

-- A bin-grid coord in [0, 16)³.
genBinCoord :: Gen (Int, Int, Int)
genBinCoord = (,,) <$> choose (0, n - 1) <*> choose (0, n - 1) <*> choose (0, n - 1)
  where n = numBinsPerAxis

genHistogram :: Gen Histogram4096
genHistogram = histogramFromOKLabs <$> listOf genOKLab

tests :: TestTree
tests = testGroup "Bottleneck16 (16³ OKLab histogram as a typed probability simplex)"
  [ testProperty "constants: 16 bins/axis, 4096 bins, grid matches Spec.Coverage" $
      once $
           numBinsPerAxis == coverageBinsPerAxis
        && numBins == 16 * 16 * 16
        && numBins == 4096

  , testProperty "mass preservation: Σ H = 1 (tol 1e-9)" $
      forAll genHistogram (lawMassPreservation 1e-9)

  , testProperty "non-negativity: every bin ≥ 0" $
      forAll genHistogram lawNonNegative

  , testProperty "binIndex ∘ binToCoords is the identity on [0, 4096)" $
      forAll (choose (0, numBins - 1)) $ \i ->
        binIndex (binToCoords i) == i

  , testProperty "binToCoords ∘ binIndex is the identity on [0, 16)³" $
      forAll genBinCoord lawBinIndexRoundTrip

  , testProperty "uniform histogram is mass-1 non-negative" $
      once $
           lawMassPreservation 1e-12 uniformHistogram
        && lawNonNegative uniformHistogram

  , testProperty "coverage compatibility: #non-zero bins = occupiedBins[pal]" $
      forAll genPalette lawCoverageCompatibility

  , testProperty "mkHistogramFromSimplex round-trips through unHistogram" $
      forAll genHistogram $ \h ->
        case mkHistogramFromSimplex 1e-6 (unHistogram h) of
          Just h' -> h' == h
          Nothing -> False

  , testProperty "mkHistogramFromSimplex rejects wrong-length vectors" $
      once $
        mkHistogramFromSimplex 1e-9 (U.replicate (numBins + 1) (1.0 / fromIntegral (numBins + 1))) == Nothing

  , testProperty "mkHistogramFromSimplex rejects negative entries" $
      once $
        let v = U.generate numBins (\i -> if i == 0 then -1.0 else 2.0 / fromIntegral numBins)
        in mkHistogramFromSimplex 1e-9 v == Nothing

  , -- Sanity: histogramFromPalette's #non-zero bins divided by 4096 gives the
    -- existing coverage fraction on a single palette (mirroring the coverage law).
    testProperty "non-zero fraction matches gamutCoverageFraction on a single palette" $
      forAll genPalette $ \pal ->
        let Histogram4096 v = histogramFromPalette pal
            nonZero         = U.length (U.filter (> 0) v)
            f               = fromIntegral nonZero / fromIntegral numBins :: Double
        in abs (f - gamutCoverageFraction [pal]) < 1e-12
  ]
