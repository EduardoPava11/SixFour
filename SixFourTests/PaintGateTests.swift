import Testing
@testable import SixFour

/// W1 gate (2026-07-03): the paint budget GATES WHERE the gene invents. Swift
/// twins of the spec laws `lawZeroPaintVolumeIsFloor` (an all-off mask is the
/// byte-exact floor), `lawPaintGatesBlockLocal` (one painted 16³ cell moves ONLY
/// its own 4³ block of the 64³), and `lawMaskUpsampleIsBlockReplication` — plus
/// the GPU/CPU gated-parity extension of `CurateBuilderTests` gate 1, so the
/// Metal ladder and the CPU preview stay interchangeable WITH paint, by proof.
struct PaintGateTests {

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

    private let theta: [Double] = [0.3, -0.08, 0.02] + Array(repeating: 0.015, count: 18)

    /// The Morton→device conversion and the nil shortcut: a neutral budget masks
    /// to nil (callers keep the whole-volume arm), and painting ONE cell yields
    /// exactly one live bit at the right device (t,r,c) index.
    @Test func deviceMaskNeutralIsNilAndSingleCellLandsAtDeviceIndex() throws {
        #expect(NudgePaintModel.deviceMask(budget: SixFourModelIO.neutralNudge()) == nil)

        var budget = SixFourModelIO.neutralNudge()
        let (x, y, z) = (5, 9, 3)
        budget[NudgePaintModel.mortonIndex(x: x, y: y, z: z)][7] = 32
        let mask = try #require(NudgePaintModel.deviceMask(budget: budget))
        #expect(mask.count == 16 * 16 * 16)
        #expect(mask.filter { $0 }.count == 1)
        #expect(mask[(z * 16 + y) * 16 + x])            // device order: t=z, row=y, col=x
    }

    /// `lawZeroPaintVolumeIsFloor` at ship shape: an all-off mask gates every
    /// cell, so the gene arm IS the deterministic floor byte-for-byte, for a
    /// genuinely nonzero θ.
    @Test func allOffMaskIsTheByteExactFloor() throws {
        let sub = randomSubstrate(side: 16, seed: 0x5041_494E_5400_0001)
        let allOff = [Bool](repeating: false, count: 16 * 16 * 16)
        let gated = try #require(OctantCube.expandProposal(substrate: sub, theta: theta,
                                                           paintMask: allOff))
        let floor = try #require(OctantCube.expandProposal(substrate: sub, theta: nil))
        #expect(gated == floor)
    }

    /// `lawPaintGatesBlockLocal` at ship shape: ONE painted 16-cell moves ONLY
    /// its own 4³ block of the 64³ (every other voxel is the floor byte-for-byte)
    /// and genuinely moves it. Also pins the nil-mask shortcut: ungated == the
    /// legacy whole-volume gene arm.
    @Test func onePaintedCellMovesOnlyItsOwnBlock() throws {
        let sub = randomSubstrate(side: 16, seed: 0x5041_494E_5400_0002)
        let (ct, cr, cc) = (3, 12, 7)                    // the painted cell (t, r, c)
        var mask = [Bool](repeating: false, count: 16 * 16 * 16)
        mask[(ct * 16 + cr) * 16 + cc] = true

        let gated = try #require(OctantCube.expandProposal(substrate: sub, theta: theta,
                                                           paintMask: mask))
        let floor = try #require(OctantCube.expandProposal(substrate: sub, theta: nil))
        let legacy = try #require(OctantCube.expandProposal(substrate: sub, theta: theta))
        #expect(gated != legacy)                          // the gate is not a no-op
        #expect(legacy != floor)                          // θ genuinely invents

        var insideMoved = false
        var outsideMismatches = 0
        for t in 0 ..< 64 {
            for r in 0 ..< 64 {
                for c in 0 ..< 64 {
                    let inBlock = t / 4 == ct && r / 4 == cr && c / 4 == cc
                    let base = ((t * 64 + r) * 64 + c) * 3
                    for ch in 0 ..< 3 where gated[base + ch] != floor[base + ch] {
                        if inBlock { insideMoved = true } else { outsideMismatches += 1 }
                    }
                }
            }
        }
        #expect(outsideMismatches == 0)                   // floor everywhere else
        #expect(insideMoved)                              // the painted block moves
    }

    /// `lawMaskUpsampleIsBlockReplication` in Swift: each bit governs exactly its
    /// 2×2×2 children, no smear, no swap.
    @Test func maskUpsampleIsBlockReplication() throws {
        var rng = Rng(state: 0x5041_494E_5400_0003)
        let side = 4
        let mask = (0 ..< side * side * side).map { _ in rng.next() % 2 == 0 }
        let up = OctantCube.upsampleMask(side: side, mask: mask)
        let s2 = side * 2
        #expect(up.count == s2 * s2 * s2)
        for tt in 0 ..< s2 {
            for rr in 0 ..< s2 {
                for cc in 0 ..< s2 {
                    let parent = ((tt / 2) * side + (rr / 2)) * side + (cc / 2)
                    #expect(up[(tt * s2 + rr) * s2 + cc] == mask[parent])
                }
            }
        }
    }

    /// The GPU ladder and the CPU preview stay bit-equal WITH the paint gate
    /// (extends `CurateBuilderTests` gate 1 to the gated arm).
    @Test func gpuGatedBuildEqualsCpuGatedPreview() throws {
        let builder = try #require(CurateBuilder())
        let sub = randomSubstrate(side: 16, seed: 0x5041_494E_5400_0004)
        var mask = [Bool](repeating: false, count: 16 * 16 * 16)
        for i in stride(from: 0, to: mask.count, by: 37) { mask[i] = true }

        let gpu = try #require(builder.build(substrate: sub, theta: theta,
                                             rungs: 2, paintMask: mask))
        let cpu = try #require(OctantCube.expandProposal(substrate: sub, theta: theta,
                                                         paintMask: mask))
        #expect(gpu == cpu)
    }
}
