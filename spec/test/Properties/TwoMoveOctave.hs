module Properties.TwoMoveOctave (tests) where

import Test.Tasty
import Test.Tasty.QuickCheck

import SixFour.Spec.Dim6 (Dim6(..))
import SixFour.Spec.RelationalResidual (P6(..))
import SixFour.Spec.SubstrateDomain (substrateBound)
import SixFour.Spec.TwoMoveOctave

genP6 :: Gen P6
genP6 = P6 <$> g <*> g <*> g <*> g <*> g <*> g
  where g = choose (-32768, 32768)

-- a P6 AT/near the substrate edge, so the domain law is non-vacuous
genP6Edge :: Gen P6
genP6Edge = P6 <$> e <*> e <*> e <*> e <*> e <*> e
  where e = elements [b, b - 1, b - 2, -b, -b + 1, -1, 0, 1]
        b = substrateBound

genAxis :: Gen Dim6
genAxis = elements [DimL, DimA, DimB, DimX, DimY, DimT]

genDelta :: Gen Int
genDelta = elements [-2, -1, 1, 2]

genOctave :: Gen Octave
genOctave = elements [CoarseGlobal, FineLocal]

tests :: TestTree
tests = testGroup "TwoMoveOctave (global-then-local a,b two-move; move algebra + invariants)"
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
  , testProperty "the move COST is one composed d6 (start to final)" $
      forAll genP6 lawMoveCostIsTwo
  , testProperty "HONESTY: moveMagnitude is a CONSTANT 2 (not a content signal)" $
      forAll genP6 lawMoveMagnitudeIsConstant
  , testProperty "the mid funnel is one GLOBAL step from the start" $
      forAll genP6 lawMidFunnelIsOneGlobalStep
  , testProperty "GEODESIC: legs add, no cancellation (mid funnel on the shortest path)" $
      forAll genP6 lawTwoMoveIsGeodesic
  , testProperty "SOUNDNESS: every path is magnitude 2" $
      forAll genP6 lawEveryPathIsMagnitudeTwo
  , testProperty "REVERSIBLE: inverseMove restores the start (undo-by-history)" $
      forAll genAxis $ \ax -> forAll genDelta $ \d -> forAll genOctave $ \o -> forAll genP6 $ \p ->
        lawMoveIsReversible ax d o p
  , testProperty "single moves COMMUTE (the abelian backbone of same-endpoint)" $
      forAll genAxis $ \a1 -> forAll genDelta $ \d1 -> forAll genAxis $ \a2 -> forAll genDelta $ \d2 ->
        forAll genP6 $ \p -> lawMovesCommute a1 d1 a2 d2 p
  , testProperty "DOMAIN: a two-move near the edge refuses past +-B (matches the Zig kernel)" $
      forAll genP6Edge lawTwoMoveRespectsDomain
  ]
