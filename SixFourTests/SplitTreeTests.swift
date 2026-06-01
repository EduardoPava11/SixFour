import Testing
import Foundation
import simd
@testable import SixFour

/// Gates the `SplitTree` Swift port against `SixFour.Spec.SplitTree` (Haskell
/// source of truth). Mirrors `spec/test/Properties/SplitTree.hs` — the same
/// greyscale golden — and pins the branching collapse. Added BEFORE the treemap
/// refactor so the refactor cannot silently drift the source of truth.
struct SplitTreeTests {

    private func ic(_ i: Int, _ l: Float, _ a: Float = 0, _ b: Float = 0) -> IndexedColor {
        IndexedColor(index: i, oklab: SIMD3<Float>(l, a, b), srgb: SIMD3<UInt8>(0, 0, 0))
    }

    private struct LCG { var s: UInt64; mutating func f() -> Float { s = s &* 6364136223846793005 &+ 1; return Float(s >> 40) / Float(1 << 24) } }
    private func palette256(_ seed: UInt64) -> [IndexedColor] {
        var g = LCG(s: seed)
        return (0 ..< 256).map { ic($0, g.f(), g.f() - 0.5, g.f() - 0.5) }
    }

    /// Pinned golden: four greyscale points (a=b=0 → widest axis L). Sorted by
    /// (L, index): (0.1,0),(0.2,2),(0.8,3),(0.9,1) → leaf order [0,2,3,1], root
    /// splits L at 0.5.
    @Test func golden_greyscale() {
        let t = SplitTree.build([ic(0, 0.1), ic(1, 0.9), ic(2, 0.2), ic(3, 0.8)])
        #expect(t.leaves.map(\.index) == [0, 2, 3, 1])
        guard case let .branch(axis, pos, _, _) = t else {
            Issue.record("root should be a branch"); return
        }
        #expect(axis == .L)
        #expect(abs(pos - 0.5) < 1e-6)
    }

    /// Every branching view (16²/4⁴/2⁸) preserves the full 256-leaf set.
    @Test func collapsePreservesLeaves() {
        let t = SplitTree.build(palette256(0x5EED))
        for b in [PaletteBranching.b16, .b4, .b2] {
            #expect(Set(t.view(b).leaves.map(\.index)) == Set(0 ..< 256))
            #expect(t.view(b).leaves.count == 256)        // factor^depth == 256
        }
    }

    /// Deterministic regardless of input order (pinned (coord, index) tie-break).
    @Test func deterministicUnderPermutation() {
        let p = palette256(0xABCD)
        #expect(SplitTree.build(p).leaves.map(\.index) == SplitTree.build(p.reversed()).leaves.map(\.index))
    }

    /// Single-colour and the edge of the build recursion.
    @Test func singleLeaf() {
        let t = SplitTree.build([ic(7, 0.5)])
        #expect(t.leaves.map(\.index) == [7])
    }
}
