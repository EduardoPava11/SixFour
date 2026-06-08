module Properties.CellMechanics (tests) where

import Test.Tasty
import Test.Tasty.QuickCheck

import SixFour.Spec.CellMechanics
import SixFour.Spec.MovableLayout (ColorIdentity, allIdentities, Placement, defaultPlacement, move)

-- | A random valid placement (same construction as Properties.MovableLayout): fold a few
-- arbitrary moves through 'move' from the default, so every state is reachable + valid.
genPlacement :: Gen Placement
genPlacement = do
  n     <- choose (0, 6 :: Int)
  steps <- vectorOf n ((,) <$> elements allIdentities <*> genDelta)
  pure (foldl (\p (i, d) -> move p i d) defaultPlacement steps)

genDelta :: Gen (Int, Int)
genDelta = (,) <$> choose (-120, 120) <*> choose (-260, 260)

genIdentity :: Gen ColorIdentity
genIdentity = elements allIdentities

genCell :: Gen (Int, Int)
genCell = (,) <$> choose (-200, 200) <*> choose (-200, 200)

-- | A random well-formed pulse (psMin ≤ psMax, period ≥ 2) for the pulse laws.
genPulse :: Gen PulseSpec
genPulse = do
  period <- choose (2, 80)
  lo     <- choose (0, q16One)
  hi     <- choose (lo, q16One)
  pure (PulseSpec period lo hi)

tests :: TestTree
tests = testGroup "CellMechanics (grid-cell interaction: lifetime, detent, haptics, reactive feedback)"
  [ -- The interaction lifetime FSM ------------------------------------------------
    testProperty "lawGestureTotal: gestureStep is total over every (phase, event)" $
      once lawGestureTotal

  , testProperty "lawGestureNoOrphan: every phase reachable from Resting" $
      once lawGestureNoOrphan

  , testProperty "lawDragRequiresHold: Lifted reachable ONLY through the hold gate" $
      once lawDragRequiresHold

  , testProperty "lawTapIsFastRelease: a fast release from Pressed is a tap, a drop is not" $
      once lawTapIsFastRelease

  , testProperty "lawSettleReturnsResting: commit → Settling → Resting (no dangling state)" $
      once lawSettleReturnsResting

    -- The detent (cell-crossing ticks) --------------------------------------------
  , testProperty "lawTickConservation: a unit drag fires exactly cellsCrossed ticks" $
      forAll genCell $ \a -> forAll genCell $ \b -> lawTickConservation a b

  , testProperty "lawTickSymmetric: cellsCrossed symmetric, zero on the diagonal" $
      forAll genCell $ \a -> forAll genCell $ \b -> lawTickSymmetric a b

    -- The green-frame law (verdict ≡ move) ----------------------------------------
  , testProperty "lawDropColorMatchesMove: the drop verdict equals what move will do (∀ p i d)" $
      forAll genPlacement $ \p ->
      forAll genIdentity  $ \i ->
      forAll genDelta     $ \d -> lawDropColorMatchesMove p i d

    -- explicit WITNESS: the legacy reject (Palette16 onto Field64) shows Reject.
  , testProperty "reject WITNESS: dropVerdict (Palette16 onto Field64) == Reject" $
      once (dropVerdict defaultPlacement (toEnum 1) (-24, -123) == Reject)

    -- Reactive color + pulse ------------------------------------------------------
  , testProperty "lawPulseBounded: every sample stays within [psMin, psMax]" $
      forAll genPulse $ \spec -> \tick -> lawPulseBounded spec tick

  , testProperty "lawPulsePeriodic: the pulse repeats every period (even periods)" $
      forAll genPulse $ \spec -> \tick -> lawPulsePeriodic spec tick

  , testProperty "lawReactiveFaster: reject ≤ accept period; farther drag never slows it" $
      forAll genIdentity $ \i -> \m1 m2 -> lawReactiveFaster (mechanicsFor i) m1 m2

    -- GOLDEN cross-language pins (re-derived by the Swift selfCheck) ---------------
  , testProperty "golden phase trace: scanl gestureStep over goldenGesture is the pinned trace" $
      once (goldenPhaseTrace == [Resting, Pressed, Lifted, Lifted, Lifted, Settling, Resting])

  , testProperty "golden haptics: the lift pops and the valid drop confirms" $
      once (goldenHaptics == [Nothing, Just LiftPop, Nothing, Nothing, Just DropAccept, Nothing])
  ]
