import SwiftUI
import simd

/// Swift mirror of `SixFour.Spec.CellShapes` — the golden cell-mask geometry the
/// GRID HUD primitives draw with (the closed drawing vocabulary, §5). The 64-tick
/// ring endpoint table is the *generated* `SixFourCellShapes.ringTickEndpoints`
/// (`Generated/CellShapesContract.swift`), pinned byte-for-byte by `cabal test`;
/// the renderer indexes it instead of recomputing `atan2` per cell.
///
/// `cellAtRadius` reuses the spec's `floor`-based formula (NOT `round`) so a cell it
/// computes at the tick radius is bit-identical to the generated endpoint — the
/// contract's `selfCheck()` asserts exactly this Haskell↔Swift parity.
enum CellShapes {
    /// The generated golden endpoint table (64 cells, k = 0 at top, clockwise).
    static let ringTickEndpoints = SixFourCellShapes.ringTickEndpoints
    /// The radius (cells) at which a gauge tick terminates.
    static let ringTickRadius = SixFourCellShapes.ringTickRadius

    /// The cell at tick `k`'s ray at `radius`, on a `side×side` sprite. Mirrors
    /// `SixFour.Spec.CellShapes.cellAtRadius`: `θ = 2πk/ticks`, 0 at top, clockwise,
    /// `floor` for exact spec parity. Per-TICK (a closed form), never per-cell `atan2`.
    @inline(__always)
    static func cellAtRadius(side: Int, radius: Double, tick k: Int, ticks: Int) -> (col: Int, row: Int) {
        let c0 = Double(side) / 2
        let theta = 2 * Double.pi * Double(k) / Double(ticks)
        let px = c0 + radius * sin(theta)
        let py = c0 - radius * cos(theta)
        return (Int(floor(px)), Int(floor(py)))
    }

    /// Cell `(c,r)` is inside the filled disc of `radius` on a `side×side` sprite.
    @inline(__always)
    static func inDisc(side: Int, radius: Double, _ c: Int, _ r: Int) -> Bool {
        let c0 = Double(side) / 2
        return CellGeom.dist(c, r, c0, c0) <= radius
    }

    /// Cell `(c,r)` is inside the half-open annulus `(r0, r1]` on a `side×side` sprite.
    @inline(__always)
    static func inAnnulus(side: Int, _ r0: Double, _ r1: Double, _ c: Int, _ r: Int) -> Bool {
        let c0 = Double(side) / 2
        let d = CellGeom.dist(c, r, c0, c0)
        return d > r0 && d <= r1
    }
}
