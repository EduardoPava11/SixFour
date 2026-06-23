module Properties.HalfwayLatent (tests) where

import Test.Tasty
import Test.Tasty.QuickCheck

import SixFour.Spec.HalfwayLatent

tests :: TestTree
tests = testGroup "HalfwayLatent (the encoder fuse IS the never-surfaced 32³ midpoint)"
  [ testProperty "KEYSTONE: fuse == midpoint (vitTokens·vitDModel == latentWorkingMemoryVoxels Down)" $
      once lawFuseIsMidpoint
  , testProperty "the midpoint is the geometric mean of 16³ and 64³ ((32³)² == 16³·64³)" $
      once lawHalfwayDimIsGeometricMean
  , testProperty "the waist token axis is the depth-2 octant lattice (8² = 64)" $
      once lawWaistTokensAreOctantLeaves
  , testProperty "the waist tokens agree with the synthesis nTokens" $
      once lawWaistTokensMatchSynthesis
  ]
