//  ZigPortLatticeTests.swift
//  Swift port of the LATTICE-section Zig tests (2026-07-06), gating the
//  KernelsLattice.swift twin of Native/src/kernels.zig:
//    * haar_fixture_test.zig          — spec-fixtures haar_golden.json (skip-if-absent)
//    * cube_expand_fixture_test.zig   — spec-fixtures cube_expand_golden.json (skip-if-absent)
//    * rgbt4d_fixture_test.zig        — spec-fixtures rgbt4d_golden.json (skip-if-absent)
//    * invertibility_break_test.zig   — adversarial totality/refusal witnesses
//    * haar_tensor_float_test.zig     — fp16 cooperative-matrix loss model
//    * haar_barrier_hazard_test.zig   — deterministic single-threaded schedule model
//    * haar_barrier_race_test.zig     — deterministic single-threaded schedule model
//    * haar_coherency_premature_read_test.zig — deterministic publication model
//    * haar_inplace_intralevel_race_test.zig  — deterministic order model
//
//  All four "race"/"hazard"/"coherency" Zig tests are single-threaded MODELS of
//  bad schedules (no std.Thread anywhere), so every assertion ports 1:1.
//
//  XCTest (not swift-testing) so fixture-absent cases can XCTSkip, mirroring the
//  Zig error.SkipZigTest discipline. Fixtures: trainer/out (the Zig
//  build_options.fixture_dir default); build with `cd spec && cabal run spec-fixtures`.

import XCTest
import Foundation
@testable import SixFour

// Private copies of the kernels.zig RC_* codes (the kernel file's are file-private).
private let rcOK: Int32 = 0
private let rcOutOfRange: Int32 = 7
// The reversible-substrate domain bound B = 2^29 − 1 and 2B (kernels.zig
// SUBSTRATE_BOUND / DETAIL_BOUND — file-private in the port, pinned here by value).
private let substrateB: Int32 = 536_870_911
private let detailB: Int32 = 1_073_741_822

final class ZigPortLatticeTests: XCTestCase {

    // ── fixture plumbing (trainer/out, skip-if-absent) ────────────────────────

    private static let fixtureDir = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent() // SixFourTests/
        .deletingLastPathComponent() // repo root
        .appendingPathComponent("trainer/out")

