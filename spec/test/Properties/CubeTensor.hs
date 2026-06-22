module Properties.CubeTensor (tests) where

import Test.Tasty
import Test.Tasty.QuickCheck

import SixFour.Spec.CubeTensor

genI :: Gen Int
genI = choose (-(2^(16 :: Int)), 2^(16 :: Int))   -- Q16 range

-- a well-formed tensor at depth d (8^d voxels per channel)
genTensor :: Gen CubeTensor
genTensor = do
  d <- elements [0, 1]
  let n = 8 ^ d
  CubeTensor d <$> vectorOf n genI <*> vectorOf n genI <*> vectorOf n genI

tests :: TestTree
tests = testGroup "CubeTensor (the one canonical voxel-tensor object)"
  [ testProperty "every channel has 8^d voxels" $
      forAll genTensor lawCubeTensorVoxelCount
  , testProperty "the three channels are aligned" $
      forAll genTensor lawChannelsAligned
  , testProperty "carrier channel is DimL; search are DimA/DimB" $
      forAll genTensor lawCarrierChannelIsL
  , testProperty "toChannelSoA round-trips (forward)" $
      forAll genTensor lawChannelSoARoundTrip
  , testProperty "fromChannelSoA round-trips (back)" $
      forAll genTensor $ \ct ->
        lawChannelSoARoundTripBack (ctDepth ct) (toChannelSoA ct)
  , testProperty "search-swap fixes the carrier and is involutive" $
      forAll genTensor lawSearchSwapFixesCarrier
  ]
