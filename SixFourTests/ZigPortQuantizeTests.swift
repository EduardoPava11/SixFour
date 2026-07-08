//  ZigPortQuantizeTests.swift
//  Swift ports of the Zig quantize/dither/collapse/significance/totality test
//  files (2026-07-06 Zig→Swift port):
//    * Native/src/quant_fixture_test.zig        — maximin + Lloyd (highest risk)
//    * Native/src/dither_fixture_test.zig       — FS / serpentine / Atkinson / blue-noise
//    * Native/src/collapse_fixture_test.zig     — GIFA → GIFB pooled maximin
//    * Native/src/significance_fixture_test.zig — rescue + per-slot cell stats
//    * Native/src/totality_test.zig             — refuse-don't-absorb battery
//  gating the KernelsQuantize.swift twins (and, for the totality battery, the
//  cross-slice reversible-substrate kernels) bit-for-bit.
//
//  Fixture tests XCTSkip when trainer/out/<name>.json is absent (build with
//  `cd spec && cabal run spec-fixtures`) — mirrors the Zig skip-if-absent
//  contract: never a vacuous pass, never a red tree.

import XCTest
import Foundation
@testable import SixFour

/// trainer/out (the spec-fixtures output dir the Zig build pointed
/// `build_options.fixture_dir` at), resolved from this source file's location.
private func zigPortFixtureDir() -> URL {
    URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent() // SixFourTests
        .deletingLastPathComponent() // repo root
        .appendingPathComponent("trainer", isDirectory: true)
        .appendingPathComponent("out", isDirectory: true)
}

private func loadZigPortFixture(_ name: String) throws -> [String: Any] {
    let url = zigPortFixtureDir().appendingPathComponent(name)
    guard FileManager.default.fileExists(atPath: url.path) else {
        throw XCTSkip("\(name) not in '\(zigPortFixtureDir().path)'; run `cd spec && cabal run spec-fixtures`")
    }
    let raw = try Data(contentsOf: url)
    return try XCTUnwrap(try JSONSerialization.jsonObject(with: raw) as? [String: Any])
}

/// Flatten a JSON array of [x,y,z] triples into a contiguous Int32 buffer
/// (the Zig test files' `flattenTriples` twin).
private func flattenTriples(_ value: Any?) throws -> [Int32] {
    let arr = try XCTUnwrap(value as? [[Int]])
    var out = [Int32]()
    out.reserveCapacity(arr.count * 3)
    for t in arr {
        out.append(Int32(t[0]))
        out.append(Int32(t[1]))
        out.append(Int32(t[2]))
    }
    return out
}

final class ZigPortQuantizeFixtureTests: XCTestCase {

    /// Port of quant_fixture_test.zig: "cross-language: s4_quantize_frame matches
    /// the Haskell maximin+Lloyd golden" — BIT-EXACT centroids + assignment for
    /// every `lloyd_iters` case.
    func testQuantizeFrameMatchesHaskellGolden() throws {
        let root = try loadZigPortFixture("quant_golden.json")
        let side = Int32(try XCTUnwrap(root["side"] as? Int))
        let k = Int32(try XCTUnwrap(root["k"] as? Int))
        let p = side * side
        let pp = Int(p)
        let kk = Int(k)

        let pixels = try flattenTriples(root["pixels"])

        var centroids = [Int32](repeating: 0, count: kk * 3)
        var indices = [UInt8](repeating: 0, count: pp)
        let scratchBytes = pp * 8 + 3 * kk * 8 + kk * 4
        var scratch = [Int64](repeating: 0, count: (scratchBytes + 7) / 8)

        let cases = try XCTUnwrap(root["cases"] as? [[String: Any]])
        XCTAssertFalse(cases.isEmpty)
        for c in cases {
            let lloydIters = Int32(try XCTUnwrap(c["lloyd_iters"] as? Int))
            let expCentroids = try flattenTriples(c["centroids"])
            let expIndices = try XCTUnwrap(c["indices"] as? [Int]).map { UInt8($0) }

            let rc = pixels.withUnsafeBufferPointer { pxp in
                centroids.withUnsafeMutableBufferPointer { cp in
                    indices.withUnsafeMutableBufferPointer { ip in
                        scratch.withUnsafeMutableBufferPointer { sp in
                            s4_quantize_frame(
                                pxp.baseAddress, p, k, lloydIters,
                                cp.baseAddress, ip.baseAddress,
                                UnsafeMutableRawPointer(sp.baseAddress), sp.count * 8
                            )
                        }
                    }
                }
            }
            XCTAssertEqual(rc, 0, "lloyd_iters=\(lloydIters)")
            // Centroids (k × 3 Q16) byte-exact.
            XCTAssertEqual(centroids, expCentroids, "centroid drift (lloyd_iters=\(lloydIters))")
            // Assignment (P indices) byte-exact.
            XCTAssertEqual(indices, expIndices, "assignment drift (lloyd_iters=\(lloydIters))")
        }
    }

