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
import SixFour.Spec.LookNetD  (sigmaDecoderMask, decoderLevelDims, decoderOutputDim)
import SixFour.Spec.SigmaPairHead (sigmaPairDegreesOfFreedom, sigmaPairDepth, sigmaPairLeaves)
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

  , testProperty "PyTorch module emits DECODER_OUT_DIM = 384 (= SIGMA_PAIR_DOF)" $
      once (contains ("DECODER_OUT_DIM       = " <> T.pack (show decoderOutputDim))
                     emitLookNetTorch
            && decoderOutputDim == sigmaPairDegreesOfFreedom
            && decoderOutputDim == 384)

  , testProperty "PyTorch module emits SIGMA_PAIR_* pins (DOF 384, DEPTH 7, LEAVES 256)" $
      once (contains ("SIGMA_PAIR_DOF        = " <> T.pack (show sigmaPairDegreesOfFreedom)) emitLookNetTorch
         && contains ("SIGMA_PAIR_DEPTH      = " <> T.pack (show sigmaPairDepth))            emitLookNetTorch
         && contains ("SIGMA_PAIR_LEAVES     = " <> T.pack (show sigmaPairLeaves))           emitLookNetTorch
         && sigmaPairDegreesOfFreedom == 384 && sigmaPairDepth == 7 && sigmaPairLeaves == 256)

  , testProperty "PyTorch module emits L6 reconstruct_sigma_pair (256-leaf σ-pair palette)" $
      once (contains "def reconstruct_sigma_pair(coeffs" emitLookNetTorch
         && contains "def _haar_reconstruct(coeffs" emitLookNetTorch)

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

  , testProperty "PyTorch module emits SIGMA_DECODER_MASK bit-identical to Haskell" $
      once (contains ("SIGMA_DECODER_MASK = " <> pyBoolList sigmaDecoderMask)
                     emitLookNetTorch)

  , testProperty "PyTorch module defines the layer classes (L3Encoder, SharedBlock, L4Recursion, L5Decoder)" $
      once (contains "class L3Encoder(nn.Module)"   emitLookNetTorch
         && contains "class SharedBlock(nn.Module)" emitLookNetTorch
         && contains "class L4Recursion(nn.Module)" emitLookNetTorch
         && contains "class L5Decoder(nn.Module)"   emitLookNetTorch
         && contains "class LookNet(nn.Module)"     emitLookNetTorch)

  , testProperty "Mixture-of-Recursions: ONE shared block reused CORE_DEPTH times" $
      once (contains "SHARED_BLOCK_COUNT    = 1" emitLookNetTorch
         && contains "RECURSION_STEPS       = " emitLookNetTorch
         && contains "self.g = SharedBlock()"   emitLookNetTorch
         && contains "for _ in range(RECURSION_STEPS)" emitLookNetTorch)

  , testProperty "PyTorch module applies σ-mask in SharedBlock refine (.sigma_mask)" $
      once (contains "self.w1.weight * self.sigma_mask" emitLookNetTorch
         && contains "self.w2.weight * self.sigma_mask" emitLookNetTorch)

  , testProperty "halting head is σ-INVARIANT: reads only (‖achroma‖², ‖chroma‖²)" $
      once (contains "HALT_FEATURE_DIM      = 2" emitLookNetTorch
         && contains "(achroma ** 2).sum(dim=-1)" emitLookNetTorch
         && contains "(chroma ** 2).sum(dim=-1)"  emitLookNetTorch
         && contains "torch.stack"                emitLookNetTorch
         && contains "self.halt_mlp"              emitLookNetTorch)

  , testProperty "L5Decoder reads per-step contexts (head i ← contexts[i])" $
      once (contains "def forward(self, contexts: list)" emitLookNetTorch
         && contains "F.linear(contexts[i], w)" emitLookNetTorch)

  , testProperty "SharedBlock refine uses tanh (odd activation) — required for σ-equivariance" $
      once (contains "torch.tanh"     emitLookNetTorch
         && not (contains "F.gelu"    emitLookNetTorch)
         && not (contains "F.relu"    emitLookNetTorch)
         && not (contains "F.silu"    emitLookNetTorch))

  , testProperty "L3Encoder uses no bias (a constant bias breaks σ-equivariance unless σ-fixed)" $
      once (contains "bias=False" emitLookNetTorch
         && not (contains "self.phi1" emitLookNetTorch))

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
