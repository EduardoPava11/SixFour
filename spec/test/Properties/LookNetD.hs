{-# LANGUAGE DataKinds           #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE TypeApplications    #-}

module Properties.LookNetD (tests) where

import Test.Tasty
import Test.Tasty.QuickCheck
import Test.QuickCheck

import qualified Data.Vector.Unboxed as U

import SixFour.Spec.Tensor   (Tensor1(..))
import SixFour.Spec.Color    (OKLab(..))
import SixFour.Spec.PairTree (HaarPalette(..))
import SixFour.Spec.LookNetE (HiddenContext(..))
import SixFour.Spec.LookNetD

genHiddenContext :: Gen HiddenContext
genHiddenContext = do
  xs <- vectorOf 64 (choose (-1, 1) :: Gen Double)
  pure (HiddenContext (Tensor1 (U.fromList xs)))

genOKLab :: Gen OKLab
genOKLab = OKLab <$> choose (0, 1) <*> choose (-0.4, 0.4) <*> choose (-0.4, 0.4)

-- A well-formed depth-'decoderTreeDepth' (= 7) generator Haar palette: level ℓ
-- has 2^ℓ offsets.
genHaarPalette :: Gen HaarPalette
genHaarPalette = do
  rt   <- genOKLab
  lvls <- mapM (\l -> vectorOf (2 ^ l) genOKLab) [0 .. decoderTreeDepth - 1]
  pure (HaarPalette rt lvls)

genDecoderOutput :: Gen DecoderOutput
genDecoderOutput = do
  xs <- vectorOf 384 (choose (-1, 1) :: Gen Double)
  pure (DecoderOutput (Tensor1 (U.fromList xs)))

tests :: TestTree
tests = testGroup "LookNetD (L5 σ-pair tree decoder — per-level heads, σ₃₈₄ output, block-diagonal weights)"

  [ testProperty "structural constants: output dim 384, root dim 3, 128 generator triples, depth 7" $
      once (decoderOutputDim == 384 && rootDim == 3 && numTriples == 128 && decoderTreeDepth == 7)

  , testProperty "head sizes: root(3) + 7 generator levels [3,6,12,24,48,96,192] = 8 heads, sum 384" $
      once (length decoderLevelDims == 8 && sum decoderLevelDims == 384)

  , testProperty "σ₃₈₄ is an involution (per-triple sign-flip squared = identity)" $
      forAll genDecoderOutput lawSigmaDecoderInvolution

  , testProperty "σ₃₈₄ is orthogonal (Euclidean-norm preserving)" $
      forAll genDecoderOutput lawSigmaDecoderOrthogonal

  , testProperty "σ₃₈₄ acts as per-triple OKLab σ: (L,a,b) ↦ (L,-a,-b) on every triple" $
      forAll genDecoderOutput lawSigmaDecoderMatchesPerTriple

  , testProperty "reference decoder is the zero map (neutral-grey SigmaPairTree by construction)" $
      forAll genHiddenContext lawDecoderRefIsZero

  , testProperty "reference decoder σ-equivariance: 0 ∘ σ = σ ∘ 0 = 0 (trivial base case)" $
      forAll genHiddenContext lawDecoderRefSigmaEquivariance

  , testProperty "decoder pruning arithmetic: 13568 free / 24576 naive ≈ 0.552 (45% σ-pruned)" $
      once lawDecoderPruningArithmetic

  , testProperty "flattenHaar ∘ toHaarPalette round-trips well-formed generator palettes (EXACT)" $
      forAll genHaarPalette lawHaarFlattenRoundTrip

  , testProperty "recursion-driven decoder with reference block ≡ zero decoder" $
      forAll genHiddenContext lawDecoderFromRecursionMatchesZero

  , testProperty "L6 reconstruct yields exactly 256 σ-pair leaves" $
      forAll genHiddenContext lawReconstructSigmaPairLeaves
  ]
