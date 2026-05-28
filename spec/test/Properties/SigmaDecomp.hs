module Properties.SigmaDecomp (tests) where

import Test.Tasty
import Test.Tasty.QuickCheck
import Test.QuickCheck

import qualified Data.Vector.Unboxed as U

import SixFour.Spec.Color        (OKLab(..))
import SixFour.Spec.Bottleneck16 ( Histogram4096(..), numBins, numBinsPerAxis
                                 , histogramFromOKLabs, uniformHistogram )
import SixFour.Spec.SigmaDecomp

genOKLab :: Gen OKLab
genOKLab = OKLab <$> choose (0, 1) <*> choose (-0.4, 0.4) <*> choose (-0.4, 0.4)

genHistogram :: Gen Histogram4096
genHistogram = histogramFromOKLabs <$> listOf1 genOKLab

genBinIndex :: Gen Int
genBinIndex = choose (0, numBins - 1)

tests :: TestTree
tests = testGroup "SigmaDecomp (σ-eigenspace split of the 16³ histogram)"
  [ testProperty "σ_bin is an involution on [0, 4096)" $
      forAll genBinIndex lawSigmaBinInvolution

  , testProperty "dimensional accounting: 0 fixed bins, 2048 orbits, sym = asym = 2048" $
      once $
           sigmaFixedBinCount == 0
        && sigmaOrbitCount    == 2048
        && dimSigmaSym        == 2048
        && dimSigmaAsym       == 2048
        && dimSigmaSym + dimSigmaAsym == numBins

  , testProperty "σ_bin is a true permutation: image of [0,4096) covers [0,4096)" $
      once $
        let imgs = [ sigmaBinPerm i | i <- [0 .. numBins - 1] ]
        in length imgs == numBins
           && minimum imgs == 0
           && maximum imgs == numBins - 1

  , testProperty "L is preserved by σ_bin (chromatic-only involution)" $
      forAll genBinIndex $ \i ->
        let n  = numBinsPerAxis
            iL = i `div` (n * n)
            jL = sigmaBinPerm i `div` (n * n)
        in iL == jL

  , testProperty "symmetric part is still a probability simplex (mass-1, non-neg)" $
      forAll genHistogram $ \h ->
        lawSymPartMassOne 1e-9 h && lawSymPartNonNeg h

  , testProperty "orthogonal decomposition: ⟨H_sym, H_asym⟩ = 0" $
      forAll genHistogram (lawOrthogonalDecomp 1e-12)

  , testProperty "Parseval: ‖H‖² = ‖H_sym‖² + ‖H_asym‖²" $
      forAll genHistogram (lawParseval 1e-12)

  , testProperty "sigmaSymFraction ∈ [0, 1]" $
      forAll genHistogram $ \h ->
        let f = sigmaSymFraction h
        in f >= 0 && f <= 1 + 1e-12

  , testProperty "uniform histogram has sigmaSymFraction = 1" $
      once (lawUniformIsSym 1e-12)

  , testProperty "uniform histogram has zero σ-antisymmetric mass" $
      once $
        let h = uniformHistogram
            n = sigmaAsymNormSquared h
        in abs n < 1e-24

  , testProperty "a σ-paired OKLab list yields sigmaSymFraction = 1" $
      forAll (listOf1 genOKLab) (lawSigmaPairedListIsSym 1e-9)

  , -- Asymmetric extremal: a single-colour palette that does NOT land on a
    -- σ-fixed point of the (a,b) grid has strictly < 1 sigmaSymFraction.
    testProperty "single off-axis colour has sigmaSymFraction = 0.5" $
      forAll (OKLab <$> choose (0, 1) <*> choose (0.1, 0.4) <*> choose (0.1, 0.4)) $ \c ->
        let h = histogramFromOKLabs [c]
            f = sigmaSymFraction h
        in abs (f - 0.5) < 1e-9
  ]
