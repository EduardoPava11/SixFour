module Properties.Wu (tests) where

import Test.Tasty
import Test.Tasty.QuickCheck
import Test.QuickCheck

import qualified Data.Vector         as V
import qualified Data.Vector.Unboxed as U

import SixFour.Spec.Color   (OKLab(..), okLabDistanceSquared)
import SixFour.Spec.StageA
import SixFour.Spec.Palette (Palette(..))
import SixFour.Spec.Indices (IndexTensor(..))
import SixFour.Spec.Laws    (lawWuShapesOut)

-- Use very small frames so QuickCheck is fast: H = W = 4, K = 8.

type H = 4
type W = 4
type K = 8

genFrame :: Gen (Frame H W)
genFrame = do
  let n = 4 * 4 :: Int
  xs <- vectorOf n $ do
    l <- choose (0, 1)
    a <- choose (-0.4, 0.4)
    b <- choose (-0.4, 0.4)
    pure (OKLab l a b)
  pure (Frame (V.fromList xs))

-- A full ship-shape frame (64×64) — lawWuShapesOut pins against Spec.Shape's kVal=256 /
-- pixelsPerFrame=4096, so it must be exercised at the canonical shape, not the tiny one.
genShipFrame :: Gen (Frame 64 64)
genShipFrame = do
  xs <- vectorOf (64 * 64) (OKLab <$> choose (0, 1) <*> choose (-0.4, 0.4) <*> choose (-0.4, 0.4))
  pure (Frame (V.fromList xs))

tests :: TestTree
tests = testGroup "StageA / variance-cut reference"
  [ testProperty "output palette has exactly K entries" $
      forAll genFrame $ \fr ->
        let (Palette pv, _) = runStageA (varianceCutReference @H @W @K) fr
        in V.length pv == 8
  , testProperty "output indices have exactly H*W entries, all in [0, K-1]" $
      forAll genFrame $ \fr ->
        let (_, IndexTensor iv) = runStageA (varianceCutReference @H @W @K) fr
        in U.length iv == 16
           && U.all (\i -> i >= 0 && i < 8) iv
  , testProperty "lawWuShapesOut: ship-shape Stage A output pinned (palette 256, indices 4096)" $
      once $ forAll genShipFrame $ \fr ->
        lawWuShapesOut (varianceCutReference @64 @64 @256) fr

  -- The two obligations the module header CLAIMS but no law pinned (audit 2026-07-03):
  -- "pinned, deterministic" and "reconstructs the frame under nearest-OKLab".
  , testProperty "DETERMINISM: two runs on the same frame give identical (palette, indices)" $
      forAll genFrame $ \fr ->
        let (Palette p1, IndexTensor i1) = runStageA (varianceCutReference @H @W @K) fr
            (Palette p2, IndexTensor i2) = runStageA (varianceCutReference @H @W @K) fr
        in p1 == p2 && i1 == i2

  , testProperty "NEAREST-ASSIGNMENT: every pixel's index is a nearest centroid in OKLab" $
      forAll genFrame $ \fr@(Frame pixels) ->
        let (Palette pal, IndexTensor ix) = runStageA (varianceCutReference @H @W @K) fr
            dist p j = okLabDistanceSquared p (pal V.! j)
            bestFor p = V.minimum (V.map (okLabDistanceSquared p) pal)
        in and [ dist px (ix U.! i) <= bestFor px
               | (i, px) <- zip [0 ..] (V.toList pixels) ]
  ]
