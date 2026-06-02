import Testing
import simd
@testable import SixFour

/// Byte-exact gate for the Q16 global-palette collapse (GIFA → GIFB).
///
/// `FarthestPointCollapse` is the hand-written Swift port of
/// `SixFour.Spec.Collapse.globalCollapseQ16` (maximin over the pooled per-frame
/// palettes, in Q16 integers). `CollapseGolden` is generated from that spec by
/// `cabal run spec-codegen`. Because the collapse is pure integer math, the port
/// must reproduce every value EXACTLY — no tolerance.
struct CollapseGoldenTests {

    @Test func collapseReproducesGoldenExactly() {
        let frames = CollapseGolden.frames
        let pooled = frames.flatMap { $0 }

        // Pooled candidate cloud size.
        #expect(pooled.count == CollapseGolden.pooledCount)

        // Integer cloud mean (the first-seed reference), truncating division.
        var sl: Int64 = 0, sa: Int64 = 0, sb: Int64 = 0
        for p in pooled { sl += Int64(p.x); sa += Int64(p.y); sb += Int64(p.z) }
        let n = Int64(pooled.count)
        let mean = SIMD3<Int32>(Int32(sl / n), Int32(sa / n), Int32(sb / n))
        #expect(mean == CollapseGolden.pooledMean)

        // The maximin chosen-index sequence + leaves, bit-for-bit.
        let result = FarthestPointCollapse().collapse(perFramePalettes: frames, k: CollapseGolden.k)
        #expect(result.chosenIndices == CollapseGolden.chosenIndices)
        #expect(result.chosenIndices.first == CollapseGolden.firstIndex)
        #expect(result.leaves == CollapseGolden.leaves)

        // Each frame re-indexed against the global leaves, bit-for-bit.
        for (f, frame) in frames.enumerated() {
            let idx = FarthestPointCollapse.reindex(frame: frame, leaves: result.leaves)
            #expect(idx == CollapseGolden.reindexedFrames[f], "frame \(f) re-index drift")
        }
    }

    /// Gamut closure: every leaf is an actual pooled input colour (never invents colour).
    @Test func everyLeafIsAPooledInput() {
        let pooled = Set(CollapseGolden.frames.flatMap { $0 })
        for leaf in CollapseGolden.leaves {
            #expect(pooled.contains(leaf), "collapse invented a colour not in the input")
        }
    }
}
