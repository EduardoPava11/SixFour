import Testing
import Foundation
import simd
@testable import SixFour

/// Gates the `GridLayout` Swift port against `SixFour.Spec.GridAxis` (Haskell
/// source of truth). The golden mirrors `spec/test/Properties/GridAxis.hs`
/// exactly — same colours, same axes, same expected placement.
struct GridLayoutTests {

    private func ic(_ i: Int, _ l: Float, _ a: Float, _ b: Float) -> IndexedColor {
        // srgb is irrelevant to layout (sort keys read .oklab); fill with anything.
        IndexedColor(index: i, oklab: SIMD3<Float>(l, a, b), srgb: SIMD3<UInt8>(0, 0, 0))
    }

    /// Pinned golden: side = 2, x = L, y = a → [[0, 3], [2, 1]].
    @Test func golden_side2_LbyA() {
        let colors = [
            ic(0, 0.1,  0.2, 0),
            ic(1, 0.9, -0.1, 0),
            ic(2, 0.2,  0.3, 0),
            ic(3, 0.8, -0.2, 0),
        ]
        let g = GridLayout.layoutN(side: 2, x: .L, y: .a, colors: colors)
        #expect(g == [[0, 3], [2, 1]])
    }

    /// A full 16×16 layout places every one of the 256 slots exactly once.
    @Test func fullLayoutIsBijection() {
        var s: UInt64 = 0xC0FFEE
        func f() -> Float { s = s &* 6364136223846793005 &+ 1; return Float(s >> 40) / Float(1 << 24) }
        let colors = (0 ..< 256).map { ic($0, f(), f() - 0.5, f() - 0.5) }
        let g = GridLayout.layout(x: .a, y: .L, colors: colors)
        #expect(g.count == 16)
        #expect(g.allSatisfy { $0.count == 16 })
        #expect(Set(g.flatMap { $0 }) == Set(0 ..< 256))
    }

    /// Deterministic regardless of input order (the (scalar, index) tie-break).
    @Test func deterministicUnderPermutation() {
        var s: UInt64 = 0xBEEF
        func f() -> Float { s = s &* 6364136223846793005 &+ 1; return Float(s >> 40) / Float(1 << 24) }
        let colors = (0 ..< 256).map { ic($0, f(), f() - 0.5, f() - 0.5) }
        #expect(GridLayout.layout(x: .chroma, y: .hue, colors: colors)
             == GridLayout.layout(x: .chroma, y: .hue, colors: colors.reversed()))
    }

    /// Wrong-size input → empty (the full-palette contract).
    @Test func wrongSizeIsEmpty() {
        #expect(GridLayout.layout(x: .L, y: .a, colors: [ic(0, 0.5, 0, 0)]).isEmpty)
    }
}
