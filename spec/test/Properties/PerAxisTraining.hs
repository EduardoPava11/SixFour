module Properties.PerAxisTraining (tests) where

import Test.Tasty
import Test.Tasty.QuickCheck

import SixFour.Spec.PerAxisTraining

tests :: TestTree
tests = testGroup "PerAxisTraining (the six-axis ledger verified by TRAINING, not op-structure)"
  [ testProperty "a band is learned in isolation (band 0 trained, band 1 stays at floor)" $
      once lawBandLearnedInIsolation
  , testProperty "distinct bands learn distinct targets with no cross-talk" $
      once lawPerBandTargetsAreIndependent
  , testProperty "EVERY one of the seven detail bands is independently learnable" $
      once lawEverySearchBandIsIndependentlyLearnable
  ]
