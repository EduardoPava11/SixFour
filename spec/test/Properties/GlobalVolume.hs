module Properties.GlobalVolume (tests) where

import Test.Tasty
import Test.Tasty.QuickCheck

import SixFour.Spec.GlobalVolume

tests :: TestTree
tests = testGroup "GlobalVolume (whole-GIF brand for one global palette)"
  [ testProperty "completeness rejects a missing slot (surjectivity is load-bearing)"
      lawCompleteRejectsMissingSlot
  , testProperty "whole-GIF completeness is WEAKER than per-frame (disjoint subsets, union = K)"
      lawCompleteWeakerThanPerFrame
  , testProperty "significant pooled counts sum to the exact total mass"
      lawSignificantTotalMass
  , testProperty "significance backs every slot (≥ minPopulation)"
      lawSignificantBacksEverySlot
  ]
