module Properties.MinimalInstructionSet (tests) where

import Test.Tasty
import Test.Tasty.QuickCheck

import SixFour.Spec.MinimalInstructionSet

tests :: TestTree
tests = testGroup "MinimalInstructionSet (the minimum decode instructions for 16³+data)"
  [ testProperty "A-form: 16 ordered palettes suffice (no index map)" $
      once lawSixteenPalettesSuffice
  , testProperty "B-form is LOSSY: same (L,x,y,t) skeleton, different colour" $
      once lawBSkeletonIsLossy
  , testProperty "chroma (a,b) are SEARCH axes dropped by the B-skeleton" $
      once lawChromaIsSearchResidual
  , testProperty "the duality is asymmetric: A reconstructs, B is lossy" $
      once lawDualMinimalProjections
  ]
