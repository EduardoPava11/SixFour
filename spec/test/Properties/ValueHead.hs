{- |
Module      : Properties.ValueHead
Description : Property tests for 'SixFour.Spec.ValueHead' — the BT value head's
              on-device training law (nn-6).

Small shapes keep the finite-difference gradient check sharp; the
'lawReducesToLinear*' laws pin that the linear Bradley–Terry head is the
zero-residual special case (continuous with 'Properties.PreferenceUpdate').
-}
module Properties.ValueHead (tests) where

import Test.Tasty
import Test.Tasty.QuickCheck

import SixFour.Spec.Preference (Embedding)
import SixFour.Spec.ValueHead

genShape :: Gen ValueShape
genShape = ValueShape <$> choose (1, 4) <*> choose (1, 3)

genParamsFor :: ValueShape -> Gen [Double]
genParamsFor sh = vectorOf (paramCount sh) (choose (-1, 1))

genEmbN :: Int -> Gen Embedding
genEmbN n = vectorOf n (choose (-1, 1))

tests :: TestTree
tests = testGroup "ValueHead (BT-MLP value head: linear floor + gated tanh residual)"
  [ testProperty "analytic gradient matches central finite differences (backprop correct)" $
      forAll genShape $ \sh -> forAll (genParamsFor sh) $ \ps ->
      forAll (genEmbN (vsIn sh)) $ \w -> forAll (genEmbN (vsIn sh)) $ \l ->
      forAll (choose (0, 0.2)) $ \eps ->
        lawValueGradientFiniteDiff eps sh ps w l
  , testProperty "a small-eta step does not increase the pair loss (local descent)" $
      forAll genShape $ \sh -> forAll (genParamsFor sh) $ \ps ->
      forAll (genEmbN (vsIn sh)) $ \w -> forAll (genEmbN (vsIn sh)) $ \l ->
      forAll (choose (1.0e-4, 0.05)) $ \eta ->
        lawValueStepDecreasesLoss eta sh ps w l
  , testProperty "w2 = 0 reduces the head to the linear BT floor (forward)" $
      forAll genShape $ \sh -> forAll (genParamsFor sh) $ \ps ->
      forAll (genEmbN (vsIn sh)) $ \x ->
        lawReducesToLinear sh ps x
  , testProperty "w2 = 0 reduces the training gradient to PreferenceUpdate.btPairGradient" $
      forAll genShape $ \sh -> forAll (genParamsFor sh) $ \ps ->
      forAll (genEmbN (vsIn sh)) $ \w -> forAll (genEmbN (vsIn sh)) $ \l ->
        lawReducesToLinearGradient sh ps w l
  , testProperty "label smoothing gives a finite optimal margin logit(1-eps)" $
      forAll (choose (0.01, 0.49)) $ \eps -> forAll (choose (-10, 10)) $ \d ->
        lawSmoothingHasFiniteOptimum eps d
  , testProperty "deployed value head is 24->32->1 (856 params)" $
      defaultValueShape == ValueShape 24 32 && paramCount defaultValueShape == 856
  ]
