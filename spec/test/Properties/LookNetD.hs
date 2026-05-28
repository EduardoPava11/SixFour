{-# LANGUAGE DataKinds           #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE TypeApplications    #-}

module Properties.LookNetD (tests) where

import Test.Tasty
import Test.Tasty.QuickCheck
import Test.QuickCheck

import qualified Data.Vector.Unboxed as U

import SixFour.Spec.Tensor   (Tensor1(..))
import SixFour.Spec.LookNetE (HiddenContext(..))
import SixFour.Spec.LookNetD

genHiddenContext :: Gen HiddenContext
genHiddenContext = do
  xs <- vectorOf 64 (choose (-1, 1) :: Gen Double)
  pure (HiddenContext (Tensor1 (U.fromList xs)))

genDecoderOutput :: Gen DecoderOutput
genDecoderOutput = do
  xs <- vectorOf 768 (choose (-1, 1) :: Gen Double)
  pure (DecoderOutput (Tensor1 (U.fromList xs)))

tests :: TestTree
tests = testGroup "LookNetD (L5 tree decoder — per-level heads, σ₇₆₈ output, block-diagonal weights)"

  [ testProperty "structural constants: output dim 768, root dim 3, 256 OKLab triples" $
      once (decoderOutputDim == 768 && rootDim == 3 && numTriples == 256)

  , testProperty "head sizes: root(3) + 8 Haar levels [3,6,12,24,48,96,192,384] = 9 heads, sum 768" $
      once (length decoderLevelDims == 9 && sum decoderLevelDims == 768)

  , testProperty "σ₇₆₈ is an involution (per-triple sign-flip squared = identity)" $
      forAll genDecoderOutput lawSigma768Involution

  , testProperty "σ₇₆₈ is orthogonal (Euclidean-norm preserving)" $
      forAll genDecoderOutput lawSigma768Orthogonal

  , testProperty "σ₇₆₈ acts as per-triple OKLab σ: (L,a,b) ↦ (L,-a,-b) on every triple" $
      forAll genDecoderOutput lawSigma768MatchesPerTriple

  , testProperty "reference decoder is the zero map (neutral-grey HaarPalette by construction)" $
      forAll genHiddenContext lawDecoderRefIsZero

  , testProperty "reference decoder σ-equivariance: 0 ∘ σ = σ ∘ 0 = 0 (trivial base case)" $
      forAll genHiddenContext lawDecoderRefSigmaEquivariance

  , testProperty "decoder pruning arithmetic: 27136 free / 49152 naive ≈ 0.552 (45% σ-pruned)" $
      once lawDecoderPruningArithmetic
  ]