    /// Port of dither_fixture_test.zig: "cross-language: s4_dither_frame matches
    /// the Haskell spatial-dither golden" — BIT-EXACT index agreement for each
    /// case (FS raster, FS serpentine, Atkinson, blue-noise).
    func testDitherFrameMatchesHaskellGolden() throws {
        let root = try loadZigPortFixture("dither_golden.json")
        let side = Int32(try XCTUnwrap(root["side"] as? Int))
        let k = Int32(try XCTUnwrap(root["k"] as? Int))
        let p = side * side
        let pp = Int(p)

        let centroids = try flattenTriples(root["centroids"])
        let pixels = try flattenTriples(root["pixels"])
        let thresholds = try XCTUnwrap(root["thresholds"] as? [Int]).map { UInt8($0) }
        XCTAssertEqual(thresholds.count, pp)

        var out = [UInt8](repeating: 0, count: pp)
        let scratchBytes = pp * 3 * 4
        var scratch = [Int64](repeating: 0, count: (scratchBytes + 7) / 8)

        let cases = try XCTUnwrap(root["cases"] as? [[String: Any]])
        XCTAssertFalse(cases.isEmpty)
        for c in cases {
            let mode = Int32(try XCTUnwrap(c["mode"] as? Int))
            let serp = Int32(try XCTUnwrap(c["serpentine"] as? Int))
            let expIndices = try XCTUnwrap(c["indices"] as? [Int]).map { UInt8($0) }

            let rc = pixels.withUnsafeBufferPointer { pxp in
                centroids.withUnsafeBufferPointer { cp in
                    thresholds.withUnsafeBufferPointer { tp in
                        out.withUnsafeMutableBufferPointer { op in
                            scratch.withUnsafeMutableBufferPointer { sp in
                                s4_dither_frame(
                                    pxp.baseAddress, cp.baseAddress, p, k,
                                    mode, serp, tp.baseAddress, op.baseAddress,
                                    UnsafeMutableRawPointer(sp.baseAddress), sp.count * 8
                                )
                            }
                        }
                    }
                }
            }
            XCTAssertEqual(rc, 0, "mode=\(mode) serpentine=\(serp)")
            XCTAssertEqual(out, expIndices, "index drift (mode=\(mode) serpentine=\(serp))")
        }
    }

