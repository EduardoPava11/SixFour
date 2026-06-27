module Properties.Convergence (tests) where

import Test.Tasty
import Test.Tasty.QuickCheck

import SixFour.Spec.Convergence

tests :: TestTree
tests = testGroup "Convergence (the convergence teaching: convex objective, unique min iff w_value>0)"
  [ testProperty "cell loss is convex in the palette"        lawCellLossConvex
  , testProperty "value loss is convex in the palette"       lawValueLossConvex
  , testProperty "the composite is convex (w_value >= 0)"    lawCompositeConvex
  , testProperty "cell minimizer is NOT unique (checkerboard null space)" lawCellMinimizerNotUnique
  , testProperty "value minimizer IS unique (strict convexity)"          lawValueMinimizerUnique
  , testProperty "CAPSTONE: composite has a unique global min iff w_value>0" lawCompositeUniqueMinIffValueWeighted
  , testProperty "convex => no spurious local minima"        lawConvexNoSpuriousLocalMin
  , testProperty "a gradient step contracts toward the target" lawGradStepContractsToTarget
  , testProperty "convergence is governed by the lattice rank" lawConvergenceGovernedByLatticeRank
  ]
