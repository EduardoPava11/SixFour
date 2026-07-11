import Foundation
import Testing
import simd
@testable import SixFour

/// `Spec.TemporalLoop`'s laws on the Swift twin (2026-07-11 link-ledger
/// wave 2): exact loop closure as an index identity, the golden cosine table,
/// and the lossless temporal Haar whose flooring must match the owned kernels
/// (not Swift's truncating division).
struct TemporalLoopTests {

    @Test func loopClosureIsExactForAllIndices() {
        // lawLoopIndexIsBitmask + lawTemporalLoopClosesExact + wrap.
        for t in -130...130 {
            #expect(TemporalLoop.temporalCos(t + TemporalLoop.period) == TemporalLoop.temporalCos(t))
        }
        for t in 0...300 {
            #expect(TemporalLoop.loopIndex(t) == t % TemporalLoop.period)
        }
        // The seam, concretely: frame 64 lands on exactly frame 0's value.
        #expect(TemporalLoop.temporalCos(TemporalLoop.period) == TemporalLoop.temporalCos(0))
        #expect(TemporalLoop.cosLutQ16.count == TemporalLoop.period)
    }

    @Test func cosTableMatchesTheReferenceGeneration() {
        // The golden literals equal round-half-to-even of the reference cosine
        // (the spec's exact generation) — pins the embedded table.
        for t in 0..<TemporalLoop.period {
            let reference = (cos(2 * Double.pi * Double(t) / 64) * 65536).rounded(.toNearestOrEven)
            #expect(TemporalLoop.cosLutQ16[t] == Int32(reference), "t=\(t)")
        }
    }

    @Test func temporalSplitJoinIsLossless() {
        // lawTemporalSplitJoinExact on even AND odd lengths, negative-heavy
        // values (the flooring-sensitive regime).
        var seed: UInt64 = 0xC0FF_EE00_0C7A_7007
        func value() -> Int32 {
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            return Int32(truncatingIfNeeded: seed >> 40) % 140_000
        }
        for length in [1, 2, 7, 63, 64] {
            let series = (0..<length).map { _ in SIMD3<Int32>(value(), value(), value()) }
            let (low, high) = TemporalLoop.haarSplitTime(series)
            #expect(TemporalLoop.haarJoinTime(low: low, high: high) == series, "length \(length)")
            #expect(TemporalLoop.temporalResidual(series) == low)
            #expect(low.count == (length + 1) / 2 && high.count == length / 2)
        }
    }

    @Test func liftUsesFlooredHalvingNotTruncation() {
        // x=0, y=1 → detail −1; floored −1/2 = −1 ⇒ parent 0. Truncating
        // division would give parent 1 — the exact drift the spec's
        // lawTemporalLiftMatchesHaar exists to prevent.
        let (parent, detail) = TemporalLoop.liftPair(SIMD3<Int32>(0, 0, 0), SIMD3<Int32>(1, 1, 1))
        #expect(detail == SIMD3<Int32>(-1, -1, -1))
        #expect(parent == SIMD3<Int32>(0, 0, 0))
        let (x, y) = TemporalLoop.unliftPair(parent, detail)
        #expect(x == SIMD3<Int32>(0, 0, 0) && y == SIMD3<Int32>(1, 1, 1))
    }

    @Test func burstSummaryReadsRealShapes() {
        // A 64-frame series of 4-leaf palettes: the summary splits 32/32 and a
        // constant burst has zero temporal detail.
        let still = Array(repeating: [SIMD3<Int32>(65536, -3, 7)], count: 64)
        let summary = TemporalLoop.burstTemporalSummary(paletteQ16Frames: still)
        #expect(summary?.low == 32 && summary?.high == 32 && summary?.maxDetailQ16 == 0)
    }
}