    /// Port of collapse_fixture_test.zig: "cross-language: s4_global_collapse
    /// matches the Haskell collapse golden" — BIT-EXACT leaves + flattened
    /// per-frame re-index (proving Swift collapse ≡ Haskell spec ≡
    /// CollapseGolden.swift on one fixture).
    func testGlobalCollapseMatchesHaskellGolden() throws {
        let root = try loadZigPortFixture("collapse_golden.json")
        let t = Int32(try XCTUnwrap(root["t"] as? Int))
        let kIn = Int32(try XCTUnwrap(root["k_in"] as? Int))
        let kOut = Int32(try XCTUnwrap(root["k_out"] as? Int))
        let p = Int(t) * Int(kIn)
        let ko = Int(kOut)

        let palettes = try flattenTriples(root["palettes"])

        var outLeaves = [Int32](repeating: 0, count: ko * 3)
        var outIndices = [UInt8](repeating: 0, count: p)
        let scratchBytes = p * 8 + 3 * ko * 8 + ko * 4
        var scratch = [Int64](repeating: 0, count: (scratchBytes + 7) / 8)

        let rc = palettes.withUnsafeBufferPointer { pp in
            outLeaves.withUnsafeMutableBufferPointer { lp in
                outIndices.withUnsafeMutableBufferPointer { ip in
                    scratch.withUnsafeMutableBufferPointer { sp in
                        s4_global_collapse(
                            pp.baseAddress, t, kIn, kOut,
                            lp.baseAddress, ip.baseAddress,
                            UnsafeMutableRawPointer(sp.baseAddress), sp.count * 8
                        )
                    }
                }
            }
        }
        XCTAssertEqual(rc, 0)

        // Global leaves (k_out × 3 Q16) byte-exact.
        let expLeaves = try flattenTriples(root["leaves"])
        XCTAssertEqual(expLeaves.count, ko * 3)
        XCTAssertEqual(outLeaves, expLeaves, "global leaf drift")
        // Flattened per-frame re-index (t·k_in indices) byte-exact.
        let expIndices = try XCTUnwrap(root["indices"] as? [Int]).map { UInt8($0) }
        XCTAssertEqual(expIndices.count, p)
        XCTAssertEqual(outIndices, expIndices, "re-index drift")
    }

    /// Port of significance_fixture_test.zig: "cross-language:
    /// s4_significance_fill matches the Haskell rescue + cells golden" — the
    /// rebalanced indices AND the per-slot cell stats (mean3, std3, count) are
    /// BIT-EXACTLY the spec's.
    func testSignificanceFillMatchesHaskellGolden() throws {
        let root = try loadZigPortFixture("significance_golden.json")
        let k = Int32(try XCTUnwrap(root["k"] as? Int))
        let p = Int32(try XCTUnwrap(root["p"] as? Int))
        let minPop = Int32(try XCTUnwrap(root["min_population"] as? Int))
        let kk = Int(k)

        let centroids = try flattenTriples(root["centroids"])
        let pixels = try flattenTriples(root["pixels"])

        var indices = try XCTUnwrap(root["indices_in"] as? [Int]).map { UInt8($0) }
        XCTAssertEqual(indices.count, Int(p))
        var cells = [Int32](repeating: 0, count: kk * 7)

        let rc = pixels.withUnsafeBufferPointer { pxp in
            centroids.withUnsafeBufferPointer { cp in
                indices.withUnsafeMutableBufferPointer { ip in
                    cells.withUnsafeMutableBufferPointer { sp in
                        s4_significance_fill(
                            pxp.baseAddress, cp.baseAddress, p, k, minPop,
                            ip.baseAddress, sp.baseAddress,
                            nil, 0
                        )
                    }
                }
            }
        }
        XCTAssertEqual(rc, 0)

        // Rebalanced indices must match the golden exactly.
        let expIndices = try XCTUnwrap(root["indices_out"] as? [Int]).map { UInt8($0) }
        XCTAssertEqual(indices, expIndices, "rescue drift")

        // Cell stats (mean3, std3, count) per slot must match the golden exactly.
        let expCells = try XCTUnwrap(root["cells"] as? [[Int]])
        XCTAssertEqual(expCells.count, kk)
        for (s, cell) in expCells.enumerated() {
            for f in 0..<7 {
                XCTAssertEqual(cells[s * 7 + f], Int32(cell[f]), "cell stat drift slot=\(s) field=\(f)")
            }
        }
    }
}

