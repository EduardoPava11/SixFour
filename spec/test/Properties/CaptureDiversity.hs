module Properties.CaptureDiversity (tests) where

import Test.Tasty
import Test.Tasty.QuickCheck

import SixFour.Spec.CaptureDiversity

tests :: TestTree
tests = testGroup "CaptureDiversity (HOW to capture the most diverse signal: the exposure-tiling proof)"
  [ testGroup "The recipe — tiling maximizes diversity"
      [ testProperty "coverage <= min(sceneDR, nScales·W) (the two ceilings)" $
          \w dr evs -> lawCoverageBoundedByBudget w dr evs
      , testProperty "tiling ACHIEVES the ceiling (and zero overlap when it fits) — optimal" $
          \w dr -> lawTilingMaximizesCoverage w dr
      , testProperty "no assignment beats tiling" $
          \w dr evs -> lawTilingIsAtLeastAnyAssignment w dr evs
      , testProperty "convergent exposures = minimal coverage, maximal redundancy" $
          \w dr c -> lawConvergenceMinimizesDiversity w dr c
      , testProperty "separability rank = distinct windows (tiling full, convergence singular)" $
          once lawDistinctExposuresFullRank
      ]

  , testGroup "The honest limits (also theorems)"
      [ testProperty "diversity is scene-bounded: coverage <= sceneDR (easy scenes collapse)" $
          \w dr evs -> lawDiversityCappedByScene w dr evs
      , testProperty "the 4:2:1 cadence forces nested distinct exposures (2-stop spread)" $
          once lawCadenceForcesNestedExposures
      , testProperty "gain is REQUIRED: cadence's 2 stops can't tile a wider window" $
          \w -> lawCadenceSpreadNeedsGainToTile w
      ]
  ]
