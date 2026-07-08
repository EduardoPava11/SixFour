//  ZigPortV21Tests.swift
//  Swift port of the V2.1 cross-language fixture tests (2026-07-06):
//    Native/src/v21_collapse_fixture_test.zig
//    Native/src/v21_counts_fixture_test.zig
//    Native/src/v21_hist_fixture_test.zig
//    Native/src/v21_mode_relative_fixture_test.zig
//    Native/src/v21_octant_fixture_test.zig
//    Native/src/v21_opponent_fixture_test.zig
//    Native/src/v21_palette_delta_fixture_test.zig
//    Native/src/v21_soft_hist_fixture_test.zig
//    Native/src/v21_wdist1d_fixture_test.zig
//  plus the inline transport/pushforward golden from kernels.zig (the only
//  coverage of s4_v21_transport / s4_v21_pushforward; inline literals, no fixture).
//
//  The fixtures are the spec-fixtures JSON goldens in trainer/out (the SAME
//  files the Zig tests read via build_options.fixture_dir, default
//  Native/../trainer/out). Skip-if-absent, exactly like the Zig
//  `error.SkipZigTest` path: build with `cd spec && cabal run spec-fixtures`.

import XCTest
@testable import SixFour

final class ZigPortV21Tests: XCTestCase {

    // Local copies of the kernels.zig RC_* codes the ported tests assert on.
    private let rcOK: Int32 = 0
    private let rcNullPtr: Int32 = 1
    private let rcOutOfRange: Int32 = 7

    // MARK: - Fixture loading (the readFileAlloc + std.json twin)