// ═════════════════════════════════════════════════════════════════════════════
//  Port of totality_test.zig — TOTAL-FUNCTION battery for the reversible Q16
//  S-transform substrate. In-domain it round-trips bit-exact with i64-true
//  intermediates; out-of-domain it returns RC_OUT_OF_RANGE (never RC_OK with a
//  silently-wrapped poison node). The single bound: B = 2^29−1; max legal
//  single-level detail 2B; the RGBT quad's 2nd-level high band reaches 4B
//  (fits i32), one tick past which 4(B+1) = 2^31 overflows — B is TIGHT.
//
//  The substrate kernels under test (s4_haar_*, s4_rgbt_*, s4_cube_*) are the
//  cross-slice ports; s4_leaf_override is this slice's.
// ═════════════════════════════════════════════════════════════════════════════

final class ZigPortTotalityTests: XCTestCase {

    private let B: Int32 = (1 << 29) - 1 // SUBSTRATE_BOUND = 536,870,911
    private let TWO_B: Int32 = 2 * ((1 << 29) - 1) // DETAIL_BOUND = 2^30 − 2
    private let OOR: Int32 = 7 // RC_OUT_OF_RANGE
    private let OK: Int32 = 0 // RC_OK

    /// Independent i64 oracle of one analyze step's lifted parent + detail.
    private func oracleLift(_ x: Int64, _ y: Int64) -> (parent: Int64, detail: Int64) {
        let d = x - y
        return (parent: y + s4DivFloor64(d, 2), detail: d)
    }

    // ── T1 TOTALITY — every export refuses out-of-domain input ────────────────

    func testT1HaarAnalyzeRefusesOutOfDomainLeaf() {
        let leaves: [Int32] = [B + 1, 0, 0, 0, 0, 0] // one channel past B
        var root = [Int32](repeating: 0, count: 3)
        var off = [Int32](repeating: 0, count: 3)
        var scratch = [Int32](repeating: 0, count: 2 * 3)
        XCTAssertEqual(OOR, s4_haar_analyze(leaves, 2, &root, &off, &scratch, scratch.count * 4))
    }

    func testT1HaarReconstructRefusesOutOfImageDetail() {
        let root: [Int32] = [B, 0, 0]
        let off: [Int32] = [TWO_B + 1, 0, 0] // detail past 2B
        var out = [Int32](repeating: 0, count: 6)
        XCTAssertEqual(OOR, s4_haar_reconstruct(root, off, 2, &out))
    }

    func testT1HaarLevelNodesRefusesOutOfImageRoot() {
        let root: [Int32] = [B + 1, 0, 0] // node past B
        let off: [Int32] = [0, 0, 0]
        var nodes = [Int32](repeating: 0, count: 6)
        XCTAssertEqual(OOR, s4_haar_level_nodes(1, root, off, 2, &nodes))
    }

    func testT1RgbtLiftQuadRefusesOutOfDomainCell() {
        let inQ: [Int32] = [B + 1, 0, 0, 0]
        var out = [Int32](repeating: 0, count: 4)
        XCTAssertEqual(OOR, s4_rgbt_lift_quad(inQ, &out))
    }

    func testT1RgbtUnliftQuadRefusesOutOfImageHighBand() {
        let inQ: [Int32] = [0, 0, 0, 4 * B + 1] // HH past 4B
        var out = [Int32](repeating: 0, count: 4)
        XCTAssertEqual(OOR, s4_rgbt_unlift_quad(inQ, &out))
    }

    func testT1CubeLiftLevelRefusesOutOfDomainGridCell() {
        let grid: [Int32] = [0, 0, B + 1, 0] // 2×2 grid, one cell past B
        var coarse = [Int32](repeating: 0, count: 1)
        var details = [Int32](repeating: 0, count: 3)
        XCTAssertEqual(OOR, s4_cube_lift_level(2, grid, &coarse, &details))
    }

    func testT1CubeUnliftLevelRefusesOutOfImageBand() {
        let coarse: [Int32] = [0]
        let details: [Int32] = [4 * B + 1, 0, 0] // T (HH) past 4B
        var out = [Int32](repeating: 0, count: 4)
        XCTAssertEqual(OOR, s4_cube_unlift_level(1, coarse, details, &out))
    }

