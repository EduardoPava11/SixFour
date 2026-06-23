module Properties.PerceptualEncoder (tests) where

import Test.Tasty
import Test.Tasty.QuickCheck

import SixFour.Spec.SameObjectInvariance (Cube(..))
import SixFour.Spec.PerceptualEncoder

-- | A well-formed cube at a small octant depth (d in 0..2 ⇒ 1, 8, or 64 voxels/channel).
genDepthCube :: Gen (Int, Cube)
genDepthCube = do
  d <- choose (0, 2)
  let n = 8 ^ d
  cl <- vectorOf n (choose (-1000, 1000))
  ca <- vectorOf n (choose (-1000, 1000))
  cb <- vectorOf n (choose (-1000, 1000))
  pure (d, Cube cl ca cb)

tests :: TestTree
tests = testGroup "PerceptualEncoder (Encoder B: the (L,a,b,x,y,t) point cloud)"
  [ testProperty "embeds all 8^d voxels with faithful colour + injective position" $
      forAll genDepthCube $ \(d, c) -> lawPerceptualEmbedsAllSixAxes d c
  , testProperty "voxel distance IS d6 and is position-aware" $
      once lawPerceptualReusesD6
  ]
