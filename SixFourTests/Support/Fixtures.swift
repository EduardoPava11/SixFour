import Foundation
import simd

/// Deterministic LCG shared by the Stage B Sinkhorn test fixtures.
///
/// Previously duplicated three ways: a `SeedableLCG` struct in
/// `StageBSinkhornTests` and the same arithmetic inlined twice as closures in
/// `LogDomainSinkhornTests`. The advance-then-transform order is preserved
/// exactly, so the random sequence (and therefore every surjectivity outcome
/// the tests assert on) is byte-identical to the old inline versions.
struct SeedableLCG {
    var state: UInt64
    init(seed: UInt64) { self.state = seed &+ 0x9E37_79B9_7F4A_7C15 }
    mutating func nextUInt() -> UInt64 {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return state
    }
    mutating func next01() -> Double {
        Double(nextUInt() >> 11) / Double(1 << 53)
    }
}

/// Synthetic per-frame palettes + index maps for Stage B merge tests.
struct SinkhornFixture {
    let palettes: [[SIMD3<Float>]]
    let indices: [[UInt8]]
}

/// Build a synthetic Stage B fixture, deterministic in `seed`. `pixelsPerFrame`
/// must be a multiple of K=256; each of the 256 palette slots is emitted
/// `pixelsPerFrame / 256` times per frame, then shuffled. Sized large enough
/// that adaptive-θ Sinkhorn can reach a surjective hard-NN remap — small
/// candidate sets don't have enough donor mass for K=256 surjectivity.
func makeSinkhornFixture(
    seed: UInt64,
    frames: Int,
    pixelsPerFrame: Int = 4096
) -> SinkhornFixture {
    precondition(pixelsPerFrame % 256 == 0, "pixelsPerFrame must be a multiple of K=256")
    let repeatsPerSlot = pixelsPerFrame / 256
    var rng = SeedableLCG(seed: seed)
    var palettes: [[SIMD3<Float>]] = []
    var indices: [[UInt8]] = []
    for _ in 0..<frames {
        var pal: [SIMD3<Float>] = []
        pal.reserveCapacity(256)
        for _ in 0..<256 {
            let l = Float(rng.next01())
            let a = Float(rng.next01() * 0.8 - 0.4)
            let b = Float(rng.next01() * 0.8 - 0.4)
            pal.append(SIMD3<Float>(l, a, b))
        }
        palettes.append(pal)
        // Each palette slot appears `repeatsPerSlot` times, shuffled.
        var idx: [UInt8] = []
        idx.reserveCapacity(pixelsPerFrame)
        for slot in 0..<256 {
            for _ in 0..<repeatsPerSlot {
                idx.append(UInt8(slot))
            }
        }
        for i in stride(from: idx.count - 1, to: 0, by: -1) {
            let j = Int(rng.nextUInt() % UInt64(i + 1))
            idx.swapAt(i, j)
        }
        indices.append(idx)
    }
    return SinkhornFixture(palettes: palettes, indices: indices)
}
