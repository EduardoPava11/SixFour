module Properties.TwoMoveOctave (tests) where

import Test.Tasty
import Test.Tasty.QuickCheck

import SixFour.Spec.RelationalResidual (P6(..))
import SixFour.Spec.TwoMoveOctave

genP6 :: Gen P6
genP6 = P6 <$> g <*> g <*> g <*> g <*> g <*> g
  where g = choose (-32768, 32768)

tests :: TestTree
tests = testGroup "TwoMoveOctave (global-then-local a,b two-move; one composed d6 signal; the mid funnel)"
  [ testProperty "KEYSTONE: a diagonal's two orderings differ at the mid funnel, same endpoint" $
      forAll genP6 lawDiagonalOrderingsDifferAtIntermediate
  , testProperty "GLOBAL is the coarser octave, LOCAL the finer" $
      once lawGlobalIsCoarserOctave
  , testProperty "VALUE distance is LINEAR (a unit step is d6 == 1 at every octave)" $
      forAll genP6 lawValueDistanceIsLinear
  , testProperty "SCALE distance is OCTAVE (log2), distinct from the value metric" $
      once lawScaleDistanceIsOctave
  , testProperty "the two-move set reaches exactly 8 magnitude-2 endpoints" $
      once lawTwoMoveEndpointsAreEight
  , testProperty "the SIGNAL is one composed d6 (start to final)" $
      forAll genP6 lawSignalIsComposedD6
  , testProperty "the mid funnel is one GLOBAL step from the start" $
      forAll genP6 lawMidFunnelIsOneGlobalStep
  ]
