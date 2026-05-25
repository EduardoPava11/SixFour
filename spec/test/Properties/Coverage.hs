module Properties.Coverage (tests) where

import Test.Tasty
import Test.Tasty.QuickCheck
import Test.QuickCheck

import qualified Data.Vector as V
import           Data.Maybe  (fromJust)

import SixFour.Spec.Color    (OKLab(..))
import SixFour.Spec.Palette  (Palette(..), mkPalette)
import SixFour.Spec.Coverage

-- Tiny K = 8 palette so QuickCheck is cheap; the laws are size-independent.
type K = 8

genOKLab :: Gen OKLab
genOKLab = OKLab <$> choose (0, 1) <*> choose (-0.4, 0.4) <*> choose (-0.4, 0.4)

genPalette :: Gen (Palette K)
genPalette = fromJust . mkPalette @K <$> vectorOf 8 genOKLab

tests :: TestTree
tests = testGroup "Coverage (gamut diversity metric)"
  [ testProperty "fraction ∈ [0, 1]" $
      forAll (listOf genPalette) $ \ps ->
        let f = gamutCoverageFraction ps in f >= 0 && f <= 1

  , testProperty "occupied bins ≤ total cells" $
      forAll (listOf genPalette) $ \ps ->
        occupiedBins ps <= coverageBinsPerAxis ^ (3 :: Int)

  , testProperty "monotone under union: coverage(a ++ b) ≥ coverage(a)" $
      forAll ((,) <$> listOf genPalette <*> listOf genPalette) $ \(a, b) ->
        occupiedBins (a ++ b) >= occupiedBins a

  , testProperty "S_K gauge-invariant: reordering a palette's entries is free" $
      forAll genPalette $ \(Palette v) ->
        occupiedBins [Palette v] == occupiedBins [Palette (V.reverse v)]

  , testProperty "a single-colour palette occupies exactly one bin" $
      forAll genOKLab $ \c ->
        occupiedBins [Palette (V.replicate 8 c)] == 1

  , testProperty "bin indices stay in [0, n)" $
      forAll genOKLab $ \c ->
        let (iL, ia, ib) = okLabBin c
            n = coverageBinsPerAxis
        in iL >= 0 && iL < n && ia >= 0 && ia < n && ib >= 0 && ib < n
  ]
