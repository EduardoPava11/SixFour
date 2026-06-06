module Properties.FrontProjection (tests) where

import Test.Tasty
import Test.Tasty.QuickCheck

import SixFour.Spec.FrontProjection

-- | The GIF loop length (N = 64).
n :: Int
n = 64

-- | A deterministic synthetic index cube: N frames, each fieldSide² indices in
-- [0,255] (mirrors the splitmix cube in VoxelRestPoseIdentityTests, but pure-arith
-- so it needs no RNG). Built once as a CAF; sampling forces only a few frames.
synthCube :: IndexCube
synthCube =
  [ [ (f * 31 + i * 7) `mod` 256 | i <- [0 .. fieldSide * fieldSide - 1] ]
  | f <- [0 .. n - 1] ]

-- | Deterministic per-frame palettes (N × 256 Q16 OKLab triples). Distinct per frame
-- so a wrong frame selection would produce a DIFFERENT colour (the test has teeth).
synthPalettes :: Palettes
synthPalettes =
  [ [ (f * 1000 + k, k - 128, f - 32) | k <- [0 .. 255] ]
  | f <- [0 .. n - 1] ]

-- | Sample points (cursor, (x,y)) — the same shape the Swift test checks.
samples :: [(Int, (Int, Int))]
samples = [ (c, p)
          | c <- [0, 1, 31, 63]
          , p <- [(0, 0), (63, 63), (17, 42), (40, 5)] ]

tests :: TestTree
tests = testGroup "FrontProjection (RULE-CUBE-2D-IDENTITY — 2D GIF == cube near face)"
  [ -- the near face shows the current frame, for EVERY cursor (pure arithmetic;
    -- reuses PlaybackClock threeDFrontFace == twoDFrame)
    testProperty "lawFrontIsCurrentFrame: front face == GIF frame ∀ cursor in [0,N)" $
      once (all (lawFrontIsCurrentFrame n) [0 .. n - 1])

    -- the keystone identity: 2D pixel == 3D front-face pixel at every sampled place
  , testProperty "lawRestPoseEqualsGifFrame: 2D pixel == cube near-face pixel (sampled)" $
      once (all (\(c, p) -> lawRestPoseEqualsGifFrame n synthCube synthPalettes c p) samples)

    -- and over arbitrary in-field places / cursors (quantified)
  , testProperty "lawRestPoseEqualsGifFrame holds for arbitrary cursor and field place" $
      forAll (choose (0, n - 1)) $ \c ->
        forAll (choose (0, fieldSide - 1)) $ \x ->
          forAll (choose (0, fieldSide - 1)) $ \y ->
            lawRestPoseEqualsGifFrame n synthCube synthPalettes c (x, y)

    -- totality: the projection never reads off the cube
  , testProperty "lawFrontIndexInRange: projection stays on the field (sampled)" $
      once (all (\(c, p) -> lawFrontIndexInRange n synthCube c p) samples)

    -- teeth: the palettes really are distinct per frame, so a wrong frame would fail
  , testProperty "the synthetic palettes differ per frame (the identity test has teeth)" $
      once (colourCheck)
  ]
  where
    -- frame 0 and frame 1 give different colours for the same index ⇒ frame choice matters
    colourCheck =
      gifPixelAt n synthCube synthPalettes 0 (0, 0)
        /= gifPixelAt n synthCube synthPalettes 1 (0, 0)
