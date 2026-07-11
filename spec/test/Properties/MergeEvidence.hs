module Properties.MergeEvidence (tests) where

import Test.Tasty
import Test.Tasty.QuickCheck

import SixFour.Spec.MergeEvidence
import SixFour.Spec.CaptureRecord (TelemetrySnapshot (..))
import SixFour.Spec.MergeBoard
  ( Board (..), GameOp (..), MoveOp (..), playAll, pourCap, regionCount )

-- Ops include out-of-range regions on purpose: totality is part of the
-- surface. Pours are common so random walks exercise the deposits.
genOp :: Gen GameOp
genOp = frequency
  [ (3, pure GPour)
  , (7, GMove <$> choose (-2, regionCount + 1)
              <*> elements [OpS, OpK, OpI])
  ]

genOps :: Gen [GameOp]
genOps = resize 120 (listOf genOp)

-- Hostile schedules: negative entries, wrong lengths (short AND long) — the
-- effectiveDeposit clamps are under test, not spared.
genSchedule :: Gen EvidenceSchedule
genSchedule = oneof
  [ vectorOf pourCap (choose (-8, 12))
  , resize 40 (listOf (choose (-8, 12)))
  , pure derivedSchedule
  , fairSplit <$> choose (0, 64)
  ]

genTelemetry :: Gen (Maybe TelemetrySnapshot)
genTelemetry = oneof
  [ pure Nothing
  , Just <$> (TelemetrySnapshot
                <$> resize 5 (listOf (choose (-4, 128)))
                <*> resize 5 (listOf (choose (0, 100000)))
                <*> choose (0, 1500))
  ]

tests :: TestTree
tests = testGroup "MergeEvidence (pour credit from the burst's OWN telemetry: derived special case, fair split, schedule-replayed keystone, wire-composed)"
  [ -- The derived special case -----------------------------------------------
    testProperty "lawDerivedScheduleIsStep: under the constant schedule playAllWith == playAll on EVERY op list" $
      forAll genOps lawDerivedScheduleIsStep

  , testProperty "lawFullBudgetYieldsConstant: a full-window budget (or no snapshot) earns exactly today's constant 4s, by arithmetic not signature" $
      \as com -> lawFullBudgetYieldsConstant as com

  , testProperty "lawUnmeasuredCannotMasquerade: short arrivals earn ONLY their own budget, whatever the comovement byte claims" $
      \a b c com -> lawUnmeasuredCannotMasquerade a b c com

  , testProperty "lawHealthyLadderYieldsConstant: arrivals 64/32/16 -> budget 192 -> clamp 64 -> constant 4" $
      once lawHealthyLadderYieldsConstant

  , testProperty "lawWeavePlanBudgetIsFullWindow: the shipped 24/12/4 weave prices at exactly the window (24+24+16=64)" $
      once lawWeavePlanBudgetIsFullWindow

    -- The fair split ---------------------------------------------------------
  , testProperty "lawScheduleSplitConserves: fairSplit sums to the budget, every slot floor-or-ceiling of the even share" $
      \a -> lawScheduleSplitConserves a

  , testProperty "goldenFairSplit: the pinned splits for budgets 0, 3, 24, 40, 64" $
      once (   fairSplit 0  == replicate 16 0
            && fairSplit 3  == [0,0,0,0,0,1,0,0,0,0,1,0,0,0,0,1]
            && fairSplit 24 == [1,2,1,2,1,2,1,2,1,2,1,2,1,2,1,2]
            && fairSplit 40 == [2,3,2,3,2,3,2,3,2,3,2,3,2,3,2,3]
            && fairSplit 64 == replicate 16 4 )

  , testProperty "lawScheduleNeverExceedsWindow: scheduleOf is 16 non-negative slots summing to at most the window" $
      forAll genTelemetry lawScheduleNeverExceedsWindow

    -- The keystones ----------------------------------------------------------
  , testProperty "lawWordReplaysBoardUnderSchedule (GENERALIZED KEYSTONE): the word replays the board under ITS schedule" $
      forAll ((,) <$> genSchedule <*> genOps) (uncurry lawWordReplaysBoardUnderSchedule)

  , testProperty "lawRecordedWordReplaysWithTelemetry (WIRE KEYSTONE): seal tel+dw in ONE v3 record, decode, replay — same board" $
      \as ns como -> forAll genOps $ \ops ->
        lawRecordedWordReplaysWithTelemetry as ns como ops

    -- Conservation and honesty -----------------------------------------------
  , testProperty "lawSignalLedgerConservedUnderSchedule: signal == effective deposits - spends, never negative, pours capped" $
      forAll ((,) <$> genSchedule <*> genOps) (uncurry lawSignalLedgerConservedUnderSchedule)

  , testProperty "lawBankNeedsMeasurementUnderSchedule: all-coarse pours bank ZERO under ANY schedule (the gate is orthogonal)" $
      forAll ((,) <$> genSchedule <*> choose (0, 32)) (uncurry lawBankNeedsMeasurementUnderSchedule)

  , testProperty "lawUnlockMonotoneUnderSchedule: banked 32-evidence never decreases under any schedule" $
      forAll ((,) <$> genSchedule <*> genOps) (uncurry lawUnlockMonotoneUnderSchedule)

  , testProperty "lawShortEvidenceCannotConstruct: total evidence < 48 packets -> no op list fully constructs (refuse, never invent)" $
      forAll ((,) <$> genSchedule <*> genOps) (uncurry lawShortEvidenceCannotConstruct)

    -- The pinned evidence run ------------------------------------------------
  , testProperty "golden evidence trace: canonicalEvidenceRun under fairSplit 40 — every field pinned, refusal absent, replay exact" $
      once $
        let s = fairSplit 40
            b = playAllWith s canonicalEvidenceRun
        in bDepths b == ([0, 1, 1] ++ replicate 13 0)
           && bSignal b == 7
           && bSpent b == 3
           && bPours b == 4
           && bBank32 b == 10
           && bWord b == [ GPour, GMove 0 OpS, GPour, GMove 1 OpS, GPour
                         , GMove 0 OpK, GPour, GMove 2 OpS, GMove 3 OpI ]
           && playAllWith s (bWord b) == b
           && playAll canonicalEvidenceRun /= b   -- the constant game DIFFERS: evidence scaling is real
  ]
