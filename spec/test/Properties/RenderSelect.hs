module Properties.RenderSelect (tests) where

import Test.Tasty
import Test.Tasty.QuickCheck

import SixFour.Spec.RenderSelect

tests :: TestTree
tests = testGroup "RenderSelect (rung 1: select the independent scale per region — keeps the streams independent)"
  [ testProperty "depth 2 everywhere = the fine identity (V64 untouched)" $
      \xs -> lawFineIsIdentity xs
  , testProperty "coarse reads the INDEPENDENT V16 replicate, not a pool of V64" $
      \a b -> lawCoarseSelectsIndependentCoarse a b
  , testProperty "KEYSTONE: a region's output depends ONLY on its chosen scale's volume" $
      \a b c d -> lawSelectReadsChosenSourceOnly a b c d
  , testProperty "raising one region's depth is local (only its voxels change)" $
      \r a b c -> lawSelectIsLocal r a b c
  , testProperty "shared clock: a coarse region is constant across its 4-frame window" $
      \xs -> lawTemporalReplicateOnSharedClock xs
  ]
