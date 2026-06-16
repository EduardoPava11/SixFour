module Properties.Sinkhorn (tests) where

import Test.Tasty
import Test.Tasty.QuickCheck

import SixFour.Spec.Color    (OKLab(..))
import SixFour.Spec.Sinkhorn

genOKLab :: Gen OKLab
genOKLab = OKLab <$> choose (0, 1) <*> choose (-0.4, 0.4) <*> choose (-0.4, 0.4)

-- A small discrete measure (1–5 atoms) with strictly-positive weights — the regime
-- the spec's law tests exercise (the full-palette fidelity surface is the trainer's).
genMeasure :: Gen Measure
genMeasure = do
  k <- choose (1, 5)
  let atom = (,) <$> genOKLab <*> choose (0.05, 2.0)
  vectorOf k atom

tests :: TestTree
tests = testGroup "Sinkhorn (debiased entropic-OT fidelity)"
  [ testProperty "transport cost T_ε(α,β) ≥ 0" $
      forAll genMeasure $ \a ->
        forAll genMeasure $ \b -> lawSinkhornCostNonNegative a b

  , testProperty "self-divergence is EXACTLY zero: S_ε(α,α) = 0" $
      forAll genMeasure lawSinkhornSelfDivergenceZero

  , testProperty "divergence is non-negative: S_ε(α,β) ≥ 0 (finite-iter slack)" $
      forAll genMeasure $ \a ->
        forAll genMeasure $ \b -> lawSinkhornDivergenceNonNegative a b

  , testProperty "divergence is symmetric: S_ε(α,β) = S_ε(β,α)" $
      forAll genMeasure $ \a ->
        forAll genMeasure $ \b -> lawSinkhornDivergenceSymmetric a b

  , -- THE bridge law: between point masses S_ε reduces to squared OKLab distance,
    -- exactly (mirrors the Bures Σ→0 reduction).
    testProperty "singleton reduction: S_ε(δx, δy) == okLabDistanceSquared x y" $
      forAll genOKLab $ \x ->
        forAll genOKLab $ \y -> lawSinkhornSingletonIsSquaredDistance x y
  ]
