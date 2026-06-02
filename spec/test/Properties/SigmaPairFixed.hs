module Properties.SigmaPairFixed (tests) where

import Test.Tasty
import Test.Tasty.QuickCheck

import SixFour.Spec.PairTreeFixed (OKLabI, HaarPaletteI, analyzeFixed)
import SixFour.Spec.SigmaPairFixed

-- A Q16 OKLab triple.
genPxI :: Gen OKLabI
genPxI = (,,) <$> choose (0, 65536) <*> choose (-26214, 26214) <*> choose (-26214, 26214)

-- A well-formed integer Haar tree of depth 0..7 (the σ-pair generator tree is depth 7).
genHaarI :: Gen HaarPaletteI
genHaarI = do
  d <- choose (0, 7) :: Gen Int
  analyzeFixed <$> vectorOf (2 ^ d) genPxI

-- An even-length integer palette (length 2^(d+1) so the 2^d evens form a clean tree).
genEvenLeaves :: Gen [OKLabI]
genEvenLeaves = do
  d <- choose (0, 6) :: Gen Int
  vectorOf (2 ^ (d + 1)) genPxI

tests :: TestTree
tests = testGroup "SigmaPairFixed (owned integer σ-pair genome — EXACT, no tolerance)"
  [ testProperty "σ-reflect is an involution (integer)" $
      forAll genPxI lawSigmaReflectInvolutionI

  , testProperty "reconstructPaired ∘ analyzePaired = id EXACTLY (integer round-trip)" $
      forAll genHaarI lawReconstructAnalyzePairedFixedRoundTrip

  , testProperty "analyzePaired projects ANY palette onto the σ-fixed subspace EXACTLY" $
      forAll genEvenLeaves lawAnalyzePairedFixedProjectsSigmaFixed

  , testProperty "σ-partner (k^1) of a leaf IS its σ-reflection (the 2⁸ brush rule)" $
      forAll genHaarI $ \t -> forAll (choose (0, 1000)) (lawSigmaPartnerIsReflection t)
  ]
