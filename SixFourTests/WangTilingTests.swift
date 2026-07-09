//  WangTilingTests.swift
//  Golden-parity gate for the Swift twin of `Spec.WangTiling`.
//
//  The authority is the Haskell spec: every literal below is COPIED from
//  `Spec.WangTiling` (or derived by running the spec itself — annotated per
//  literal), never re-derived in Swift. The twin's exact ℚ(φ) arithmetic,
//  tile/op tables, attention rows and reveal ladder must reproduce them
//  byte-for-byte — any drift between the spec and this twin is a failed test
//  here, never a debugging session later. (The CaptureRecordTests pattern.)

import XCTest
@testable import SixFour

final class WangTilingTests: XCTestCase {

    // ── Oracle goldens ────────────────────────────────────────────────────────

    /// `Spec.WangTiling.goldenWindow8` — copied literal (lawGoldenWindowPinned):
    /// the 8×8 window at the origin (rows n = 0..7, cols m = 0..7).
    private static let specGoldenWindow8: [[Int]] = [
        [0, 0, 0, 1, 1, 0, 0, 0],
        [9, 9, 9, 10, 3, 9, 9, 9],
        [7, 3, 10, 4, 3, 10, 3, 8],
        [5, 7, 4, 5, 7, 4, 3, 10],
        [5, 6, 6, 6, 6, 6, 7, 4],
        [0, 1, 1, 1, 1, 1, 0, 0],
        [9, 10, 3, 8, 7, 3, 9, 9],
        [10, 4, 3, 10, 2, 8, 7, 3],
    ]

    /// Spec-derived: 4×4 windows anchored at (10⁹, −10⁹) and (−999999937,
    /// 999999937) — the exact arithmetic does not degrade far from the origin.
    private static let specFarWindowA: [[Int]] =
        [[8, 7, 3, 8], [10, 2, 8, 7], [4, 5, 7, 5], [0, 0, 0, 0]]
    private static let specFarWindowB: [[Int]] =
        [[0, 1, 1, 0], [9, 10, 3, 9], [10, 4, 3, 10], [4, 5, 7, 4]]

    func testGoldenWindow8MatchesSpec() {
        let window = (0 ..< 8).map { n in (0 ..< 8).map { m in S4WangTiling.tileIndexAt(m, n) } }
        XCTAssertEqual(window, Self.specGoldenWindow8)
    }

    func testFarWindowsMatchSpec() {
        let a = (0 ..< 4).map { n in
            (0 ..< 4).map { m in S4WangTiling.tileIndexAt(1_000_000_000 + m, -1_000_000_000 + n) }
        }
        let b = (0 ..< 4).map { n in
            (0 ..< 4).map { m in S4WangTiling.tileIndexAt(-999_999_937 + m, 999_999_937 + n) }
        }
        XCTAssertEqual(a, Self.specFarWindowA)
        XCTAssertEqual(b, Self.specFarWindowB)
    }

    /// `Spec.WangTiling.jrTiles` — copied literal (w,e,s,n): 11 pairwise-distinct
    /// tiles over 4 carriers / 5 grades (lawElevenTiles + lawFourColors).
    func testTileTableMatchesSpec() {
        let spec: [(Int, Int, Int, Int)] = [
            (2, 2, 1, 4), (2, 2, 0, 2), (3, 1, 1, 1), (3, 1, 2, 2), (3, 3, 3, 1),
            (3, 0, 1, 1), (0, 0, 1, 0), (0, 3, 2, 1), (1, 0, 2, 2), (1, 1, 4, 2),
            (1, 3, 2, 3),
        ]
        XCTAssertEqual(S4WangTiling.tiles.count, 11)
        for (t, q) in zip(S4WangTiling.tiles, spec) {
            XCTAssertEqual([t.w, t.e, t.s, t.n], [q.0, q.1, q.2, q.3])
        }
        XCTAssertEqual(Set(S4WangTiling.tiles.flatMap { [$0.w, $0.e] }), Set(0 ... 3))
        XCTAssertEqual(Set(S4WangTiling.tiles.flatMap { [$0.s, $0.n] }), Set(0 ... 4))
    }

