import Testing
@testable import SixFour

/// Golden gate for `S4MergeEvidence` + `S4MergeBoard.step(_:schedule:)` — the
/// Swift twins of `Spec.MergeEvidence` (SIGNAL FROM THE READS). Every pinned
/// vector is mirrored VERBATIM from the Haskell battery
/// (`spec/test/Properties/MergeEvidence.hs`): the fairSplit pins for budgets
/// {0, 3, 24, 40, 64}, the derived/healthy/weave-plan constancy guarantees,
/// the non-constant fairSplit-40 evidence trace with every final board field,
/// the generalized replay keystone, and the constant-game divergence foil.
/// The ladder is device-only (the Simulator has no camera), so this
/// synthetic-telemetry battery IS the exercisable path.
struct MergeEvidenceTests {

    // MARK: - The fair split (lawScheduleSplitConserves + the pins)

    /// `goldenFairSplit`: the Haskell-pinned splits for budgets 0/3/24/40/64,
    /// plus conservation over the whole reachable sweep — length 16, sums to
    /// the budget exactly, every slot the floor or ceiling of the even share.
    @Test func goldenFairSplit() {
        #expect(S4MergeEvidence.fairSplit(0) == [Int](repeating: 0, count: 16))
        #expect(S4MergeEvidence.fairSplit(3) == [0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1])
        #expect(S4MergeEvidence.fairSplit(24) == [1, 2, 1, 2, 1, 2, 1, 2, 1, 2, 1, 2, 1, 2, 1, 2])
        #expect(S4MergeEvidence.fairSplit(40) == [2, 3, 2, 3, 2, 3, 2, 3, 2, 3, 2, 3, 2, 3, 2, 3])
        #expect(S4MergeEvidence.fairSplit(64) == [Int](repeating: 4, count: 16))
        #expect(S4MergeEvidence.fairSplit(-7) == [Int](repeating: 0, count: 16))  // clamp
        for a in 0...64 {
            let es = S4MergeEvidence.fairSplit(a)
            #expect(es.count == S4MergeBoard.pourCap)
            #expect(es.reduce(0, +) == a)
            let q = a / 16
            #expect(es.allSatisfy { $0 == q || $0 == q + 1 })
        }
    }

    // MARK: - The constancy guarantees (today's game is the derived case)

    /// `lawFullBudgetYieldsConstant`: a full-window budget earns exactly
    /// today's constant 4s BY ARITHMETIC (arrivals price past the window and
    /// clamp) — never by a comovement-signature branch; so does an absent
    /// snapshot; and the constant sums to the whole window.
    @Test func fullBudgetYieldsConstant() {
        let derived = S4TelemetrySnapshot(arrivals: [60, 30, 15],
                                          sampleVolumes: [1, 8, 64],
                                          comovementPermille: 1000)
        #expect(S4MergeEvidence.schedule(from: derived) == S4MergeBoard.derivedSchedule)
        let hotter = S4TelemetrySnapshot(arrivals: [64, 32, 16],
                                         sampleVolumes: [1, 8, 64],
                                         comovementPermille: 1400)
        #expect(S4MergeEvidence.schedule(from: hotter) == S4MergeBoard.derivedSchedule)
        #expect(S4MergeEvidence.schedule(from: nil) == S4MergeBoard.derivedSchedule)
        #expect(S4MergeBoard.derivedSchedule.reduce(0, +) == S4MergeEvidence.windowUnits)
    }

    /// `lawUnmeasuredCannotMasquerade`: an INTERRUPTED ladder burst whose
    /// comovement windows all REFUSED reads the 1000 sentinel on the wire —
    /// it must earn ONLY its own measured color-time, never the full
    /// constant (routing on the sentinel was the conflation that let a
    /// 16-unit burst fund a 64-unit game).
    @Test func unmeasuredShortBurstCannotMasquerade() {
        let interrupted = S4TelemetrySnapshot(arrivals: [6, 3, 1],
                                              sampleVolumes: [1, 8, 64],
                                              comovementPermille: 1000)
        let es = S4MergeEvidence.schedule(from: interrupted)
        #expect(es != S4MergeBoard.derivedSchedule)
        #expect(es.reduce(0, +) == 16)   // 6·1 + 3·2 + 1·4 — its own budget
    }

