{- |
Module      : Properties.Proposer
Description : Property tests for 'SixFour.Spec.Proposer' — the composed
              propose-candidates organ (orthogonal seed → value-rank → SH).

Generators mirror 'Properties.GenomePair' (depth-0..7 integer-Haar base, an
arbitrary-width ranking that exercises the cold-start fallback); the taste oracle
under test is the candidate's W-norm, a real deterministic value.
-}
module Properties.Proposer (tests) where

import Test.Tasty
import Test.Tasty.QuickCheck

import SixFour.Spec.PairTreeFixed (OKLabI, HaarPaletteI, analyzeFixed)
import SixFour.Spec.GenomePair    (Ranking, GenomeDisplacement, genomeNorm, bandWeights)
import SixFour.Spec.Proposer

genPxI :: Gen OKLabI
genPxI = (,,) <$> choose (0, 65536) <*> choose (-26214, 26214) <*> choose (-26214, 26214)

genHaarI :: Gen HaarPaletteI
genHaarI = do
  d <- choose (0, 7) :: Gen Int
  analyzeFixed <$> vectorOf (2 ^ d) genPxI

genRanking :: Gen Ranking
genRanking = do
  k <- choose (0, 160) :: Gen Int
  vectorOf k (choose (0, 1.0e6))

-- | The taste oracle under test: a candidate's W-norm (real, deterministic).
val :: GenomeDisplacement -> Double
val = genomeNorm bandWeights

tests :: TestTree
tests = testGroup "Proposer (orthogonal seed -> value-rank -> Sequential Halving)"
  [ testProperty "surfaces exactly two orthogonal candidates (informative A/B)" $
      forAll genHaarI $ \g0 -> forAll genRanking $ \r ->
        lawProposalSurfacesTwoOrthogonal g0 r val
  , testProperty "predicted winner is the value model's max (at Q16 resolution)" $
      forAll genHaarI $ \g0 -> forAll genRanking $ \r ->
        lawProposalWinnerIsValueMax g0 r val
  , testProperty "visit policy target is a distribution (sums to one)" $
      forAll genHaarI $ \g0 -> forAll genRanking $ \r ->
        lawProposalVisitTargetSumsToOne g0 r val
  , testProperty "proposal is deterministic (same inputs => same proposal)" $
      forAll genHaarI $ \g0 -> forAll genRanking $ \r ->
        lawProposalDeterministic g0 r val
  ]
