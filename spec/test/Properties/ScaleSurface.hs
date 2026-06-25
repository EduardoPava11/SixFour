module Properties.ScaleSurface (tests) where

import Test.Tasty
import Test.Tasty.QuickCheck

import SixFour.Spec.ScaleSurface

tests :: TestTree
tests = testGroup "ScaleSurface (the grid exception: 256³ shares the 64³ footprint, density not size)"
  [ testProperty "the 256³ surface is the same on-screen size as the 64³ (Field64 footprint)" $
      once lawSuperResShareFootprintWith64
  , testProperty "GRID EXCEPTION: display footprint is independent of content resolution" $
      once lawFootprintIndependentOfResolution
  , testProperty "the 256³ gain is 4x density, not size (would overflow the grid otherwise)" $
      once lawSuperResIsDensityNotSize
  ]
