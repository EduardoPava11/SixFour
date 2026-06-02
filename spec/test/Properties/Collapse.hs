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
import SixFour.Spec.QuantFixed (distSqQ16, nearestCentroidQ16)

-- Tiny K = 6 so QuickCheck is cheap; the laws are size-independent.
type K = 6

genOKLab :: Gen OKLab
genOKLab = OKLab <$> choose (0, 1) <*> choose (-0.4, 0.4) <*> choose (-0.4, 0.4)

genPalette :: Gen (Palette K)
genPalette = fromJust . mkPalette @K <$> vectorOf 6 genOKLab

-- A Q16 OKLab triple: L ∈ [0, 2^16], a,b ∈ [±0.4·2^16].
genPxQ16 :: Gen (Int, Int, Int)
genPxQ16 = (,,) <$> choose (0, 65536) <*> choose (-26214, 26214) <*> choose (-26214, 26214)

-- 1..6 frames of 1..8 Q16 colours each (bounded, so QuickCheck stays cheap).
genFramesQ16 :: Gen [[(Int, Int, Int)]]
genFramesQ16 = resize 6 (listOf1 (resize 8 (listOf1 genPxQ16)))

tests :: TestTree
tests = testGroup "Collapse (per-frame palettes → one)"
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

  -- The shipped Q16 collapse (byte-exact, the home of the golden) -------------

  , testProperty "Q16: collapse yields exactly k leaves (k>0, non-empty pool)" $
      forAll genFramesQ16 $ \fs -> forAll (choose (1, 12)) $ \k ->
        length (globalCollapseQ16 k fs) == k

  , testProperty "Q16: no invented colour — every leaf is a pooled input" $
      forAll genFramesQ16 $ \fs -> forAll (choose (1, 12)) $ \k ->
        let pool = pooledCandidatesQ16 fs
        in all (`elem` pool) (globalCollapseQ16 k fs)

  , testProperty "Q16: chosen indices select the leaves and stay in pool range" $
      forAll genFramesQ16 $ \fs -> forAll (choose (1, 12)) $ \k ->
        let pool = pooledCandidatesQ16 fs
            idxs = globalCollapseIndicesQ16 k fs
        in all (\i -> i >= 0 && i < length pool) idxs
           && map (pool !!) idxs == globalCollapseQ16 k fs

  , testProperty "Q16: re-index assigns the nearest leaf (strict-< lowest index)" $
      forAll genFramesQ16 $ \fs -> forAll (choose (1, 12)) $ \k ->
        let leaves = globalCollapseQ16 k fs
            lv     = V.fromList leaves
        in and [ reindexFrameQ16 leaves frame !! j == nearestCentroidQ16 lv c
               | frame <- fs, (j, c) <- zip [0 ..] frame ]

  , testProperty "Q16: every re-index target is a valid leaf index" $
      forAll genFramesQ16 $ \fs -> forAll (choose (1, 12)) $ \k ->
        let leaves = globalCollapseQ16 k fs
        in all (all (\i -> i >= 0 && i < length leaves)) (map (reindexFrameQ16 leaves) fs)
  ]
