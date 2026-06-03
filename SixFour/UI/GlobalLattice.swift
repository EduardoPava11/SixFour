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
/// Scope: the **2 pt capture lattice only**. The Review/palette screens keep their own
/// 6 pt `SFTheme.gifCellPt` family (EXEMPT-REVIEW-PITCH) — the two pitches never share a
/// screen (Law #3).
///
/// Interim authority: the Haskell `Spec.Lattice` golden that will pin these numbers and
/// enumerate every widget cell-rect is **[PLANNED]** (§9.3/§9.8); until it ships this is
/// the single Swift source of truth. A `struct` (not an `enum`) because the safe-area
/// band shift becomes instance state the day `CellField` consumes it (§9.8).
struct GlobalLattice {
    /// The unique gcd-derived pitch that tiles the screen: 2 pt = 6 device-px @3x.
    static let cellPt: CGFloat = 2

    /// The full-screen lattice — 201 cols × 437 rows at `cellPt`.
    static let cols = 201
    static let rows = 437

    // MARK: Widget cell-counts (square blocks; grow by more cells, never bigger cells)

    /// The shutter: 34 cells = 68 pt. Clears the 22-cell (44 pt) touch floor.
    static let shutterCells = 34
    /// Secondary square controls (gear, selector segments): 24 cells = 48 pt.
    static let controlCells = 24
    /// The diversity gauge ring: 60 cells = 120 pt.
    static let ringCells = 60
    /// Radial ticks on the gauge — one per GIF frame.
    static let ringTicks = 64

    // MARK: The one conversion

    /// cells → points. The ONLY place a cell count becomes a point size.
    @inline(__always) static func pt(_ cells: Int) -> CGFloat { CGFloat(cells) * cellPt }
}
