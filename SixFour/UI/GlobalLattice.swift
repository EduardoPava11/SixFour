import SwiftUI

/// GRID **Law #5 — the SOLE owner of cell↔point math** for the capture HUD.
///
/// The capture surface is a single global lattice: `gcd(402, 874) = 2`, so a **2 pt**
/// cell is the unique pitch that tiles the iPhone 17 Pro portrait screen edge-to-edge
/// → exactly **201 columns × 437 rows** (docs/SIXFOUR-DESIGN-LANGUAGE.md §2). Every HUD
/// widget is a square block of cells and grows by using **more cells, never a bigger
/// cell** (Law #1). This type owns the pitch, the lattice dimensions, the widget
/// cell-counts, and the one cells→points conversion, so **no view computes `× cellPt`
/// itself**.
///
/// **Verified mirror (Law #8).** Every number below is sourced from `SixFourLattice`
/// in `Generated/LatticeContract.swift`, emitted byte-for-byte from the Haskell
/// `SixFour.Spec.Lattice` and gated by `cabal test` (the gcd pitch, the shutter
/// closure `15·2 + 2·2 = 34`, the touch floor, the golden split, every-dim-is-cells).
/// `GlobalLattice` is the typed `CGFloat` facade — it adds *no* independent authority;
/// it only re-types the spec constants for SwiftUI. Change a number in `Spec.Lattice`,
/// regenerate, and it cascades here. (This closes the prior "interim authority" gap:
/// the constants no longer live in Swift.)
///
/// Scope: the **2 pt capture lattice only**. The Review/palette screens keep their own
/// 6 pt `SFTheme.gifCellPt` family (EXEMPT-REVIEW-PITCH) — the two pitches never share a
/// screen (Law #3). A `struct` (not an `enum`) because the safe-area band shift becomes
/// instance state the day `CellField` consumes it (§9.8).
struct GlobalLattice {
    /// The unique gcd-derived pitch that tiles the screen: 2 pt = 6 device-px @3x.
    static let cellPt: CGFloat = CGFloat(SixFourLattice.cellPt)

    /// The full-screen lattice — 201 cols × 437 rows at `cellPt`.
    static let cols = SixFourLattice.cols
    static let rows = SixFourLattice.rows

    // MARK: Widget cell-counts (square blocks; grow by more cells, never bigger cells)

    /// The hero preview: 64 cells = 1 GIF pixel per cell (the cube law).
    static let previewCells = SixFourLattice.previewCells
    /// HIG 44 pt minimum hit target, in cells. The floor every interactive widget clears.
    static let touchFloorCells = SixFourLattice.touchFloorCells
    /// Secondary square controls (gear, selector segments): 24 cells = 48 pt.
    static let controlCells = SixFourLattice.controlCells
    /// The shutter: 34 cells = 68 pt. Clears the 22-cell (44 pt) touch floor.
    static let shutterCells = SixFourLattice.shutterCells
    /// Shutter filled-disc radius (Ø30) + ring-band thickness — the closure `15·2 + 2·2 = 34`.
    static let shutterDiscRadiusCells = SixFourLattice.shutterDiscRadiusCells
    static let shutterRingThicknessCells = SixFourLattice.shutterRingThicknessCells
    /// The diversity gauge ring: 60 cells = 120 pt.
    static let ringCells = SixFourLattice.ringCells
    /// Radial ticks on the gauge — one per GIF frame.
    static let ringTicks = SixFourLattice.ringTicks
    /// Wordmark TITLE register height in cells (rows 96–115).
    static let wordmarkRows = SixFourLattice.wordmarkRows
    /// Wordmark advance width in cells (cols 68–191): 7·16 + 6·2 = 124.
    static let wordmarkCols = SixFourLattice.wordmarkCols
    /// A selector segment never narrows below the touch floor.
    static let segmentCells = SixFourLattice.segmentCells
    /// The Swiss gutter: one cell.
    static let gutterCells = SixFourLattice.gutterCells

    // MARK: The golden vertical layout (preview anchor)

    static let previewStartRow = SixFourLattice.previewStartRow
    static let previewEndRow = SixFourLattice.previewEndRow
    static let previewStartCol = SixFourLattice.previewStartCol
    static let previewEndCol = SixFourLattice.previewEndCol

    // MARK: The one conversion

    /// cells → points. The ONLY place a cell count becomes a point size.
    @inline(__always) static func pt(_ cells: Int) -> CGFloat { CGFloat(cells) * cellPt }
}
