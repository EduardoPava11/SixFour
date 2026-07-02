import Testing
@testable import SixFour

/// Gates for the CPU octant rung + the decide preview's invented expansion
/// (`OctantCube` — the engine behind "what accepting would ship").
struct OctantCubeTests {

    /// The Swift lift is byte-exact to the Zig oracle, and unlift inverts it —
    /// including negatives (the floor-division sign path).
    @Test func liftMatchesZigAndUnliftInverts() throws {
        var seed: UInt64 = 0x4F43_5455_4265_5354
        func next() -> Int {
            seed ^= seed >> 12; seed ^= seed << 25; seed ^= seed >> 27
            return Int(Int32(truncatingIfNeeded: seed &* 0x2545_F491_4F6C_DD1D) % 60000)
        }
        for _ in 0 ..< 200 {
            let block = (0 ..< 8).map { _ in next() }
            let swift = OctantCube.lift(block)
            let zig = try #require(SixFourNative.octantLift(block: block.map(Int32.init)))
            #expect(swift == zig.map(Int.init))
            #expect(OctantCube.unlift(coarse: swift[0], detail: Array(swift[1...])) == block)
        }
    }

    /// Zero detail (nil θ / the zero gene) makes the up-rung the deterministic
    /// nearest-neighbour floor: every 2×2×2 block is its parent's constant.
    @Test func zeroThetaUpRungIsTheNearestNeighbourFloor() {
        let vol = (0 ..< 8).map { $0 * 1000 - 3500 }   // a 2³ cube, signed values
        let up = OctantCube.upRung(vol, side: 2, theta: nil)
        #expect(up.count == 64)
        for t in 0 ..< 4 {
            for r in 0 ..< 4 {
                for c in 0 ..< 4 {
                    let parent = vol[((t / 2) * 2 + (r / 2)) * 2 + (c / 2)]
                    #expect(up[(t * 4 + r) * 4 + c] == parent)
                }
            }
        }
    }

    /// A nonzero θ invents detail: the gene expansion differs from the floor on
    /// the gene channel and NOWHERE else (a/b ride the floor).
    @Test func geneExpandsDifferOnlyOnTheGeneChannel() throws {
        // A 16-frame × 16² substrate with varied values (deterministic).
        let substrate: [[VoxelReduce.Px]] = (0 ..< 16).map { t in
            (0 ..< 256).map { p in
                (l: (t * 256 + p) % 40000, a: (p * 37) % 9000 - 4500, b: (t * 911) % 7000 - 3500)
            }
        }
        let floor = try #require(OctantCube.expandProposal(substrate: substrate, theta: nil))
        // A θ big enough that predictCommitted clears the Q16 commit margin.
        var theta = [Double](repeating: 0, count: 21)
        theta[0] = 0.05   // band 0, constant feature → detail ≈ 3277 everywhere
        let gene = try #require(OctantCube.expandProposal(substrate: substrate, theta: theta))
        #expect(floor.count == 64 * 64 * 64 * 3 && gene.count == floor.count)

        var lDiffers = false
        for i in stride(from: 0, to: floor.count, by: 3) {
            if gene[i] != floor[i] { lDiffers = true }
            #expect(gene[i + 1] == floor[i + 1])   // a: floor everywhere
            #expect(gene[i + 2] == floor[i + 2])   // b: floor everywhere
        }
        #expect(lDiffers)
    }

    /// The floor expansion preserves every 16³ voxel as its 4×4×4 block constant —
    /// the proposal really is what the preview magnifies.
    @Test func floorExpansionMagnifiesTheProposalExactly() throws {
        let substrate: [[VoxelReduce.Px]] = (0 ..< 16).map { t in
            (0 ..< 256).map { p in (l: t * 100 + p, a: -p, b: t) }
        }
        let out = try #require(OctantCube.expandProposal(substrate: substrate, theta: nil))
        for t in 0 ..< 16 {
            for y in 0 ..< 16 {
                for x in 0 ..< 16 {
                    let px = substrate[t][y * 16 + x]
                    let i = (((t * 4) * 64 + (y * 4)) * 64 + (x * 4)) * 3
                    #expect(Int(out[i]) == px.0 && Int(out[i + 1]) == px.1 && Int(out[i + 2]) == px.2)
                }
            }
        }
    }
}
