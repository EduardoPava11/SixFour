{- |
Module      : SixFour.Spec.MergeEvidence
Description : SIGNAL FROM THE READS — THE MERGE's pour economy, credited from the burst's OWN telemetry instead of a synthetic constant, without touching "SixFour.Spec.MergeBoard" or the wire. The GIF is a gross approximation; the three reads are the evidence — so a pour's deposit becomes a slot of an 'EvidenceSchedule': 16 integers (one per pour) derived DETERMINISTICALLY from the "SixFour.Spec.CaptureRecord" 'TelemetrySnapshot' already sealed beside the decision word. 'colorTimeBudget' prices the burst's arrivals in window units (arrivals × 'SixFour.Spec.WeaveOrder.unitsOf', clamped to the 64-unit window); 'fairSplit' spreads the budget over the 16 pours by exact integer fair division; 'scheduleOf' is the total rule — no snapshot yields 'derivedSchedule', otherwise the schedule is PRICED BY ARRIVALS ALONE (never the comovement byte: 1000 permille means both "derived" and "could not measure", so routing on it would let an interrupted unmeasured burst masquerade as fully-funded — 'lawUnmeasuredCannotMasquerade'). The honest full cases converge on today's constant by ARITHMETIC: a full derived snapshot (64\/32\/16 arrivals → 192, clamped) and the shipped weave plan (24\/12\/4 — @24·1+12·2+4·4 = 64@, 'lawWeavePlanBudgetIsFullWindow') both price to the window ('lawFullBudgetYieldsConstant', 'lawHealthyLadderYieldsConstant'), so TODAY'S GAME IS BYTE-FOR-BYTE THE DERIVED SPECIAL CASE ('lawDerivedScheduleIsStep' — MergeBoard and its goldens stand untouched). 'stepWith' is 'SixFour.Spec.MergeBoard.step' with exactly one change: a pour deposits its schedule slot (clamped at 0; out-of-range slots deposit 0; zero-deposit pours are ACCEPTED honest duds). The GENERALIZED KEYSTONE 'lawWordReplaysBoardUnderSchedule' keeps replay a pure function of @(schedule, word)@, and the WIRE KEYSTONE 'lawRecordedWordReplaysWithTelemetry' composes it end-to-end through the existing v3 record — @tel@ and @dw@ live in ONE record, so replay needs NO wire version bump and every pinned golden byte stands. Honesty is a law, not a hope: short evidence cannot construct ('lawShortEvidenceCannotConstruct' — the game refuses, it never invents), the measurement gate is orthogonal to evidence scaling ('lawBankNeedsMeasurementUnderSchedule'), and the unlock stays monotone ('lawUnlockMonotoneUnderSchedule'). GHC-boot-only.
-}
-- COMPARTMENT: PURE-SPEC-WALL | tag:none
module SixFour.Spec.MergeEvidence
  ( -- * The evidence schedule
    EvidenceSchedule
  , derivedSchedule
  , effectiveDeposit
    -- * Pricing the snapshot in window units
  , colorTimeBudget
  , fairSplit
  , scheduleOf
    -- * The evidence-credited step
  , stepWith
  , playAllWith
    -- * The pinned evidence run
  , canonicalEvidenceRun
    -- * Laws
  , lawDerivedScheduleIsStep
  , lawScheduleSplitConserves
  , lawFullBudgetYieldsConstant
  , lawUnmeasuredCannotMasquerade
  , lawHealthyLadderYieldsConstant
  , lawWeavePlanBudgetIsFullWindow
  , lawWordReplaysBoardUnderSchedule
  , lawSignalLedgerConservedUnderSchedule
  , lawBankNeedsMeasurementUnderSchedule
  , lawUnlockMonotoneUnderSchedule
  , lawScheduleNeverExceedsWindow
  , lawShortEvidenceCannotConstruct
  , lawRecordedWordReplaysWithTelemetry
  ) where

import SixFour.Spec.CaptureRecord
  ( CaptureRecord (..), TelemetrySnapshot (..), decisionWordFromCbor, decode
  , encodeRecord, goldenRecordV3, telemetryFromCbor )
