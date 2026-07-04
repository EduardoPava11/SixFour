module Properties.KinematicHaltPrior (tests) where

import Test.Tasty
import Test.Tasty.QuickCheck

import SixFour.Spec.KinematicHaltPrior

genCoeffs :: Gen [Integer]
genCoeffs = vectorOf 4 (choose (-60, 60))

genDegree :: Gen Int
genDegree = choose (0, 3)

tests :: TestTree
tests = testGroup "KinematicHaltPrior (order-k certification wired into the PonderNet objective)"
  [ testGroup "Minimal sufficiency in exact integers"
      [ testProperty "L_j == 0 iff j >= certifiedOrder (halting depth == kinematic order == S-packets)" $
          forAll genDegree $ \d -> forAll genCoeffs (lawResidualZeroIffAtOrAboveOrder d)
      ]

  , testGroup "The pointed prior behaves in the PonderNet machinery"
      [ testProperty "proper distribution, mass exactly 1 at the certified step" $
          forAll (choose (0, 100)) lawCertifiedPriorIsProperAndPointed
      , testProperty "spends exactly k+1 expected steps (the bill equals the claimed depth)" $
          forAll (choose (0, 100)) lawCertifiedPriorSpendsExactlyK
      ]

  , testGroup "Optimality under the trainer's own objective"
      [ testProperty "certified prior achieves exactly ZERO expected loss" $
          forAll genDegree $ \d -> forAll genCoeffs (lawCertifiedPriorAchievesZeroLoss d)
      , testProperty "TEETH: one step early pays expected loss >= 1 (integer residual, no epsilon)" $
          forAll genDegree $ \d -> forAll genCoeffs (lawEarlyHaltPaysResidual d)
      , testProperty "KEYSTONE: cheapest zero-loss pointed halt == certifiedOrder" $
          forAll genDegree $ \d -> forAll genCoeffs (lawCheapestZeroLossHaltIsCertifiedOrder d)
      ]
  ]
