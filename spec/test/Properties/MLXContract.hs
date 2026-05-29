{-# LANGUAGE OverloadedStrings #-}

module Properties.MLXContract (tests) where

import           Test.Tasty
import           Test.Tasty.QuickCheck
import qualified Data.Text             as T
import           Data.Text             (Text)

import SixFour.Codegen.MLX     (emitLookNetMLX)
import SixFour.Codegen.CoreML  (emitLookNetTorch, emitLookNetConstants, pyBoolList)
import SixFour.Spec.Tensor     (sigma64Mask, gmmTokenSigmaMask)
import SixFour.Spec.LookNetD   (sigma768Mask, decoderOutputDim)
import SixFour.Spec.LookNet    (modelDim)
import SixFour.Spec.LookNetR   (coreDepth)

-- The MLX codegen output is text. Tests pin that the mlx.nn module emits the
-- same constants the spec declares AND — crucially — that every shared constant
-- line is byte-identical to the PyTorch emitter (the cross-emitter golden sync
-- that lets MLX-trained weights transfer to the dormant CoreML fallback).

contains :: Text -> Text -> Bool
contains needle hay = T.isInfixOf needle hay

tests :: TestTree
tests = testGroup "MLXContract (Codegen.MLX emits an mlx.nn module in sync with the spec + the torch emitter)"

  [ testProperty "MLX module emits MODEL_DIM = 64" $
      once (contains ("MODEL_DIM             = " <> T.pack (show modelDim)) emitLookNetMLX)

  , testProperty "MLX module emits CORE_DEPTH = 8" $
      once (contains ("CORE_DEPTH            = " <> T.pack (show coreDepth)) emitLookNetMLX)

  , testProperty "MLX module emits DECODER_OUT_DIM = 768" $
      once (contains ("DECODER_OUT_DIM       = " <> T.pack (show decoderOutputDim)) emitLookNetMLX)

  , testProperty "MLX module emits all three σ-masks bit-identical to the spec" $
      once (contains ("SIGMA64_MASK = " <> pyBoolList sigma64Mask) emitLookNetMLX
         && contains ("GMM_TOKEN_SIGMA_MASK = " <> pyBoolList gmmTokenSigmaMask) emitLookNetMLX
         && contains ("SIGMA768_MASK = " <> pyBoolList sigma768Mask) emitLookNetMLX)

  , testProperty "MLX module defines the layer classes (L3Encoder, SharedBlock, L4Recursion, L5Decoder, LookNet)" $
      once (contains "class L3Encoder(nn.Module)"   emitLookNetMLX
         && contains "class SharedBlock(nn.Module)" emitLookNetMLX
         && contains "class L4Recursion(nn.Module)" emitLookNetMLX
         && contains "class L5Decoder(nn.Module)"   emitLookNetMLX
         && contains "class LookNet(nn.Module)"     emitLookNetMLX)

  , testProperty "MLX module uses the mlx idiom: import mlx, def __call__ (NOT def forward)" $
      once (contains "import mlx.core as mx" emitLookNetMLX
         && contains "import mlx.nn as nn"   emitLookNetMLX
         && contains "def __call__"          emitLookNetMLX
         && not (contains "def forward"      emitLookNetMLX)
         && not (contains "import torch"      emitLookNetMLX))

  , testProperty "MLX module uses mx.tanh (odd activation) and no relu/gelu/silu" $
      once (contains "mx.tanh" emitLookNetMLX
         && not (contains "relu" emitLookNetMLX)
         && not (contains "gelu" emitLookNetMLX)
         && not (contains "silu" emitLookNetMLX))

  , testProperty "MLX module: no bias, sum-pool over tokens (permutation-invariant)" $
      once (contains "bias=False"          emitLookNetMLX
         && contains "mx.sum(h, axis=1)"   emitLookNetMLX)

  , testProperty "MLX Mixture-of-Recursions: ONE shared block reused RECURSION_STEPS times" $
      once (contains "SHARED_BLOCK_COUNT    = 1" emitLookNetMLX
         && contains "self.g = SharedBlock()"    emitLookNetMLX
         && contains "for _ in range(RECURSION_STEPS)" emitLookNetMLX)

  , testProperty "MLX halting head is σ-INVARIANT: reads only (‖achroma‖², ‖chroma‖²)" $
      once (contains "HALT_FEATURE_DIM      = 2" emitLookNetMLX
         && contains "mx.sum(achroma * achroma, axis=-1)" emitLookNetMLX
         && contains "mx.sum(chroma * chroma, axis=-1)"   emitLookNetMLX
         && contains "mx.stack"      emitLookNetMLX
         && contains "self.halt_mlp" emitLookNetMLX)

  , testProperty "MLX decoder reads per-step contexts (head i ← contexts[i])" $
      once (contains "def __call__(self, contexts)" emitLookNetMLX
         && contains "contexts[i] @ w.T"            emitLookNetMLX)

  , -- THE cross-emitter golden sync: every shared constant line is byte-identical
    -- in both emitters, so MLX-trained weights transfer to the CoreML fallback.
    testProperty "cross-emitter sync: every shared constant line is byte-identical in MLX and torch" $
      once (all (\ln -> contains ln emitLookNetMLX && contains ln emitLookNetTorch)
                (filter (not . T.null) emitLookNetConstants))
  ]