import SixFour.Spec.MergeBoard
  ( Board (..), GameOp (..), MoveOp (..), Reject (..), Verdict (..)
  , countAtLeast, fullyConstructed, initBoard, playAll, pourCap, pourDeposit
  , step )
import SixFour.Spec.WeaveOrder (WeaveRung (..), unitsOf, windowUnits)

-- ─────────────────────────────────────────────────────────────────────────────
-- The evidence schedule
-- ─────────────────────────────────────────────────────────────────────────────

-- | One deposit per pour, in window units — pinned length 'pourCap' (16).
-- The replay parameter: a board built under a schedule replays under the SAME
-- schedule ('lawWordReplaysBoardUnderSchedule'), and the schedule is a pure
-- function of the telemetry sealed in the same record ('scheduleOf').
type EvidenceSchedule = [Integer]

-- | The derived-mode schedule: 'pourDeposit' (4) in every slot — sums to
-- exactly 'windowUnits' (64). Under this schedule 'stepWith' IS
-- 'SixFour.Spec.MergeBoard.step' ('lawDerivedScheduleIsStep'): today's game,
-- byte for byte.
derivedSchedule :: EvidenceSchedule
derivedSchedule = replicate pourCap (toInteger pourDeposit)

-- | The deposit pour @i@ actually makes under a schedule: the slot clamped at
-- 0, and 0 for any out-of-range slot — total over EVERY schedule a hostile
-- generator can produce, so the keystone quantifies over all of them.
effectiveDeposit :: EvidenceSchedule -> Int -> Integer
effectiveDeposit s i
  | i < 0 || i >= length s = 0
  | otherwise              = max 0 (s !! i)

-- ─────────────────────────────────────────────────────────────────────────────
-- Pricing the snapshot
-- ─────────────────────────────────────────────────────────────────────────────

-- | The burst's evidence budget in window units: per rung (fine→coarse, the
-- 'TelemetrySnapshot' arrival order), arrivals × 'unitsOf' (1\/2\/4 — each
-- arrival of a rung-k frame spans @2^k@ units), summed and clamped to
-- 'windowUnits' — a burst can never be worth more than its own window.
-- Healthy 64\/32\/16 prices at 192 → clamps to 64; the shipped weave plan's
-- 24\/12\/4 prices at exactly 64 ('lawWeavePlanBudgetIsFullWindow' — the
-- one-sensor cadence mismatch absorbed lawfully). Negative arrivals clamp to
-- 0; missing entries read 0.
colorTimeBudget :: TelemetrySnapshot -> Integer
colorTimeBudget ts =
  min (toInteger windowUnits)
      (sum [ max 0 a * toInteger (unitsOf r)
           | (a, r) <- zip (tsArrivals ts) [W64, W32, W16] ])

-- | Exact integer fair division of a budget @a@ over the 16 pours:
-- @e_i = ⌊(i+1)·a\/16⌋ − ⌊i·a\/16⌋@ — sums to exactly @a@ (telescoping),
-- every slot is @⌊a\/16⌋@ or @⌈a\/16⌉@ ('lawScheduleSplitConserves'), no
-- floats, no remainder bias. Negative budgets clamp to 0.
fairSplit :: Integer -> EvidenceSchedule
fairSplit aRaw =
  [ (toInteger (i + 1) * a) `div` cap - (toInteger i * a) `div` cap
  | i <- [0 .. pourCap - 1] ]
  where
    a   = max 0 aRaw
    cap = toInteger pourCap

-- | THE TOTAL RULE — schedule from the (optional) sealed snapshot:
-- no snapshot → 'derivedSchedule' (v1\/v2-without-tel records replay today's
-- game); otherwise 'fairSplit' of the 'colorTimeBudget' — pricing by
-- ARRIVALS ALONE, never by the comovement byte. The comovement sentinel
-- (1000 permille) means BOTH "fell back to derived" and "could not measure"
-- ("SixFour.Spec.RungTelemetry" — no evidence of independence is not
-- evidence of independence), so routing on it would let a short interrupted
-- burst whose windows all REFUSED masquerade as fully-funded
-- ('lawUnmeasuredCannotMasquerade' pins the refusal). Pricing needs no
-- signature: a full derived snapshot's arrivals (64\/32\/16) price to 192,
-- clamp to the window, and earn exactly the constant
-- ('lawFullBudgetYieldsConstant') — the honest cases converge by arithmetic,
-- not by branch. A pure function of the snapshot — no floats, no clock, no
-- hidden state, no feature flag ('lawRecordedWordReplaysWithTelemetry' rides
-- on exactly this purity: the LIVE game and every future replay reader call
-- this same rule on the same sealed bytes).
scheduleOf :: Maybe TelemetrySnapshot -> EvidenceSchedule
scheduleOf Nothing   = derivedSchedule
scheduleOf (Just ts) = fairSplit (colorTimeBudget ts)

