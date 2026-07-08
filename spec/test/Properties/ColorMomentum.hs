module Properties.ColorMomentum (tests) where

import Test.Tasty
import Test.Tasty.QuickCheck

import SixFour.Spec.ColorMomentum

genBlock :: Gen [Integer]
genBlock = vectorOf 8 (choose (-100000, 100000))

tests :: TestTree
tests = testGroup "ColorMomentum (mass = reversal-even coarse; momentum = reversal-odd t-band; flux = W1)"
  [ testGroup "The arrow splits the grading"
      [ testProperty "mass is reversal-even" $
          forAll genBlock lawMassIsReversalEven
      , testProperty "momentum is reversal-odd" $
          forAll genBlock lawMomentumIsReversalOdd
      , testProperty "momentum IS the (negated) t-band" $
          forAll genBlock lawMomentumIsTheTBand
      , testProperty "every band negates iff it contains t (the GHCi table, quantified)" $
          forAll genBlock lawGradingSplitsByTheArrow
      ]

  , testGroup "K keeps mass, kills momentum; flux is transported mass"
      [ testProperty "a pure momentum kick moves momentum by 8d and mass by 0" $
          forAll genBlock $ \b -> forAll (choose (-1000, 1000)) (lawKPreservesMassKillsMomentum b)
      , testProperty "W1 charges mass x distance (a d-level drift costs exactly d)" $
          \d l -> lawFluxChargesMassTimesDistance d l
      , testProperty "flux triangle recursion: net <= summed per-tick" $
          \a b c -> lawFluxTriangleRecursion a b c
      ]
  ]
