module Properties.GaussianChroma (tests) where

import Test.Tasty
import Test.Tasty.QuickCheck

import SixFour.Spec.RefinementSystem
  ( lawModuleSmulOne, lawModuleAddInverse, lawModuleSmulMul
  , lawModuleSmulDistribModule, lawModuleSmulDistribRing )
import SixFour.Spec.GaussianChroma

genInt :: Gen Integer
genInt = choose (-50, 50)

genPair :: Gen (Int, Int)
genPair = (,) <$> choose (-50, 50) <*> choose (-50, 50)

genGCD :: Gen GColourDelta
genGCD = GColourDelta <$> genInt <*> (packChroma <$> genPair)

tests :: TestTree
tests = testGroup "GaussianChroma (the ℤ[i] chroma knob: faithful re-encoding + a hue-rotation op)"
  [ testGroup "GColourDelta as RModule ℤ (fixed shape => every module law strict, incl. inverse)"
      [ testProperty "smul rone = id" $ forAll genGCD lawModuleSmulOne
      , testProperty "additive inverse (strict, unlike ragged ColourDelta)" $
          forAll genGCD lawModuleAddInverse
      , testProperty "smul (a*b) = smul a . smul b" $
          forAll genInt $ \a -> forAll genInt $ \b -> forAll genGCD $ \x -> lawModuleSmulMul a b x
      , testProperty "smul r (x+y) = smul r x + smul r y" $
          forAll genInt $ \r -> forAll genGCD $ \x -> forAll genGCD $ \y ->
            lawModuleSmulDistribModule r x y
      , testProperty "smul (a+b) x = smul a x + smul b x" $
          forAll genInt $ \a -> forAll genInt $ \b -> forAll genGCD $ \x ->
            lawModuleSmulDistribRing a b x
      , testProperty "scale by ℤ is componentwise" $
          forAll genInt $ \k -> forAll genInt $ \l -> forAll genPair $ \p ->
            lawChromaScaleByRealIsComponentwise k l p
      ]
  , testGroup "ℤ[i] chroma: faithful re-encoding + the hue-rotation operator"
      [ testProperty "addition agrees with real pairs (faithful)" $
          forAll genPair $ \p -> forAll genPair $ \q -> lawChromaAddAgreesWithRealPairs p q
      , testProperty "unit i = 90° quarter-turn (a,b)->(-b,a)" $
          forAll genPair lawChromaUnitIsQuarterTurn
      , testProperty "quarter-turn preserves chroma norm" $
          forAll genPair lawChromaUnitRotationPreservesNorm
      , testProperty "quarter-turn has order 4 (i^4=1)" $
          forAll genPair lawChromaQuarterTurnOrderFour
      ]
  ]
