//  MergeEvidence.swift
//  SIGNAL FROM THE READS — the hand-written Swift twin of `Spec.MergeEvidence`.
//
//  The GIF is a gross approximation; the three reads are the evidence. So a
//  pour's deposit becomes a slot of an EVIDENCE SCHEDULE: 16 integers (one per
//  pour) derived DETERMINISTICALLY from the `S4TelemetrySnapshot` already
//  sealed beside the decision word in the same `.s4cr` record — replay stays a
//  pure function of `(schedule, word)` and the wire needs NO version bump
//  (`Spec.MergeEvidence.lawRecordedWordReplaysWithTelemetry`).
//
//  THE TOTAL RULE (`scheduleOf`): no snapshot → the derived constant;
//  otherwise the exact integer fair split of the burst's color-time budget —
//  priced by ARRIVALS ALONE, never the comovement byte (the 1000‰ sentinel
//  means both "derived" and "could not measure", so routing on it would let
//  an interrupted unmeasured burst masquerade as fully-funded:
//  `lawUnmeasuredCannotMasquerade`). Full bursts price past the window and
//  clamp to the constant by arithmetic (`lawFullBudgetYieldsConstant`).
//  THE COMPATIBILITY GUARANTEES (all pinned in the spec + mirrored in
//  `MergeEvidenceTests`):
//  • full-window budgets ⇒ today's constant 4s (`lawFullBudgetYieldsConstant`),
//  • a healthy full ladder (64/32/16 arrivals: 64·1+32·2+16·4 = 192 → clamp 64)
//    ⇒ the constant too (`lawHealthyLadderYieldsConstant`),
//  • the shipped weave plan (24/12/4: 24·1+12·2+4·4 = 64 = the FULL window)
//    ⇒ the constant — the one-sensor cadence mismatch absorbed lawfully
//    (`lawWeavePlanBudgetIsFullWindow`).
//  Honesty is a law, not a hope: short evidence cannot construct
//  (`lawShortEvidenceCannotConstruct` — the game refuses, never invents), the
//  measurement gate is orthogonal to evidence scaling
//  (`lawBankNeedsMeasurementUnderSchedule`), and the unlock stays monotone.
//
//  The step itself lives on `S4MergeBoard` (`step(_:schedule:)` — the state's
//  file owns the setters); this file owns the schedule DERIVATION. Pure
//  integer value math, zero dependencies (not even Foundation).

/// Schedule derivation — the twin of `Spec.MergeEvidence`'s pricing half.
enum S4MergeEvidence {

    /// The derived-mode schedule (re-exported from the board so both spellings
    /// name ONE array): `pourDeposit` (4) in every slot, sums to exactly
    /// `windowUnits` (64). Under it the game is byte-for-byte today's
    /// (`lawDerivedScheduleIsStep`).
    static var derivedSchedule: [Int] { S4MergeBoard.derivedSchedule }

    /// The 320 cs window in weave units (`Spec.WeaveOrder.windowUnits`) —
    /// DERIVED from the economy identity it prices
    /// (`Spec.MergeBoard.lawEconomyIsTheWindow`: window = threshold32 =
    /// `pourCap × pourDeposit`), never a free 64: if the economy ever moves,
    /// the budget ceiling moves with it by compile-time link.
    static let windowUnits = S4MergeBoard.pourCap * S4MergeBoard.pourDeposit

    /// Weave units one arrival of each rung spans, fine → coarse (the
    /// `S4TelemetrySnapshot.arrivals` order): `Spec.WeaveOrder.unitsOf` —
    /// DELEGATED to the one Swift owner of the pool-depth ladder
    /// (`ColorTimeDisplayMath.displayPeriodTicks` = 1/2/4), the same integers
    /// the display cadence and the slide's detents read.
    static let unitsPerRung = ColorTimeDisplayMath.displayPeriodTicks

    /// The burst's evidence budget in window units — the twin of
    /// `Spec.MergeEvidence.colorTimeBudget`: per rung, arrivals × `unitsOf`,
    /// summed and clamped to the window (a burst can never be worth more than
    /// its own 320 cs). Arrivals are wire-unsigned; each is pre-capped at
    /// `windowUnits` before the multiply — EXACT under the outer clamp
    /// (any arrival ≥ 64 already prices ≥ the whole window) and overflow-free
    /// for any `UInt64` the wire can carry. Missing entries read 0.
    static func colorTimeBudget(arrivals: [UInt64]) -> Int {
        var total = 0
        for (a, u) in zip(arrivals, unitsPerRung) {
            total += Int(min(a, UInt64(windowUnits))) * u
        }
        return min(windowUnits, total)
    }

    /// Exact integer fair division of a budget over the 16 pours — the twin of
    /// `Spec.MergeEvidence.fairSplit`: `e_i = ⌊(i+1)·a/16⌋ − ⌊i·a/16⌋`, which
    /// telescopes to exactly `a` and puts every slot at the floor or ceiling
    /// of the even share (`lawScheduleSplitConserves`). No floats, no
    /// remainder bias. Negative budgets clamp to 0; Int64 internals keep the
    /// multiply exact for any budget a caller can reach.
    static func fairSplit(_ budget: Int) -> [Int] {
        let a = Int64(max(0, min(budget, Int(Int32.max))))
        let cap = Int64(S4MergeBoard.pourCap)
        return (0 ..< S4MergeBoard.pourCap).map { i in
            Int((Int64(i + 1) * a) / cap - (Int64(i) * a) / cap)
        }
    }

    /// THE TOTAL RULE — the twin of `Spec.MergeEvidence.scheduleOf`: schedule
    /// from the (optional) sealed snapshot. No snapshot → `derivedSchedule`
    /// (v1 / v2-without-tel records replay today's game); otherwise
    /// `fairSplit` of the `colorTimeBudget` — priced by ARRIVALS ALONE,
    /// never the comovement byte (1000 permille means both "derived" and
    /// "could not measure", so routing on it would let an interrupted
    /// unmeasured burst masquerade as fully-funded —
    /// `lawUnmeasuredCannotMasquerade`). A full derived snapshot's arrivals
    /// price past the window and clamp to today's constant by arithmetic
    /// (`lawFullBudgetYieldsConstant`). A pure function of the snapshot — no
    /// floats, no clock, no hidden state, NO FEATURE FLAG: the live game and
    /// every future replay reader call this same rule on the same sealed
    /// bytes (`lawRecordedWordReplaysWithTelemetry`).
    static func schedule(from telemetry: S4TelemetrySnapshot?) -> [Int] {
        guard let telemetry else { return derivedSchedule }
        return fairSplit(colorTimeBudget(arrivals: telemetry.arrivals))
    }
}
