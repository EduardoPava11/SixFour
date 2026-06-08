import SwiftUI
import simd

/// The rounded-rectangle PLAY BOUNDARY — a clear, VISIBLE frame INSET from the screen
/// edges (clear of the Dynamic Island at top and the home indicator at bottom), with
/// corners stepped in whole CELLS. Two jobs:
///   1. `footprintFits` — a movable widget may NOT be placed past the frame or into a
///      rounded corner (the move's nearest-free search + a launch re-home enforce it).
///   2. `isOutline` — the visible 2-cell edge `BoundaryView` draws.
///
/// Faithful Swift mirror of the designed `Spec.Boundary` (stepped rounded-rect); promote
/// to a golden-pinned spec module when the boundary phase lands. Tier-2: simd only.
enum Boundary {
    /// Lattice extent in cells (the screen): 100 × 218.
    static let cols = SixFourLattice.cols
    static let rows = SixFourLattice.rows

    /// Inset margins (cells) from each screen edge. Top clears the Dynamic Island
    /// (~16 cells = 64 pt); bottom clears the home indicator (~8 cells); sides a clear
    /// visible gutter. The frame is the rect [minC,maxC) × [minR,maxR).
    static let insetX = 3
    static let insetTop = 16
    static let insetBottom = 10
    /// Corner radius in cells (56 pt) — MATCHES the iPhone 17 Pro display corner so the
    /// 4-corner `footprintFits` test keeps a square widget fully inside the curved screen
    /// (it can never be moved where the physical rounding crops a corner).
    static let cornerCells = 14

    static var minC: Int { insetX }
    static var maxC: Int { cols - insetX }       // exclusive
    static var minR: Int { insetTop }
    static var maxR: Int { rows - insetBottom }  // exclusive

    /// Is cell `(c, r)` INSIDE the inset rounded rect? Plain rectangle except in the four
    /// corner quadrants, where it must lie within the quarter-disc of radius `cornerCells`.
    /// Integer Euclidean test (no floats), the same disc mirrored 4-fold at the inset corners.
    static func inside(_ c: Int, _ r: Int) -> Bool {
        guard c >= minC, c < maxC, r >= minR, r < maxR else { return false }
        let rad = cornerCells
        let nx = c < minC + rad ? (minC + rad) - c : (c >= maxC - rad ? c - (maxC - rad - 1) : 0)
        let ny = r < minR + rad ? (minR + rad) - r : (r >= maxR - rad ? r - (maxR - rad - 1) : 0)
        return nx * nx + ny * ny <= rad * rad
    }

    /// Does a widget footprint (`w × h` at top-left `col, row`) fit ENTIRELY inside the
    /// frame? The region is convex, so testing the four corner cells suffices.
    static func footprintFits(col: Int, row: Int, w: Int, h: Int) -> Bool {
        inside(col, row) && inside(col + w - 1, row)
            && inside(col, row + h - 1) && inside(col + w - 1, row + h - 1)
    }

    /// Is `(c, r)` within `thickness` cells of the frame edge (a 2-cell-thick visible border)?
    static func isOutline(_ c: Int, _ r: Int) -> Bool {
        guard inside(c, r) else { return false }
        for d in 1 ... 2 {
            if !inside(c - d, r) || !inside(c + d, r) || !inside(c, r - d) || !inside(c, r + d) {
                return true
            }
        }
        return false
    }
}

/// The visible rounded edge: the inset `Boundary` frame painted as a 2-cell-thick outline
/// over the full lattice, in a bright ink so it reads on the live checker ground. Inert.
struct BoundaryView: View {
    var ink: SIMD3<UInt8> = SIMD3(90, 210, 255)   // bright cyan frame
    var body: some View {
        CellSprite(cols: Boundary.cols, rows: Boundary.rows, cellPt: GlobalLattice.gif(1)) { c, r in
            Boundary.isOutline(c, r) ? ink : nil
        }
        .frame(width: GlobalLattice.gif(Boundary.cols), height: GlobalLattice.gif(Boundary.rows))
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
