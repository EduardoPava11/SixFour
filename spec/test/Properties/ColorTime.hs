module Properties.ColorTime (tests) where

import Test.Tasty
import Test.Tasty.QuickCheck
import Data.Ratio ((%))

import SixFour.Spec.ColorTime

-- Positive exact rationals (durations Δ₀, irradiance Ē) from small integer ratios.
genPos :: Gen Rational
genPos = do
  n <- choose (1, 4096) :: Gen Integer
  d <- choose (1, 4096) :: Gen Integer
  pure (n % d)

-- Nonnegative rationals (linear samples, photon counts) — includes exact 0.
genNonNeg :: Gen Rational
genNonNeg = frequency [(1, pure 0), (9, genPos)]

-- Ladder rungs 0..6 (64² … 1²); laws abs their argument, so any Int is safe.
genRung :: Gen Int
genRung = choose (0, 6)

-- A temporal window as its per-frame samples / shutter durations (may be empty).
genWindow :: Gen [Rational]
genWindow = choose (0, 24) >>= \n -> vectorOf n genNonNeg

tests :: TestTree
tests = testGroup "ColorTime (τ_c = temporal support of a chromatic measurement; SNR ∝ √τ_c)"
  [ testProperty "MEASURE: color-time is finitely additive over concatenated windows" $
      forAll genWindow $ \a -> forAll genWindow $ \b -> lawColorTimeAdditive a b
  , testProperty "QUARTIC: light ladder ⇒ τ_c(k) = 4^k · Δ₀" $
      forAll genPos $ \d0 -> forAll genRung $ \k -> lawColorTimeQuartic d0 k
  , testProperty "UNIFICATION: optical light ratio 2^k == temporal pool depth T_k" $
      forAll genRung lawStopEqualsPoolIndex
  , testProperty "√ POWER LAW (exact on squares): SNR²(k) = Ē · 4^k · Δ₀" $
      forAll genPos $ \e -> forAll genPos $ \d0 -> forAll genRung $ \k -> lawSnrSqrtPowerLaw e d0 k
  , testProperty "chromaticity variance ∝ 1/N: Var · N = 1" $
      forAll genPos lawChromaVarianceInverse
  , testProperty "photon counting is Poisson: Fano factor = 1" $
      forAll genPos lawFanoUnity
  , testProperty "SUMS COMPOSE: Σ(concat) = Σ(map Σ) — partition-invariant linear carrier" $
      forAll (resize 12 (listOf genWindow)) lawSumsCompose
  , testProperty "MEANS DO NOT COMPOSE: witnessed unequal-partition counterexample" $
      once lawMeansDoNotCompose
  , testProperty "LINEAR BEATS GAMMA (Jensen, γ=²): mean(γ) ≥ γ(mean), gap = Var" $
      forAll genWindow lawLinearBeatsGamma
  , testProperty "MOTION AVERAGED: temporalAverage ∈ [min,max] of the trajectory" $
      forAll genWindow lawMotionAverageInHull
  ]