    private func loadFixture<T: Decodable>(_ name: String, as type: T.Type) throws -> T {
        let url = Self.fixtureDir.appendingPathComponent(name)
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw XCTSkip("\(name) not in '\(Self.fixtureDir.path)'; run `cd spec && cabal run spec-fixtures`")
        }
        return try JSONDecoder().decode(T.self, from: Data(contentsOf: url))
    }

    private struct HaarGolden: Decodable {
        let n: Int32
        let leaves: [[Int32]]
        let root: [Int32]
        let offsets: [[Int32]]
        let level_nodes: [[[Int32]]]
    }

    private struct CubeExpandGolden: Decodable {
        let side: Int32
        let vol: [Int32]
        let details: [Int32]
        let expected_floor: [Int32]
        let expected_gene: [Int32]
    }

    private struct RGBT4DGolden: Decodable {
        let side: Int32
        let grid: [Int32]
        let lift_in: [Int32]
        let lift_out: [Int32]
        let level_coarse: [Int32]
        let level_details: [[Int32]]
    }

    // ── shared helpers ────────────────────────────────────────────────────────

    /// Run the real analyze→reconstruct round trip on `leaves` (n triples).
    /// Returns true iff byte-exact (haar tests' realRoundTrips twin).
    private func realRoundTrips(_ leaves: [Int32], _ n: Int32) -> Bool {
        let nn = Int(n)
        var root = [Int32](repeating: 0, count: 3)
        var off = [Int32](repeating: 0, count: (nn - 1) * 3)
        var scratch = [Int32](repeating: 0, count: nn * 3)
        guard s4_haar_analyze(leaves, n, &root, &off, &scratch, nn * 3 * 4) == rcOK else { return false }
        var got = [Int32](repeating: 0, count: nn * 3)
        guard s4_haar_reconstruct(root, off, n, &got) == rcOK else { return false }
        return got == leaves
    }

    /// Analyze wrapper: returns (root, offsets) or nil on non-rcOK.
    private func analyze(_ leaves: [Int32], _ n: Int32) -> (root: [Int32], off: [Int32])? {
        let nn = Int(n)
        var root = [Int32](repeating: 0, count: 3)
        var off = [Int32](repeating: 0, count: (nn - 1) * 3)
        var scratch = [Int32](repeating: 0, count: nn * 3)
        guard s4_haar_analyze(leaves, n, &root, &off, &scratch, nn * 3 * 4) == rcOK else { return nil }
        return (root, off)
    }

    /// floor-div pair unlift, byte-identical to the kernel's inner reconstruct
    /// cell — restated so the tests can model alternative SCHEDULES of the same
    /// exact arithmetic (the Zig sibling tests' `unliftPair`).
    private func unliftPair(_ node: Int32, _ d: Int32) -> (x: Int32, y: Int32) {
        let y = node - s4DivFloor(d, 2)
        return (y + d, y)
    }

    // ══════════════════════════════════════════════════════════════════════════
    //  haar_fixture_test.zig — cross-language integer-Haar golden
    // ══════════════════════════════════════════════════════════════════════════

    func testHaarGoldenAnalyzeReconstructLevelNodes() throws {
        let g = try loadFixture("haar_golden.json", as: HaarGolden.self)
        let n = g.n
        let nn = Int(n)
        let leaves = g.leaves.flatMap { $0 }
        let expOffsets = g.offsets.flatMap { $0 } // (n-1) triples

        var gotRoot = [Int32](repeating: 0, count: 3)
        var gotOffsets = [Int32](repeating: 0, count: (nn - 1) * 3)
        var scratch = [Int32](repeating: 0, count: nn * 3)

        // analyze: root + offsets byte-exact.
        XCTAssertEqual(rcOK, s4_haar_analyze(leaves, n, &gotRoot, &gotOffsets, &scratch, nn * 3 * 4))
        XCTAssertEqual(g.root, gotRoot)
        XCTAssertEqual(expOffsets, gotOffsets)

        // reconstruct: leaves come back EXACTLY (lossless integer Haar).
        var gotLeaves = [Int32](repeating: 0, count: nn * 3)
        XCTAssertEqual(rcOK, s4_haar_reconstruct(gotRoot, gotOffsets, n, &gotLeaves))
        XCTAssertEqual(leaves, gotLeaves)

        // level_nodes: the abstraction cascade — each level byte-exact vs the
        // Haskell levelNodesFixed golden.
        for (l, lvl) in g.level_nodes.enumerated() {
            let exp = lvl.flatMap { $0 }
            var got = [Int32](repeating: 0, count: exp.count)
            XCTAssertEqual(rcOK, s4_haar_level_nodes(Int32(l), gotRoot, gotOffsets, n, &got))
            XCTAssertEqual(exp, got, "level \(l) node drift")
        }
        // Deepest level == the full reconstruction (the leaves).
        let depth = g.level_nodes.count - 1
        var gotFull = [Int32](repeating: 0, count: nn * 3)
        _ = s4_haar_level_nodes(Int32(depth), gotRoot, gotOffsets, n, &gotFull)
        XCTAssertEqual(leaves, gotFull)
    }

    // ══════════════════════════════════════════════════════════════════════════
    //  cube_expand_fixture_test.zig — DEVICE-layout volume-expand golden
    // ══════════════════════════════════════════════════════════════════════════

    func testCubeExpandGoldenFloorAndGeneArms() throws {
        let g = try loadFixture("cube_expand_golden.json", as: CubeExpandGolden.self)
        let s = Int(g.side)
        XCTAssertEqual(s * s * s, g.vol.count)
        XCTAssertEqual(g.vol.count * 7, g.details.count)
        let fineN = 8 * s * s * s
        XCTAssertEqual(fineN, g.expected_floor.count)
        XCTAssertEqual(fineN, g.expected_gene.count)

        var out = [Int32](repeating: 0, count: fineN)

        // Arm 1: the zero-detail deterministic floor (details == nil).
        XCTAssertEqual(rcOK, s4_cube_expand_rung(g.vol, g.side, nil, &out))
        XCTAssertEqual(g.expected_floor, out)

        // Arm 2: the gene arm (committed detail bands supplied).
        XCTAssertEqual(rcOK, s4_cube_expand_rung(g.vol, g.side, g.details, &out))
        XCTAssertEqual(g.expected_gene, out)

        // The two arms genuinely differ (the gene invents; the fixture's bands are nonzero).
        XCTAssertNotEqual(g.expected_floor, g.expected_gene)
    }

    // ══════════════════════════════════════════════════════════════════════════
    //  rgbt4d_fixture_test.zig — RGBT-4D golden (the Metal/Zig/Swift alignment gate)
    // ══════════════════════════════════════════════════════════════════════════

    func testRGBT4DGoldenLiftQuadAndCubeLevel() throws {
        let g = try loadFixture("rgbt4d_golden.json", as: RGBT4DGolden.self)
        let levelDetails = g.level_details.flatMap { $0 }

        // quad lift byte-exact + exact round-trip.
        var q4 = [Int32](repeating: 0, count: 4)
        XCTAssertEqual(rcOK, s4_rgbt_lift_quad(g.lift_in, &q4))
        XCTAssertEqual(g.lift_out, q4)
        var back = [Int32](repeating: 0, count: 4)
        XCTAssertEqual(rcOK, s4_rgbt_unlift_quad(q4, &back))
        XCTAssertEqual(g.lift_in, back)

        // level lift: coarse plane + detail planes byte-exact (pins the tiling layout).
        let h = Int(g.side) / 2
        var coarse = [Int32](repeating: 0, count: h * h)
        var details = [Int32](repeating: 0, count: h * h * 3)
        XCTAssertEqual(rcOK, s4_cube_lift_level(g.side, g.grid, &coarse, &details))
        XCTAssertEqual(g.level_coarse, coarse)
        XCTAssertEqual(levelDetails, details)

        // level reconstruct: the grid comes back EXACTLY (lossless within capture).
        var gotGrid = [Int32](repeating: 0, count: g.grid.count)
        XCTAssertEqual(rcOK, s4_cube_unlift_level(Int32(h), coarse, details, &gotGrid))
        XCTAssertEqual(g.grid, gotGrid)
    }

    // ══════════════════════════════════════════════════════════════════════════
    //  invertibility_break_test.zig — (a) i32 OVERFLOW → total-function refusal
    // ══════════════════════════════════════════════════════════════════════════

    func testOverflowExtremeOppositeSignAnalyzeRefuses() {
        // Witness: x = +2e9, y = −2e9 (both legal i32, ~18× past B). d = x − y =
        // 4e9 > i32 max. POST-redesign: REFUSE (never RC_OK-with-corruption).
        let x: Int32 = 2_000_000_000
        let y: Int32 = -2_000_000_000
        let dTrue = Int64(x) - Int64(y)
        XCTAssertEqual(Int64(4_000_000_000), dTrue) // the wide-truth detail

        let leaves: [Int32] = [x, 1, -1, y, 2, -2] // n=2; first L-channel pair is the OOR witness
        var root: [Int32] = [0, 0, 0]
        var off: [Int32] = [0, 0, 0]
        var scratch = [Int32](repeating: 0, count: 2 * 3)
        XCTAssertEqual(rcOutOfRange, s4_haar_analyze(leaves, 2, &root, &off, &scratch, 2 * 3 * 4))
    }

    func testOverflowIntMaxIntMinLeavesAnalyzeRefuses() {
        let leaves: [Int32] = [Int32.max, 0, 0, Int32.min, 0, 0]
        var root = [Int32](repeating: 0, count: 3)
        var off = [Int32](repeating: 0, count: 3)
        var scratch = [Int32](repeating: 0, count: 2 * 3)
        // Both leaves are far out of domain ⇒ refuse at the input-validation head.
        XCTAssertEqual(rcOutOfRange, s4_haar_analyze(leaves, 2, &root, &off, &scratch, 2 * 3 * 4))
    }

    func testOverflowReconstructOutOfImageOffsetsRefuses() {
        // root=INT_MAX, d=INT_MAX are outside the legal image (|node| ≤ B, |d| ≤ 2B).
        let root: [Int32] = [Int32.max, 0, 0]
        let off: [Int32] = [Int32.max, 0, 0]
        var out = [Int32](repeating: 0, count: 6)
        XCTAssertEqual(rcOutOfRange, s4_haar_reconstruct(root, off, 2, &out))

        // Also a node that is IN-range but a detail just past 2B: y+d would overflow
        // the ±B image → refuse on the per-detail check inside unliftChecked.
        let root2: [Int32] = [substrateB, 0, 0]
        let off2: [Int32] = [detailB + 1, 0, 0]
        var out2 = [Int32](repeating: 0, count: 6)
        XCTAssertEqual(rcOutOfRange, s4_haar_reconstruct(root2, off2, 2, &out2))
    }

    // ══════════════════════════════════════════════════════════════════════════
    //  invertibility_break_test.zig — s4_leaf_override producer-side guards
    //  (s4_leaf_override is owned by the sibling port slice; called by name)
    // ══════════════════════════════════════════════════════════════════════════

    func testLeafOverrideNullDeltaEqualsZeroDeltaEqualsFloor() {
        let gens: [Int32] = [50000, -12000, 9000, -3000, 40000, -25000] // 2 generators
        let zero = [Int32](repeating: 0, count: 6)
        var outNull = [Int32](repeating: 0, count: 12)
        var outZero = [Int32](repeating: 0, count: 12)
        XCTAssertEqual(rcOK, s4_leaf_override(gens, nil, 2, &outNull))
        XCTAssertEqual(rcOK, s4_leaf_override(gens, zero, 2, &outZero))
        // null path == zero-δ path byte-for-byte (the no-op short-circuit IS the floor):
        XCTAssertEqual(outNull, outZero)
        // and equals the raw σ-pair of the generators (the floor):
        let expect: [Int32] = [
            50000, -12000, 9000, 50000, 12000, -9000, // g0, σ(g0)
            -3000, 40000, -25000, -3000, -40000, 25000, // g1, σ(g1)
        ]
        XCTAssertEqual(expect, outNull)
    }

    func testLeafOverrideCeilingAndPastBoundRefused() {
        // generator at maxInt, δ=+1 → g+δ overflows i32 in i64-truth; producer refuses.
        let gens: [Int32] = [Int32.max, 0, 0]
        let deltas: [Int32] = [1, 0, 0]
        var out = [Int32](repeating: 0, count: 6)
        XCTAssertEqual(rcOutOfRange, s4_leaf_override(gens, deltas, 1, &out))

        // Even a "legal-looking" sum past B refuses: ga = 2^30 > B = 2^29−1 would
        // make the downstream analyze detail ga−(−ga)=2^31 overflow. Stop it here.
        let gens2: [Int32] = [0, 1 << 30, 0]
        var out2 = [Int32](repeating: 0, count: 6)
        XCTAssertEqual(rcOutOfRange, s4_leaf_override(gens2, nil, 1, &out2))
    }

    func testLeafOverrideIntMinGeneratorRefused() {
        // PRE: out[o+4] = −ga negated INT_MIN (overflow). POST: |ga| = 2^31 ≫ B, so
        // the producer refuses before any negate — the σ-pair can never be malformed.
        let gens: [Int32] = [0, Int32.min, 0]
        var out = [Int32](repeating: 0, count: 6)
        XCTAssertEqual(rcOutOfRange, s4_leaf_override(gens, nil, 1, &out))
    }

    // ══════════════════════════════════════════════════════════════════════════
    //  invertibility_break_test.zig — (b) @divFloor vs @divTrunc sign
    // ══════════════════════════════════════════════════════════════════════════

    /// Trunc-port inverse (the C `/` / signed `>>1` an MSL/Metal port emits).
    private func reconstructTrunc(_ root: [Int32], _ off: [Int32], _ n: Int) -> [Int32] {
        var out = [Int32](repeating: 0, count: n * 3)
        out[0] = root[0]
        out[1] = root[1]
        out[2] = root[2]
        var cur = 1
        while cur < n {
            let outStart = cur - 1
            var i = cur
            while i > 0 {
                i -= 1
                for c in 0..<3 {
                    let node = out[i * 3 + c]
                    let d = off[(outStart + i) * 3 + c]
                    let y = node - d / 2 // <-- TRUNC, the wrong primitive
                    out[(2 * i) * 3 + c] = y + d
                    out[(2 * i + 1) * 3 + c] = y
                }
            }
            cur *= 2
        }
        return out
    }

    func testDivFloorNegativeOddDetailRoundTripsTruncPortDiverges() {
        // Witness on signed a/b channels; every level produces odd-negative details.
        let leaves: [Int32] = [
            -32768, 0, 1, // leaf0
            32767, -128, -1, // leaf1
            -3, 127, -5, // leaf2
            0, -64, 33, // leaf3
        ]
        let n: Int32 = 4
        // floor (real kernel) round-trips byte-exact:
        XCTAssertTrue(realRoundTrips(leaves, n))

        // analyze, then run the trunc-port inverse and assert it DIVERGES.
        guard let hp = analyze(leaves, n) else { return XCTFail("analyze failed") }
        let truncLeaves = reconstructTrunc(hp.root, hp.off, 4)
        // Non-vacuity: floor != trunc on these details, so the trunc port BREAKS id.
        XCTAssertNotEqual(leaves, truncLeaves)

        // Pin the canonical fork numerically: d=−1 → floor=−1, trunc=0.
        XCTAssertEqual(Int32(-1), s4DivFloor(-1, 2))
        XCTAssertEqual(Int32(0), Int32(-1) / 2)
        // Even control: d=−4 → floor==trunc==−2 (fork only fires on odd-negative).
        XCTAssertEqual(s4DivFloor(-4, 2), Int32(-4) / 2)
    }

    // ══════════════════════════════════════════════════════════════════════════
    //  invertibility_break_test.zig — (c) IN-PLACE ascending expansion corrupts
    // ══════════════════════════════════════════════════════════════════════════

    /// ASCENDING in-place expansion — the data-flow a naive one-thread-per-i port
    /// realizes (writes slot 2i before a later i reads slot i). Interleaved form.
    private func reconstructAscendingInterleaved(_ root: [Int32], _ off: [Int32], _ n: Int) -> [Int32] {
        var out = [Int32](repeating: 0, count: n * 3)
        out[0] = root[0]
        out[1] = root[1]
        out[2] = root[2]
        var cur = 1
        while cur < n {
            let outStart = cur - 1
            var i = 0
            while i < cur { // <-- ASCENDING (the hazard)
                for c in 0..<3 {
                    let node = out[i * 3 + c]
                    let d = off[(outStart + i) * 3 + c]
                    let y = node - s4DivFloor(d, 2)
                    out[(2 * i) * 3 + c] = y + d
                    out[(2 * i + 1) * 3 + c] = y
                }
                i += 1
            }
            cur *= 2
        }
        return out
    }

    func testInPlaceRaceDescendingRoundTripsAscendingCorrupts() {
        // n=8, large mixed-sign details at every level so a clobbered slot can never
        // coincidentally equal the correct value.
        let leaves: [Int32] = [
            1 << 27, 1, -1,
            -(1 << 27), 2, -2,
            0, 1 << 26, 7,
            123457, -(1 << 26), -3,
            -1, 3, 5,
            1 << 25, -4, 11,
            -3, 6, -9,
            5, -7, 13,
        ]
        let n: Int32 = 8
        // descending (real kernel) round-trips:
        XCTAssertTrue(realRoundTrips(leaves, n))

        guard let hp = analyze(leaves, n) else { return XCTFail("analyze failed") }
        let asc = reconstructAscendingInterleaved(hp.root, hp.off, 8)
        // ASSERTION: ascending order does NOT round-trip → ordering is load-bearing.
        XCTAssertNotEqual(leaves, asc)
    }

    // ══════════════════════════════════════════════════════════════════════════
    //  invertibility_break_test.zig — (d) stale level-ℓ parent read breaks id
    // ══════════════════════════════════════════════════════════════════════════

    func testBarrierStaleParentReadBreaksSequentialHolds() {
        // n=4, parents move at every level (odd detail +7, large magnitude).
        let leaves: [Int32] = [
            1 << 20, 0, -3,
            0, 11, 5,
            (1 << 20) + 7, -9, 2,
            0, 0, 0,
        ]
        let n = 4
        XCTAssertTrue(realRoundTrips(leaves, Int32(n)))

        // Model the missing global barrier: level ≥1 reads the ORIGINAL leaves
        // (stale, un-flushed low half) instead of level-0's lifted parents.
        var work = leaves
        var snap = [Int32](repeating: 0, count: n * 3)
        var off = [Int32](repeating: 0, count: (n - 1) * 3)
        var cur = n
        var level = 0
        while cur > 1 {
            if level == 0 {
                for i in 0..<(n * 3) { snap[i] = work[i] }
            } else {
                for i in 0..<(n * 3) { snap[i] = leaves[i] } // STALE
            }
            let half = cur / 2
            let outStart = half - 1
            for i in 0..<half {
                for c in 0..<3 {
                    let x = snap[(2 * i) * 3 + c]
                    let y = snap[(2 * i + 1) * 3 + c]
                    let d = x - y
                    work[i * 3 + c] = y + s4DivFloor(d, 2)
                    off[(outStart + i) * 3 + c] = d
                }
            }
            cur = half
            level += 1
        }
        let racedRoot: [Int32] = [work[0], work[1], work[2]]
        var racedLeaves = [Int32](repeating: 0, count: n * 3)
        XCTAssertEqual(rcOK, s4_haar_reconstruct(racedRoot, off, Int32(n), &racedLeaves))
        // ASSERTION: the raced cascade does NOT round-trip.
        XCTAssertNotEqual(leaves, racedLeaves)
    }

    // ══════════════════════════════════════════════════════════════════════════
    //  invertibility_break_test.zig — (e) fp16 tensor cores lose low Q16 bits
    // ══════════════════════════════════════════════════════════════════════════

    /// Coerce an i32 through f16 (the cooperative-matrix element type) and back.
    private func thruF16(_ v: Int32) -> Int32 {
        let f = Float16(Float(v)) // may round / saturate
        if !Float(f).isFinite { return v } // (witness keeps finite)
        return Int32(Float(f).rounded())
    }

    func testTensorFloatF16LosesLowBitsIntegerLiftExact() {
        // Detail 2049 = smallest int above fp16's 2048 exact-integer ceiling.
        let leaves: [Int32] = [
            2049, 4097, -2049, // leaf0 — all three details just past 2^11
            0, 0, 0, // leaf1
        ]
        let n: Int32 = 2
        // (1) INTEGER PATH EXACT:
        XCTAssertTrue(realRoundTrips(leaves, n))
        guard let hp = analyze(leaves, n) else { return XCTFail("analyze failed") }
        XCTAssertEqual(Int32(2049), hp.off[0]) // L detail exact in i32

        // (2) FLOAT PATH LOSSY: route the detail through f16 → collapses 2049 → 2048.
        let rt = thruF16(hp.off[0])
        XCTAssertEqual(Int32(2048), rt)
        XCTAssertNotEqual(rt, hp.off[0])

        // Confirm a full fp16-lift round trip breaks id on a higher-magnitude witness.
        // Pair (65537, 1): d=65536, parent=1+32768=32769 → f16 parent 32769→32768.
        let x: Int32 = 65537
        let y: Int32 = 1
        let dI = x - y
        let parentI = y + s4DivFloor(dI, 2)
        let parentF16 = thruF16(parentI)
        let dF16 = thruF16(dI)
        let yBack = parentF16 - s4DivFloor(dF16, 2)
        let xBack = yBack + dF16
        XCTAssertNotEqual(xBack, x) // float butterfly already broken
    }

    // ══════════════════════════════════════════════════════════════════════════
    //  invertibility_break_test.zig — (f) output-buffer-contents independence
    // ══════════════════════════════════════════════════════════════════════════

    func testUnifiedMemoryReconstructIndependentOfPoisonedOutput() {
        // n=8, alternating ±extreme. ±B = ±(2^29−1) — the MAX in-domain magnitude
        // (so the first-level detail d = B−(−B) = 2B is the largest legal detail).
        let B: Int32 = 536_870_911 // 2^29 − 1
        let leaves: [Int32] = [
            B, 1, -1,
            -B, 2, -2,
            1, 3, -3,
            -1, 4, -4,
            7, 5, -5,
            -7, 6, -6,
            123, 7, -7,
            -123, 8, -8,
        ]
        let n: Int32 = 8
        var root = [Int32](repeating: 0, count: 3)
        var off = [Int32](repeating: 0, count: 21)
        var scratch = [Int32](repeating: 0, count: 8 * 3)
        // The pairs are (B, −B) → d = 2B = 2^30−2 < 2^31−1, in-domain ⇒ rcOK.
        XCTAssertEqual(rcOK, s4_haar_analyze(leaves, n, &root, &off, &scratch, 8 * 3 * 4))

        // Reconstruct into a ZEROED buffer:
        var clean = [Int32](repeating: 0, count: 24)
        XCTAssertEqual(rcOK, s4_haar_reconstruct(root, off, n, &clean))
        XCTAssertEqual(leaves, clean)

        // Reconstruct into a POISONED buffer (0xDEADBEEF sentinel = −559038737):
        var poison = [Int32](repeating: -559_038_737, count: 24)
        XCTAssertEqual(rcOK, s4_haar_reconstruct(root, off, n, &poison))
        // Byte-identical to the clean run → no hidden output-buffer read dependency.
        XCTAssertEqual(clean, poison)
        XCTAssertEqual(leaves, poison)

        // analyze: poison out_offsets first; assert root+offsets identical to clean.
        var off2 = [Int32](repeating: -559_038_737, count: 21)
        var root2 = [Int32](repeating: -559_038_737, count: 3)
        XCTAssertEqual(rcOK, s4_haar_analyze(leaves, n, &root2, &off2, &scratch, 8 * 3 * 4))
        XCTAssertEqual(root, root2)
        XCTAssertEqual(off, off2)
    }

    // ══════════════════════════════════════════════════════════════════════════
    //  invertibility_break_test.zig — (g) Core-AI ULP divergence vs Q16-floor snap
    // ══════════════════════════════════════════════════════════════════════════

    func testCoreAIULPDivergenceCollapsedByQ16FloorSnap() {
        // Two devices' floats straddle a Q16 cell around K=63570.
        let K: Int32 = 63570
        let vA = (Double(K) + 0.4999) / 65536.0 // device A: just below K + 0.5
        let vB = (Double(K) + 0.5001) / 65536.0 // device B: just above

        // BYPASS path: naive round(v·65536) per device, fed straight into analyze.
        let leafA = Int32((vA * 65536.0).rounded()) // K
        let leafB = Int32((vB * 65536.0).rounded()) // K+1
        XCTAssertNotEqual(leafA, leafB) // one ULP flipped the Q16 leaf

        func buildLeaves(_ perturbed: Int32) -> [Int32] {
            // n=8, the perturbed L leaf adjacent to a sibling so analyze sees a
            // differing detail; a,b channels constant.
            return [
                perturbed, 100, -100,
                63569, 100, -100,
                63571, 100, -100,
                63568, 100, -100,
                63572, 100, -100,
                63567, 100, -100,
                63573, 100, -100,
                63566, 100, -100,
            ]
        }
        guard let hpA = analyze(buildLeaves(leafA), 8), let hpB = analyze(buildLeaves(leafB), 8) else {
            return XCTFail("analyze failed")
        }
        // ASSERTION (1): the two devices' analyze output DIFFERS — the ABI alone
        // does NOT protect cross-device identity.
        XCTAssertFalse(hpA.root == hpB.root && hpA.off == hpB.off)

        // GUARD path: route BOTH floats through a snap-to-Q16-grid floor (reenterQ16
        // modeled as floor(v·65536) — collapses both ULP-neighbours to ONE cell).
        let snapA = Int32((vA * 65536.0).rounded(.down))
        let snapB = Int32((vB * 65536.0).rounded(.down))
        XCTAssertEqual(snapA, snapB) // both land on K
        let sa = buildLeaves(snapA)
        let sb = buildLeaves(snapB)
        guard let hpSA = analyze(sa, 8), let hpSB = analyze(sb, 8) else {
            return XCTFail("analyze failed")
        }
        // ASSERTION (2): after the floor snap, the two devices are BYTE-IDENTICAL.
        XCTAssertEqual(hpSA.root, hpSB.root)
        XCTAssertEqual(hpSA.off, hpSB.off)
        // and the snapped leaves round-trip exactly:
        XCTAssertTrue(realRoundTrips(sa, 8))
    }

    func testWidenHalfToQ16GoldenTable() {
        // Pin the only float step feeding the lift (exact f16→f32→×2^16, clamp
        // ±2^30, no fp16 intermediate). 0x7BFF = 65504 → clamp to 2^30.
        let cases: [(bits: UInt16, q16: Int32)] = [
            (0x0001, 0), // 2^-24 subnormal → 0
            (0x03FF, 4), // largest subnormal → 3.996 → 4
            (0x0400, 4), // smallest normal
            (0x3801, 32800),
            (0x3555, 21840),
            (0xB801, -32800),
            (0x7BFF, 1_073_741_824), // max finite half → clamp to 2^30
        ]
        for c in cases {
            var out: Int32 = 0
            XCTAssertEqual(rcOK, s4_widen_half_to_q16([c.bits], 1, &out))
            XCTAssertEqual(c.q16, out, "bits=0x\(String(c.bits, radix: 16, uppercase: true))")
        }
    }

    // ══════════════════════════════════════════════════════════════════════════
    //  haar_tensor_float_test.zig — fp16 cooperative-matrix lift model
    // ══════════════════════════════════════════════════════════════════════════

    /// Saturating f16 → i32 (non-finite clamps to the i32 extreme so the test
    /// asserts SILENT byte-loss rather than crashing).
    private func satI32(_ v: Float16) -> Int32 {
        if v.isNaN { return 0 }
        if v == .infinity { return Int32.max }
        if v == -.infinity { return Int32.min }
        return Int32(v)
    }

    /// S-transform forward, identical arithmetic to `s4_haar_analyze`'s inner cell,
    /// but with every integer operand coerced through f16 — the element type a
    /// Metal 4 cooperative-matrix / tensor instruction would use. For any
    /// |value| > 2048 this silently drops low bits, so reversibility is lost.
    private func analyzeViaTensorCore(_ leaves: [Int32], _ n: Int, _ outRoot: inout [Int32], _ outOffsets: inout [Int32]) {
        var work = leaves
        var cur = n
        while cur > 1 {
            let half = cur / 2
            let outStart = half - 1
            for i in 0..<half {
                for c in 0..<3 {
                    // Operands enter the "tensor core" as f16.
                    let xf = Float16(Float(work[(2 * i) * 3 + c]))
                    let yf = Float16(Float(work[(2 * i + 1) * 3 + c]))
                    let df = xf - yf // d = x − y, in f16
                    // floor(d/2): emulate the integer lift on the float unit.
                    let halfd = (df / 2.0).rounded(.down)
                    let parentf = yf + halfd
                    work[i * 3 + c] = satI32(parentf)
                    outOffsets[(outStart + i) * 3 + c] = satI32(df)
                }
            }
            cur = half
        }
        outRoot = [work[0], work[1], work[2]]
    }

    func testTensorFloatCooperativeMatrixLiftBreaksRoundTrip() {
        // n = 2 leaves (depth 1) — the SMALLEST case; one sLift, no cascade needed.
        // Witness sits in the WORST silent-loss band: finite in f16 (< 65504) but
        // above the exact-integer ceiling 2^11 = 2048 (f16 step ≥ 4 there); each
        // channel carries an odd low bit that floor(d/2) round-trips in i32 but
        // f16 destroys.
        let leaves: [Int32] = [
            9001, 4097, 3001, // leaf0
            4099, 8195, 6005, // leaf1
        ]
        let n = 2

        // --- correct i32 kernel: round-trips exactly (control) ---
        guard let hp = analyze(leaves, Int32(n)) else { return XCTFail("analyze failed") }
        var goodLeaves = [Int32](repeating: 0, count: n * 3)
        XCTAssertEqual(rcOK, s4_haar_reconstruct(hp.root, hp.off, Int32(n), &goodLeaves))
        XCTAssertEqual(leaves, goodLeaves) // INVARIANT holds for the i32 kernel

        // --- "tensor core" port (fp16): feed through the EXACT integer inverse ---
        var badRoot = [Int32](repeating: 0, count: 3)
        var badOff = [Int32](repeating: 0, count: (n - 1) * 3)
        analyzeViaTensorCore(leaves, n, &badRoot, &badOff)

        var badLeaves = [Int32](repeating: 0, count: n * 3)
        XCTAssertEqual(rcOK, s4_haar_reconstruct(badRoot, badOff, Int32(n), &badLeaves))

        // THE ASSERTION: the fp16 tensor-core lift does NOT round-trip.
        XCTAssertNotEqual(leaves, badLeaves)
    }

    // ══════════════════════════════════════════════════════════════════════════
    //  haar_barrier_hazard_test.zig — dropped inter-level barrier model (N=8)
    //  Single-channel schedule models over the SAME exact arithmetic.
    // ══════════════════════════════════════════════════════════════════════════

    /// Reference in-place reconstruct restricted to ONE channel, mirroring the
    /// owned kernel's per-level loop (high→low). Round-trips by construction.
    private func reconstructInPlaceCh(_ root: Int32, _ offsets: [Int32], _ n: Int) -> [Int32] {
        var out = [Int32](repeating: 0, count: n)
        out[0] = root
        var cur = 1
        while cur < n {
            let outStart = cur - 1
            var i = cur
            while i > 0 {
                i -= 1
                let r = unliftPair(out[i], offsets[outStart + i])
                out[2 * i] = r.x
                out[2 * i + 1] = r.y
            }
            cur *= 2
        }
        return out
    }

    /// THE DROPPED-BARRIER SCHEDULE: level ℓ+1 reads from a SNAPSHOT captured
    /// BEFORE level ℓ published its writes.
    private func reconstructMissingBarrierCh(_ root: Int32, _ offsets: [Int32], _ n: Int) -> [Int32] {
        var out = [Int32](repeating: 0, count: n)
        out[0] = root
        var prev = out // buffer state the NEXT level will (wrongly) read
        var cur = 1
        var level = 0
        while cur < n {
            let outStart = cur - 1
            // Level 0 legitimately reads `out`; every subsequent level reads `prev`
            // — the stale, not-yet-synchronized buffer (the missing-barrier hazard).
            let src = level == 0 ? out : prev
            let snapshot = out // capture BEFORE this level writes
            var i = cur
            while i > 0 {
                i -= 1
                let r = unliftPair(src[i], offsets[outStart + i])
                out[2 * i] = r.x
                out[2 * i + 1] = r.y
            }
            prev = snapshot // next level reads THIS (pre-write) state ⇒ stale
            cur *= 2
            level += 1
        }
        return out
    }

    /// THE BARRIER-FREE-SAFE PORT: double-buffered ping-pong (read src, write dst;
    /// no aliasing so no fence needed under .untracked).
    private func reconstructPingPongCh(_ root: Int32, _ offsets: [Int32], _ n: Int) -> [Int32] {
        var a = [Int32](repeating: 0, count: n)
        var b = [Int32](repeating: 0, count: n)
        a[0] = root
        var srcIsA = true
        var cur = 1
        while cur < n {
            let outStart = cur - 1
            for i in 0..<cur {
                let node = srcIsA ? a[i] : b[i]
                let r = unliftPair(node, offsets[outStart + i])
                if srcIsA {
                    b[2 * i] = r.x
                    b[2 * i + 1] = r.y
                } else {
                    a[2 * i] = r.x
                    a[2 * i + 1] = r.y
                }
            }
            srcIsA.toggle()
            cur *= 2
        }
        return srcIsA ? a : b
    }

    /// De-interleave one channel's root + offsets after an owned analyze.
    private func analyzeChannel(_ leaves3: [[Int32]], _ c: Int) -> (rootC: Int32, offC: [Int32], expect: [Int32])? {
        let n = leaves3.count
        let leavesIL = leaves3.flatMap { $0 }
        guard let hp = analyze(leavesIL, Int32(n)) else { return nil }
        var offC = [Int32](repeating: 0, count: n - 1)
        for k in 0..<(n - 1) { offC[k] = hp.off[k * 3 + c] }
        let expect = leaves3.map { $0[c] }
        return (hp.root[c], offC, expect)
    }

    func testBarrierHazardDroppedInterLevelBarrierBreaksPingPongSurvives() {
        // Adversarial WITNESS: large mixed-sign details at every level so a stale
        // read cannot accidentally coincide with the correct value.
        let leaves3: [[Int32]] = [
            [1 << 28, -32768, 7],
            [-(1 << 28), 32767, -7],
            [0, 65536, -65535],
            [123456, -65537, 65536],
            [-1, 1, -1],
            [2147483647 >> 2, -(2147483647 >> 2), 3],
            [-3, 0, 1],
            [5, -5, 0],
        ]
        var anyChannelBroke = false
        for c in 0..<3 {
            guard let ch = analyzeChannel(leaves3, c) else { return XCTFail("analyze failed") }
            // (control) owned in-place model round-trips this channel exactly.
            XCTAssertEqual(ch.expect, reconstructInPlaceCh(ch.rootC, ch.offC, 8))
            // (2) GUARD — barrier-free-safe ping-pong port is byte-exact.
            XCTAssertEqual(ch.expect, reconstructPingPongCh(ch.rootC, ch.offC, 8))
            // (1) WITNESS — dropped inter-level barrier reads stale buffer state.
            if reconstructMissingBarrierCh(ch.rootC, ch.offC, 8) != ch.expect { anyChannelBroke = true }
        }
        // The barrier MUST be load-bearing: at least one channel's round-trip is
        // destroyed when the inter-level synchronization is dropped.
        XCTAssertTrue(anyChannelBroke)
    }

    // ══════════════════════════════════════════════════════════════════════════
    //  haar_barrier_race_test.zig — stale level-ℓ read on the ANALYZE side (n=4)
    // ══════════════════════════════════════════════════════════════════════════

    func testBarrierRaceStaleLevelReadBreaksAnalyzeCascade() {
        // n = 4 (depth 2) is the smallest case with a cross-level dependency.
        let n = 4
        let big: Int32 = 1 << 20
        let leaves: [Int32] = [
            big, 0, -3, // leaf0
            0, 11, 5, // leaf1
            big + 7, -9, 2, // leaf2
            0, 0, 0, // leaf3
        ]

        // --- correct sequential kernel: round-trips exactly (control) ---
        guard let hp = analyze(leaves, Int32(n)) else { return XCTFail("analyze failed") }
        var goodLeaves = [Int32](repeating: 0, count: n * 3)
        XCTAssertEqual(rcOK, s4_haar_reconstruct(hp.root, hp.off, Int32(n), &goodLeaves))
        XCTAssertEqual(leaves, goodLeaves)

        // --- raced ("missing barrier") analyze: level ≥ 1 reads the ORIGINAL
        // leaves (stale) instead of level-0's lifted parents ---
        var work = leaves
        var snap = [Int32](repeating: 0, count: n * 3)
        var badOff = [Int32](repeating: 0, count: (n - 1) * 3)
        var cur = n
        var level = 0
        while cur > 1 {
            if level == 0 {
                for i in 0..<(n * 3) { snap[i] = work[i] }
            } else {
                for i in 0..<(n * 3) { snap[i] = leaves[i] } // stale
            }
            let half = cur / 2
            let outStart = half - 1
            for i in 0..<half {
                for c in 0..<3 {
                    let x = snap[(2 * i) * 3 + c] // <-- stale read on level ≥ 1
                    let y = snap[(2 * i + 1) * 3 + c]
                    let d = x - y
                    work[i * 3 + c] = y + s4DivFloor(d, 2)
                    badOff[(outStart + i) * 3 + c] = d
                }
            }
            cur = half
            level += 1
        }
        let badRoot: [Int32] = [work[0], work[1], work[2]]
        var badLeaves = [Int32](repeating: 0, count: n * 3)
        XCTAssertEqual(rcOK, s4_haar_reconstruct(badRoot, badOff, Int32(n), &badLeaves))
        // THE ASSERTION: the raced cascade does NOT round-trip.
        XCTAssertNotEqual(leaves, badLeaves)
    }

    // ══════════════════════════════════════════════════════════════════════════
    //  haar_coherency_premature_read_test.zig — partial publication model (N=8)
    // ══════════════════════════════════════════════════════════════════════════

    /// Producer/consumer model of the inverse cascade across a CPU↔GPU handoff:
    /// on the level-1 handoff only `publishPrefix` of the producer's written child
    /// slots are visible; the rest keep the stale pre-dispatch value.
    private func reconstructHandoffCh(_ root: Int32, _ offsets: [Int32], _ n: Int, _ publishPrefix: Int) -> [Int32] {
        var out = [Int32](repeating: 0, count: n)
        out[0] = root
        var cur = 1
        var level = 0
        while cur < n {
            let outStart = cur - 1
            // Buffer state the consumer would see BEFORE this level's producer writes.
            let stale = out
            // The full (correct) output — "the GPU dispatch result".
            var staged = out
            var i = cur
            while i > 0 {
                i -= 1
                let r = unliftPair(out[i], offsets[outStart + i])
                staged[2 * i] = r.x
                staged[2 * i + 1] = r.y
            }
            let handoff = (level == 1)
            if handoff && publishPrefix < 2 * cur {
                // Premature read: publish only the first `publishPrefix` written
                // child slots; the rest stay stale (pre-dispatch value).
                for slot in 0..<(2 * cur) {
                    out[slot] = slot < publishPrefix ? staged[slot] : stale[slot]
                }
            } else {
                // Fully published (waitUntilCompleted / no boundary at this level).
                for slot in 0..<(2 * cur) { out[slot] = staged[slot] }
            }
            cur *= 2
            level += 1
        }
        return out
    }

    func testCoherencyPrematureReadBreaksFencedReadSurvives() {
        let leaves3: [[Int32]] = [
            [1 << 28, -32768, 7],
            [-(1 << 28), 32767, -7],
            [0, 65536, -65535],
            [123456, -65537, 65536],
            [-1, 1, -1],
            [2147483647 >> 2, -(2147483647 >> 2), 3],
            [-3, 0, 1],
            [5, -5, 0],
        ]
        let leavesIL = leaves3.flatMap { $0 }
        var anyChannelBroke = false
        for c in 0..<3 {
            guard let ch = analyzeChannel(leaves3, c) else { return XCTFail("analyze failed") }
            // CONTROL: owned kernel round-trips this channel exactly.
            guard let hp = analyze(leavesIL, 8) else { return XCTFail("analyze failed") }
            var gotOwned = [Int32](repeating: 0, count: 8 * 3)
            XCTAssertEqual(rcOK, s4_haar_reconstruct(hp.root, hp.off, 8, &gotOwned))
            for r in 0..<8 { XCTAssertEqual(ch.expect[r], gotOwned[r * 3 + c]) }

            // (2) GUARD — FULLY-published handoff (waitUntilCompleted fired): byte-exact.
            XCTAssertEqual(ch.expect, reconstructHandoffCh(ch.rootC, ch.offC, 8, 8))

            // (1) WITNESS — PREMATURE read: only slot 0 of the handoff level's
            // writes published; the rest hold stale bytes.
            if reconstructHandoffCh(ch.rootC, ch.offC, 8, 1) != ch.expect { anyChannelBroke = true }
        }
        // The completion fence MUST be load-bearing.
        XCTAssertTrue(anyChannelBroke)
    }

    // ══════════════════════════════════════════════════════════════════════════
    //  haar_inplace_intralevel_race_test.zig — intra-level order model (N=8)
    // ══════════════════════════════════════════════════════════════════════════

    /// THE NAIVE PARALLEL-EQUIVALENT ORDER (ascending i, same in-place buffer):
    /// at cur=4, i=1 writes out[2] BEFORE i=2 reads it as its node — the
    /// write-before-read corruption. Single channel.
    private func reconstructAscendingInPlaceCh(_ root: Int32, _ offsets: [Int32], _ n: Int) -> [Int32] {
        var out = [Int32](repeating: 0, count: n)
        out[0] = root
        var cur = 1
        while cur < n {
            let outStart = cur - 1
            for i in 0..<cur {
                let node = out[i] // may already be CLOBBERED by a lower i's write
                let r = unliftPair(node, offsets[outStart + i])
                out[2 * i] = r.x
                out[2 * i + 1] = r.y
            }
            cur *= 2
        }
        return out
    }

    func testIntraLevelRaceAscendingBreaksDescendingAndPingPongSurvive() {
        let leaves3: [[Int32]] = [
            [1 << 27, -32768, 7],
            [-(1 << 27), 32767, -7], // huge cross-sibling delta ⇒ parent != child by ~2^27
            [0, 65536, -65535],
            [123457, -65537, 65536], // odd ⇒ exercises floor division at the alias slot
            [-1, 1, -1],
            [1 << 26, -(1 << 26), 3],
            [-3, 0, 1],
            [5, -5, 0],
        ]
        var anyChannelBroke = false
        for c in 0..<3 {
            guard let ch = analyzeChannel(leaves3, c) else { return XCTFail("analyze failed") }
            // CONTROL — owned high→low order round-trips this channel exactly.
            XCTAssertEqual(ch.expect, reconstructInPlaceCh(ch.rootC, ch.offC, 8))
            // GUARD — ping-pong (any thread order safe) is byte-exact.
            XCTAssertEqual(ch.expect, reconstructPingPongCh(ch.rootC, ch.offC, 8))
            // WITNESS — ascending in-place (the naive parallel map) destroys the
            // round-trip via intra-level write-before-read aliasing.
            if reconstructAscendingInPlaceCh(ch.rootC, ch.offC, 8) != ch.expect { anyChannelBroke = true }
        }
        // The high→low order (equivalently, a per-i anti-dependency barrier) MUST
        // be load-bearing.
        XCTAssertTrue(anyChannelBroke)
    }

    /// Cross-check the SAME hazard through the SHIPPED export surface: the owned
    /// s4_haar_reconstruct (high→low) round-trips the full interleaved witness, so
    /// iteration order is the only variable between correct and broken.
    func testIntraLevelRaceOwnedReconstructRoundTripsWitness() {
        let leaves: [Int32] = [
            1 << 27, -32768, 7,
            -(1 << 27), 32767, -7,
            0, 65536, -65535,
            123457, -65537, 65536,
            -1, 1, -1,
            1 << 26, -(1 << 26), 3,
            -3, 0, 1,
            5, -5, 0,
        ]
        guard let hp = analyze(leaves, 8) else { return XCTFail("analyze failed") }
        var got = [Int32](repeating: 0, count: 8 * 3)
        XCTAssertEqual(rcOK, s4_haar_reconstruct(hp.root, hp.off, 8, &got))
        XCTAssertEqual(leaves, got)
    }
}
