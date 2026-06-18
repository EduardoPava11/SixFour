import Testing
@testable import SixFour

/// Gate for the per-frame cube-ladder export assembly {16³, 64³, 256³} carrying the genome.
/// Self-contained: rung dimensions are deterministic, and the spliced genome round-trips out of the
/// GIF byte stream via `GenomeCarrier.extract` (the saved-learnings contract).
struct ABExportFamilyTests {

    /// A small 4³ cube (frames = side = 4, factor = 2 ⇒ rungs 2³ / 4³ / 8³) exercises the ladder.
    private func cube(frames: Int, side: Int) -> [UInt8] {
        (0..<(frames * side * side)).map { UInt8($0 % 7) }
    }

    @Test func rungDimensionsAreCorrect() {
        let fam = ABExportFamily.assemble(indexCube: cube(frames: 4, side: 4), frames: 4, side: 4,
                                          factor: 2, genome: Array(repeating: 0, count: 384))
        #expect(fam.rung64.side == 4 && fam.rung64.frames.count == 4)
        #expect(fam.rung64.frames[0].count == 16)
        #expect(fam.rung256.side == 8 && fam.rung256.frames[0].count == 64)   // 8² = 4² × 4
        #expect(fam.rung16.side == 2 && fam.rung16.frames.count == 2)         // 4 frames / 2
        #expect(fam.rung16.frames[0].count == 4)                              // 2²
    }

    @Test func genomeRoundTripsThroughTheSplicedGif() {
        let genome = (0..<384).map { $0 * 17 - 3000 }
        let fam = ABExportFamily.assemble(indexCube: cube(frames: 4, side: 4), frames: 4, side: 4,
                                          factor: 2, genome: genome)
        // A minimal GIF89a header to splice into.
        let fakeGif: [UInt8] = Array("GIF89a".utf8) + [0, 0, 0, 0, 0, 0, 0] + [0x3B]
        let exported = ABExportFamily.spliceGenome(into: fakeGif, block: fam.genomeBlock)
        #expect(GenomeCarrier.extract(exported) == .success(
            GenomeCarrier.Payload(
                header: GenomeCarrier.Header(major: 1, minor: 0, flags: 0, dof: 384, radix: 0,
                                             deviceIdHash: 0, btCompares: 0),
                coeffs: genome)))
    }
}
