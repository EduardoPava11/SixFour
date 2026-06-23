module Properties.ConstructionEncoder (tests) where

import Test.Tasty
import Test.Tasty.QuickCheck

import SixFour.Spec.ConstructionEncoder

-- | A small Q16 colour.
genColour :: Gen QColour
genColour = (,,) <$> choose (-1000, 1000) <*> choose (-1000, 1000) <*> choose (-1000, 1000)

-- | A well-formed construction at a small octant depth (d in 0..2 ⇒ 1, 8, or 64 voxels),
-- with a non-empty palette and every index a real slot.
genConstruction :: Gen Construction
genConstruction = do
  d   <- choose (0, 2)
  np  <- choose (1, 6)
  pal <- vectorOf np genColour
  let n = 8 ^ d
  idx <- vectorOf n (choose (0, np - 1))
  pure (Construction d pal idx)

tests :: TestTree
tests = testGroup "ConstructionEncoder (Encoder A: palette + index map -> pixels)"
  [ testProperty "build executes the palette lookup at every voxel" $
      forAll genConstruction lawConstructionExecutesToPixels
  , testProperty "a valid construction builds exactly 8^d voxels per channel" $
      forAll genConstruction lawBuildIsTotalOnValid
  , testProperty "the index map carries information (re-pointing a voxel moves it)" $
      once lawBuildRespectsIndex
  , testProperty "identity index lays the palette verbatim (the A-form 'no index map' core)" $
      forAll (choose (0, 2)) $ \d -> forAll (listOf genColour) $ \pal ->
        lawIdentityIndexIsPaletteInOrder d pal
  ]