    /// `lawHealthyLadderYieldsConstant` + `lawWeavePlanBudgetIsFullWindow`:
    /// a perfect independent burst (64/32/16 → 192 → clamp 64) AND the
    /// shipped one-sensor weave (24/12/4 → 24+24+16 = 64, the FULL window —
    /// the cadence mismatch absorbed lawfully) both play exactly today's game.
    @Test func healthyLadderAndWeavePlanYieldConstant() {
        let healthy = S4TelemetrySnapshot(arrivals: [64, 32, 16],
                                          sampleVolumes: [1, 8, 64],
                                          comovementPermille: 250)
        #expect(S4MergeEvidence.colorTimeBudget(arrivals: healthy.arrivals) == 64)
        #expect(S4MergeEvidence.schedule(from: healthy) == S4MergeBoard.derivedSchedule)

        let weavePlan = S4TelemetrySnapshot(arrivals: [24, 12, 4],
                                            sampleVolumes: [1, 8, 64],
                                            comovementPermille: 250)
        #expect(S4MergeEvidence.colorTimeBudget(arrivals: weavePlan.arrivals) == 64)
        #expect(S4MergeEvidence.schedule(from: weavePlan) == S4MergeBoard.derivedSchedule)
        // The driver's own plan agrees with the pinned 24/12/4.
        let plan = MultiScaleLadder.weavePlan()
        #expect(MultiScaleLadder.plannedOwnedCount(plan, scale: .fine64) == 24)
        #expect(MultiScaleLadder.plannedOwnedCount(plan, scale: .mid32) == 12)
        #expect(MultiScaleLadder.plannedOwnedCount(plan, scale: .coarse16) == 4)
    }

    /// `lawScheduleNeverExceedsWindow`: whatever the telemetry claims —
    /// including wire-maximal arrivals — the schedule is 16 non-negative
    /// slots summing to at most the window. A burst funds at most its own
    /// 320 cs of game.
    @Test func scheduleNeverExceedsWindow() {
        let snapshots: [S4TelemetrySnapshot?] = [
            nil,
            S4TelemetrySnapshot(arrivals: [], sampleVolumes: [], comovementPermille: 0),
            S4TelemetrySnapshot(arrivals: [1, 2, 3], sampleVolumes: [1, 8, 64],
                                comovementPermille: 500),
            S4TelemetrySnapshot(arrivals: [63, 0, 0], sampleVolumes: [1, 8, 64],
                                comovementPermille: 100),
            S4TelemetrySnapshot(arrivals: [UInt64.max, UInt64.max, UInt64.max],
                                sampleVolumes: [1, 8, 64], comovementPermille: 0),
            S4TelemetrySnapshot(arrivals: [24, 12, 4], sampleVolumes: [1, 8, 64],
                                comovementPermille: 999),
        ]
        for ts in snapshots {
            let es = S4MergeEvidence.schedule(from: ts)
            #expect(es.count == S4MergeBoard.pourCap)
            #expect(es.allSatisfy { $0 >= 0 })
            #expect(es.reduce(0, +) <= S4MergeEvidence.windowUnits)
        }
        // A short burst prices below the window and splits exactly.
        let short = S4MergeEvidence.schedule(from: S4TelemetrySnapshot(
            arrivals: [63, 0, 0], sampleVolumes: [1, 8, 64], comovementPermille: 100))
        #expect(short.reduce(0, +) == 63)
        #expect(short != S4MergeBoard.derivedSchedule)
    }

    // MARK: - The pinned evidence run (the non-constant replay golden)

    /// `canonicalEvidenceRun` under `fairSplit 40` (the alternating 2/3
    /// schedule): four pours, three splits, one K, one PhaseLocked REFUSAL
    /// (the ninth op — absent from the word), one hold. Every final board
    /// field pinned from the Haskell battery; the word replays the board
    /// under ITS schedule (the GENERALIZED KEYSTONE); the constant game
    /// DIFFERS (evidence scaling is real, not a renamed constant).
    private static let evidenceRun: [S4MergeOp] = [
        .pour,
        .move(0, .s),
        .pour,
        .move(1, .s),
        .pour,
        .move(0, .k),
        .pour,
        .move(2, .s),
        .move(1, .s),   // refused: PhaseLocked (bank32 10 < 64) — not recorded
        .move(3, .i),
    ]

