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

    /// Branch-aware collapse (SIXFOUR-WIDGETS Family 2 / RADIX-CONTROLS §4 Step 1): the
    /// radix choice now reaches the collapse OUTPUT via `.branchedLeaves`, additively —
    /// the maximin `.leaves` are never disturbed.
    @Test func branchAwareCollapseProjectsLeaves() {
        let frames = CollapseGolden.frames
        let collapser = FarthestPointCollapse()

        // .b16 (flat) is the identity on BOTH the default ctor and the branch-aware path.
        let flat = collapser.collapse(perFramePalettes: frames, k: CollapseGolden.k)
        #expect(flat.branching == .b16)
        #expect(flat.branchedLeaves == flat.leaves)
        let b16 = collapser.collapse(perFramePalettes: frames, k: CollapseGolden.k, branching: .b16)
        #expect(b16.branchedLeaves == b16.leaves)

        // .b4 / .b2 thread branching into the genome projection without moving the leaves:
        // the collapse output equals BranchedPalette.projectQ16(leaves, branching) exactly.
        for branching in [PaletteBranching.b4, .b2] {
            let r = collapser.collapse(perFramePalettes: frames, k: CollapseGolden.k, branching: branching)
            #expect(r.branching == branching)
            #expect(r.leaves == flat.leaves, "branch-aware collapse must not disturb the maximin leaves")
            #expect(r.branchedLeaves == BranchedPalette.projectQ16(flat.leaves, branching: branching))
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