-- ─────────────────────────────────────────────────────────────────────────────
-- The evidence-credited step
-- ─────────────────────────────────────────────────────────────────────────────

-- | 'SixFour.Spec.MergeBoard.step' parameterized by an 'EvidenceSchedule' —
-- IDENTICAL except that an accepted pour deposits 'effectiveDeposit' at the
-- board's pour index (instead of the constant 'pourDeposit'): signal grows by
-- it, the bank credits it per measuring region against the PRE-pour depths,
-- and a zero-deposit pour is an ACCEPTED honest dud (the burst had nothing
-- for that slice; the word records the attempt). Moves delegate to 'step'
-- unchanged — evidence scaling touches deposits only.
stepWith :: EvidenceSchedule -> GameOp -> Board -> (Board, Verdict)
stepWith s op b = case op of
  GPour
    | bPours b >= pourCap -> (b, Rejected PoursExhausted)
    | otherwise ->
        let e  = fromInteger (effectiveDeposit s (bPours b))
            b' = b { bSignal = bSignal b + e
                   , bPours  = bPours b + 1
                   , bBank32 = bBank32 b + e * countAtLeast 1 b
                   }
        in (b' { bWord = bWord b' ++ [GPour] }, Accept)
  GMove {} -> step op b

-- | Fold a whole op list from 'SixFour.Spec.MergeBoard.initBoard' under a
-- schedule (refusals are no-ops by 'stepWith').
playAllWith :: EvidenceSchedule -> [GameOp] -> Board
playAllWith s = foldl (\b op -> fst (stepWith s op b)) initBoard

-- ─────────────────────────────────────────────────────────────────────────────
-- The pinned evidence run
-- ─────────────────────────────────────────────────────────────────────────────

-- | The pinned evidence-mode trace, played under @'fairSplit' 40@ (the
-- alternating 2\/3 schedule): four pours, three splits, one K, one PhaseLocked
-- REFUSAL (the ninth op — absent from the word), one hold. Final board pinned
-- in the property battery (signal 7, spent 3, pours 4, bank32 10, a 9-op
-- word) — the non-constant replay golden the Swift twin mirrors.
canonicalEvidenceRun :: [GameOp]
canonicalEvidenceRun =
  [ GPour
  , GMove 0 OpS
  , GPour
  , GMove 1 OpS
  , GPour
  , GMove 0 OpK
  , GPour
  , GMove 2 OpS
  , GMove 1 OpS   -- refused: PhaseLocked (bank32 10 < 64) — not recorded
  , GMove 3 OpI
  ]

-- ─────────────────────────────────────────────────────────────────────────────
-- Laws
-- ─────────────────────────────────────────────────────────────────────────────

-- | TODAY'S GAME IS THE DERIVED SPECIAL CASE: under 'derivedSchedule',
-- 'playAllWith' equals 'playAll' on EVERY op list — every field, refusals
-- included. "SixFour.Spec.MergeBoard" and its goldens stand byte-for-byte
-- untouched; evidence crediting is purely additive.
lawDerivedScheduleIsStep :: [GameOp] -> Bool
lawDerivedScheduleIsStep ops =
  playAllWith derivedSchedule ops == playAll ops

-- | The fair split CONSERVES: length 'pourCap', sums to exactly the (clamped)
-- budget, and every slot is the floor or the ceiling of the even share — no
-- unit invented, none lost, none hoarded in one pour.
lawScheduleSplitConserves :: Integer -> Bool
lawScheduleSplitConserves aRaw =
  let a  = max 0 aRaw
      es = fairSplit aRaw
      q  = a `div` toInteger pourCap
  in length es == pourCap
     && sum es == a
     && all (\e -> e == q || e == q + 1) es

