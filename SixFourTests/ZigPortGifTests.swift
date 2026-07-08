//  ZigPortGifTests.swift
//  Swift ports of the Zig GIF-codec test files (2026-07-06 Zig→Swift port):
//    * Native/src/gif_fixture_test.zig          — the monolithic burst entrypoint
//    * Native/src/gif_assemble_fixture_test.zig — the LZW + GIF89a serialiser
//  gating the KernelsGif.swift twins byte-for-byte against the Haskell goldens.
//
//  Fixture policy (mirrors the Zig skip-if-absent contract): the burst golden is
//  the committed `GifGoldenFixture` embedding (byte-identical to
//  trainer/out/golden.gif + golden_input.halfs, so it never skips); the assemble
//  golden reads trainer/out/gif_golden.* and XCTSkips when absent (build with
//  `cd spec && cabal run spec-fixtures`).

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

/// Load a fixture file or skip the test (never a vacuous pass, never a red tree).
private func loadZigPortFixture(_ name: String) throws -> Data {
    let url = zigPortFixtureDir().appendingPathComponent(name)
    guard FileManager.default.fileExists(atPath: url.path) else {
        throw XCTSkip("\(name) not in '\(zigPortFixtureDir().path)'; run `cd spec && cabal run spec-fixtures`")
    }
    return try Data(contentsOf: url)
}

final class ZigPortGifTests: XCTestCase {

    /// Port of gif_fixture_test.zig: "cross-language: Haskell golden GIF
    /// reproduced byte-exactly by the Zig core" — now by the SWIFT core.
    /// Small dims (2×32²×256), Floyd-Steinberg (mode 0, no STBN mask),
    /// Lloyd = 15, delay 5 cs — the exact params the golden was produced with.
    func testEncodeBurstReproducesHaskellGoldenGifByteExactly() {
        let golden = [UInt8](GifGoldenFixture.goldenGif)
        let halfs = GifGoldenFixture.goldenInputHalfs
        let fc = GifGoldenFixture.frameCount
        let sd = GifGoldenFixture.side
        let kk = GifGoldenFixture.k

        let bound = s4_gif_encode_burst_bound(fc, sd, kk)
        XCTAssertGreaterThan(bound, 0)
        let scratchBytes = s4_burst_scratch_bytes(fc, sd, kk)
        XCTAssertGreaterThan(scratchBytes, 0)

        var out = [UInt8](repeating: 0, count: bound)
        // Int64-backed scratch so the carve's i64 regions are 8-aligned for sure.
        var scratch = [Int64](repeating: 0, count: (scratchBytes + 7) / 8)
        var outLen = 0

        let rc = halfs.withUnsafeBufferPointer { hp in
            out.withUnsafeMutableBufferPointer { op in
                scratch.withUnsafeMutableBufferPointer { sp in
                    s4_gif_encode_burst(
                        hp.baseAddress,
                        fc, sd, kk,
                        0, // input_space = linear-sRGB halfs
                        GifGoldenFixture.lloydIters, // 15 (matches burstLloyd)
                        0, // dither_mode = Floyd-Steinberg (no STBN mask needed)
                        0, // serpentine
                        nil, // stbn_mask (FS ignores it)
                        GifGoldenFixture.frameDelayCentiseconds, // 5 (20 fps)
                        nil, // comment
                        0,
                        op.baseAddress, op.count, &outLen,
                        UnsafeMutableRawPointer(sp.baseAddress), sp.count * 8
                    )
                }
            }
        }
        XCTAssertEqual(rc, 0)
        XCTAssertEqual(Array(out[0..<outLen]), golden,
                       "burst GIF bytes (\(outLen)) != Haskell golden (\(golden.count))")
    }

    /// Port of gif_assemble_fixture_test.zig: "cross-language: s4_gif_assemble
    /// reproduces the Haskell GIF golden byte-exactly". Feeds the SAME indices +
    /// palettes the Haskell driver wrote and asserts the produced GIF is
    /// BYTE-EXACTLY the golden (no transcendental, just exact bytes).
    func testGifAssembleReproducesHaskellGoldenByteExactly() throws {
        let metaRaw = try loadZigPortFixture("gif_golden.json")
        let meta = try XCTUnwrap(try JSONSerialization.jsonObject(with: metaRaw) as? [String: Any])

        let frameCount = Int32(try XCTUnwrap(meta["frame_count"] as? Int))
        let side = Int32(try XCTUnwrap(meta["side"] as? Int))
        let k = Int32(try XCTUnwrap(meta["k"] as? Int))
        let delayCs = UInt16(try XCTUnwrap(meta["delay_cs"] as? Int))
        let comment = Array(try XCTUnwrap(meta["comment"] as? String).utf8)

        let indices = [UInt8](try loadZigPortFixture("gif_golden_indices.bin"))
        let palettes = [UInt8](try loadZigPortFixture("gif_golden_palettes.bin"))
        let golden = [UInt8](try loadZigPortFixture("gif_golden.gif"))

        // Shapes must line up with the binary payloads.
        let p = Int(side) * Int(side)
        XCTAssertEqual(indices.count, Int(frameCount) * p)
        XCTAssertEqual(palettes.count, Int(frameCount) * Int(k) * 3)

        let bound = s4_gif_encode_burst_bound(frameCount, side, k)
        var out = [UInt8](repeating: 0, count: bound)
        var outLen = 0

        let rc = indices.withUnsafeBufferPointer { ip in
            palettes.withUnsafeBufferPointer { pp in
                comment.withUnsafeBufferPointer { cp in
                    out.withUnsafeMutableBufferPointer { op in
                        s4_gif_assemble(
                            ip.baseAddress, pp.baseAddress,
                            frameCount, side, k, delayCs,
                            cp.baseAddress, Int32(comment.count),
                            op.baseAddress, op.count, &outLen
                        )
                    }
                }
            }
        }
        XCTAssertEqual(rc, 0)
        XCTAssertEqual(Array(out[0..<outLen]), golden,
                       "assembled GIF bytes (\(outLen)) != Haskell golden (\(golden.count))")
    }
}
