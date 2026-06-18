import Testing
@testable import SixFour

/// Gate for the gene archive (saved learnings) + the NetSynth256 scaffold. Pure functions tested
/// in-memory (no disk).
struct GeneArchiveTests {

    @Test func distanceSqIsZeroForEqual() {
        #expect(GeneArchive.distanceSq([1, -2, 3], [1, -2, 3]) == 0)
        #expect(GeneArchive.distanceSq([0, 0], [3, 4]) == 25)
    }

    @Test func nearestPicksTheClosestGene() {
        let genes = [
            Gene(coeffs: [100, 100, 100], compares: 1),
            Gene(coeffs: [0, 0, 0], compares: 2),
            Gene(coeffs: [-50, -50, -50], compares: 3),
        ]
        let near = GeneArchive.nearest(to: [10, 10, 10], in: genes)
        #expect(near == genes[1])   // [0,0,0] is closest to [10,10,10]
    }

    @Test func nearestOfEmptyIsNil() {
        #expect(GeneArchive.nearest(to: [1, 2, 3], in: []) == nil)
    }

    @Test func netSynth256IsFloorIdentityWithoutWeights() {
        let floor: [UInt8] = (0..<64).map { UInt8($0 % 13) }
        // No trained weights ⇒ synthesis equals the nearest-neighbour floor exactly.
        #expect(NetSynth256.synthesize(floor: floor, genome: Array(repeating: 0, count: 384)) == floor)
        #expect(NetSynth256.synthesize(floor: floor, genome: [1, 2, 3]) == floor)
        #expect(NetSynth256.hasLearnedWeights == false)
    }
}
