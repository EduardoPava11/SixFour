//  S4SIMTPropertyTests.swift
//  The SIMT parity gate (2026-07-06): every SIMT twin must equal the scalar
//  AUTHORITY bit-for-bit on every input. Seeded property sweep across the
//  divisor lattice — sides that stress full lanes, tails, q=1 (identity
//  pooling), q=side (single bin), and non-multiple-of-16 rows.

import XCTest
@testable import SixFour

private struct SplitMix64 {
    var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
    mutating func byte() -> UInt8 { UInt8(truncatingIfNeeded: next()) }
}

final class S4SIMTPropertyTests: XCTestCase {

    /// scalar == SIMT across the divisor lattice, random bytes, 3 seeds per
    /// shape. Shapes chosen to hit: rows % 16 == 0 and != 0, q = 1, q = side,
    /// odd q, and the shipped 64/32/16 ladder.
    func testPoolSumsSRGB8SimdEqualsScalarAuthority() {
        let shapes: [(side: Int, out: Int)] = [
            (64, 16), (64, 32), (64, 64), (64, 1),      // the ladder + extremes
            (16, 16), (32, 8),                          // q = 1, q = 4
            (48, 16), (96, 32), (240, 16),              // q = 3 (odd), larger
            (8, 8), (8, 4), (8, 2), (8, 1),             // smallest SIMD sides (24-byte rows: 1 lane + 8 tail)
            (40, 8), (56, 8),                           // rows 120/168 bytes (tail 8)
            (128, 16), (176, 16),                       // rows 384/528 bytes (tail 0/tail 0)
        ]
        var rng = SplitMix64(seed: 0x51D7_0000_8B17_0001)
        for (side, out) in shapes {
            for trial in 0..<3 {
                var rgb = [UInt8](repeating: 0, count: side * side * 3)
                for j in rgb.indices { rgb[j] = rng.byte() }
                var scalar = [UInt64](repeating: 0, count: out * out * 3)
                var simd = [UInt64](repeating: 1, count: out * out * 3) // poisoned
                let rcS = rgb.withUnsafeBufferPointer { bp in
                    scalar.withUnsafeMutableBufferPointer { sp in
                        s4PoolSumsSRGB8Scalar(bp.baseAddress!, side, out, sp.baseAddress!)
                    }
                }
                let rcV = rgb.withUnsafeBufferPointer { bp in
                    simd.withUnsafeMutableBufferPointer { sp in
                        s4PoolSumsSRGB8SIMD(bp.baseAddress!, side, out, sp.baseAddress!)
                    }
                }
                XCTAssertEqual(rcS, 0, "\(side)→\(out) trial \(trial)")
                XCTAssertEqual(rcV, 0, "\(side)→\(out) trial \(trial)")
                XCTAssertEqual(simd, scalar,
                    "SIMT != scalar authority at \(side)→\(out) trial \(trial) (seed pinned)")
            }
        }
    }

    /// The exported symbol (whichever path it dispatches to) agrees with the
    /// scalar authority — the dispatcher can never change bytes.
    func testExportedPoolSumsEqualsAuthority() {
        var rng = SplitMix64(seed: 0x51D7_0000_8B17_0002)
        for (side, out) in [(64, 16), (48, 16), (6, 3), (4, 2)] {  // incl. sub-lane scalar fallback
            var rgb = [UInt8](repeating: 0, count: side * side * 3)
            for j in rgb.indices { rgb[j] = rng.byte() }
            var viaExport = [UInt64](repeating: 0, count: out * out * 3)
            var authority = [UInt64](repeating: 0, count: out * out * 3)
            XCTAssertEqual(s4_pool_sums_srgb8(rgb, Int32(side), Int32(out), &viaExport), 0)
            let rc = rgb.withUnsafeBufferPointer { bp in
                authority.withUnsafeMutableBufferPointer { sp in
                    s4PoolSumsSRGB8Scalar(bp.baseAddress!, side, out, sp.baseAddress!)
                }
            }
            XCTAssertEqual(rc, 0)
            XCTAssertEqual(viaExport, authority, "\(side)→\(out): dispatcher changed bytes")
        }
    }

    /// Saturation adversary: an all-white image maximizes every accumulator —
    /// the widening ladder must carry q·255 per column and q²·255 per bin
    /// without wrap, at the largest shape in the sweep.
    func testAllWhiteSaturationCarriesExactly() {
        let side = 240, out = 16, q = side / out
        let rgb = [UInt8](repeating: 255, count: side * side * 3)
        var sums = [UInt64](repeating: 0, count: out * out * 3)
        XCTAssertEqual(s4_pool_sums_srgb8(rgb, Int32(side), Int32(out), &sums), 0)
        let expect = UInt64(q * q) * 255
        XCTAssertTrue(sums.allSatisfy { $0 == expect }, "white bin != q²·255")
    }
}
