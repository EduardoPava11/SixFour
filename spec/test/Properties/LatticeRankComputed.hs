module Properties.LatticeRankComputed (tests) where

import Test.Tasty
import Test.Tasty.QuickCheck

import SixFour.Spec.LatticeRankComputed

tests :: TestTree
tests = testGroup "LatticeRankComputed (de-vacuify Convergence's rank literal: compute rank(S) for real)"
  [ testProperty "AUDIT: computeRank spaceLattice == 3 (real elimination, not a literal)"
      (once lawSpaceLatticeRankIsThree)
  , testProperty "the computed rank agrees with the Convergence literal it replaces"
      (once lawComputedRankMatchesConvergenceLiteral)
  , testProperty "TEETH: degenerate lattices (drop-t / collinear-t) compute rank 2"
      (once lawDegenerateLatticeRankIsTwo)
  , testProperty "Sᵀ·cb == [0,0,0] by exact arithmetic (left-null-space membership, not prose)"
      (once lawCheckerboardInLeftNullSpace)
  , testProperty "DISCRIMINATES: in-span column colX maps to Sᵀ·colX = [4,2,2] /= 0"
      (once lawInSpanPerturbationSeen)
  , testProperty "CAPSTONE: the rank claim is computed, not asserted"
      (once lawRankClaimIsComputedNotAsserted)
  ]
