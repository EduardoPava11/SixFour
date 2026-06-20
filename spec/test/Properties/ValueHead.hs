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
import Test.QuickCheck

import SixFour.Spec.Preference (Embedding)
import SixFour.Spec.ValueHead

genShape :: Gen ValueShape
genShape = ValueShape <$> choose (1, 4) <*> choose (1, 3)

genParamsFor :: ValueShape -> Gen [Double]
genParamsFor sh = vectorOf (paramCount sh) (choose (-1, 1))

genEmbN :: Int -> Gen Embedding
genEmbN n = vectorOf n (choose (-1, 1))

genCompareN :: Int -> Gen (Embedding, Embedding)
genCompareN n = (,) <$> genEmbN n <*> genEmbN n

genLogN :: Int -> Gen [(Embedding, Embedding)]
genLogN n = choose (0, 6) >>= \k -> vectorOf k (genCompareN n)

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
    -- nn-10: fixed-order training trajectory + cross-device golden signature ----
  , testProperty "nn-10: training trajectory + key signature are deterministic" $
      forAll genShape $ \sh -> forAll (genParamsFor sh) $ \ps0 ->
      forAll (genLogN (vsIn sh)) $ \cmps -> forAll (genCompareN (vsIn sh)) $ \probe ->
        lawTrainTrajectoryDeterministic 0.05 1.0e-3 0.05 sh ps0 cmps probe
  , testProperty "nn-10: trajectory is the ordered fold (length log + 1; last = foldl')" $
      forAll genShape $ \sh -> forAll (genParamsFor sh) $ \ps0 ->
      forAll (genLogN (vsIn sh)) $ \cmps ->
        lawTrainTrajectoryFixedOrder 0.05 1.0e-3 0.05 sh ps0 cmps
  , testProperty "nn-10: q16 signature survives the float->q16->float round-trip (cross-device)" $
      forAll genShape $ \sh -> forAll (genParamsFor sh) $ \ps0 ->
      forAll (genLogN (vsIn sh)) $ \cmps -> forAll (genCompareN (vsIn sh)) $ \probe ->
        lawTrajectoryKeyRequantStable 0.05 1.0e-3 0.05 sh ps0 cmps probe
  , testProperty "nn-10 GOLDEN: fixed training run reproduces the pinned q16 key signature" $
      let actual = trajectoryKeys 0.05 1.0e-3 0.05 goldenShape goldenInit goldenLog goldenProbe
      in counterexample ("actual = " ++ show actual) (actual == goldenKeys)
  ]

-- nn-10 golden: a fixed, small training run whose integer q16 decision signature is
-- pinned as a regression gate (the contract a device trainer must reproduce).
goldenShape :: ValueShape
goldenShape = ValueShape 2 2

goldenInit :: [Double]
goldenInit = [0.1, -0.2, 0.3, 0.4, -0.1, 0.2, 0.05, -0.05, 0.2, -0.1]

goldenLog :: [(Embedding, Embedding)]
goldenLog =
  [ ([1, 0], [0, 1])
  , ([0.5, 0.5], [-0.5, 0.2])
  , ([0.2, -0.3], [0.1, 0.4])
  ]

goldenProbe :: (Embedding, Embedding)
goldenProbe = ([1, 0], [0, 1])

-- The probe margin's q16 key after each training step (init + 3 Compares); it
-- drifts upward as the head learns to separate the probe pair. A device trainer
-- reproducing this fixed run must produce exactly this integer signature.
goldenKeys :: [Int]
goldenKeys = [20491, 23144, 24115, 25347]
