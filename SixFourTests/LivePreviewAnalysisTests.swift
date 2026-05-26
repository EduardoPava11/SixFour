import Testing
import Foundation
import simd
@testable import SixFour

/// The live diversity instrument's analysis: distinct 16³ OKLab bins +
/// dominant hue from one preview tile. The gauge must read the *same* coverage
/// the renderer optimizes (spec binning), so flat scenes read near-zero and
/// colour-rich scenes saturate the gauge.
struct LivePreviewAnalysisTests {

    private let side = 64
    private let count = 64 * 64        // 4096
    private let bins = SixFourShape.coverageBinsPerAxis   // 16

    private func tile(_ pixels: [SIMD3<Float>]) -> OKLabTile {
        OKLabTile(side: side, pixels: pixels, captureNanos: 0, palette: [], finalShift: 0)
    }

    @Test func flatSceneOccupiesOneBinAndTinyGauge() {
        let color = SIMD3<Float>(0.5, 0.0, 0.0)
        let r = LivePreviewAnalysis.analyze(tile(Array(repeating: color, count: count)))
        #expect(r.occupiedBins == 1, "a single colour occupies exactly one bin")
        #expect(abs(r.gauge - 1.0 / Float(SixFourShape.K)) < 1e-5, "gauge = 1/K for one bin")
        // Dominant tint is that colour, exactly (one bin → mean == the colour).
        #expect(r.tint == ColorScience.okLabToSRGB8(OKLab(color)))
        #expect(r.accents.first == r.tint)
    }

    @Test func colourRichSceneSaturatesTheGauge() {
        // One pixel at the centre of every 16³ bin → 4096 distinct bins.
        var px = [SIMD3<Float>](); px.reserveCapacity(count)
        for lB in 0..<bins {
            for aB in 0..<bins {
                for bB in 0..<bins {
                    let L = (Float(lB) + 0.5) / Float(bins)
                    let a = (Float(aB) + 0.5) / Float(bins) - 0.5
                    let b = (Float(bB) + 0.5) / Float(bins) - 0.5
                    px.append(SIMD3<Float>(L, a, b))
                }
            }
        }
        #expect(px.count == count)
        let r = LivePreviewAnalysis.analyze(tile(px))
        #expect(r.occupiedBins >= SixFourShape.K, "rich scene exceeds K distinct bins")
        #expect(r.gauge == 1.0, "gauge saturates at ≥ K bins")
    }

    @Test func dominantHueIsTheMostPopulatedBin() {
        let dominant = SIMD3<Float>(0.3, 0.2, 0.1)   // 3000 px
        let minor    = SIMD3<Float>(0.7, -0.2, -0.1) // 1096 px
        let px = Array(repeating: dominant, count: 3000)
                 + Array(repeating: minor, count: count - 3000)
        let r = LivePreviewAnalysis.analyze(tile(px))
        #expect(r.occupiedBins == 2)
        #expect(r.tint == ColorScience.okLabToSRGB8(OKLab(dominant)),
                "tint is the most-populated bin's colour")
    }

    @Test func emptyTileIsTheEmptyReadout() {
        let r = LivePreviewAnalysis.analyze(tile([]))
        #expect(r.occupiedBins == 0 && r.gauge == 0)
    }
}
