import Testing
@testable import SixFour

/// The curate-build engine gates (LAUNCH L1.3 — "form follows function"): every
/// stage the curate surface fronts is proven across its tiers BEFORE any widget
/// composes it.
///
///   1. GPU chain == the shipped decide preview (Metal ladder vs `OctantCube`
///      CPU, all three channels, gene arm included) — the surfaces are
///      interchangeable by proof.
///   2. GPU ladder == the Zig oracle iterated (Metal vs `s4_cube_expand_rung`
///      twice) — the chain introduces nothing the single-rung twin didn't gate.
///   3. The frame slicing == the spec layout pin (position-coded volume,
///      mirrors `Spec.CurateRealize.lawFramesPartitionVolume`).
///   4. The whole sandwich int→int: constant substrate → GPU floor ladder →
///      Zig quantizer → every pixel reproduces the constant exactly (the
///      zero-gene floor survives to indexed-GIF content).
struct CurateBuilderTests {

    private struct Rng {
        var state: UInt64
        mutating func next() -> UInt64 {
            state ^= state >> 12; state ^= state << 25; state ^= state >> 27
            return state &* 0x2545_F491_4F6C_DD1D
        }
        mutating func int(bound: Int) -> Int {
            Int(truncatingIfNeeded: next() % UInt64(2 * bound + 1)) - bound
        }
    }

    private func randomSubstrate(side: Int, seed: UInt64) -> [[VoxelReduce.Px]] {
        var rng = Rng(state: seed)
        return (0 ..< side).map { _ in
            (0 ..< side * side).map { _ in
                (rng.int(bound: 20000), rng.int(bound: 20000), rng.int(bound: 20000))
            }
        }
    }

    /// GATE 1: the GPU build at rungs 2 is BIT-EQUAL to the shipped decide
    /// preview (`OctantCube.expandProposal`) — floor AND gene arms.
    @Test func gpuBuildEqualsTheDecidePreview() throws {
        let builder = try #require(CurateBuilder())
        let sub = randomSubstrate(side: 16, seed: 0x6355_5241_5445_0001)
        let theta: [Double] = [0.3, -0.08, 0.02] + Array(repeating: 0.015, count: 18)

        let gpuFloor = try #require(builder.build(substrate: sub, theta: nil, rungs: 2))
        let cpuFloor = try #require(OctantCube.expandProposal(substrate: sub, theta: nil))
        #expect(gpuFloor == cpuFloor)

        let gpuGene = try #require(builder.build(substrate: sub, theta: theta, rungs: 2))
        let cpuGene = try #require(OctantCube.expandProposal(substrate: sub, theta: theta))
        #expect(gpuGene == cpuGene)
    }

    /// GATE 2: the ladder is exactly the Zig oracle iterated — the chain adds
    /// nothing the single-rung twin didn't already gate (floor arm, side 4 → 16).
    @Test func ladderFloorEqualsIteratedZigOracle() throws {
        let builder = try #require(CurateBuilder())
        var rng = Rng(state: 0x6355_5241_5445_0002)
        let vol = (0 ..< 64).map { _ in Int32(rng.int(bound: 30000)) }

        let gpu = try #require(builder.expandLadder(base: vol, side: 4, rungs: 2, theta: nil))
        let zig1 = try #require(SixFourNative.cubeExpandRung(volume: vol, side: 4, details: nil))
        let zig2 = try #require(SixFourNative.cubeExpandRung(volume: zig1, side: 8, details: nil))
        #expect(gpu == zig2)
    }

    /// GATE 3: the frame slicing is the spec layout pin — on a position-coded
    /// volume (channel ch of voxel i carries 3·i + ch), frame t pixel p is
    /// exactly its own coordinates (mirrors `lawFramesPartitionVolume`).
    @Test func volumeFramesLayoutIsExact() throws {
        let side = 4
        let n = side * side * side
        var flat = [Int32]()
        flat.reserveCapacity(n * 3)
        for i in 0 ..< n {
            let base = Int32(3 * i)
            flat.append(base)
            flat.append(base + 1)
            flat.append(base + 2)
        }
        let frames = try #require(CurateBuilder.volumeFrames(side: side, flat: flat))
        #expect(frames.count == side)
        for t in 0 ..< side {
            for p in 0 ..< side * side {
                let i = t * side * side + p
                #expect(frames[t][p * 3] == Int32(3 * i))
                #expect(frames[t][p * 3 + 1] == Int32(3 * i + 1))
                #expect(frames[t][p * 3 + 2] == Int32(3 * i + 2))
            }
        }
        // A short buffer refuses rather than mis-slices.
        #expect(CurateBuilder.volumeFrames(side: side, flat: Array(flat.dropLast())) == nil)
    }

    /// GATE 4: the whole sandwich, int → int: a FLAT substrate through the GPU
    /// floor ladder and the Zig quantizer realizes losslessly to the constant —
    /// zero-gene == floor holds all the way to indexed-GIF content
    /// (mirrors `lawConstantFloorRealizesToOneColour` on the real kernels).
    @Test func constantFloorRealizesLosslessThroughTheNativeQuantizer() throws {
        let builder = try #require(CurateBuilder())
        let colour: VoxelReduce.Px = (12288, -4096, 6553)
        let sub: [[VoxelReduce.Px]] = (0 ..< 4).map { _ in
            (0 ..< 16).map { _ in colour }
        }
        let vol = try #require(builder.build(substrate: sub, theta: nil, rungs: 2))
        let realized = try #require(CurateBuilder.realize(volume: vol, side: 16, k: 4, lloydIters: 1))
        #expect(realized.count == 16)
        for q in realized {
            for idx in q.indices {
                let c = Int(idx) * 3
                #expect(Int(q.centroids[c]) == colour.0)
                #expect(Int(q.centroids[c + 1]) == colour.1)
                #expect(Int(q.centroids[c + 2]) == colour.2)
            }
        }
    }
}
