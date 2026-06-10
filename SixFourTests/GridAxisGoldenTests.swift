import Testing
import simd
@testable import SixFour

/// Pins the Review grid's hand-ported 2-axis layout (`GridAxis.layout`, the rank-sort
/// placement) and the end-to-end `GridScript` surface (layout → `Order.fromGrid` →
/// `GridScript.surfaceColors`) to the spec golden `SixFour.Spec.GridAxis.gridLayout` /
/// `GridScript.surfaceBitmap` (`GridAxisGolden`). Integer-exact: the fixture's dyadic
/// coordinates are representable identically in Swift `Float` and Haskell `Double`, so
/// the sort placement cannot diverge by precision.
struct GridAxisGoldenTests {

    /// Rebuild the fixture as `[IndexedColor]`; index = array position (matches the spec).
    private func fixture() -> [IndexedColor] {
        GridAxisGolden.colors.enumerated().map { (i, c) in
            IndexedColor(index: i,
                         oklab: SIMD3<Float>(Float(c.x), Float(c.y), Float(c.z)),
                         srgb: SIMD3<UInt8>(0, 0, 0))
        }
    }

    private func axes() -> (GridAxis, GridAxis) {
        (GridAxis(rawValue: GridAxisGolden.xAxis)!, GridAxis(rawValue: GridAxisGolden.yAxis)!)
    }

    @Test func layoutMatchesGolden() {
        let (x, y) = axes()
        let grid = GridLayout.layout(x: x, y: y, colors: fixture())
        #expect(grid == GridAxisGolden.gridLayout)
    }

    @Test func gridScriptSurfaceMatchesGolden() {
        let (x, y) = axes()
        let grid = GridLayout.layout(x: x, y: y, colors: fixture())
        let order = Order.fromGrid(grid)
        let script = GridScript.review(side: GridAxisGolden.side, order: order)
        // Identity palette: palette[slot].x == slot, so surfaceColors[rank].x == slot at rank.
        let palette = (0 ..< (GridAxisGolden.side * GridAxisGolden.side))
            .map { SIMD3<UInt8>(UInt8($0 & 255), 0, 0) }
        let surface = script.surfaceColors(palette: palette).map { Int($0.x) }
        #expect(surface == GridAxisGolden.surface)
    }
}
