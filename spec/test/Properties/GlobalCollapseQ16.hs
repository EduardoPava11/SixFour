module Properties.GlobalCollapseQ16 (tests) where

import Test.Tasty
import Test.Tasty.QuickCheck
import Test.QuickCheck

import qualified Data.Vector as V

import SixFour.Spec.GlobalCollapseQ16
import SixFour.Spec.QuantFixed (nearestCentroidQ16)

-- A Q16 OKLab triple: L ∈ [0, 2^16], a,b ∈ [±0.4·2^16].
genPxQ16 :: Gen (Int, Int, Int)
genPxQ16 = (,,) <$> choose (0, 65536) <*> choose (-26214, 26214) <*> choose (-26214, 26214)

-- 1..6 frames of 1..8 Q16 colours each (bounded, so QuickCheck stays cheap).
genFramesQ16 :: Gen [[(Int, Int, Int)]]
genFramesQ16 = resize 6 (listOf1 (resize 8 (listOf1 genPxQ16)))

tests :: TestTree
tests = testGroup "GlobalCollapseQ16 (the shipped byte-exact Q16 collapse + HARD-MUST-1 scope gate)"
  [ testProperty "Q16: collapse yields exactly k leaves (k>0, non-empty pool)" $
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

  -- HARD MUST #1: per-frame palettes only (the spec-level scope gate) ----------

  , testProperty "shipped scope is per-frame (HARD MUST #1: no global palette)" $
      shippedScope == PerFrame

  , testProperty "the shipped scope never pools across frames (no globalCollapseQ16)" $
      not (poolsAcrossFrames shippedScope)

  , testProperty "only Global scope pools; PerFrame keeps every frame independent" $
      poolsAcrossFrames Global && not (poolsAcrossFrames PerFrame)
  ]
