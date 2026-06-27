module Properties.RefinementSystem (tests) where

import Test.Tasty
import Test.Tasty.QuickCheck

import SixFour.Spec.RefinementSystem

genInt :: Gen Integer
genInt = choose (-1000, 1000)

genGaussian :: Gen Gaussian
genGaussian = Gaussian <$> ((,) <$> choose (-100, 100) <*> choose (-100, 100))

genTripleI :: Gen (Triple Integer)
genTripleI = Triple <$> genInt <*> genInt <*> genInt

genTripleG :: Gen (Triple Gaussian)
genTripleG = Triple <$> genGaussian <*> genGaussian <*> genGaussian

genDyad8 :: Gen Dyad8
genDyad8 = Dyad8 <$> vectorOf 8 genInt

genTern3 :: Gen Tern3
genTern3 = Tern3 <$> vectorOf 3 genInt

-- Ring laws as one reusable block over a generator (proves the SAME laws over different rings).
ringLaws :: (CommutativeRing r, Eq r, Show r) => String -> Gen r -> TestTree
ringLaws name g = testGroup name
  [ testProperty "+ assoc" $ forAll g $ \a -> forAll g $ \b -> forAll g $ \c -> lawRingAddAssoc a b c
  , testProperty "+ comm" $ forAll g $ \a -> forAll g $ \b -> lawRingAddComm a b
  , testProperty "+ identity" $ forAll g lawRingAddIdentity
  , testProperty "+ inverse" $ forAll g lawRingAddInverse
  , testProperty "* assoc" $ forAll g $ \a -> forAll g $ \b -> forAll g $ \c -> lawRingMulAssoc a b c
  , testProperty "* comm" $ forAll g $ \a -> forAll g $ \b -> lawRingMulComm a b
  , testProperty "* identity" $ forAll g lawRingMulIdentity
  , testProperty "distributive" $ forAll g $ \a -> forAll g $ \b -> forAll g $ \c -> lawRingDistrib a b c
  ]

-- Module laws over a (scalar, module) generator pair.
moduleLaws :: (RModule r m, Eq m, Show r, Show m) => String -> Gen r -> Gen m -> TestTree
moduleLaws name gr gm = testGroup name
  [ testProperty "smul rone = id" $ forAll gm lawModuleSmulOne
  , testProperty "additive inverse" $ forAll gm lawModuleAddInverse
  , testProperty "smul (a*b) = smul a . smul b" $
      forAll gr $ \a -> forAll gr $ \b -> forAll gm $ \x -> lawModuleSmulMul a b x
  , testProperty "smul r (x+y) = smul r x + smul r y" $
      forAll gr $ \r -> forAll gm $ \x -> forAll gm $ \y -> lawModuleSmulDistribModule r x y
  , testProperty "smul (a+b) x = smul a x + smul b x" $
      forAll gr $ \a -> forAll gr $ \b -> forAll gm $ \x -> lawModuleSmulDistribRing a b x
  ]

liftLaws :: (ReversibleLift f, Eq f, Show f) => String -> Int -> Gen f -> TestTree
liftLaws name b g = testGroup name
  [ testProperty "unlift . lift = id (bijection)" $ forAll g lawLiftRoundTrips
  , testProperty "fromVec . toVec = id" $ forAll g lawFromToVec
  , testProperty ("detail count == b-1 == " ++ show (b - 1)) $ forAll g lawLiftDetailCount
  ]

-- Unit-group laws over a generator (proves the "not a field" structure at each ring).
unitLaws :: (CommutativeRing r, Eq r, Show r) => String -> Gen r -> TestTree
unitLaws name g = testGroup name
  [ testProperty "units closed under * (they form a group)" $ forAll g lawUnitsClosedUnderMul
  , testProperty "unitInverse defined EXACTLY on units (x*x⁻¹=1 iff unit, else Nothing)" $
      forAll g lawUnitInverseOnlyOnUnits
  ]

tests :: TestTree
tests = testGroup "RefinementSystem (the spine: CommutativeRing -> RModule -> ReversibleLift)"
  [ ringLaws "CommutativeRing over ℤ (the Q16 base, units ±1, NOT a field)" genInt
  , ringLaws "CommutativeRing over ℤ[i] (Gaussian integers — the SECOND ring)" genGaussian
  , unitLaws "ℤ* = {±1} (the enumerated unit group, not a field)" genInt
  , unitLaws "ℤ[i]* = {±1,±i} (the four quarter-turns)" genGaussian
  , testProperty "teeth: 2 (ℤ) and 1+i, 2 (ℤ[i]) are non-units (no inverse)" $
      once lawNonUnitsHaveNoInverse
  , testProperty "Gaussian units ARE the quarter-turns; i⁻¹ = -i (ties GaussianChroma)" $
      once lawGaussianUnitsAreQuarterTurns
  , moduleLaws "RModule over ℤ³ (the ColourDelta carrier)" genInt genTripleI
  , moduleLaws "RModule over ℤ[i]³ (Gaussian chroma — base-ring generalizes)" genGaussian genTripleG
  , liftLaws "ReversibleLift: dyadic b=8 octant" 8 genDyad8
  , liftLaws "ReversibleLift: NON-DYADIC b=3 (the generalization)" 3 genTern3
  ]
