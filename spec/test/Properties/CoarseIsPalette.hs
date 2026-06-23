module Properties.CoarseIsPalette (tests) where

import Test.Tasty
import Test.Tasty.QuickCheck

import SixFour.Spec.SameObjectInvariance (Cube(..))
import SixFour.Spec.CoarseIsPalette

-- | A well-formed coarse 16³ cube (8^4 = 4096 voxels per channel).
genCoarseCube :: Gen Cube
genCoarseCube = do
  let n = 8 ^ (4 :: Int)   -- 4096
  cl <- vectorOf n (choose (-100, 100))
  ca <- vectorOf n (choose (-100, 100))
  cb <- vectorOf n (choose (-100, 100))
  pure (Cube cl ca cb)

tests :: TestTree
tests = testGroup "CoarseIsPalette (16²=256 as a compile-time theorem)"
  [ testProperty "16*16 == 256 (Refl) and 16 is the unique palette-sized frame" $
      once lawCoarseFrameSizeIsPaletteSize
  , testProperty "coarse 16³ reshapes bijectively into 16 palettes of 256" $
      forAll genCoarseCube lawCoarseIsStackOfPalettes
  , testProperty "each coarse palette equals its frame's perceptual colours (encoders coincide)" $
      forAll genCoarseCube lawCoarsePaletteComparesToPerFrame
  , testProperty "16 ordered palettes reconstruct the cube, NO index map" $
      forAll genCoarseCube lawSixteenPalettesReconstructCube
  , testProperty "the 32³ midpoint is a 4-palette stack (the organisable level)" $
      once lawMidpointIsPaletteStack
  ]