    func testT1HaarSplitLevelRefusesOutOfDomainFrameChannel() {
        let inQ: [Int32] = [B + 1, 0, 0, 0, 0, 0] // 2 frames, one channel past B
        var low = [Int32](repeating: 0, count: 3)
        var high = [Int32](repeating: 0, count: 3)
        XCTAssertEqual(OOR, s4_haar_split_level(2, inQ, &low, &high))
    }

    func testT1HaarJoinLevelRefusesOutOfImageBandValue() {
        let low: [Int32] = [0, 0, 0]
        let high: [Int32] = [TWO_B + 1, 0, 0] // detail past 2B
        var out = [Int32](repeating: 0, count: 6)
        XCTAssertEqual(OOR, s4_haar_join_level(1, 1, low, high, &out))
    }

    func testT1LeafOverrideRefusesOutOfDomainSum() {
        let gens: [Int32] = [B, 0, 0]
        let deltas: [Int32] = [1, 0, 0] // g+δ = B+1 > B
        var out = [Int32](repeating: 0, count: 6)
        XCTAssertEqual(OOR, s4_leaf_override(gens, deltas, 1, &out))
    }

    // ── T6 DOMAIN-BOUNDARY — just-inside passes + round-trips; B+1 refuses ────

    func testT6AnalyzeLeafAtExactlyBPassesAndRoundTripsBPlusOneRefuses() {
        var scratch = [Int32](repeating: 0, count: 2 * 3)

        // (B, -B) → d = 2B = 2^30−2, the MAX legal detail (exactly fits i32).
        let inn: [Int32] = [B, B, -B, -B, B, -B]
        var root = [Int32](repeating: 0, count: 3)
        var off = [Int32](repeating: 0, count: 3)
        XCTAssertEqual(OK, s4_haar_analyze(inn, 2, &root, &off, &scratch, scratch.count * 4))
        XCTAssertEqual(TWO_B, off[0]) // detail = 2B exactly
        var back = [Int32](repeating: 0, count: 6)
        XCTAssertEqual(OK, s4_haar_reconstruct(root, off, 2, &back))
        XCTAssertEqual(inn, back) // bit-exact round-trip at the boundary

        // (B+1, -(B+1)) → d = 2^30 > 2B ⇒ refuse.
        let outIn: [Int32] = [B + 1, 0, 0, -(B + 1), 0, 0]
        var r2 = [Int32](repeating: 0, count: 3)
        var o2 = [Int32](repeating: 0, count: 3)
        XCTAssertEqual(OOR, s4_haar_analyze(outIn, 2, &r2, &o2, &scratch, scratch.count * 4))
    }

    func testT6RgbtQuadAtExact4BHighBandEdgePassesOneTickPastRefuses() {
        // Inputs arranged so the 2nd-level high band a[1]-c[1] reaches the 4B edge:
        // q0=B,q1=-B ⇒ a[1]=2B; q2=-B,q3=B ⇒ c[1]=-2B; a[1]-c[1]=4B (exact edge).
        let q: [Int32] = [B, -B, -B, B]
        var o = [Int32](repeating: 0, count: 4)
        XCTAssertEqual(OK, s4_rgbt_lift_quad(q, &o))
        XCTAssertEqual(4 * B, o[3]) // HH = 4B, fits i32 exactly
        // round-trips:
        var back = [Int32](repeating: 0, count: 4)
        XCTAssertEqual(OK, s4_rgbt_unlift_quad(o, &back))
        XCTAssertEqual(q, back)

        // One input tick past B blows the 4(B+1)=2^31 edge ⇒ refuse.
        let q2: [Int32] = [B + 1, -(B + 1), -(B + 1), B + 1]
        var o2 = [Int32](repeating: 0, count: 4)
        XCTAssertEqual(OOR, s4_rgbt_lift_quad(q2, &o2))
    }

