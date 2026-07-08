//  KernelsSIMT.swift
//  THE SIMT MACHINERY (2026-07-06) — 8-bit lanes, widening accumulators,
//  byte-exact by construction.
//
//  DESIGN CONTRACT. GIF89a is 8-bit on every wire surface (indices ≤ 8 bpp
//  through LZW, palette entries 3×8-bit), so the DATA PLANE of this machinery
//  is UInt8: one SIMD16<UInt8> lane = 16 samples = one NEON q-register. Only
//  ACCUMULATORS widen (u8 → u32 lanes → u64 bins) — they must (one 16-px run
//  of white is already 4080 > 255) — and the widening is exactness-free:
//  integer sums reassociate exactly (Spec.ColorTime lawSumsCompose), so ANY
//  lane order and ANY widening ladder produces the identical u64 carrier.
//  In Spec.DataParallel terms every reduction here is DetClass EXACT; this is
//  the CPU face of the same SIMT story the Metal twins tell on the GPU.
//
//  AUTHORITY POLICY. The scalar port (the byte-exact twin of the Zig core) is
//  the AUTHORITY; every SIMT kernel is a TWIN that must equal it bit-for-bit
//  on every input. The gate is property-based (S4SIMTPropertyTests: seeded
//  random images across the divisor lattice, scalar == SIMT), mirroring the
//  Zig↔Metal parity pattern the color head already uses.
//
//  SHAPE. Block-sum pooling factors into two folds:
//    PASS 1 (the O(side²) work, fully SIMD): fold the q rows of a bin-row
//      into per-column u32 sums — lanes of 16 bytes widened and accumulated;
//      the row tail (< 16 bytes) is zero-padded into a final lane (padding
//      with zeros is exact for sums).
//    PASS 2 (the O(side) work, scalar): fold each bin's q columns per channel
//      from the u32 column sums into the u64 bin carrier.
//  Column sums fit u32 for any side ≤ 2^24 (q·255 ≤ side·255).

/// One up-widening lane accumulation step: 16 bytes → 16 u32 lanes, added
/// exactly. The compiler lowers the conversion to NEON widening moves.
@inline(__always)
func s4LaneAccumulate(_ acc: inout SIMD16<UInt32>, _ bytes: SIMD16<UInt8>) {
    acc &+= SIMD16<UInt32>(truncatingIfNeeded: bytes)
}

/// SIMT twin of `s4PoolSumsSRGB8Scalar`: exact block-sum pooling of an sRGB8
/// square (side×side, 3 bytes/px row-major) into out_side² u64 bin sums.
/// Preconditions (validated by the exported dispatcher): out_side | side.
func s4PoolSumsSRGB8SIMD(
    _ rgb: UnsafePointer<UInt8>,
    _ s: Int,
    _ o: Int,
    _ out_sums: UnsafeMutablePointer<UInt64>
) -> Int32 {
    let q = s / o           // bin side in pixels
    let rowBytes = s * 3    // one image row in bytes
    let fullLanes = rowBytes / 16
    let tail = rowBytes % 16
    let laneCount = fullLanes + (tail > 0 ? 1 : 0)

    let raw = UnsafeRawPointer(rgb)

    return withUnsafeTemporaryAllocation(of: SIMD16<UInt32>.self, capacity: laneCount) { col in
        for by in 0..<o {
            // PASS 1: per-column u32 sums over this bin-row's q image rows.
            for l in 0..<laneCount { col[l] = SIMD16<UInt32>() }
            let rowBase = by * q * rowBytes
            for dy in 0..<q {
                let base = rowBase + dy * rowBytes
                for l in 0..<fullLanes {
                    let v = raw.loadUnaligned(fromByteOffset: base + l * 16,
                                              as: SIMD16<UInt8>.self)
                    s4LaneAccumulate(&col[l], v)
                }
                if tail > 0 {
                    var padded = SIMD16<UInt8>()
                    for t in 0..<tail { padded[t] = rgb[base + fullLanes * 16 + t] }
                    s4LaneAccumulate(&col[laneCount - 1], padded)
                }
            }
            // PASS 2: fold each bin's q pixel-columns per channel into u64.
            for bx in 0..<o {
                var sum0: UInt64 = 0
                var sum1: UInt64 = 0
                var sum2: UInt64 = 0
                let colBase = bx * q * 3
                for dx in 0..<q {
                    let c0 = colBase + dx * 3
                    sum0 += UInt64(col[c0 >> 4][c0 & 15])
                    sum1 += UInt64(col[(c0 + 1) >> 4][(c0 + 1) & 15])
                    sum2 += UInt64(col[(c0 + 2) >> 4][(c0 + 2) & 15])
                }
                let bin = (by * o + bx) * 3
                out_sums[bin] = sum0
                out_sums[bin + 1] = sum1
                out_sums[bin + 2] = sum2
            }
        }
        return S4_RC_OK
    }
}
