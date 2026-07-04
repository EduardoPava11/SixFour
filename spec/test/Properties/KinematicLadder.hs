module Properties.KinematicLadder (tests) where

import Test.Tasty
import Test.Tasty.QuickCheck

import SixFour.Spec.KinematicLadder

genStream :: Gen [Integer]
genStream = vectorOf 16 (choose (-1000, 1000))

genBlock :: Gen [Integer]
genBlock = vectorOf 8 (choose (-4000, 4000))

genCoeffs :: Gen [Integer]
genCoeffs = vectorOf 4 (choose (-50, 50))

tests :: TestTree
tests = testGroup "KinematicLadder (velocity -> acceleration up the rungs; exact discrete calculus)"
  [ testGroup "The Pascal transfer function (physics coarsens by binomial rows)"
      [ testProperty "Delta^k coarsens by Pascal row k+1: (1,2,1), (1,3,3,1), (1,4,6,4,1)" $
          forAll genStream lawKthDifferenceCoarsensByPascal
      ]

  , testGroup "Newton-Mahler: the 2-adic-native Taylor expansion"
      [ testProperty "full expansion reproduces any trajectory: f(t) = sum C(t,k) Delta^k f(0)" $
          forAll genStream lawNewtonMahlerExpansion
      ]

  , testGroup "The budget estimator (kinematic order == halting depth == S-packets owed)"
      [ testProperty "Delta^{k+1} == 0 => order-k prediction exact (zero packets beyond k)" $
          forAll genCoeffs lawPolynomialTrajectoryHaltsExactly
      , testProperty "TEETH: t^{k+1} escapes order k with residual exactly (k+1)!" $
          once lawOrderKPlusOneLeavesResidual
      ]

  , testGroup "The latents ARE the physics (bridge to OctantViews)"
      [ testProperty "every band = (-1)^|S| * pooled mixed difference (independent recursion)" $
          forAll genBlock lawBandsAreMixedDifferences
      ]
  ]
