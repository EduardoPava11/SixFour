//  MergeBoardTests.swift
//  Golden-parity gate for the hand-written THE MERGE game core.
//
//  The authority is the Haskell spec: `Spec.MergeBoard` (15 laws). Two pins
//  were generated from the spec itself and copied here as literals, never
//  derived: the canonical tight construction (`lawCanonicalRunConstructs`)
//  and a 22-op golden trace that exercises every refusal family, the phase
//  unlock, and the K/I verbs (computed with `playAll`/`step` in GHCi,
//  2026-07-10). Any drift between the Swift game the user plays and the
//  algebra the training corpus assumes is a failed test here.

import XCTest
@testable import SixFour

final class MergeBoardTests: XCTestCase {

    // MARK: The canonical tight construction

    /// `Spec.MergeBoard.lawCanonicalRunConstructs`: 12 pours, 48 spent,
    /// signal 0, fully constructed, and every op accepted (word == run).
    func testCanonicalRunConstructs() {
        let b = S4MergeBoard.playAll(S4MergeBoard.canonicalConstruction)
        XCTAssertTrue(b.fullyConstructed)
        XCTAssertEqual(b.word, S4MergeBoard.canonicalConstruction)
        XCTAssertEqual(b.pours, 12)
        XCTAssertEqual(b.spent, 48)
        XCTAssertEqual(b.signal, 0)
    }

    // MARK: The golden trace (pinned from GHCi against Spec.MergeBoard)

    /// 22 ops: every refusal family (NoSignal, PhaseLocked, OffBoard,
    /// AlreadyCoarsest), the S/K/I verbs, and the energy-gate unlock.
    private static let goldenOps: [S4MergeOp] = [
        .move(3, .s),        // Rejected NoSignal (opening board is broke)
        .pour,               // Accept
        .move(3, .s),        // Accept (16→32)
        .move(3, .s),        // Rejected PhaseLocked (32→64 before the window)
        .move(16, .s),       // Rejected OffBoard
        .pour, .pour,        // Accept ×2 (bank32 += 4 each: one region ≥ 32)
        .move(3, .k),        // Accept (back to coarse — the claim withdrawn)
        .move(3, .i),        // Accept (explicit hold, recorded)
        .pour,               // Accept (all-coarse again: banks ZERO)
        .move(0, .s), .move(1, .s), .move(2, .s), .move(3, .s), // Accept ×4
        .pour, .pour, .pour, .pour, // Accept ×4 (16 per pour → unlock)
        .move(0, .s),        // Accept (32→64: the gate is open)
        .move(15, .k),       // Rejected AlreadyCoarsest
        .move(0, .k),        // Accept (64 back to 32)
        .move(0, .s),        // Accept (and finer again — spent remembers)
    ]

    /// The spec's verdict sequence for `goldenOps`, in order.
    func testGoldenTraceVerdicts() {
        var b = S4MergeBoard()
        let verdicts = Self.goldenOps.map { b.step($0) }
        let expected: [S4MergeVerdict] = [
            .rejected(.noSignal), .accept, .accept,
            .rejected(.phaseLocked), .rejected(.offBoard),
            .accept, .accept, .accept, .accept, .accept,
            .accept, .accept, .accept, .accept,
            .accept, .accept, .accept, .accept,
            .accept, .rejected(.alreadyCoarsest), .accept, .accept,
        ]
        XCTAssertEqual(verdicts, expected)
    }

    /// The spec's final state for `goldenOps`: depths [2,1,1,1,0…],
    /// signal 23, spent 9, pours 8, bank32 72, and the 18-op word's codes.
    func testGoldenTraceFinalState() {
        let b = S4MergeBoard.playAll(Self.goldenOps)
        XCTAssertEqual(b.depths, [2, 1, 1, 1] + [Int](repeating: 0, count: 12))
        XCTAssertEqual(b.signal, 23)
        XCTAssertEqual(b.spent, 9)
        XCTAssertEqual(b.pours, 8)
        XCTAssertEqual(b.bank32, 72)
        XCTAssertEqual(b.word.count, 18)
        XCTAssertEqual(b.decisionWordCodes,
                       [0, 10, 0, 0, 11, 12, 0, 1, 4, 7, 10, 0, 0, 0, 0, 1, 2, 1])
    }

