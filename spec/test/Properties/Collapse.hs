module Properties.Collapse (tests) where

import Test.Tasty
import Test.Tasty.QuickCheck
import Test.QuickCheck

import           Data.Maybe (fromJust)

import qualified Data.Vector as V

import SixFour.Spec.Color    (OKLab(..))
import SixFour.Spec.Palette  (Palette, mkPalette, paletteToList)
import SixFour.Spec.Collapse
import SixFour.Spec.Coverage (occupiedBins)

-- Tiny K = 6 so QuickCheck is cheap; the laws are size-independent.
type K = 6

genOKLab :: Gen OKLab
genOKLab = OKLab <$> choose (0, 1) <*> choose (-0.4, 0.4) <*> choose (-0.4, 0.4)

genPalette :: Gen (Palette K)
genPalette = fromJust . mkPalette @K <$> vectorOf 6 genOKLab

tests :: TestTree
tests = testGroup "Collapse (per-frame palettes → one: the float maximin baseline)"
  [ testProperty "outputs exactly K entries" $
      forAll (listOf1 genPalette) $ \ps ->
        length (paletteToList (farthestPointCollapse ps)) == 6

  , testProperty "no invented colour: every collapsed entry is an input colour" $
      forAll (listOf1 genPalette) $ \ps ->
        let pool = pooledCandidates ps
        in all (`elem` pool) (paletteToList (farthestPointCollapse ps))

  , testProperty "containment: collapsed gamut ⊆ inputs' gamut" $
      forAll (listOf1 genPalette) $ \ps ->
        occupiedBins [farthestPointCollapse ps] <= occupiedBins ps

  , testProperty "idempotent coverage: collapsing one K-palette keeps its gamut" $
      forAll genPalette $ \p ->
        occupiedBins [farthestPointCollapse [p]] == occupiedBins [p]
  ]