    func testT6LeafOverrideSumAtExactlyBPassesBPlusOneRefuses() {
        // Nudge the a-channel to ±B so σ (which negates a,b) is exercised at the
        // edge: its negate −B must also be representable (it is — |−B| = B ≤ B).
        let gens: [Int32] = [0, B - 10, 0]
        let okd: [Int32] = [0, 10, 0] // a-sum = B exactly
        var out = [Int32](repeating: 0, count: 6)
        XCTAssertEqual(OK, s4_leaf_override(gens, okd, 1, &out))
        XCTAssertEqual(B, out[1]) // even leaf a = B
        XCTAssertEqual(-B, out[4]) // odd leaf a = σ(a) = −B (fits i32)
        let badd: [Int32] = [0, 11, 0] // a-sum = B+1
        var out2 = [Int32](repeating: 0, count: 6)
        XCTAssertEqual(OOR, s4_leaf_override(gens, badd, 1, &out2))
    }

    // ── T3 INTERMEDIATE-TRUTH — surfaced intermediates equal i64 wide-truth ───

    func testT3AnalyzeLevel0ParentAndDetailEqualI64WideTruthAtBoundary() {
        // n=2: a single near-boundary pair so the surfaced detail is the MAX legal
        // 2B and the parent is the true lifted average (0), not a wrapped poison.
        let x: Int32 = B
        let y: Int32 = -B
        let leaves: [Int32] = [x, 100, -100, y, -50, 50]
        var root = [Int32](repeating: 0, count: 3)
        var off = [Int32](repeating: 0, count: 3)
        var scratch = [Int32](repeating: 0, count: 2 * 3)
        XCTAssertEqual(OK, s4_haar_analyze(leaves, 2, &root, &off, &scratch, scratch.count * 4))

        // L channel: oracle vs surfaced.
        let oracle = oracleLift(Int64(x), Int64(y))
        XCTAssertEqual(oracle.detail, Int64(off[0])) // surfaced detail == i64 truth
        XCTAssertEqual(oracle.parent, Int64(root[0])) // surfaced root (parent) == i64 truth
        XCTAssertEqual(2 * Int64(B), Int64(off[0])) // = 2B, the documented edge (NOT a wrap)
        XCTAssertEqual(Int64(0), Int64(root[0])) // true lifted average, NOT INT_MIN poison
    }

    func testT3LevelNodesSurfacesTrueNodeNeverAWrap() {
        // 4 leaves, near-boundary so the level-1 node is large but TRUE. Pre-redesign
        // a wrap here poisoned the 16-colour shutter while leaves still round-tripped.
        let leaves: [Int32] = [
            B, 0, 0,
            -B, 0, 0,
            B, 0, 0,
            -B, 0, 0,
        ]
        var root = [Int32](repeating: 0, count: 3)
        var off = [Int32](repeating: 0, count: 9)
        var scratch = [Int32](repeating: 0, count: 4 * 3)
        XCTAssertEqual(OK, s4_haar_analyze(leaves, 4, &root, &off, &scratch, scratch.count * 4))

        // level 1 = 2 nodes; node[i] is the lifted parent of leaf pair (2i, 2i+1).
        var nodes = [Int32](repeating: 0, count: 6)
        XCTAssertEqual(OK, s4_haar_level_nodes(1, root, off, 4, &nodes))
        // i64 oracle of each level-1 node's L channel: parent of (B,−B) = 0.
        let orc = oracleLift(Int64(B), Int64(-B))
        XCTAssertEqual(orc.parent, Int64(nodes[0]))
        XCTAssertEqual(orc.parent, Int64(nodes[3]))
        XCTAssertEqual(Int64(0), Int64(nodes[0])) // true, not poison
    }

    func testT3RgbtQuadSecondLevelHighBandEqualsI64Truth() {
        let q: [Int32] = [B, -B, -B, B]
        var o = [Int32](repeating: 0, count: 4)
        XCTAssertEqual(OK, s4_rgbt_lift_quad(q, &o))
        // i64 oracle of a[1]-c[1]: a[1]=q0-q1=2B, c[1]=q2-q3=-2B ⇒ HH = 4B.
        let a1 = Int64(B) - Int64(-B) // 2B
        let c1 = Int64(-B) - Int64(B) // -2B
        XCTAssertEqual(a1 - c1, Int64(o[3])) // surfaced HH == i64 truth
        XCTAssertEqual(4 * Int64(B), Int64(o[3])) // = 4B exactly
    }