-- | A FULL BUDGET yields the constant: any snapshot whose arrivals price to
-- at least the window (a full derived burst's 64\/32\/16 → 192, the healthy
-- ladder's 24\/12\/4 → 64) earns exactly 'derivedSchedule'; so does an
-- absent snapshot; and the constant sums to the whole window. The honest
-- full cases converge on today's game by ARITHMETIC (clamp + fair split),
-- never by a signature branch.
lawFullBudgetYieldsConstant :: [Integer] -> Integer -> Bool
lawFullBudgetYieldsConstant as com =
  let full = TelemetrySnapshot (zipWith max [64, 32, 16] padded) [1, 8, 64]
                               (abs com `mod` 2000)
      padded = take 3 (map (max 0) as ++ [0, 0, 0])
  in scheduleOf (Just full) == derivedSchedule
     && scheduleOf Nothing == derivedSchedule
     && sum derivedSchedule == toInteger windowUnits

-- | THE ANTI-CONFLATION THEOREM: a snapshot whose arrivals price BELOW the
-- window earns exactly its own budget — REGARDLESS of the comovement byte.
-- The 1000-permille sentinel means both "derived" and "could not measure"
-- (short windows REFUSE), so an interrupted ladder burst that failed to
-- measure independence must not masquerade as fully-funded: pours may only
-- credit color-time the burst actually delivered
-- ('lawShortEvidenceCannotConstruct' is this law's downstream teeth).
lawUnmeasuredCannotMasquerade :: Integer -> Integer -> Integer -> Integer -> Bool
lawUnmeasuredCannotMasquerade a64 a32 a16 com =
  let as = [abs a64 `mod` 16, abs a32 `mod` 8, abs a16 `mod` 3]
      ts = TelemetrySnapshot as [1, 8, 64] (abs com `mod` 2000)
      budget = colorTimeBudget ts
  in budget < toInteger windowUnits
     && scheduleOf (Just ts) == fairSplit budget
     && sum (scheduleOf (Just ts)) == budget

-- | A HEALTHY FULL LADDER yields the constant too: arrivals 64\/32\/16 price
-- at @64·1 + 32·2 + 16·4 = 192@, clamp to the window, and fair-split to
-- 'pourDeposit' in every slot — the compatibility guarantee: a perfect
-- independent burst plays exactly today's game.
lawHealthyLadderYieldsConstant :: Bool
lawHealthyLadderYieldsConstant =
  let ts = TelemetrySnapshot [64, 32, 16] [1, 8, 64] 250
  in sum (zipWith (*) [64, 32, 16] [1, 2, 4]) == (192 :: Integer)
     && colorTimeBudget ts == toInteger windowUnits
     && scheduleOf (Just ts) == derivedSchedule

-- | THE WEAVE PLAN'S BUDGET IS THE FULL WINDOW: the shipped one-sensor weave
-- owns 24\/12\/4 frames (not the spec's 64\/32\/16 cadence pins), and
-- @24·1 + 12·2 + 4·4 = 64@ — the cadence mismatch is absorbed LAWFULLY: a
-- full ladder burst funds the full window and plays today's constants.
lawWeavePlanBudgetIsFullWindow :: Bool
lawWeavePlanBudgetIsFullWindow =
  let ts = TelemetrySnapshot [24, 12, 4] [1, 8, 64] 250
  in colorTimeBudget ts == toInteger windowUnits
     && scheduleOf (Just ts) == derivedSchedule

-- | GENERALIZED KEYSTONE — the word replays the board UNDER ITS SCHEDULE: for
-- ANY schedule and any op list, replaying the built board's own word under
-- the SAME schedule reproduces the board exactly, every field. Replay is a
-- pure function of @(schedule, word)@ — evidence enters as a recorded
-- parameter, never as hidden state.
lawWordReplaysBoardUnderSchedule :: EvidenceSchedule -> [GameOp] -> Bool
lawWordReplaysBoardUnderSchedule s ops =
  let b = playAllWith s ops
  in playAllWith s (bWord b) == b

-- | The signal ledger stays exact under any schedule: signal = the effective
-- deposits actually made minus the spends, never negative, pours capped —
-- the MergeBoard conservation law with the constant generalized.
lawSignalLedgerConservedUnderSchedule :: EvidenceSchedule -> [GameOp] -> Bool
lawSignalLedgerConservedUnderSchedule s ops =
  let b = playAllWith s ops
  in toInteger (bSignal b)
       == sum [ effectiveDeposit s i | i <- [0 .. bPours b - 1] ]
            - toInteger (bSpent b)
     && bSignal b >= 0
     && bPours b <= pourCap

-- | The measurement gate is ORTHOGONAL to evidence scaling: under ANY
-- schedule, pours on the all-coarse board bank ZERO — evidence money cannot
-- buy the 32-gate without measuring at 32 first, exactly as today.
lawBankNeedsMeasurementUnderSchedule :: EvidenceSchedule -> Int -> Bool
lawBankNeedsMeasurementUnderSchedule s n =
  bBank32 (playAllWith s (replicate (max 0 n) GPour)) == 0

-- | The unlock stays MONOTONE under any schedule: banked 32-evidence never
-- decreases along any op list (deposits are clamped non-negative; K still
-- withdraws the claim, never the measurement).
lawUnlockMonotoneUnderSchedule :: EvidenceSchedule -> [GameOp] -> Bool
lawUnlockMonotoneUnderSchedule s ops = go initBoard ops
  where
    go _ [] = True
    go b (op : rest) =
      let b' = fst (stepWith s op b)
      in bBank32 b' >= bBank32 b && go b' rest

-- | No schedule the total rule produces exceeds the window: length 'pourCap',
-- non-negative slots, sum ≤ 'windowUnits' — a burst funds at most its own
-- 320 cs of game, whatever the telemetry claims.
lawScheduleNeverExceedsWindow :: Maybe TelemetrySnapshot -> Bool
lawScheduleNeverExceedsWindow mts =
  let es = scheduleOf mts
  in length es == pourCap
     && all (>= 0) es
     && sum es <= toInteger windowUnits

-- | SHORT EVIDENCE CANNOT CONSTRUCT: if a schedule's total effective deposits
-- fall below the 48-packet victory floor
-- ('SixFour.Spec.MergeBoard.lawWinCostsTheLadder'), NO op list fully
-- constructs the board — phase 2 may be honestly unreachable. The game
-- refuses; it never invents evidence.
lawShortEvidenceCannotConstruct :: EvidenceSchedule -> [GameOp] -> Bool
lawShortEvidenceCannotConstruct s ops =
  sum [ effectiveDeposit s i | i <- [0 .. pourCap - 1] ] >= 48
    || not (fullyConstructed (playAllWith s ops))

-- | WIRE KEYSTONE — the recorded word replays WITH its telemetry, end to end,
-- on the EXISTING v3 wire: build a board under the snapshot's schedule, seal
-- snapshot AND word in ONE record (the 'goldenRecordV3' shape — no version
-- bump, no new key), encode, decode, re-derive the schedule from the decoded
-- snapshot, replay the decoded word — the SAME board, every field. The reader
-- needs nothing outside the record; v1\/v2\/v3 golden bytes stand unchanged.
-- (Fields are normalized non-negative: the wire's carrier is unsigned.)
lawRecordedWordReplaysWithTelemetry :: [Integer] -> [Integer] -> Integer -> [GameOp] -> Bool
lawRecordedWordReplaysWithTelemetry asRaw nsRaw comoRaw ops =
  let ts    = TelemetrySnapshot (map (max 0) asRaw) (map (max 0) nsRaw)
                                (max 0 comoRaw)
      s     = scheduleOf (Just ts)
      b     = playAllWith s ops
      bytes = encodeRecord goldenRecordV3
                { crTelemetry = Just ts, crDecisionWord = bWord b }
  in case decode bytes of
       Just (v, []) ->
         case (telemetryFromCbor v, decisionWordFromCbor v) of
           (Just tel', Just dw') -> playAllWith (scheduleOf tel') dw' == b
           _                     -> False
       _ -> False
