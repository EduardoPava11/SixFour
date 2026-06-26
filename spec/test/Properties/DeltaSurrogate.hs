module Properties.DeltaSurrogate (tests) where

import Test.Tasty
import Test.Tasty.QuickCheck

import SixFour.Spec.ConstructionEncoder (QColour)
import SixFour.Spec.DeltaSurrogate

genQColours :: Gen [QColour]
genQColours = do
  k <- choose (0, 6)
  vectorOf k ((,,) <$> choose (-3000, 3000) <*> choose (-3000, 3000) <*> choose (-3000, 3000))

-- A base/target index pair over K slots (same length, all in range) for the transport bridge.
genIndexPair :: Gen (Int, [Int], [Int])
genIndexPair = do
  k <- choose (1, 8)
  n <- choose (0, 8)
  base <- vectorOf n (choose (0, k - 1))
  tgt  <- vectorOf n (choose (0, k - 1))
  pure (k, base, tgt)

tests :: TestTree
tests = testGroup "DeltaSurrogate (differentiable training surrogates; hard commit re-enters the byte-exact carrier)"
  [ testGroup "VALUE head — continuous OKLab regression"
      [ testProperty "decode∘embed == id (integer target is a fixpoint of the relaxation)" $
          forAll genQColours lawValueSurrogateDecodesToCarrier
      , testProperty "regression loss is zero exactly at the target" $
          forAll genQColours lawValueLossZeroAtTarget
      , testProperty "loss is a SQUARED metric: scaling error by c scales loss by c² (regression, not L1/CE)" $
          forAll genQColours $ \xs -> forAll (choose (0, 20)) $ \c -> lawValueLossIsRegression xs c
      ]

  , testGroup "POLICY head — per-voxel categorical (softmax / cross-entropy)"
      [ testProperty "KEYSTONE: argmax commit re-enters the byte-exact IndexDelta transport" $
          forAll genIndexPair $ \(k, base, tgt) -> lawPolicySurrogateDecodesToTransport k base tgt
      , testProperty "argmax commit is deterministic (lowest-index tie-break, no float coin-flip)" $
          once lawPolicyArgmaxDeterministic
      , testProperty "cross-entropy strictly prefers the target slot (a genuine classification objective)" $
          forAll (choose (0, 10)) $ \k -> forAll (choose (0, 30)) $ \t -> forAll (choose (0, 30)) $ \w ->
            lawPolicyCrossEntropyPrefersTarget k t w
      , testProperty "BACKWARD: CE gradient step lowers loss + argmax reaches the data slot (train-time)" $
          once lawPolicyCEGradientMovesTowardTarget
      , testProperty "COMMIT: margin-guarded commit falls back to the data slot at a float near-tie" $
          once lawPolicyArgmaxMarginOrFallback
      ]
  ]
