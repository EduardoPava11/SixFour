module Properties.GestureAxis (tests) where

import Test.Tasty
import Test.Tasty.QuickCheck

import SixFour.Spec.RelationalResidual (P6(..))
import SixFour.Spec.DetentNudge        (AdmissibleStep, Sign(..), ABAxis(..), mkAdmissibleStep)
import SixFour.Spec.ChromaRotation     (Detent(..))
import SixFour.Spec.GestureAxis

-- An admissible swipe (retry off-grid combinations, e.g. C6 at 90°/270°).
genStep :: Gen AdmissibleStep
genStep = do
  d  <- elements [C12, C8, C6]
  q  <- choose (0, 3)
  s  <- elements [Minus, Plus]
  ax <- elements [AxisA, AxisB]
  case mkAdmissibleStep d q s ax of
    Just st -> pure st
    Nothing -> genStep

-- A perceptual point well inside the substrate domain (|v| <= 2^29-1).
genP6 :: Gen P6
genP6 = P6 <$> c <*> c <*> c <*> c <*> c <*> c
  where c = choose (-100000, 100000)

tests :: TestTree
tests = testGroup "GestureAxis (swipe -> Dim6 search axis -> domain-guarded commit)"
  [ testProperty "a committed gesture is always in-domain (routes through safeNudge)" $
      forAll genStep $ \st -> forAll genP6 $ \p -> lawGestureRoutesThroughGuard st p
  , testProperty "TEETH: a +1 swipe at the +a domain edge refuses" $
      once lawGestureRefusesAtEdge
  , testProperty "a swipe moves only the {a,b} search axes (carrier {L,t} fixed)" $
      forAll genStep $ \st -> forAll genP6 $ \p -> lawGestureTargetsSearchAxes st p
  , testProperty "colour search axes have position twins via phi6 (a<->x, b<->y)" $
      once lawGestureColourHasPositionTwin
  , testProperty "a swipe then its flip returns to start (in-domain reversibility)" $
      forAll genStep $ \st -> forAll genP6 $ \p -> lawGestureReversibleInDomain st p
  ]
