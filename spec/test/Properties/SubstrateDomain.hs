module Properties.SubstrateDomain (tests) where

import Test.Tasty
import Test.Tasty.QuickCheck

import SixFour.Spec.SubstrateDomain

-- a scalar inside the invertible domain
genDom :: Gen Int
genDom = choose (negate substrateBound, substrateBound)

genQuad :: Gen (Int, Int, Int, Int)
genQuad = (,,,) <$> genDom <*> genDom <*> genDom <*> genDom

tests :: TestTree
tests = testGroup "SubstrateDomain (the +-B=2^29-1 invertible domain; matches Zig RC_OUT_OF_RANGE)"
  [ testProperty "within domain the lift round-trips exactly" $
      forAll genQuad lawDomainRoundTrips
  , testProperty "within domain EVERY lift band fits i32 (the Zig totality guard is sound)" $
      forAll genQuad lawDomainFitsI32
  , testProperty "TEETH: the bound B is tight (B fits i32, B+1 overflows)" $
      once lawBoundIsTight
  , testProperty "a single-level detail of two in-domain values stays within 2B" $
      forAll genDom $ \x -> forAll genDom $ \y -> lawDetailWithinTwoB x y
  ]
