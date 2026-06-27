module Properties.GlobalUniqueness (tests) where

import Test.Tasty
import Test.Tasty.QuickCheck

import SixFour.Spec.GlobalUniqueness

tests :: TestTree
tests = testGroup "GlobalUniqueness (STRICT convexity of composite w>0 -> the target is the UNIQUE global min in every direction)"
  [ testProperty "ENGINE: composite Jensen gap = cell gap + w * value gap (exact, both signs of w)" lawJensenGapDecomposesByRank
  , testProperty "full-rank value gap is strictly positive for distinct p,q (= 1/2 lam(1-lam)|p-q|^2)"   lawValueGapStrictPositiveFullRank
  , testProperty "degenerate p==q gives EQUALITY (all gaps 0) so the strict laws aren't trivial"         lawDegenerateDirectionGivesEquality
  , testProperty "the cell objective is FLAT (gap 0) along the cell-blind checkerboard direction"        lawCheckerboardDirectionCellBlind
  , testProperty "TOOTH a: STRICT < for arbitrary distinct p,q at w=1 (affine would tie and fail)"       lawStrictGapArbitraryDistinctAtUnitWeight
  , testProperty "TOOTH b: uniqueness needs w>0 IN the cell-blind direction (w=0 ties, w>0 strict)"      lawStrictConvexityNeedsValueWeightInBlindDirection
  , testProperty "strictly convex in EVERY direction (4 distinct) at w>0, not one witness"               lawStrictlyConvexEveryDirectionAtPositiveWeight
  , testProperty "CAPSTONE: target is the UNIQUE global min iff w>0 (w=0 admits the checkerboard tie)"   lawTargetUniqueGlobalMinIffValueWeighted
  ]