    /// `lawOracleWindowsValid` (the KEYSTONE): oracle windows are edge-consistent
    /// Wang patches — at the origin, at ±10⁶, and at the ±10⁹ far anchors.
    func testOracleWindowsAreValidWangPatches() {
        for anchor in [(0, 0), (-1_000_000, 1_000_000), (1_000_000_000, -1_000_000_000),
                       (-999_999_937, 999_999_937), (12_345, -54_321)] {
            let w = S4WangTiling.window(at: anchor, width: 4, height: 4)
            XCTAssertTrue(S4WangTiling.windowValid(w), "invalid window at \(anchor)")
        }
    }

    /// `lawOracleDeterministic`: recomputation + differently-anchored windows
    /// agree — the oracle is context-free (random access).
    func testOracleIsContextFree() {
        let (m, n) = (777, -333)
        XCTAssertEqual(S4WangTiling.tileAt(m, n), S4WangTiling.tileAt(m, n))
        let shifted = S4WangTiling.window(at: (m - 1, n - 1), width: 3, height: 3)
        XCTAssertEqual(shifted[1][1], S4WangTiling.tileAt(m, n))
    }

    /// `lawNonperiodicWitness` (bounded): every candidate period |v| ≤ 2 has a
    /// defect inside the 12×12 origin window (arXiv:1506.06492 Thm 3's face).
    func testNonperiodicWitness() {
        let probe = (0 ..< 12).flatMap { m in (0 ..< 12).map { n in (m, n) } }
        for (v1, v2) in [(1, 0), (0, 1), (1, 1), (2, 0), (0, 2), (2, 1), (1, 2), (2, 2)] {
            XCTAssertTrue(probe.contains { m, n in
                S4WangTiling.tileIndexAt(m, n) != S4WangTiling.tileIndexAt(m + v1, n + v2)
            }, "period (\(v1),\(v2)) undetected")
        }
    }

    // ── State-machine goldens ─────────────────────────────────────────────────

    /// The tile→op DECISION OF RECORD — copied literal of the spec table as
    /// indices into `opsCanonical` (lawOpAssignmentPinned): bijective, 11 ops.
    func testOpAssignmentPinned() {
        XCTAssertEqual(S4WangTiling.opIndexOfTile, [10, 7, 9, 4, 1, 5, 2, 0, 6, 3, 8])
        XCTAssertEqual(Set(S4WangTiling.opIndexOfTile), Set(0 ... 10))
        XCTAssertEqual(S4WangTiling.opsCanonical.count, 11)
        XCTAssertEqual(Set(S4WangTiling.opsCanonical).count, 11)
        XCTAssertEqual(S4WangTiling.opOfIndex(7), .i)  // t7, the most frequent tile
    }

