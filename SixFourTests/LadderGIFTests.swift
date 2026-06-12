import Testing
import simd
@testable import SixFour

/// Gate for the pure GIF-ladder index transforms (SIXFOUR-WIDGETS Family 1): the global
/// reindex (the 64³-B / GIFB core) and the 16³ working-copy subsample (the cheap,
/// any-time export). All byte-exact — no tolerance.
struct LadderGIFTests {

    // MARK: Global reindex (GIFB)

    @Test func globalRemapPicksNearestLeaf() {
        let global: [OKLabQ16] = [
            OKLabQ16(0, 0, 0),
            OKLabQ16(65536, 0, 0),
            OKLabQ16(0, 65536, 0),
        ]
        // Three per-frame slots, each sitting next to a different global leaf.
        let perFrame: [OKLabQ16] = [
            OKLabQ16(120, 0, 0),       // → leaf 0
            OKLabQ16(60000, 30, 0),    // → leaf 1
            OKLabQ16(40, 61000, 12),   // → leaf 2
        ]
        let remap = LadderGIF.globalRemap(perFramePalette: perFrame, global: global)
        #expect(remap == [0, 1, 2])
        // Cross-check every entry against the canonical nearest rule.
        for (i, c) in perFrame.enumerated() {
            #expect(Int(remap[i]) == FarthestPointCollapse.nearestQ16(c, global))
            #expect(remap[i] < UInt8(global.count))
        }
    }

    @Test func reindexFrameAppliesLUT() {
        #expect(LadderGIF.reindexFrame([0, 1, 2, 1, 0], remap: [2, 0, 1]) == [2, 0, 1, 0, 2])
    }

    @Test func reindexCubeReindexesEveryFrameAgainstGlobal() {
        let global: [OKLabQ16] = [OKLabQ16(0, 0, 0), OKLabQ16(65536, 0, 0)]
        let perFramePalettes: [[OKLabQ16]] = [
            [OKLabQ16(10, 0, 0), OKLabQ16(64000, 0, 0)],   // remap → [0, 1]
            [OKLabQ16(64000, 0, 0), OKLabQ16(10, 0, 0)],   // remap → [1, 0]
        ]
        let frames: [[UInt8]] = [[0, 1, 0], [0, 1, 1]]
        let out = LadderGIF.reindexCubeToGlobal(perFramePalettes: perFramePalettes,
                                                frameIndices: frames, global: global)
        #expect(out[0] == [0, 1, 0])   // LUT [0,1] applied to [0,1,0]
        #expect(out[1] == [1, 0, 0])   // LUT [1,0] applied to [0,1,1]
        // Every output index addresses the global table.
        for frame in out { for i in frame { #expect(i < UInt8(global.count)) } }
    }

    // MARK: 16³ working copy

    @Test func spatialDownsampleTakesBlockCorners() {
        let f = (0 ..< 16).map { UInt8($0) }          // a 4×4 frame, row-major 0…15
        // 4→2, stride 2: corners at (0,0)=0,(0,1)=2,(1,0)=8,(1,1)=10.
        #expect(LadderGIF.spatialDownsample(f, srcSide: 4, dstSide: 2) == [0, 2, 8, 10])
    }

    @Test func spatialDownsample64to16HasRightSize() {
        let frame64 = [UInt8](repeating: 7, count: 64 * 64)
        #expect(LadderGIF.spatialDownsample(frame64, srcSide: 64, dstSide: 16).count == 16 * 16)
    }

    @Test func spatialDownsampleRejectsIndivisible() {
        let f = (0 ..< 9).map { UInt8($0) }            // 3×3, not divisible by 2
        #expect(LadderGIF.spatialDownsample(f, srcSide: 3, dstSide: 2) == f)  // unchanged
    }

    @Test func temporalSubsampleIsEvenFloorStride() {
        let frames = Array(0 ..< 8)
        #expect(LadderGIF.temporalSubsample(frames, dstCount: 4) == [0, 2, 4, 6])
        // 64 → 16 keeps the first frame and spreads across the burst.
        let big = Array(0 ..< 64)
        let sub = LadderGIF.temporalSubsample(big, dstCount: 16)
        #expect(sub.count == 16)
        #expect(sub.first == 0)
        #expect(sub == stride(from: 0, to: 64, by: 4).map { $0 })
    }

    @Test func workingCopyIs16Cubed() {
        let cube = (0 ..< 64).map { _ in [UInt8](repeating: 3, count: 64 * 64) }
        let wc = LadderGIF.workingCopy(frameIndices: cube)
        #expect(wc.count == 16)
        #expect(wc.allSatisfy { $0.count == 16 * 16 })
    }
}
