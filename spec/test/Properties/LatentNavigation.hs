module Properties.LatentNavigation (tests) where

import Test.Tasty
import Test.Tasty.QuickCheck

import SixFour.Spec.LatentNavigation

genGesture :: Gen Gesture
genGesture = Gesture <$> choose (-8, 8)
                     <*> ((,) <$> choose (-64, 64) <*> choose (-64, 64))

tests :: TestTree
tests = testGroup "LatentNavigation (single-16^3 steering; non-abelian; undo = history-replay, not SE<->NW)"
  [ testProperty "gesture group is non-abelian: a<>b /= b<>a" $
      once lawNonAbelian

  , testProperty "single gesture has an exact right inverse (g <> g^-1 = id)" $
      forAll genGesture lawStepHasInverse

  , testProperty "single gesture has an exact left inverse (g^-1 <> g = id)" $
      forAll genGesture lawStepHasInverseLeft

  , testProperty "SE != NW^-1: late-inverse does NOT undo an earlier gesture; history-replay does" $
      once lawUndoNeedsHistoryNotInverse

  , testProperty "history undo is well-defined: replay without the last gesture" $
      forAll (listOf genGesture) $ \p -> forAll genGesture $ \g ->
        lawHistoryUndoWellDefined p g

  , testProperty "A/B is the degenerate 1-step case (navigation subsumes the pair)" $
      forAll genGesture $ \a -> forAll genGesture $ \b ->
        lawNavigationSubsumesPair a b
  ]
