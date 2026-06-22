module Properties.EncoderFrozen (tests) where

import Test.Tasty
import Test.Tasty.QuickCheck

import SixFour.Spec.EncoderFrozen

tests :: TestTree
tests = testGroup "EncoderFrozen (the encoder = fixed lift ∘ fixed φ_B; ZERO params; the predictor θ_B is the only learned object; embedding re-enters Q16)"
  [ testProperty "the encoder lift is a bijection (frozen by proof — nothing to pre-train)" $
      once lawEncoderLiftIsBijective
  , testProperty "the embedding feature map is PARAMETER-FREE — it is blind to θ_B (locks candidate (b) out)" $
      once lawEmbeddingFeatureMapIsParameterFree
  , testProperty "the 63-param predictor θ_B is the ONLY learned object (it rides ABOVE the embedding)" $
      once lawPredictorIsTheOnlyLearnedObject
  , testProperty "INFER: the float embedding reaches a byte ONLY through the single reenterQ16 crossing" $
      once lawEmbeddingNeverBypassesQ16
  , testProperty "CONTINUOUS: committing the raw float embedding without re-entry is sub-quantum-unsafe (teeth)" $
      once lawRawEmbeddingCommitIsUnsafe
  , testProperty "FOUR-PHASE KEYSTONE: no encoder pre-training phase — the frozen lift defines the space AND makes the label" $
      once lawNoPreTrainPhase
  ]