    /// `Spec.MergeBoard.lawWordReplaysBoard` on the golden trace: replaying
    /// the board's own word reproduces the board exactly, every field.
    func testWordReplaysBoard() {
        let b = S4MergeBoard.playAll(Self.goldenOps)
        XCTAssertEqual(S4MergeBoard.playAll(b.word), b)
    }

    // MARK: The wire

    /// `Spec.CaptureRecord.lawGameOpCodeRoundTrips`: every code 0…48
    /// round-trips, and 49 refuses.
    func testOpCodeRoundTrips() {
        for code in UInt64(0)...48 {
            guard let op = S4MergeBoard.op(fromCode: code) else {
                return XCTFail("code \(code) refused")
            }
            XCTAssertEqual(S4MergeBoard.opCode(op), code)
        }
        XCTAssertNil(S4MergeBoard.op(fromCode: 49))
    }

    /// The `.s4cr` v3 golden word — pour, S@r0, S@r15, K@r0, I@r15 —
    /// emits exactly the codes pinned in `goldenRecordV3Bytes` ([0,1,46,2,48]),
    /// tying this game core to the record the shutter writes.
    func testGoldenRecordV3WordCodes() {
        let ops: [S4MergeOp] = [
            .pour, .move(0, .s), .move(15, .s), .move(0, .k), .move(15, .i),
        ]
        XCTAssertEqual(ops.map(S4MergeBoard.opCode), [0, 1, 46, 2, 48])
    }

    /// End-to-end writer shape: a played board's codes ride
    /// `S4CaptureRecord.decisionWord` into a version-3 record whose `dw`
    /// value is the codes array verbatim (the wire twin of
    /// `lawDecisionWordSurvivesTheRecord`'s writer half).
    func testDecisionWordReachesTheRecord() {
        let b = S4MergeBoard.playAll(Self.goldenOps)
        var r = S4CaptureRecord()
        r.version = 3
        r.decisionWord = b.decisionWordCodes
        let bytes = r.cborBytes
        // "dw" key then array(18) then the first three codes 0, 10, 0.
        let expected: [UInt8] = [0x62, 0x64, 0x77, 0x92, 0x00, 0x0A, 0x00]
        let found = bytes.indices.dropLast(expected.count).contains { i in
            Array(bytes[i..<(i + expected.count)]) == expected
        }
        XCTAssertTrue(found)
    }

    // MARK: The economy laws (spot mirrors of the spec's QuickCheck battery)

    /// `lawBankNeedsMeasurement`: pours on the all-coarse board bank ZERO.
    func testBankNeedsMeasurement() {
        var b = S4MergeBoard()
        for _ in 0..<16 { b.step(.pour) }
        XCTAssertEqual(b.bank32, 0)
        XCTAssertFalse(b.phase2Unlocked)
        XCTAssertEqual(b.step(.pour), .rejected(.poursExhausted))
    }

    /// `lawSignalLedgerConserved` on the golden trace: signal ==
    /// deposits − spends at every step, never negative.
    func testSignalLedgerConserved() {
        var b = S4MergeBoard()
        for op in Self.goldenOps {
            b.step(op)
            XCTAssertEqual(b.signal, S4MergeBoard.pourDeposit * b.pours - b.spent)
            XCTAssertGreaterThanOrEqual(b.signal, 0)
        }
    }

    /// `lawKKeepsAndNeverPays`: K decrements only the depth.
    func testKKeepsAndNeverPays() {
        var b = S4MergeBoard()
        b.step(.pour)
        b.step(.move(5, .s))
        let before = b
        XCTAssertEqual(b.step(.move(5, .k)), .accept)
        XCTAssertEqual(b.depths[5], 0)
        XCTAssertEqual(b.signal, before.signal)
        XCTAssertEqual(b.spent, before.spent)
        XCTAssertEqual(b.bank32, before.bank32)
    }
}