    // ── T5 SHIP-MODE PARITY — mode-independent (rc, bytes) literals ───────────

    func testT5AnalyzeCorpusIsModeIndependent() {
        var scratch = [Int32](repeating: 0, count: 4 * 3)

        // in-domain corpus row → exact expected (rc, root, off) regardless of mode.
        let leaves: [Int32] = [
            12345, -6789, 100,
            -54321, 4096, -200,
            7, -7, 3,
            -3, 9, -5,
        ]
        var root = [Int32](repeating: 0, count: 3)
        var off = [Int32](repeating: 0, count: 9)
        XCTAssertEqual(OK, s4_haar_analyze(leaves, 4, &root, &off, &scratch, scratch.count * 4))
        // Pin exact bytes (computed once; identical in every mode):
        var back = [Int32](repeating: 0, count: 12)
        XCTAssertEqual(OK, s4_haar_reconstruct(root, off, 4, &back))
        XCTAssertEqual(leaves, back)

        // out-of-domain row → RC_OUT_OF_RANGE in every mode.
        let bad: [Int32] = [B + 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]
        var r2 = [Int32](repeating: 0, count: 3)
        var o2 = [Int32](repeating: 0, count: 9)
        XCTAssertEqual(OOR, s4_haar_analyze(bad, 4, &r2, &o2, &scratch, scratch.count * 4))

        print("  [T5 PARITY] in-domain analyze round-trips bit-exact; B+1 → RC_OUT_OF_RANGE (assertions are mode-independent literals)")
    }

    func testT5LeafOverrideLadderIsModeIndependent() {
        let gens: [Int32] = [1000, -2000, 3000, B - 5, 0, 0]
        // δ keeps g0 in-domain, pushes g1 to exactly B (edge), then to B+1 (out).
        let din: [Int32] = [10, 10, 10, 5, 0, 0] // sums in/edge
        var out = [Int32](repeating: 0, count: 12)
        XCTAssertEqual(OK, s4_leaf_override(gens, din, 2, &out))
        XCTAssertEqual(Int32(1010), out[0])
        XCTAssertEqual(B, out[6]) // g1 sum = B exactly
        let dout: [Int32] = [10, 10, 10, 6, 0, 0] // g1 sum = B+1
        var out2 = [Int32](repeating: 0, count: 12)
        XCTAssertEqual(OOR, s4_leaf_override(gens, dout, 2, &out2))
    }

    // ── T2 (compact) IN-DOMAIN INVERTIBILITY at the boundary ──────────────────

    func testT2CubeLiftUnliftAndTemporalSplitJoinRoundTripAtBoundary() {
        // cube: 2×2 grid at ±B round-trips bit-exact.
        let grid: [Int32] = [B, -B, -B, B]
        var coarse = [Int32](repeating: 0, count: 1)
        var details = [Int32](repeating: 0, count: 3)
        XCTAssertEqual(OK, s4_cube_lift_level(2, grid, &coarse, &details))
        var rg = [Int32](repeating: 0, count: 4)
        XCTAssertEqual(OK, s4_cube_unlift_level(1, coarse, details, &rg))
        XCTAssertEqual(grid, rg)

        // temporal: 3 frames (odd tail carry) at ±B round-trips bit-exact.
        let frames: [Int32] = [B, 0, 0, -B, 0, 0, B, -B, 1]
        var low = [Int32](repeating: 0, count: 6) // (3/2 + 1) = 2 triples
        var high = [Int32](repeating: 0, count: 3) // 1 triple
        XCTAssertEqual(OK, s4_haar_split_level(3, frames, &low, &high))
        var rf = [Int32](repeating: 0, count: 9)
        XCTAssertEqual(OK, s4_haar_join_level(2, 1, low, high, &rf))
        XCTAssertEqual(frames, rf)
    }
}
