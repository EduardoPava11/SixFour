module Properties.GenomePair (tests) where

import Test.Tasty
import Test.Tasty.QuickCheck

import SixFour.Spec.PairTreeFixed (OKLabI, HaarPaletteI, analyzeFixed)
import SixFour.Spec.GenomePair

-- A Q16 OKLab pixel (same ranges as Properties.LeafOverride): L in [0, 65536], a/b bipolar.
genPxI :: Gen OKLabI
genPxI = (,,) <$> choose (0, 65536) <*> choose (-26214, 26214) <*> choose (-26214, 26214)

-- A well-formed integer Haar tree of depth 0..7 (the σ-pair generator tree is depth 7).
genHaarI :: Gen HaarPaletteI
genHaarI = do
  d <- choose (0, 7) :: Gen Int
  analyzeFixed <$> vectorOf (2 ^ d) genPxI

-- A ranking of arbitrary length: shorter than the generator count exercises the θ-untrained
-- cold-start fallback; longer exercises the trained path.
genRanking :: Gen Ranking
genRanking = do
  k <- choose (0, 160) :: Gen Int
  vectorOf k (choose (0, 1.0e6))

tests :: TestTree
tests = testGroup "GenomePair (KEYSTONE — orthogonal A/B candidates by disjoint generator bands)"
  [ testProperty "weights positive-definite (genomeInner is a true inner product)" $
      once lawWeightsPositiveDefinite

  , testProperty "ORTHOGONAL EXACT: genomeInner bandWeights δ_A δ_B == 0" $
      forAll genHaarI $ \g0 -> forAll genRanking (lawPairOrthogonalExact g0)

  , testProperty "DISTINCT: both W-norms ≥ minGenomeStep and δ_A ≠ δ_B" $
      forAll genHaarI $ \g0 -> forAll genRanking (lawPairDistinct g0)

  , testProperty "VALID: each candidate keeps the palette σ-fixed" $
      forAll genHaarI $ \g0 -> forAll genRanking (lawPairValidSigma g0)

  , testProperty "REVERSIBLE: each candidate round-trips the σ-pair transform" $
      forAll genHaarI $ \g0 -> forAll genRanking (lawPairReversible g0)

  , testProperty "deterministic (pure integer (δ_A, δ_B))" $
      forAll genHaarI $ \g0 -> forAll genRanking (lawPairDeterministic g0)

  , testProperty "band-disjoint support: support δ_A ∩ support δ_B = ∅" $
      forAll genHaarI $ \g0 -> forAll genRanking (lawBandDisjoint g0)

  , testProperty "cold-start ranking deterministic + full-width" $
      forAll genHaarI lawColdStartRankingDeterministic

  , testProperty "COLD START still orthogonal (empty ranking, day-1 capture)" $
      forAll genHaarI lawColdStartStillOrthogonal

  , testProperty "selector rides on disjoint bands (any ranking, any width)" $
      forAll genRanking $ \r -> forAll (choose (0, 256)) (lawSelectorRidesOnDisjoint r)
  ]
