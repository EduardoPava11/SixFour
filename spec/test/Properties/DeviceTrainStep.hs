module Properties.DeviceTrainStep (tests) where

import Test.Tasty
import Test.Tasty.QuickCheck

import SixFour.Spec.DeviceTrainStep

tests :: TestTree
tests = testGroup "DeviceTrainStep (the V3.0 on-device per-capture training gate — post-commit bytes for MPSGraph/Metal-4)"
  [ testProperty "the supervision pair is the exact lift (the capture is its own lossless training set)"
      lawSupervisionPairIsExact
  , testProperty "zero params == the floor (the descent's start point, non-vacuous)" $
      once lawDeviceZeroParamsIsFloor
  , testProperty "training drives the supervised loss down (the manufactured label is learnable)" $
      once lawDeviceTrainingDrivesLossDown
  , testProperty "THE TWIN: the committed detail after training is exactly goldenDeviceDetail" $
      once lawDeviceTrainedDetailIsGolden
  , testProperty "the descent is monotone (fixed-η divergence guard)" $
      once lawDeviceDescentMonotone
  , testProperty "the trained bands survive the Q16 commit (AboveFloorMargin — off the floor for real)" $
      once lawTrainedDetailSurvivesCommit
  , testProperty "the mean-gradient step is batch-stable (two manufactured pairs converge, no divergence)" $
      once lawDeviceBatchIsStableMeanGradient
  ]
