//  ZigPortColorTests.swift
//  Swift ports of Native/src/color_fixture_test.zig + lut_fixture_test.zig for
//  the KernelsColor.swift twin of the Zig color/LUT kernels, plus a byte-identity
//  gate for the five embedded LUT arrays against their .bin goldens.
//
//  Fixture loading mirrors the Zig tests' skip-if-absent discipline: the JSON
//  goldens live at trainer/out/ (the zig-build default fixture_dir) and the .bin
//  goldens at SixFour/Kernels/LUTGoldens/. Both are dev-machine files, not bundle resources, so
//  they are reached #filePath-relative and the test XCTSkips when unreachable.

import XCTest
import Foundation
@testable import SixFour

final class ZigPortColorTests: XCTestCase {

    // ── fixture plumbing ─────────────────────────────────────────────────────

    /// Repo root, #filePath-relative (…/SixFourTests/ZigPortColorTests.swift → …/).
    private static var repoRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // SixFourTests/
            .deletingLastPathComponent() // repo root
    }

    /// Load a JSON golden from trainer/out/ (zig build's default fixture_dir),
    /// or skip — the same skip-if-absent contract as the Zig fixture tests
    /// ("run `cd spec && cabal run spec-fixtures`").
    private func loadGolden(_ name: String) throws -> [String: Any] {
        let url = Self.repoRoot.appendingPathComponent("trainer/out").appendingPathComponent(name)
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw XCTSkip("\(name) not in trainer/out; run `cd spec && cabal run spec-fixtures`")
        }
        let data = try Data(contentsOf: url)
        let obj = try JSONSerialization.jsonObject(with: data)
        return try XCTUnwrap(obj as? [String: Any], "\(name): root is not a JSON object")
    }

    private func intField(_ obj: [String: Any], _ key: String) throws -> Int {
        try XCTUnwrap((obj[key] as? NSNumber)?.intValue, "missing/non-int '\(key)'")
    }

    /// A JSON [x,y,z] triple as [Int32] (the i32at() twin).
    private func triple(_ any: Any?, _ what: String) throws -> [Int32] {
        let arr = try XCTUnwrap(any as? [NSNumber], "\(what): not a number array")
        XCTAssertEqual(arr.count, 3, "\(what): not a triple")
        return arr.map { Int32(truncatingIfNeeded: $0.int64Value) }
    }

    // ── kernel-call wrappers (array-safe pointer bridging) ───────────────────

    private func linearToOklab(_ lin: [Int32]) -> (rc: Int32, out: [Int32]) {
        var out = [Int32](repeating: 0, count: lin.count)
        let rc = lin.withUnsafeBufferPointer { ip in
            out.withUnsafeMutableBufferPointer { op in
                s4_linear_to_oklab_q16(ip.baseAddress, Int32(lin.count / 3), op.baseAddress)
            }
        }
        return (rc, out)
    }

    private func paletteOklabToSrgb8(_ oklab: [Int32]) -> (rc: Int32, rgb: [UInt8]) {
        var rgb = [UInt8](repeating: 0, count: oklab.count)
        let rc = oklab.withUnsafeBufferPointer { ip in
            rgb.withUnsafeMutableBufferPointer { op in
                s4_palette_oklab_to_srgb8(ip.baseAddress, Int32(oklab.count / 3), op.baseAddress, nil, 0)
            }
        }
        return (rc, rgb)
    }

    // ── color_fixture_test.zig port ──────────────────────────────────────────

    /// Cross-language: Q16 linear→OKLab (and the OKLab→sRGB8 inverse) match the
    /// Haskell color golden byte-exactly. Port of color_fixture_test.zig.
    func testColorGoldenMatchesByteExactly() throws {
        let root = try loadGolden("color_golden.json")

        // The fixture must agree on the Q16 unit, else the two sides scale differently.
        XCTAssertEqual(try intField(root, "q16_one"), Int(S4_Q16_ONE))

        // Forward: linear Q16 → OKLab Q16.
        let fwd = try XCTUnwrap(root["linear_to_oklab"] as? [[String: Any]])
        XCTAssertGreaterThan(fwd.count, 0)
        for (i, c) in fwd.enumerated() {
            let lin = try triple(c["lin"], "case \(i) lin")
            let expect = try triple(c["oklab"], "case \(i) oklab")
            let r = linearToOklab(lin)
            XCTAssertEqual(r.rc, 0, "case \(i): rc")
            XCTAssertEqual(r.out, expect, "case \(i): linear→OKLab drift")
        }

        // Inverse: OKLab Q16 → sRGB8 (exercises the embedded gamma LUT).
        let inv = try XCTUnwrap(root["oklab_to_srgb8"] as? [[String: Any]])
        XCTAssertGreaterThan(inv.count, 0)
        for (i, c) in inv.enumerated() {
            let oklab = try triple(c["oklab"], "case \(i) oklab")
            let expect = try triple(c["rgb"], "case \(i) rgb")
            let r = paletteOklabToSrgb8(oklab)
            XCTAssertEqual(r.rc, 0, "case \(i): rc")
            XCTAssertEqual(r.rgb.map { Int32($0) }, expect, "case \(i): OKLab→sRGB8 drift")
        }
    }

    // ── lut_fixture_test.zig port ────────────────────────────────────────────

    /// Cross-language: look transfer + LUT extraction match the Haskell golden
    /// byte-exactly. Port of lut_fixture_test.zig (zone profile → transfer
    /// cases → the whole N³ cube).
    func testLutGoldenMatchesByteExactly() throws {
        let root = try loadGolden("lut_golden.json")

        XCTAssertEqual(try intField(root, "q16_one"), Int(S4_Q16_ONE))

        let numZones = Int32(try intField(root, "num_zones"))
        let nz = Int(numZones)

        let params = try XCTUnwrap(root["transfer_params"] as? [String: Any])
        let strength = Int32(try intField(params, "strength"))
        let chromaMin = Int32(try intField(params, "chroma_min"))
        let chromaMax = Int32(try intField(params, "chroma_max"))
        let polarity = Int32(try intField(params, "polarity"))
        let chromaEps = Int32(try intField(params, "chroma_eps"))

        // ── 1. Zone profile ──────────────────────────────────────────────────
        let pal = try XCTUnwrap(root["palette_oklab"] as? [[NSNumber]])
        let p = pal.count
        var palFlat = [Int32](repeating: 0, count: p * 3)
        for (i, tri) in pal.enumerated() {
            XCTAssertEqual(tri.count, 3)
            palFlat[i * 3 + 0] = Int32(truncatingIfNeeded: tri[0].int64Value)
            palFlat[i * 3 + 1] = Int32(truncatingIfNeeded: tri[1].int64Value)
            palFlat[i * 3 + 2] = Int32(truncatingIfNeeded: tri[2].int64Value)
        }

        var meanA = [Int32](repeating: 0, count: nz)
        var meanB = [Int32](repeating: 0, count: nz)
        var meanC = [Int32](repeating: 0, count: nz)
        var global = [Int32](repeating: 0, count: 3)

        let rcZone = palFlat.withUnsafeBufferPointer { palPtr in
            meanA.withUnsafeMutableBufferPointer { aPtr in
                meanB.withUnsafeMutableBufferPointer { bPtr in
                    meanC.withUnsafeMutableBufferPointer { cPtr in
                        global.withUnsafeMutableBufferPointer { gPtr in
                            s4_zone_profile_q16(
                                palPtr.baseAddress, Int32(p), numZones,
                                aPtr.baseAddress, bPtr.baseAddress, cPtr.baseAddress,
                                gPtr.baseAddress
                            )
                        }
                    }
                }
            }
        }
        XCTAssertEqual(rcZone, 0)

        let zp = try XCTUnwrap(root["zone_profile"] as? [String: Any])
        let expA = try XCTUnwrap(zp["mean_a"] as? [NSNumber]).map { Int32(truncatingIfNeeded: $0.int64Value) }
        let expB = try XCTUnwrap(zp["mean_b"] as? [NSNumber]).map { Int32(truncatingIfNeeded: $0.int64Value) }
        let expC = try XCTUnwrap(zp["mean_c"] as? [NSNumber]).map { Int32(truncatingIfNeeded: $0.int64Value) }
        XCTAssertEqual(meanA, expA, "zone mean_a drift")
        XCTAssertEqual(meanB, expB, "zone mean_b drift")
        XCTAssertEqual(meanC, expC, "zone mean_c drift")
        XCTAssertEqual(global, try triple(zp["global"], "zone global"), "zone global drift")

        // ── 2. Look transfer cases ───────────────────────────────────────────
        let cases = try XCTUnwrap(root["transfer_cases"] as? [[String: Any]])
        XCTAssertGreaterThan(cases.count, 0)
        for (i, c) in cases.enumerated() {
            let input = try triple(c["in"], "transfer case \(i) in")
            let expect = try triple(c["out"], "transfer case \(i) out")
            var out = [Int32](repeating: 0, count: 3)
            let rc = input.withUnsafeBufferPointer { ip in
                meanA.withUnsafeBufferPointer { aPtr in
                    meanB.withUnsafeBufferPointer { bPtr in
                        meanC.withUnsafeBufferPointer { cPtr in
                            out.withUnsafeMutableBufferPointer { op in
                                s4_look_transfer_q16(
                                    ip.baseAddress, 1,
                                    aPtr.baseAddress, bPtr.baseAddress, cPtr.baseAddress,
                                    numZones, strength, chromaMin, chromaMax,
                                    polarity, chromaEps,
                                    op.baseAddress
                                )
                            }
                        }
                    }
                }
            }
            XCTAssertEqual(rc, 0, "transfer case \(i): rc")
            XCTAssertEqual(out, expect, "transfer case \(i): look-transfer drift")
        }

        // ── 3. The whole N³ cube ─────────────────────────────────────────────
        let cubeSize = Int32(try intField(root, "cube_size"))
        let ncube = Int(cubeSize)
        let cubeLen = ncube * ncube * ncube * 3
        var cube = [Int32](repeating: 0, count: cubeLen)
        let rcCube = meanA.withUnsafeBufferPointer { aPtr in
            meanB.withUnsafeBufferPointer { bPtr in
                meanC.withUnsafeBufferPointer { cPtr in
                    cube.withUnsafeMutableBufferPointer { op in
                        s4_build_cube_q16(
                            cubeSize,
                            aPtr.baseAddress, bPtr.baseAddress, cPtr.baseAddress,
                            numZones, strength, chromaMin, chromaMax,
                            polarity, chromaEps,
                            op.baseAddress, cubeLen
                        )
                    }
                }
            }
        }
        XCTAssertEqual(rcCube, 0)

        let expCube = try XCTUnwrap(root["cube"] as? [[NSNumber]])
        XCTAssertEqual(cubeLen, expCube.count * 3)
        for (i, tri) in expCube.enumerated() {
            XCTAssertEqual(cube[i * 3 + 0], Int32(truncatingIfNeeded: tri[0].int64Value), "cube voxel \(i) R drift")
            XCTAssertEqual(cube[i * 3 + 1], Int32(truncatingIfNeeded: tri[1].int64Value), "cube voxel \(i) G drift")
            XCTAssertEqual(cube[i * 3 + 2], Int32(truncatingIfNeeded: tri[2].int64Value), "cube voxel \(i) B drift")
        }
    }

    // ── embedded LUT arrays == .bin goldens ──────────────────────────────────

    /// The five [UInt8] LUT arrays in KernelsLUTData.swift must be byte-identical
    /// to the .bin goldens kernels.zig @embedFile'd (SixFour/Kernels/LUTGoldens/*.bin). Loaded
    /// #filePath-relative — a dev-machine gate; skips when the repo files are
    /// unreachable (the .bin goldens do not ship in the test bundle).
    func testEmbeddedLutArraysMatchBinGoldens() throws {
        let pairs: [(array: [UInt8], bin: String)] = [
            (s4LutGamma, "gamma_lut.bin"),
            (s4LutSrgbLinear, "srgb_linear_lut.bin"),
            (s4LutLog3g10Decode, "log3g10_decode_lut.bin"),
            (s4LutFilmicTonemap, "filmic_tonemap_lut.bin"),
            (s4LutSrgbEncode, "srgb_encode_lut.bin"),
        ]
        for (array, bin) in pairs {
            let url = Self.repoRoot.appendingPathComponent("SixFour/Kernels/LUTGoldens").appendingPathComponent(bin)
            guard FileManager.default.fileExists(atPath: url.path) else {
                throw XCTSkip("\(bin) unreachable at \(url.path) (dev-machine-only gate)")
            }
            let golden = [UInt8](try Data(contentsOf: url))
            XCTAssertEqual(array.count, golden.count, "\(bin): length mismatch")
            XCTAssertEqual(array, golden, "\(bin): embedded LUT bytes drifted from the golden")
        }
    }
}
