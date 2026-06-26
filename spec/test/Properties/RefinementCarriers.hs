module Properties.RefinementCarriers (tests) where

import Test.Tasty
import Test.Tasty.QuickCheck

import SixFour.Spec.RefinementSystem
  ( lawModuleSmulOne, lawModuleSmulMul, lawModuleSmulDistribModule, lawModuleSmulDistribRing
  , lawLiftFRoundTrips, lawFromToVec, lawLiftDetailCount )
import SixFour.Spec.HierarchicalDelta (ColourDelta(..))
import SixFour.Spec.OctreeCell (V8(..))
import SixFour.Spec.RefinementCarriers

genInt :: Gen Integer
genInt = choose (-50, 50)

genQ :: Gen (Int, Int, Int)
genQ = (,,) <$> choose (-50, 50) <*> choose (-50, 50) <*> choose (-50, 50)

genQList :: Gen [(Int, Int, Int)]
genQList = choose (0, 6) >>= \n -> vectorOf n genQ

genColourDelta :: Gen ColourDelta
genColourDelta = ColourDelta <$> genQList

genV8 :: Gen (V8 Int)
genV8 = V8 <$> g <*> g <*> g <*> g <*> g <*> g <*> g <*> g
  where g = choose (-50, 50)

genOctLeaf8 :: Gen OctLeaf8
genOctLeaf8 = OctLeaf8 <$> genV8

-- A slot transport (permutation image) and an index map, both over a small slot set.
genTransport :: Gen [Int]
genTransport = choose (0, 6) >>= \n -> vectorOf n (choose (0, 7))

genIdx :: Gen [Int]
genIdx = choose (0, 8) >>= \n -> vectorOf n (choose (0, 7))

tests :: TestTree
tests = testGroup "RefinementCarriers (the capstone classes GOVERN the production carriers)"
  [ testGroup "ColourDelta as RModule ℤ (the VALUE ℤ-module = the real recolour ops)"
      [ testProperty "smul rone = id" $ forAll genColourDelta lawModuleSmulOne
      , testProperty "smul (a*b) = smul a . smul b" $
          forAll genInt $ \a -> forAll genInt $ \b -> forAll genColourDelta $ \x ->
            lawModuleSmulMul a b x
      , testProperty "smul r (x+y) = smul r x + smul r y" $
          forAll genInt $ \r -> forAll genColourDelta $ \x -> forAll genColourDelta $ \y ->
            lawModuleSmulDistribModule r x y
      , testProperty "smul (a+b) x = smul a x + smul b x" $
          forAll genInt $ \a -> forAll genInt $ \b -> forAll genColourDelta $ \x ->
            lawModuleSmulDistribRing a b x
      , testProperty "additive inverse (modulo trailing-zero canon)" $
          forAll genQList lawColourModuleInverseModuloCanon
      , testProperty "module ops act as recolour at the applyValueDelta call site"
          lawColourModuleActsAsRecolour
      ]
  , testGroup "OctLeaf8 as ReversibleLift (liftF IS liftOct, overriding the generic default)"
      [ testProperty "unliftF . liftF = id (bijection)" $ forAll genOctLeaf8 lawLiftFRoundTrips
      , testProperty "fromVec . toVec = id" $ forAll genOctLeaf8 lawFromToVec
      , testProperty "detail count == 7" $ forAll genOctLeaf8 lawLiftDetailCount
      , testProperty "liftF IS liftOct" $ forAll genV8 lawOctLeafLiftIsLiftOct
      , testProperty "overrides the generic prefix-difference default"
          lawOctLeafOverridesDefault
      ]
  , testGroup "IndexDelta bridged to the transport group (induced action, not one instance)"
      [ testProperty "a slot transport's action is realized by the induced positional IndexDelta" $
          forAll genTransport $ \sigma -> forAll genIdx $ \idx ->
            lawIndexDeltaRealizesTransport sigma idx
      ]
  ]