    @Test func goldenEvidenceTrace() {
        let s = S4MergeEvidence.fairSplit(40)
        var b = S4MergeBoard()
        var verdicts = [S4MergeVerdict]()
        for op in Self.evidenceRun { verdicts.append(b.step(op, schedule: s)) }
        #expect(verdicts == [
            .accept, .accept, .accept, .accept, .accept,
            .accept, .accept, .accept, .rejected(.phaseLocked), .accept,
        ])
        #expect(b.depths == [0, 1, 1] + [Int](repeating: 0, count: 13))
        #expect(b.signal == 7)
        #expect(b.spent == 3)
        #expect(b.pours == 4)
        #expect(b.bank32 == 10)
        #expect(b.word.count == 9)   // the refusal is absent
        #expect(b.word == [
            .pour, .move(0, .s), .pour, .move(1, .s), .pour,
            .move(0, .k), .pour, .move(2, .s), .move(3, .i),
        ])
        // GENERALIZED KEYSTONE (`lawWordReplaysBoardUnderSchedule`): the word
        // replays the board under the SAME schedule, every field.
        #expect(S4MergeBoard.playAll(b.word, schedule: s) == b)
        // The constant game DIFFERS: evidence scaling is real.
        #expect(S4MergeBoard.playAll(Self.evidenceRun) != b)
    }

    // MARK: - The derived special case (lawDerivedScheduleIsStep)

    /// The 22-op refusal trace (`MergeBoardTests.goldenOps`, pinned from the
    /// Haskell authority) folds IDENTICALLY — verdict for verdict, field for
    /// field — through the two-argument step under the derived constant.
    /// Today's game is byte-for-byte the derived special case.
    private static let refusalTrace: [S4MergeOp] = [
        .move(3, .s), .pour, .move(3, .s), .move(3, .s), .move(16, .s),
        .pour, .pour, .move(3, .k), .move(3, .i), .pour,
        .move(0, .s), .move(1, .s), .move(2, .s), .move(3, .s),
        .pour, .pour, .pour, .pour,
        .move(0, .s), .move(15, .k), .move(0, .k), .move(0, .s),
    ]

    @Test func derivedScheduleIsStep() {
        var classic = S4MergeBoard()
        var scheduled = S4MergeBoard()
        for op in Self.refusalTrace {
            let v1 = classic.step(op)
            let v2 = scheduled.step(op, schedule: S4MergeBoard.derivedSchedule)
            #expect(v1 == v2)
            #expect(classic == scheduled)
        }
        #expect(S4MergeBoard.playAll(Self.refusalTrace,
                                     schedule: S4MergeBoard.derivedSchedule)
                == S4MergeBoard.playAll(Self.refusalTrace))
        // The canonical tight construction survives the forward untouched.
        let canon = S4MergeBoard.playAll(S4MergeBoard.canonicalConstruction,
                                         schedule: S4MergeBoard.derivedSchedule)
        #expect(canon.fullyConstructed && canon.pours == 12
                && canon.spent == 48 && canon.signal == 0)
    }

    // MARK: - Honesty laws under any schedule

    /// `lawBankNeedsMeasurementUnderSchedule`: pours on the all-coarse board
    /// bank ZERO under ANY schedule — evidence money cannot buy the 32-gate
    /// without measuring at 32 first. Hostile negative slots deposit 0 and
    /// are ACCEPTED honest duds (the word records the attempt).
    @Test func bankNeedsMeasurementUnderAnySchedule() {
        let schedules: [[Int]] = [
            S4MergeBoard.derivedSchedule,
            S4MergeEvidence.fairSplit(40),
            S4MergeEvidence.fairSplit(3),
            [Int](repeating: -5, count: 16),   // hostile: clamps to 0-deposits
            [7],                               // hostile short: out-of-range → 0
        ]
        for s in schedules {
            var b = S4MergeBoard()
            for _ in 0..<16 { b.step(.pour, schedule: s) }
            #expect(b.bank32 == 0)
            #expect(b.pours == 16)             // duds are accepted, capped
            #expect(b.step(.pour, schedule: s) == .rejected(.poursExhausted))
        }
        // The all-negative schedule's duds: signal stays 0, word records 16 pours.
        let duds = S4MergeBoard.playAll([S4MergeOp](repeating: .pour, count: 16),
                                        schedule: [Int](repeating: -5, count: 16))
        #expect(duds.signal == 0 && duds.word.count == 16)
    }

    /// `lawUnlockMonotoneUnderSchedule`: banked 32-evidence never decreases
    /// along any op list under any schedule (K withdraws the claim, never the
    /// measurement).
    @Test func unlockMonotoneUnderSchedule() {
        for s in [S4MergeEvidence.fairSplit(40), S4MergeBoard.derivedSchedule] {
            var b = S4MergeBoard()
            var bank = 0
            for op in Self.evidenceRun + Self.refusalTrace {
                b.step(op, schedule: s)
                #expect(b.bank32 >= bank)
                bank = b.bank32
            }
        }
    }

    /// `lawShortEvidenceCannotConstruct`: total evidence below the 48-packet
    /// victory floor ⇒ NO op list fully constructs — phase 2 is honestly
    /// unreachable; the game refuses, it never invents.
    @Test func shortEvidenceCannotConstruct() {
        let s = S4MergeEvidence.fairSplit(24)   // 24 < 48
        #expect(!S4MergeBoard.playAll(S4MergeBoard.canonicalConstruction, schedule: s)
                    .fullyConstructed)
        // The full-window schedule CAN construct (the compatibility foil).
        #expect(S4MergeBoard.playAll(S4MergeBoard.canonicalConstruction,
                                     schedule: S4MergeEvidence.fairSplit(64))
                    .fullyConstructed)
    }

    /// The signal ledger under a schedule: signal == effective deposits −
    /// spends at every step, never negative (`lawSignalLedgerConservedUnderSchedule`).
    @Test func signalLedgerConservedUnderSchedule() {
        let s = S4MergeEvidence.fairSplit(40)
        var b = S4MergeBoard()
        for op in Self.evidenceRun {
            b.step(op, schedule: s)
            let deposits = (0..<b.pours).reduce(0) { $0 + S4MergeBoard.effectiveDeposit(s, $1) }
            #expect(b.signal == deposits - b.spent)
            #expect(b.signal >= 0)
        }
    }

    // MARK: - The wire composition (tel + dw in ONE record, zero wire change)

    /// The Swift half of `lawRecordedWordReplaysWithTelemetry`: build a board
    /// under the snapshot's schedule, seal snapshot AND word in ONE v3 record
    /// (no version bump beyond the existing seal, no new key), re-derive the
    /// schedule from the record's own telemetry, replay the decoded op-codes —
    /// the SAME board, every field. The reader needs nothing outside the file.
    @Test func recordedWordReplaysWithItsTelemetry() {
        let ts = S4TelemetrySnapshot(arrivals: [40, 0, 0],
                                     sampleVolumes: [1, 8, 64],
                                     comovementPermille: 420)
        let s = S4MergeEvidence.schedule(from: ts)
        #expect(s == S4MergeEvidence.fairSplit(40))   // non-constant: a real test
        let b = S4MergeBoard.playAll(Self.evidenceRun, schedule: s)

        var record = S4CaptureRecord()
        record.version = 2
        record.telemetry = ts
        record.sealDecisionWord(b.decisionWordCodes)
        #expect(record.version == 3)
        #expect(record.telemetry == ts)               // tel + dw co-located

        let decoded = record.decisionWord.compactMap(S4MergeBoard.op(fromCode:))
        #expect(decoded.count == record.decisionWord.count)
        let replayed = S4MergeBoard.playAll(
            decoded, schedule: S4MergeEvidence.schedule(from: record.telemetry))
        #expect(replayed == b)
        // The one-argument replay would be the WRONG board here — the
        // migration hazard the lint (scripts/lint-merge-replay.sh) polices.
        #expect(S4MergeBoard.playAll(decoded, schedule: S4MergeBoard.derivedSchedule) != b)
    }

    // MARK: - The model boundary (the schedule installs at construction)

    /// `DecideModel` receives the capture's IMMUTABLE schedule at
    /// construction: an evidence-scaled model pours the schedule's slot, the
    /// default model pours today's constant — and `evidenceScaled` names the
    /// difference with the one provenance vocabulary the instruments caption.
    @MainActor
    @Test func decideModelInstallsScheduleAtConstruction() {
        let scaled = DecideModel(tiles: [], gene: nil,
                                 pourSchedule: S4MergeEvidence.fairSplit(40))
        #expect(scaled.evidenceScaled)
        #expect(scaled.mergeStep(.pour) == .accept)
        #expect(scaled.merge.signal == 2)      // fairSplit(40)[0] == 2, not 4

        let derived = DecideModel(tiles: [], gene: nil)
        #expect(!derived.evidenceScaled)
        #expect(derived.mergeStep(.pour) == .accept)
        #expect(derived.merge.signal == 4)     // byte-for-byte today's game
    }
}
