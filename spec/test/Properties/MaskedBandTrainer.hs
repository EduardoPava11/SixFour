module Properties.MaskedBandTrainer (tests) where

import Test.Tasty
import Test.Tasty.QuickCheck

import SixFour.Spec.MaskedBandTrainer

tests :: TestTree
tests = testGroup "MaskedBandTrainer (the θ_B training contract — a byte-checkable twin for the MLX descent)"
  [ testProperty "zero-genome == floor (the descent's start point)" $
      once lawZeroGenomeIsFloor
  , testProperty "training drives the masked-band loss down (the label is learnable)" $
      once lawTrainingDrivesLossDown
  , testProperty "THE TWIN: the trained forward pass recovers the golden committed band (3000)" $
      once lawTrainedForwardIsGolden
  , testProperty "the descent is monotone (guard against the ill-conditioned divergence regime)" $
      once lawTrainingDescendsMonotonically
  , testProperty "DEFECT+FIX: summed-gradient diverges on a high-ṽ batch; the mean-gradient trainer converges" $
      once lawStableTrainerSurvivesBatchDivergence
  ]
