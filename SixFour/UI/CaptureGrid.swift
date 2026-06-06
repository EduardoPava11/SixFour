import SwiftUI

/// THE CAPTURE SCENE'S ONE UNIFORM CELL.
///
/// The entire capture screen is a single grid of identical cells — every preview pixel,
/// every palette swatch, and every background-checker cell are **the same size**.
/// That is the product law for this screen ("all cells one size"). Because the preview is
/// 64 cells wide and must still fit with margin to clear the rounded corners and to rotate
/// into the 64³ cube for analysis, the capture cell is **finer than the 6 pt `GlobalLattice`
/// chrome atom** used on other screens. This screen owns its own uniform pitch; the 6 pt
/// lattice still governs Review / canonical chrome.
///
/// Geometric law: preview = 64 cells, palette = 16 cells ⇒ the preview is ALWAYS 4× the
/// palette. One `cell` sets all three at once.
enum CaptureGrid {
    /// The one cell: 4 pt = 12 device-px @3x. Preview = 64 cells (256 pt), palette = 16
    /// cells (64 pt). (The palette IS the shutter — 16² ≥ the HIG tap floor.)
    static let cell: CGFloat = 4

    static let screenW: CGFloat = ScreenLattice.screenW   // 402 (iPhone 17 Pro)
    static let screenH: CGFloat = ScreenLattice.screenH   // 874

    /// Screen size in cells (ceil — the last col/row bleeds a couple pt off-screen).
    static let cols = Int((screenW / cell).rounded(.up))   // 101
    static let rows = Int((screenH / cell).rounded(.up))   // 219

    /// n cells → points. The ONLY cell↔point conversion on the capture screen.
    @inline(__always) static func pt(_ n: Int) -> CGFloat { CGFloat(n) * cell }

    // Element sizes, in cells (uniform — every element is whole cells of `cell`).
    static let previewCells = 64
    static let paletteCells = 16

    /// Cell-aligned centred X for an element `widthCells` wide (so it sits ON the grid).
    static func centeredX(_ widthCells: Int) -> CGFloat {
        pt((cols - widthCells) / 2) + pt(widthCells) / 2
    }

    // Element CENTRES (cell-aligned; .position takes the centre).
    static let previewTopCells = 22                                  // clears the Dynamic Island
    static let previewCenter = CGPoint(x: centeredX(previewCells),
                                       y: pt(previewTopCells) + pt(previewCells) / 2)   // ≈(200, 216)

    static let paletteTopCells = 145                                 // lower third (thumb-reachable)
    static let paletteCenter = CGPoint(x: centeredX(paletteCells),
                                       y: pt(paletteTopCells) + pt(paletteCells) / 2)   // ≈(200, 612)
}
