import Testing
@testable import SixFour

/// Byte-exact gate for the VoxelReduce Swift port.
///
/// `VoxelReduce` is the hand-written Swift port of `SixFour.Spec.VoxelReduce` — the joint
/// spatio-temporal `(2×2)×(2×2)→1` reduction `64³ ↔ 16³`, a composition of `CubeLadder`
/// (spatial, reused via `RGBT4DLift`) and `TemporalLoop` (temporal, reused via `RGBT4DLift.sLift`).
/// `VoxelReduceGolden` is GENERATED from the spec by `cabal run spec-codegen`
/// (`SixFour.Codegen.VoxelReduce`), so the port rides the same drift gate as `RGBT4DGolden`.
/// Pure integer (Q16) math ⇒ the substrate must match EXACTLY (the floor-division parity Haskell
/// `div` and Swift `/` disagree on for negatives is handled by `RGBT4DLift.floorDiv`).
struct VoxelReduceGoldenTests {

    private func cube(from flat: [Int], side: Int, frames: Int) -> [[VoxelReduce.Px]] {
        let nPos = side * side
        var out = [[VoxelReduce.Px]](), idx = 0
        for _ in 0..<frames {
            var frame = [VoxelReduce.Px]()
            for _ in 0..<nPos { frame.append((flat[idx], flat[idx + 1], flat[idx + 2])); idx += 3 }
            out.append(frame)
        }
        return out
    }

    private func flat(_ cube: [[VoxelReduce.Px]]) -> [Int] {
        cube.flatMap { $0.flatMap { [$0.0, $0.1, $0.2] } }
    }

    /// The substrate of the reduction matches the spec golden byte-exact (pins spatial-then-temporal).
    @Test func substrateMatchesGeneratedGolden() {
        let c = cube(from: VoxelReduceGolden.cubeFlat, side: VoxelReduceGolden.side, frames: VoxelReduceGolden.frames)
        let r = VoxelReduce.reduce(VoxelReduceGolden.levels, VoxelReduceGolden.side, c)
        #expect(flat(r.substrate) == VoxelReduceGolden.substrateFlat)
    }

    /// The reduction is lossless: expand ∘ reduce = id (the 64³↔16³ bijection on device).
    @Test func reduceExpandIsIdentity() {
        let c = cube(from: VoxelReduceGolden.cubeFlat, side: VoxelReduceGolden.side, frames: VoxelReduceGolden.frames)
        let r = VoxelReduce.reduce(VoxelReduceGolden.levels, VoxelReduceGolden.side, c)
        #expect(flat(VoxelReduce.expand(VoxelReduceGolden.levels, VoxelReduceGolden.side, r)) == flat(c))
    }

    /// Two levels (×4 = the shipped 64→16 step at this fixture's scale) also round-trips exactly.
    @Test func twoLevelReduceExpandIsIdentity() {
        let c = cube(from: VoxelReduceGolden.cubeFlat, side: VoxelReduceGolden.side, frames: VoxelReduceGolden.frames)
        let r = VoxelReduce.reduce(2, VoxelReduceGolden.side, c)
        #expect(flat(VoxelReduce.expand(2, VoxelReduceGolden.side, r)) == flat(c))
    }
}
