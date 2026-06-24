module Properties.Sinkhorn (tests) where

import Test.Tasty
import Test.Tasty.QuickCheck

import qualified Data.Vector as V

import SixFour.Spec.Color    (OKLab(..))
import SixFour.Spec.Sinkhorn
import SixFour.Spec.Laws     (lawSinkhornBalancedColumns)

genOKLab :: Gen OKLab
genOKLab = OKLab <$> choose (0, 1) <*> choose (-0.4, 0.4) <*> choose (-0.4, 0.4)

-- A small discrete measure (1–5 atoms) with strictly-positive weights — the regime
-- the spec's law tests exercise (the full-palette fidelity surface is the trainer's).
genMeasure :: Gen Measure
genMeasure = do
  k <- choose (1, 5)
  let atom = (,) <$> genOKLab <*> choose (0.05, 2.0)
  vectorOf k atom

-- Tiny transport plans for the column-balance law (Spec.Laws): balanced columns vs skewed.
balancedPlan, skewedPlan :: V.Vector (V.Vector Double)
balancedPlan = V.fromList [V.fromList [0.5, 0.5], V.fromList [0.5, 0.5]]  -- col sums [1, 1]
skewedPlan   = V.fromList [V.fromList [1.0, 0.0], V.fromList [1.0, 0.0]]  -- col sums [2, 0]

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

  , testProperty "lawSinkhornBalancedColumns: balanced plan passes, skewed plan fails (teeth)" $
      once $ lawSinkhornBalancedColumns 1e-9 balancedPlan
               && not (lawSinkhornBalancedColumns 1e-9 skewedPlan)
  ]