    /// Spec-derived slice-op goldens: `map opIdx (sliceOps s)` for s ∈
    /// {0, 1, −7, 10⁶} — the theorem-fixed SYNTAX of four pour groups.
    func testSliceOpsMatchSpec() {
        XCTAssertEqual(S4WangTiling.sliceOpIndices(0), [
            10, 10, 10, 7, 7, 10, 10, 10, 10, 10, 7, 7, 7, 10, 10, 10,
            3, 3, 3, 8, 4, 3, 3, 3, 3, 3, 6, 0, 4, 3, 3, 3,
            0, 4, 8, 1, 4, 8, 4, 6, 0, 4, 8, 9, 6, 0, 4, 6,
            5, 0, 1, 5, 0, 1, 4, 8, 5, 0, 1, 5, 0, 9, 6, 0,
        ])
        XCTAssertEqual(S4WangTiling.sliceOpIndices(1), [
            5, 2, 2, 2, 2, 2, 0, 1, 5, 2, 2, 2, 2, 2, 0, 5,
            10, 7, 7, 7, 7, 7, 10, 10, 10, 7, 7, 7, 7, 7, 10, 10,
            3, 8, 4, 6, 0, 4, 3, 3, 3, 8, 4, 6, 0, 4, 3, 3,
            8, 1, 4, 8, 9, 6, 0, 4, 8, 1, 4, 8, 9, 6, 0, 4,
        ])
        XCTAssertEqual(S4WangTiling.sliceOpIndices(-7), [
            2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2,
            7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7,
            4, 6, 0, 4, 6, 0, 4, 8, 4, 6, 0, 4, 8, 4, 6, 0,
            4, 8, 9, 6, 0, 5, 0, 1, 4, 8, 5, 0, 1, 4, 8, 9,
        ])
        XCTAssertEqual(S4WangTiling.sliceOpIndices(1_000_000), [
            8, 4, 6, 0, 4, 8, 9, 6, 0, 4, 6, 0, 4, 8, 4, 6,
            1, 4, 8, 5, 0, 1, 5, 0, 9, 6, 0, 5, 0, 1, 4, 8,
            2, 0, 1, 5, 2, 2, 2, 2, 2, 0, 5, 2, 2, 2, 0, 1,
            7, 10, 10, 10, 7, 7, 7, 7, 7, 10, 10, 7, 7, 7, 10, 10,
        ])
    }

    /// `lawSliceIsRandomAccess`: a slice computed directly equals the same rows
    /// of a double-height window; shape = 4 × 16 (the pour group).
    func testSliceIsRandomAccess() {
        for s in [0, 3, -11, 4096] {
            let tall = S4WangTiling.window(at: (0, S4WangTiling.sliceRows * s),
                                           width: S4WangTiling.sliceWidth,
                                           height: 2 * S4WangTiling.sliceRows)
            XCTAssertEqual(S4WangTiling.sliceWindow(s), Array(tall[0 ..< 4]))
            XCTAssertEqual(S4WangTiling.sliceWindow(s + 1), Array(tall[4 ..< 8]))
        }
        XCTAssertEqual(S4WangTiling.sliceWindow(0).count, 4)
        XCTAssertTrue(S4WangTiling.sliceWindow(0).allSatisfy { $0.count == 16 })
    }

    /// `lawSliceNeverRepeats` (bounded): no vertical period up to the pour
    /// group in the first nine slices.
    func testSliceNeverRepeats() {
        for period in 1 ... 4 {
            XCTAssertTrue((0 ... 8).contains { s in
                S4WangTiling.sliceOpIndices(s) != S4WangTiling.sliceOpIndices(s + period)
            }, "vertical period \(period) undetected")
        }
    }

    // ── Gene = attention goldens ──────────────────────────────────────────────

    /// `lawZeroGeneIsUniform`: the zero gene is EXACTLY uniform — 1/11 each.
    func testZeroGeneIsUniform() {
        let row = S4WangTiling.attentionOf(gene: [])
        XCTAssertEqual(row.count, 11)
        XCTAssertTrue(row.allSatisfy { $0 == S4WangTiling.Weight(num: 1, den: 11) })
    }

    /// Spec-derived: `attentionOf (Gene (65536 : replicate 20 0))` — energy on
    /// band {x} only. Exact reduced rationals, copied from the spec run.
    func testAttentionWitnessGeneMatchesSpec() {
        let row = S4WangTiling.attentionOf(gene: [65536] + Array(repeating: 0, count: 20))
        let spec: [(Int, Int)] = [
            (1, 23), (4, 23), (5, 23), (5, 23), (2, 23), (1, 23),
            (1, 23), (1, 23), (1, 23), (1, 23), (1, 23),
        ]
        XCTAssertEqual(row.map { [$0.num, $0.den] }, spec.map { [$0.0, $0.1] })
    }

