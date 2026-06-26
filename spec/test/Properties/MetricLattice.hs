module Properties.MetricLattice (tests) where

import Test.Tasty
import Test.Tasty.QuickCheck

import SixFour.Spec.MetricLattice

genVec :: Gen [Integer]
genVec = do
  d <- choose (0, 6)
  vectorOf d (choose (-1000, 1000))

genNorm :: Gen NormP
genNorm = elements [L1, LInf]

tests :: TestTree
tests = testGroup "MetricLattice (d6 generalized to an ℓ^p lattice norm; p is the knob)"
  [ testGroup "Metric axioms hold for BOTH p ∈ {1 (=d6), ∞}"
      [ testProperty "non-negative" $
          forAll genNorm $ \p -> forAll genVec $ \v -> lawNormNonNeg p v
      , testProperty "faithful (||v||=0 iff v=0)" $
          forAll genNorm $ \p -> forAll genVec $ \v -> lawNormFaithful p v
      , testProperty "symmetric metric" $
          forAll genNorm $ \p -> forAll genVec $ \x -> forAll genVec $ \y -> lawDistSymmetric p x y
      , testProperty "triangle inequality (Minkowski)" $
          forAll genNorm $ \p -> forAll genVec $ \x -> forAll genVec $ \y -> lawTriangle p x y
      ]

  , testGroup "Discrete geometry: the unit ball shape is the knob"
      [ testProperty "||v||_∞ ≤ ||v||_1 (the ℓ^∞ ball contains the ℓ¹ ball)" $
          forAll genVec lawLInfBoundedByL1
      , testProperty "ℓ¹ unit ball = cross-polytope (2d+1 integer points)" lawL1UnitBallIsCrossPolytope
      , testProperty "ℓ^∞ unit ball = hypercube (3^d integer points)" lawLInfUnitBallIsHypercube
      , testProperty "the knob is real: the two balls differ at d ≥ 2" $ once lawUnitBallsDiffer
      ]
  ]
