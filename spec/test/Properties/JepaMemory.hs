module Properties.JepaMemory (tests) where

import Test.Tasty
import Test.Tasty.QuickCheck

import SixFour.Spec.JepaMemory

tests :: TestTree
tests = testGroup "JepaMemory (the I-JEPA memory budget, pinned as one tested fact = the destructive-pivot tripwire)"
  [ testProperty "latent working memory == the pivot mid-level cube (32768 / 2097152), never surfaces" $
      once lawLatentCapacityMatchesPivotCube
  , testProperty "NO-DRIFT: the 14-int residual unit is bound to its 77-param trained carrier" $
      once lawResidualIsFourteenAndCarried
  , testProperty "the 7 detail bands agree across octree / residual / trained head" $
      once lawSevenDetailBands
  , testProperty "token capacity == octant leaf count (64..512), target side zero-learnable" $
      forAll (choose (0, 5)) lawTokenCapacityAreOctants
  , testProperty "CONSERVATION: 2 carriers + 4 searches, no axis dropped, residual = 2 * 7" $
      once lawCarrierSearchPartition
  ]
