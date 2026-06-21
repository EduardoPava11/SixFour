module Properties.OptionTree (tests) where

import Test.Tasty
import Test.Tasty.QuickCheck

import SixFour.Spec.OptionTree

genAB :: Gen (Int, Int)
genAB = (,) <$> choose (-65536, 65536) <*> choose (-65536, 65536)

tests :: TestTree
tests = testGroup "OptionTree (Merkle MCTS: PUCT + transposition + visit-count policy)"
  [ testProperty "transposition iff same surfaced hash (tier/terminal ignored)" $
      \h1 h2 -> lawTranspositionByHash h1 h2

  , testProperty "PUCT at an unvisited edge (N=0) = Q + cpuct*P*sqrt(sumN)" $
      \cpuct q p sumN -> lawPuctUnvisitedIsPrior cpuct q p sumN

  , testProperty "Q = W/N for visited edges" $
      \w n -> lawQValueIsMean w n

  , testProperty "visit-count policy sums to 1 (any action visited)" $
      \ns -> lawVisitPolicySumsToOne ns

  , testProperty "PUCT is monotone non-decreasing in the prior P" $
      \cpuct p1 p2 n sumN -> lawPuctMonotoneInPrior cpuct p1 p2 n sumN

  , testProperty "golden: puct 1.0 0.5 0.5 0 4 = 1.5" $
      once lawPuctGolden

  , testProperty "rotation dedup: canonical key invariant under chroma quarter-turn" $
      \r -> forAll (listOf genAB) (lawRotationDedup r)

  , testProperty "a look and its chroma-rotation are one node up to rotation" $
      \r -> forAll (listOf genAB) (lawTranspositionUpToRotation r)
  ]
