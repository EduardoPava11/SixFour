module Properties.PaletteGesture (tests) where

import Test.Tasty
import Test.Tasty.QuickCheck
import Test.QuickCheck

import           Data.List (nub)

import SixFour.Spec.PaletteGesture

genG :: Gen PaletteGesture
genG = elements allGestures

genDrag :: Gen DragVec
genDrag = (,) <$> choose (-65536, 65536) <*> choose (-65536, 65536)

tests :: TestTree
tests = testGroup "PaletteGesture (the gesture partition — ≤1 gesture per event, by construction)"
  [ -- ---------------- The partition is injective (headline) ----------------
    testProperty "partition is INJECTIVE: distinct gestures ⇒ distinct keys" $
      forAll genG $ \g1 -> forAll genG $ \g2 -> lawPartitionInjective g1 g2

  , testProperty "EXHAUSTIVE: no two of the 10 gestures share a key (all keys distinct)" $
      once $
        let keys = map gestureKey allGestures
        in counterexample ("keys: " ++ show keys)
             (length (nub keys) == length keys)

  , testProperty "every gesture's key selects AT MOST ONE gesture" $
      forAll genG $ \g -> lawAtMostOneGesturePerKey (gestureKey g)

  , testProperty "totality: every gesture has a key" $
      forAll genG lawEveryGestureHasAKey

    -- ---------------- The drag → OKLab δ decode is lossless ----------------
  , testProperty "2-D drag → OKLab δ round-trips EXACTLY (no DOF lost)" $
      forAll genDrag lawDragDecodeRoundTrip

  , testProperty "δ → drag → δ also round-trips (inverse both ways)" $
      forAll genDrag $ \d ->
        let delta = dragToDelta d
        in dragToDelta (deltaToDrag delta) == delta

    -- ---------------- Generator-space ops are not the additive slot ----------------
  , testProperty "generator-space ops (chroma/hue/opponent) are flagged, and are not select/scrub" $
      forAll genG lawGeneratorSpaceOpsAreNotAdditiveDelta

  , testProperty "exactly the chroma/hue/opponent ops are generator-space" $
      once $
        filter isGeneratorSpaceOp allGestures == [ChromaPush, OpponentBias, SplitToneHue]

    -- ---------------- Region sanity: same key only via different region ----------------
  , testProperty "scrub and coverage share a (Drag1,Horizontal,Instant) shape but differ by region" $
      once $
        let GestureKey r1 rec1 ax1 l1 = gestureKey ScrubBurst
            GestureKey r2 rec2 ax2 l2 = gestureKey CoverageFidelity
        in rec1 == rec2 && ax1 == ax2 && l1 == l2 && r1 /= r2
  ]