    /// trainer/out resolved from this source file's location (the Zig tests get
    /// the same directory baked in as `build_options.fixture_dir`).
    private func fixtureURL(_ name: String) -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // SixFourTests/
            .deletingLastPathComponent() // repo root
            .appendingPathComponent("trainer")
            .appendingPathComponent("out")
            .appendingPathComponent(name)
    }

    /// Load + parse a JSON golden, or skip the test when it is absent
    /// (the Zig `error.SkipZigTest` path).
    private func loadFixture(_ name: String) throws -> [String: Any] {
        let url = fixtureURL(name)
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw XCTSkip("\(name) not in 'trainer/out'; run `cd spec && cabal run spec-fixtures`")
        }
        let data = try Data(contentsOf: url)
        let obj = try JSONSerialization.jsonObject(with: data)
        return try XCTUnwrap(obj as? [String: Any], "\(name): root is not a JSON object")
    }

    private func int(_ root: [String: Any], _ key: String) throws -> Int {
        try XCTUnwrap(root[key] as? NSNumber, "missing/non-numeric '\(key)'").intValue
    }

    private func ints(_ any: Any?, _ what: String) throws -> [Int] {
        let arr = try XCTUnwrap(any as? [Any], "missing array '\(what)'")
        return try arr.map { try XCTUnwrap($0 as? NSNumber, "non-numeric element in '\(what)'").intValue }
    }

    private func intRows(_ any: Any?, _ what: String) throws -> [[Int]] {
        let arr = try XCTUnwrap(any as? [Any], "missing array-of-arrays '\(what)'")
        return try arr.map { try ints($0, what) }
    }

    /// Flatten rows of ints into [total*nl] Int32, row-major (the Zig `flatten`).
    private func flatten32(_ rows: [[Int]]) -> [Int32] {
        rows.flatMap { $0.map { Int32($0) } }
    }

    // MARK: - v21_collapse_fixture_test.zig

    /// Cross-language: s4_v21_collapse matches the Haskell V2.1 collapse golden
    /// (SixFour.Spec.V21Field.collapseQ16; argmin energy, lowest-index tie-break).
    func testCollapseMatchesHaskellGolden() throws {
        let root = try loadFixture("v21_collapse_golden.json")
        let p = try int(root, "p")
        let nLevels = try int(root, "n_levels")
        let curves = flatten32(try intRows(root["curves"], "curves"))
        let collapsed = try ints(root["collapsed"], "collapsed")

        let total = p * 3
        var out = [UInt8](repeating: 0, count: total)
        XCTAssertEqual(rcOK, s4_v21_collapse(curves, Int32(p), Int32(nLevels), &out))

        // Bit-exact: every collapsed level the kernel produces equals the spec's.
        XCTAssertEqual(collapsed.map { UInt8($0) }, out)
    }

    // MARK: - v21_counts_fixture_test.zig

    /// argmax over a Q16 mass slice, lowest index winning ties (strict >).
    private func argmaxLowest(_ xs: [Int32]) -> Int {
        var bestI = 0
        var bestV = xs[0]
        for i in 1..<xs.count where xs[i] > bestV {
            bestV = xs[i]
            bestI = i
        }
        return bestI
    }

    /// Cross-language: s4_v21_counts_to_energy matches the Haskell captured-bin golden + duality.
    /// (1) energy curves bit-exact; (2) collapse of the energy == the mode; (3) the existing
    /// s4_board_counts_to_mass_q16 argmaxes to the same mode (order-duality with the mass face).
    func testCountsToEnergyMatchesHaskellGoldenAndDuality() throws {
        let root = try loadFixture("v21_counts_golden.json")
        let p = try int(root, "p")
        let nLevels = try int(root, "n_levels")
        let counts = flatten32(try intRows(root["counts"], "counts"))
        let wantEnergy = flatten32(try intRows(root["energy"], "energy"))
        let modes = try ints(root["modes"], "modes")

        let nl = nLevels
        let ncurves = p * 3

        // (1) energy curves bit-exact.
        var energy = [Int32](repeating: 0, count: ncurves * nl)
        XCTAssertEqual(rcOK, s4_v21_counts_to_energy(counts, Int32(p), Int32(nLevels), &energy))
        XCTAssertEqual(wantEnergy, energy)

        // (2) collapse of the energy == the mode (the captured byte is the most-observed value).
        var collapsed = [UInt8](repeating: 0, count: ncurves)
        XCTAssertEqual(rcOK, s4_v21_collapse(energy, Int32(p), Int32(nLevels), &collapsed))
        XCTAssertEqual(modes.map { UInt8($0) }, collapsed)

        // (3) RESPECT THE ALGO: the existing s4_board_counts_to_mass_q16 (the mass face) argmaxes
        //     to the same mode -> the V2.1 energy face and the shipped mass kernel are order-dual.
        var mass = [Int32](repeating: 0, count: nl)
        for c in 0..<ncurves {
            var total: Int32 = 0
            for l in 0..<nl { total += counts[c * nl + l] }
            let rc = counts.withUnsafeBufferPointer { cb in
                s4_board_counts_to_mass_q16(cb.baseAddress! + c * nl, Int32(nLevels), total, &mass)
            }
            XCTAssertEqual(rcOK, rc)
            XCTAssertEqual(modes[c], argmaxLowest(mass), "curve \(c): mass-face argmax != mode")
        }
    }

    // MARK: - v21_hist_fixture_test.zig

    /// Cross-language: s4_v21_accumulate_hist matches the Haskell make_bins histogram golden
    /// (SixFour.Spec.V21Field.accumulateHist; box-decimation value counting).
    func testAccumulateHistMatchesHaskellGolden() throws {
        let root = try loadFixture("v21_hist_golden.json")
        let fx = try int(root, "fx"), fy = try int(root, "fy"), ft = try int(root, "ft")
        let dx = try int(root, "dx"), dy = try int(root, "dy"), dt = try int(root, "dt")
        let nLevels = try int(root, "n_levels")
        let fine = try ints(root["fine"], "fine").map { UInt8($0) }
        let wantCounts = try ints(root["counts"], "counts").map { Int32($0) }

        var outCounts = [Int32](repeating: 0, count: wantCounts.count)
        let rc = s4_v21_accumulate_hist(
            fine, Int32(fx), Int32(fy), Int32(ft),
            Int32(dx), Int32(dy), Int32(dt), Int32(nLevels), &outCounts)
        XCTAssertEqual(rcOK, rc)
        XCTAssertEqual(wantCounts, outCounts)
    }

    // MARK: - v21_mode_relative_fixture_test.zig

    /// Cross-language: s4_v21_centered_energy / mode_relative / anchor_at match the Haskell golden,
    /// AND the anchor reproduces the centered curve (field + GIF reconstruct the field).
    func testCenteredModeRelativeAnchorMatchHaskellGolden() throws {
        let root = try loadFixture("v21_mode_relative_golden.json")
        let p = try int(root, "p")
        let nLevels = try int(root, "n_levels")
        let total = p * 3
        let nl = nLevels

        let curves = flatten32(try intRows(root["curves"], "curves"))
        let wantCentered = flatten32(try intRows(root["centered"], "centered"))
        let wantRel = flatten32(try intRows(root["mode_relative"], "mode_relative"))
        let wantAnchored = flatten32(try intRows(root["anchored"], "anchored"))
        let modes = try ints(root["modes"], "modes").map { Int32($0) }
        XCTAssertEqual(total, modes.count)

        // 1) centered energy == spec.
        var centered = [Int32](repeating: 0, count: total * nl)
        XCTAssertEqual(rcOK, s4_v21_centered_energy(curves, Int32(p), Int32(nLevels), &centered))
        XCTAssertEqual(wantCentered, centered)

        // 2) mode-relative == spec.
        var rel = [Int32](repeating: 0, count: total * nl)
        XCTAssertEqual(rcOK, s4_v21_mode_relative(curves, Int32(p), Int32(nLevels), &rel))
        XCTAssertEqual(wantRel, rel)

        // 3) anchor(mode_relative, modes) == the golden anchored == the centered curve.
        var anchored = [Int32](repeating: 0, count: total * nl)
        XCTAssertEqual(rcOK, s4_v21_anchor_at(rel, modes, Int32(p), Int32(nLevels), &anchored))
        XCTAssertEqual(wantAnchored, anchored)
        XCTAssertEqual(wantCentered, anchored) // field + GIF reconstruct the field
    }

    // MARK: - v21_octant_fixture_test.zig

    /// Cross-language: s4_v21_octant_lift_curve matches the Haskell V2.1 octant golden
    /// (the per-level driver over the gated s4_octant_lift edge).
    func testOctantLiftCurveMatchesHaskellGolden() throws {
        let root = try loadFixture("v21_octant_golden.json")
        let nLevels = try int(root, "n_levels")
        let cellRows = try intRows(root["cells"], "cells")
        let wantCoarse = try ints(root["coarse"], "coarse").map { Int32($0) }
        let residualRows = try intRows(root["residuals"], "residuals")

        let nl = nLevels
        XCTAssertEqual(8, cellRows.count)

        // Flatten the 8 cell curves into [8*nl], cell-major (cell w, level l at w*nl + l).
        let cells = flatten32(cellRows)
        var outCoarse = [Int32](repeating: 0, count: nl)
        var outResiduals = [Int32](repeating: 0, count: 7 * nl)
        XCTAssertEqual(rcOK, s4_v21_octant_lift_curve(cells, Int32(nLevels), &outCoarse, &outResiduals))

        // Coarse curve bit-exact.
        XCTAssertEqual(wantCoarse, outCoarse)
        // All 7 residual curves bit-exact (residual-major: residual r, level l at r*nl + l).
        XCTAssertEqual(flatten32(residualRows), outResiduals)
    }

    // MARK: - v21_opponent_fixture_test.zig

    /// Cross-language: s4_v21_opponent_delta matches the Haskell V2.1 opponent golden
    /// (the encode target, lawOpponentCommutesWithDelta).
    func testOpponentDeltaMatchesHaskellGolden() throws {
        let root = try loadFixture("v21_opponent_golden.json")
        let nLevels = try int(root, "n_levels")
        let nl = nLevels

        // Each bin is [[R..],[G..],[B..]] flattened channel-major into [3*nl].
        let bin1 = flatten32(try intRows(root["bin1"], "bin1"))
        let bin2 = flatten32(try intRows(root["bin2"], "bin2"))
        let wantLab = flatten32(try intRows(root["out_lab"], "out_lab"))

        var outLab = [Int32](repeating: 0, count: 3 * nl)
        XCTAssertEqual(rcOK, s4_v21_opponent_delta(bin1, bin2, Int32(nLevels), &outLab))

        // Bit-exact on all three (L, a, b) delta curves (channel-major: c*nl + l).
        XCTAssertEqual(wantLab, outLab)
    }

    // MARK: - v21_palette_delta_fixture_test.zig

    /// Reverse the SLOT order of a flat slot-major palette (keep each RGB triple intact).
    private func reverseSlots(_ pal: [UInt8]) -> [UInt8] {
        var out = [UInt8](repeating: 0, count: pal.count)
        let k = pal.count / 3
        for s in 0..<k {
            let src = (k - 1 - s) * 3
            out[s * 3 + 0] = pal[src + 0]
            out[s * 3 + 1] = pal[src + 1]
            out[s * 3 + 2] = pal[src + 2]
        }
        return out
    }

    /// Cross-language: s4_v21_palette_delta matches the Haskell golden + symmetry + gauge invariance.
    func testPaletteDeltaMatchesHaskellGoldenSymmetryGauge() throws {
        let root = try loadFixture("v21_palette_delta_golden.json")
        let k = try int(root, "k")
        let nLevels = try int(root, "n_levels")
        let want = Int32(try int(root, "palette_delta"))
        let pal1 = try ints(root["pal1"], "pal1").map { UInt8($0) }
        let pal2 = try ints(root["pal2"], "pal2").map { UInt8($0) }

        // (1) the scalar delta is bit-exact.
        var pd: Int32 = -1
        XCTAssertEqual(rcOK, s4_v21_palette_delta(pal1, pal2, Int32(k), Int32(nLevels), &pd))
        XCTAssertEqual(want, pd)

        // (2) symmetry: delta(pal2, pal1) == delta(pal1, pal2).
        var pdSwapped: Int32 = -1
        XCTAssertEqual(rcOK, s4_v21_palette_delta(pal2, pal1, Int32(k), Int32(nLevels), &pdSwapped))
        XCTAssertEqual(want, pdSwapped)

        // (3) gauge invariance: reversing pal1's slot order (the index gauge) does not change the delta.
        let pal1Rev = reverseSlots(pal1)
        var pdGauge: Int32 = -1
        XCTAssertEqual(rcOK, s4_v21_palette_delta(pal1Rev, pal2, Int32(k), Int32(nLevels), &pdGauge))
        XCTAssertEqual(want, pdGauge)
    }

    // MARK: - v21_soft_hist_fixture_test.zig

    /// Cross-language: s4_v21_accumulate_hist_soft matches the Haskell golden + mass + exact centroid.
    /// (1) bit-exact soft counts; (2) MASS: total == (fine-sample count) * w
    /// (lawSoftHistTotalPreserved); (3) CENTROID: per (voxel,channel),
    /// sum(level*count) == sum of the cell's hi values (lawSoftSplatCentroidExact).
    func testAccumulateHistSoftMatchesHaskellGoldenMassCentroid() throws {
        let root = try loadFixture("v21_soft_hist_golden.json")
        let fx = try int(root, "fx"), fy = try int(root, "fy"), ft = try int(root, "ft")
        let dx = try int(root, "dx"), dy = try int(root, "dy"), dt = try int(root, "dt")
        let nLevels = try int(root, "n_levels")
        let w = try int(root, "w")
        let fine = try ints(root["fine"], "fine").map { Int32($0) }
        let wantCounts = try ints(root["counts"], "counts").map { Int32($0) }

        var outCounts = [Int32](repeating: 0, count: wantCounts.count)
        let rc = s4_v21_accumulate_hist_soft(
            fine, Int32(fx), Int32(fy), Int32(ft),
            Int32(dx), Int32(dy), Int32(dt), Int32(nLevels), Int32(w), &outCounts)
        XCTAssertEqual(rcOK, rc)

        // (1) bit-exact vs the Haskell golden.
        XCTAssertEqual(wantCounts, outCounts)

        // (2) MASS: total == (fine-sample count) * w.
        var total: Int64 = 0
        for c in outCounts { total += Int64(c) }
        XCTAssertEqual(Int64(fine.count) * Int64(w), total)

        // (3) EXACT CENTROID per (voxel, channel): sum(level*count) == sum of that cell's hi values.
        // Recompute the cell each fine sample lands in (the kernel's floor-division grouping),
        // accumulate its hi into an expected first-moment per cell, and compare to the
        // count-weighted level sum (lawSoftSplatCentroidExact aggregated over the cell).
        let nl = nLevels
        let ncells = wantCounts.count / nl // (ct*cy*cx*3) cells
        var momentFromHi = [Int64](repeating: 0, count: ncells)
        let cx = fx / dx
        let cy = fy / dy
        for fti in 0..<ft {
            for fyi in 0..<fy {
                for fxi in 0..<fx {
                    let cvi = ((fti / dt) * cy + (fyi / dy)) * cx + (fxi / dx)
                    for ch in 0..<3 {
                        let fineIdx = ((fti * fy + fyi) * fx + fxi) * 3 + ch
                        momentFromHi[cvi * 3 + ch] += Int64(fine[fineIdx])
                    }
                }
            }
        }
        for cell in 0..<ncells {
            var momentFromCounts: Int64 = 0
            for lvl in 0..<nl {
                momentFromCounts += Int64(lvl) * Int64(outCounts[cell * nl + lvl])
            }
            XCTAssertEqual(momentFromHi[cell], momentFromCounts, "cell \(cell): centroid drift")
        }
    }

    // MARK: - v21_wdist1d_fixture_test.zig

    /// Cross-language: s4_v21_wdist1d matches the Haskell W1 golden + symmetry + charges distance.
    func testWdist1dMatchesHaskellGoldenSymmetryDiscriminator() throws {
        let root = try loadFixture("v21_wdist1d_golden.json")
        let k = try int(root, "k")
        let nLevels = try int(root, "n_levels")
        let want = Int32(try int(root, "w1"))
        let wantDrift = Int32(try int(root, "drift_w1"))
        let wantJump = Int32(try int(root, "jump_w1"))
        let pal1 = try ints(root["pal1"], "pal1").map { UInt8($0) }
        let pal2 = try ints(root["pal2"], "pal2").map { UInt8($0) }

        // (1) the scalar W1 is bit-exact.
        var wd: Int32 = -1
        XCTAssertEqual(rcOK, s4_v21_wdist1d(pal1, pal2, Int32(k), Int32(nLevels), &wd))
        XCTAssertEqual(want, wd)

        // (2) symmetry.
        var wdSwapped: Int32 = -1
        XCTAssertEqual(rcOK, s4_v21_wdist1d(pal2, pal1, Int32(k), Int32(nLevels), &wdSwapped))
        XCTAssertEqual(want, wdSwapped)

        // (3) the discriminator: single-slot palettes at level 0, level 1 (drift), and the top level (jump).
        let top = UInt8(nLevels - 1)
        let p0: [UInt8] = [0, 0, 0]
        let pNear: [UInt8] = [1, 0, 0]
        let pFar: [UInt8] = [top, 0, 0]
        var wdDrift: Int32 = -1
        var wdJump: Int32 = -1
        XCTAssertEqual(rcOK, s4_v21_wdist1d(p0, pNear, 1, Int32(nLevels), &wdDrift))
        XCTAssertEqual(rcOK, s4_v21_wdist1d(p0, pFar, 1, Int32(nLevels), &wdJump))
        XCTAssertEqual(wantDrift, wdDrift)
        XCTAssertEqual(wantJump, wdJump)
        XCTAssertLessThan(wdDrift, wdJump) // W1 charges the ground distance (TV would tie them)
    }

    // MARK: - kernels.zig inline test (transport/pushforward golden + round-trip + guards)

    /// Port of the inline `test "s4_v21_transport / s4_v21_pushforward: golden + round-trip +
    /// guards (Spec.V21Transport)"` block in kernels.zig (inline literals, no fixture).
    /// The kernel processes p*3 curves (RGB), so p=1 lays out THREE per-channel curves; each
    /// golden repeats one curve across the 3 channels and checks the displacement replicated.
    func testTransportPushforwardGoldenRoundTripGuards() {
        // Golden 1 (rigid +1 drift): dst is src shifted by one level, so the transport is the
        // constant displacement 1 at every rank (lawTranslateIsConstantShift) and the pushforward
        // reproduces dst byte-exact. Same witness verified in the Haskell harness.
        do {
            let p: Int32 = 1
            let nl: Int32 = 6
            let mass: Int32 = 6
            let oneS: [Int32] = [2, 0, 3, 0, 1, 0] // quantiles 0,0,2,2,2,4
            let oneD: [Int32] = [0, 2, 0, 3, 0, 1] // quantiles 1,1,3,3,3,5  (= src + 1)
            let src = oneS + oneS + oneS
            let dst = oneD + oneD + oneD
            var disp = [Int32](repeating: 0, count: 18)
            XCTAssertEqual(rcOK, s4_v21_transport(src, dst, p, nl, mass, &disp))
            XCTAssertEqual([Int32](repeating: 1, count: 18), disp)
            var got = [Int32](repeating: 0, count: 18)
            XCTAssertEqual(rcOK, s4_v21_pushforward(src, disp, p, nl, mass, &got))
            XCTAssertEqual(dst, got)
        }
        // Golden 2 (crossing / non-rigid): mass moves in BOTH directions; the map has mixed signs
        // and its total absolute displacement equals the CDF-L1 Wasserstein-1 cost
        // (lawTransportCostIsW1 = 6/curve).
        do {
            let p: Int32 = 1
            let nl: Int32 = 4
            let mass: Int32 = 6
            let oneS: [Int32] = [3, 0, 0, 3] // quantiles 0,0,0,3,3,3
            let oneD: [Int32] = [0, 3, 3, 0] // quantiles 1,1,1,2,2,2
            let src = oneS + oneS + oneS
            let dst = oneD + oneD + oneD
            var disp = [Int32](repeating: 0, count: 18)
            XCTAssertEqual(rcOK, s4_v21_transport(src, dst, p, nl, mass, &disp))
            let oneCurve: [Int32] = [1, 1, 1, -1, -1, -1]
            XCTAssertEqual(oneCurve + oneCurve + oneCurve, disp)
            var w1: Int32 = 0
            for d in disp { w1 += d < 0 ? -d : d }
            XCTAssertEqual(18, w1) // 6 per curve x 3 channels
            // forward reproduces dst
            var got = [Int32](repeating: 0, count: 12)
            XCTAssertEqual(rcOK, s4_v21_pushforward(src, disp, p, nl, mass, &got))
            XCTAssertEqual(dst, got)
            // REVERSIBILITY: the negated displacement carries dst back to src exactly.
            let ndisp = disp.map { -$0 }
            var back = [Int32](repeating: 0, count: 12)
            XCTAssertEqual(rcOK, s4_v21_pushforward(dst, ndisp, p, nl, mass, &back))
            XCTAssertEqual(src, back)
        }
        // Guards: unequal mass is refused; a null pointer is refused; a displacement off the
        // alphabet is refused.
        do {
            let p: Int32 = 1
            let nl: Int32 = 4
            let oneS: [Int32] = [3, 0, 0, 3] // mass 6
            let oneD: [Int32] = [0, 2, 2, 0] // mass 4 != 6
            let src = oneS + oneS + oneS
            let dst = oneD + oneD + oneD
            var disp = [Int32](repeating: 0, count: 18)
            XCTAssertEqual(rcOutOfRange, s4_v21_transport(src, dst, p, nl, 6, &disp))
            XCTAssertEqual(rcNullPtr, s4_v21_transport(nil, dst, p, nl, 6, &disp))
            // a displacement that pushes level 3 up to level 4 (off the 0..3 alphabet) is refused.
            let badCurve: [Int32] = [0, 0, 0, 1, 1, 1]
            let bad = badCurve + badCurve + badCurve
            var out = [Int32](repeating: 0, count: 12)
            XCTAssertEqual(rcOutOfRange, s4_v21_pushforward(src, bad, p, nl, 6, &out))
        }
    }
}
