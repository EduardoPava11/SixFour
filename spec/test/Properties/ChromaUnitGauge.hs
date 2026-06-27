module Properties.ChromaUnitGauge (tests) where

import Test.Tasty
import Test.Tasty.QuickCheck

import SixFour.Spec.ChromaUnitGauge

tests :: TestTree
tests = testGroup "ChromaUnitGauge (the ℤ[i] units ARE the model's quarter-turn chroma gauge)"
  [ testProperty "BRIDGE: rmul (q-th Gaussian unit) == rotateQuarter q on chroma"
      (\q ab -> lawGaussianUnitActsAsQuarterTurn q ab)
  , testProperty "ISO: ℤ[i]* multiply ↔ index add mod 4 ↔ quarter-turn composition"
      (\p q ab -> lawUnitGroupIsoQuarterTurn p q ab)
  , testProperty "CONSUMER: canonicalQuarter dedup IS the ℤ[i] unit-group orbit"
      (\pal -> lawCanonicalQuarterIsUnitOrbit pal)
  , testProperty "TEETH: a non-unit (1+i) scales the norm, so it is no quarter-turn"
      (\ab -> lawNonUnitIsNotAQuarterTurn ab)
  ]
