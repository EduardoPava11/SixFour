{-# LANGUAGE OverloadedStrings #-}

module Properties.CoreMLContract (tests) where

import           Test.Tasty
import           Test.Tasty.QuickCheck
import qualified Data.Text             as T
import           Data.Text             (Text)

import SixFour.Codegen.CoreML
  ( emitLookNetTorch, emitBuildMlpackage
  , maxTokens, pyBoolList, pyIntList
  )
import SixFour.Spec.Tensor    (sigma64Mask, gmmTokenSigmaMask, hiddenDim)
import SixFour.Spec.LookNetD  (sigma768Mask, decoderLevelDims, decoderOutputDim)
import SixFour.Spec.PairTree  (degreesOfFreedom)
import SixFour.Spec.LookNet   (modelDim)
import SixFour.Spec.GMM       (gmmTokenDim)
import SixFour.Spec.LookNetR  (coreDepth)
import SixFour.Spec.Shape     (tVal, kVal)

-- The CoreML codegen output is text. Tests check that the emitted Python
-- pins the same constants the Haskell spec declares — if any drifts, the
-- generated trainer/.mlpackage would disagree with the on-device contract.

contains :: Text -> Text -> Bool
contains needle hay = T.isInfixOf needle hay

tests :: TestTree
tests = testGroup "CoreMLContract (Codegen.CoreML emits constants identical to the Haskell spec)"

  [ testProperty "maxTokens = T·K = 16384" $
      once (maxTokens == tVal * kVal && maxTokens == 16384)

  , testProperty "PyTorch module emits MODEL_DIM = 64" $
      once (contains ("MODEL_DIM             = " <> T.pack (show modelDim))
                     emitLookNetTorch)

  , testProperty "PyTorch module emits GMM_TOKEN_DIM = 10" $
      once (contains ("GMM_TOKEN_DIM         = " <> T.pack (show gmmTokenDim))
                     emitLookNetTorch)

  , testProperty "PyTorch module emits CORE_DEPTH = 8" $
      once (contains ("CORE_DEPTH            = " <> T.pack (show coreDepth))
                     emitLookNetTorch)

  , testProperty "PyTorch module emits DECODER_OUT_DIM = 768" $
      once (contains ("DECODER_OUT_DIM       = " <> T.pack (show decoderOutputDim))
                     emitLookNetTorch
            && degreesOfFreedom == 768)

  , testProperty "PyTorch module emits DECODER_LEVEL_DIMS matching the Haskell list" $
      once (contains ("DECODER_LEVEL_DIMS    = " <> pyIntList decoderLevelDims)
                     emitLookNetTorch)

  , testProperty "PyTorch module emits MAX_TOKENS = T·K = 16384" $
      once (contains ("MAX_TOKENS            = " <> T.pack (show maxTokens))
                     emitLookNetTorch)

  , testProperty "PyTorch module emits SIGMA64_MASK bit-identical to Haskell" $
      once (contains ("SIGMA64_MASK = " <> pyBoolList sigma64Mask)
                     emitLookNetTorch)

  , testProperty "PyTorch module emits GMM_TOKEN_SIGMA_MASK bit-identical to Haskell" $
      once (contains ("GMM_TOKEN_SIGMA_MASK = " <> pyBoolList gmmTokenSigmaMask)
                     emitLookNetTorch)

  , testProperty "PyTorch module emits SIGMA768_MASK bit-identical to Haskell" $
      once (contains ("SIGMA768_MASK = " <> pyBoolList sigma768Mask)
                     emitLookNetTorch)

  , testProperty "PyTorch module defines all three layer classes (L3Encoder, L4Block, L5Decoder)" $
      once (contains "class L3Encoder(nn.Module)" emitLookNetTorch
         && contains "class L4Block(nn.Module)"  emitLookNetTorch
         && contains "class L5Decoder(nn.Module)" emitLookNetTorch
         && contains "class LookNet(nn.Module)"   emitLookNetTorch)

  , testProperty "PyTorch module applies σ-mask in L4Block forward (.sigma_mask)" $
      once (contains "self.w1.weight * self.sigma_mask" emitLookNetTorch
         && contains "self.w2.weight * self.sigma_mask" emitLookNetTorch)

  , testProperty "PyTorch module sum-pools tokens in L3Encoder (permutation-invariant)" $
      once (contains "h.sum(dim=1)" emitLookNetTorch)

  , testProperty "build_mlpackage.py targets ANE with FP16 + iOS18" $
      once (contains "ct.ComputeUnit.CPU_AND_NE"        emitBuildMlpackage
         && contains "ct.precision.FLOAT16"             emitBuildMlpackage
         && contains "minimum_deployment_target=ct.target.iOS18" emitBuildMlpackage
         && contains "convert_to=\"mlprogram\""          emitBuildMlpackage)

  , testProperty "build_mlpackage.py uses static shapes (ANE requirement)" $
      once (contains "shape=(1, MAX_TOKENS, GMM_TOKEN_DIM)" emitBuildMlpackage)

  , testProperty "biological-ratio sanity propagates through the emit: hiddenDim == 64 == modelDim" $
      once (hiddenDim == modelDim && hiddenDim == 64)
  ]
