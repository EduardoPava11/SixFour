module Properties.CurateRealize (tests) where

import Test.Tasty
import Test.Tasty.QuickCheck

import SixFour.Spec.CurateRealize

tests :: TestTree
tests = testGroup "CurateRealize (curated volume -> per-frame palettes+indices; the L1.2 export realization)"
  [ testProperty "the layout pin: position-coded volume slices to its own coordinates (exact)" $
      once lawFramesPartitionVolume

  , testProperty "realization is FRAME-LOCAL (perturb one voxel -> only its frame changes)" $
      forAll (vectorOf 24 (choose (-30000, 30000))) $ \vals ->
        forAll (choose (0, 1000)) (lawRealizeIsFrameLocal vals)

  , testProperty "a <=k-distinct-colour frame realizes LOSSLESSLY (palette[index] == pixel)" $
      forAll (vectorOf 8 (choose (0, 100))) $ \picks ->
        forAll (choose (0, 10)) (lawPalettizableRealizeLossless picks)

  , testProperty "the ladder floor of flatness realizes to ONE colour, losslessly (floor -> GIF bytes untouched)" $
      forAll (choose (0, 100000)) $ \l -> forAll (choose (0, 100000)) $ \a ->
        forAll (choose (0, 100000)) (lawConstantFloorRealizesToOneColour l a)
  ]