    /// Spec-derived: the alternating ramp gene
    /// `[1000·(i+1)·(−1)^i | i ← [0..20]]` — copied exact rationals.
    func testAttentionRampGeneMatchesSpec() {
        let gene = (0 ..< 21).map { 1000 * ($0 + 1) * ($0 % 2 == 0 ? 1 : -1) }
        let row = S4WangTiling.attentionOf(gene: gene)
        let spec: [(Int, Int)] = [
            (4096, 74681), (20567, 149362), (18317, 149362), (16067, 149362),
            (263, 4393), (10067, 149362), (5596, 74681), (12317, 149362),
            (6721, 74681), (14567, 149362), (7846, 74681),
        ]
        XCTAssertEqual(row.map { [$0.num, $0.den] }, spec.map { [$0.0, $0.1] })
        // lawAttentionIsDistribution: strictly positive, sums to exactly 1
        // (verified in exact integer arithmetic over the common denominator).
        XCTAssertTrue(row.allSatisfy { $0.num > 0 && $0.den > 0 })
        let commonDen = 149_362 * 4_393
        let scaled = row.map { $0.num * (commonDen / $0.den) }
        XCTAssertEqual(scaled.reduce(0, +), commonDen)
    }

    /// The Q16 projection is pinned floor rounding and uniform at the zero gene.
    func testAttentionQ16Projection() {
        let uniform = S4WangTiling.attentionQ16(gene: [])
        XCTAssertEqual(uniform, Array(repeating: Int32(65536 / 11), count: 11))
        let witness = S4WangTiling.attentionQ16(gene: [65536] + Array(repeating: 0, count: 20))
        XCTAssertEqual(witness[0], Int32(65536 / 23))       // I: 1/23
        XCTAssertEqual(witness[1], Int32(4 * 65536 / 23))   // K_x: 4/23
    }

    // ── Boot resolve goldens ──────────────────────────────────────────────────

    /// The reveal ladder is exactly 4 / 8 / 16 ticks (spec boot WITNESS +
    /// lawBootResolveTerminates): earned coarse-first, nothing at tick 0.
    func testBootResolveLadder() {
        XCTAssertEqual(S4WangTiling.revealTick(.r16), 4)
        XCTAssertEqual(S4WangTiling.revealTick(.r32), 8)
        XCTAssertEqual(S4WangTiling.revealTick(.r64), 16)
        XCTAssertEqual(S4WangTiling.revealAt(0), [])
        XCTAssertEqual(S4WangTiling.revealAt(3), [])
        XCTAssertEqual(S4WangTiling.revealAt(4), [.r16])
        XCTAssertEqual(S4WangTiling.revealAt(8), [.r16, .r32])
        XCTAssertEqual(S4WangTiling.revealAt(16), [.r16, .r32, .r64])
        XCTAssertEqual(S4WangTiling.revealAt(10_000), [.r16, .r32, .r64])
        // lawBootResolveIsPourInverse: the √N reciprocity revealTick·unitsOf = 16.
        for p in S4WangTiling.TubeRung.allCases {
            XCTAssertEqual(S4WangTiling.revealTick(p) * p.unitsOf, 16)
        }
    }

    // ── Exact-arithmetic witnesses (spec ZPhi WITNESS tests) ──────────────────

    /// floor(φ)=1, floor(−φ)=−2, sign(φ−1)>0, sign(2−φ)>0, sign(1−φ)<0; and
    /// floor(q+n) == floor(q)+n far from the origin.
    func testQPhiWitness() {
        XCTAssertEqual(S4QPhi.phi.floor, 1)
        XCTAssertEqual(S4QPhi(0, -1).floor, -2)
        XCTAssertGreaterThan(S4QPhi(-1, 1).signum, 0)
        XCTAssertGreaterThan(S4QPhi(2, -1).signum, 0)
        XCTAssertLessThan(S4QPhi(1, -1).signum, 0)
        for n in [-1_000_000_000, -7, 0, 13, 999_999_999] {
            XCTAssertEqual((S4QPhi.phi + S4QPhi.fromInt(n)).floor, 1 + n)
        }
    }
}
