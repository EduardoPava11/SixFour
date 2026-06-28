module Properties.ChromaUnitMinimizer (tests) where

import Test.Tasty
import Test.Tasty.QuickCheck

import SixFour.Spec.ChromaUnitMinimizer

tests :: TestTree
tests = testGroup "ChromaUnitMinimizer (the convex value objective's unique minimizer IS the ℤ[i] unit g=i)"
  [ testProperty "g=i reproduces the hue-rotated target exactly (loss 0, the minimum attained)"
      lawUnitIMatchesHueRotatedTargetExactly
  , testProperty "CONSUMER: the objective IS Convergence.valueLoss on the chroma embedding"
      lawObjectiveIsConvergenceValueLoss
  , testProperty "CLOSED FORM: contLoss == ½·|g−i|²·‖source‖² (unique min at g=i, by formula)"
      lawContinuousLossIsDistanceToI
  , testProperty "TEETH: a non-unit (1+i) strictly loses (it scales the norm)"
      lawNonUnitMultiplierStrictlyLoses
  , testProperty "the other units {1,−1,−i} strictly lose (minimizer uniquely i among ℤ[i]*)"
      lawOtherUnitsStrictlyLose
  , testProperty "CAPSTONE: the convex value objective is uniquely minimized at the ℤ[i] unit g=i"
      (once lawValueMinimizerIsZiUnitI)
  ]
