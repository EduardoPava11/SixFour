import SwiftUI

/// GRID **Law #5 — the SOLE owner of cell↔point math** (v3.0, the 4 pt atom).
///
/// **The atom is the GIF pixel: `gifPx = 4 pt = 12 device-px @3x`** (the product's
/// pixel IS the unit the app is built from, docs/SIXFOUR-DESIGN-LANGUAGE.md). It is
/// *chosen* (not forced): integer device-px AND it expresses the 44 pt HIG touch floor
/// EXACTLY (`11·4 = 44`), which 6 pt could not. Each axis tiles to the safe-area with a
/// 2 pt sub-atom bleed (`402/4 = 100` cols, `874/4 = 218` rows). Every governed widget
/// is a square block of atoms and grows by using **more atoms, never a bigger atom**
/// (Law #1). Use `gif(_:)` for content/instrument sizes.
///
/// **`subPt = 2 pt = gifPx / 2`** is the commensurate HALF-atom for fine spacing /
/// gutters and text legibility (a glyph cannot be one atom wide). Use `pt(_:)` for
/// spacing — it is `subPt`-based and `subPt` is still 2 pt, so the app's existing
/// gutters are physically unchanged across the v2.0→v3.0 re-base. The two snap to one
/// grid (`2·subPt = gifPx`). `cellPt` names this sub-pixel substrate for spacing call-sites.
///
/// **Where a widget GOES is not here.** This type owns the atom + per-widget sizes;
/// the capture-scene LAYOUT (which cells each widget claims) is `GridLayoutContract`
/// (the contention proof). There is no golden-split anchor in the lattice anymore.
///
/// **Verified mirror (Law #8).** Every number below is sourced from `SixFourLattice`
/// in `Generated/LatticeContract.swift`, emitted byte-for-byte from the Haskell
/// `SixFour.Spec.Lattice` and gated by `cabal test` (the atom identity, the lattice
/// tiling + bleed, the shutter closure `5·2 + 1·2 = 12`, the 48 pt touch floor, the
/// golden split). `GlobalLattice` adds *no* independent authority; it re-types the
/// spec constants. Change a number in `Spec.Lattice`, regenerate, and it cascades here.
struct GlobalLattice {
    /// THE ATOM: one GIF pixel = 4 pt = 12 device-px @3x. The content/instrument unit.
    static let gifPx: CGFloat = CGFloat(SixFourLattice.gifPx)

    /// The sub-pixel substrate = 2 pt = gifPx/2 — fine spacing/gutters + text.
    /// (Kept under the name `cellPt` so the existing spacing call-sites are unchanged.)
    static let subPt: CGFloat = CGFloat(SixFourLattice.subPt)
    static let cellPt: CGFloat = CGFloat(SixFourLattice.subPt)

    /// The full-screen lattice — 100 cols × 218 rows at the `gifPx` atom.
    static let cols = SixFourLattice.cols
    static let rows = SixFourLattice.rows

    /// The EXACT grid extent in points (cols·gifPx × rows·gifPx = 400 × 872).
    /// The scene canvas is this size and is centred in the REAL screen at
    /// runtime (`GeometryReader`), so a widget's placement is device-independent
    /// and the ≤ 1-atom bleed is split symmetrically — the baked `screenWidthPt`
    /// constants pin the atom count, they do NOT pin where the grid sits.
    static let gridWidthPt: CGFloat = CGFloat(cols) * gifPx
    static let gridHeightPt: CGFloat = CGFloat(rows) * gifPx

    // MARK: Widget cell-counts (square blocks; grow by more cells, never bigger cells)

    /// The hero preview: 64 cells = 1 GIF pixel per cell (the cube law); 256 pt at 4 pt.
    static let previewCells = SixFourLattice.previewCells
    /// HIG 44 pt minimum hit target = 11 cells (exact at 4 pt). The interactive floor.
    static let touchFloorCells = SixFourLattice.touchFloorCells
    /// Secondary square controls (gear, selector segments): 12 cells = 48 pt.
    static let controlCells = SixFourLattice.controlCells
    /// The shutter / palette-as-shutter footprint: 16 cells = 64 pt. Clears the floor.
    static let shutterCells = SixFourLattice.shutterCells
    /// Shutter filled-disc radius (Ø12) + ring-band thickness — the closure `6·2 + 2·2 = 16`.
    static let shutterDiscRadiusCells = SixFourLattice.shutterDiscRadiusCells
    static let shutterRingThicknessCells = SixFourLattice.shutterRingThicknessCells
    /// The diversity gauge ring: 20 cells = 80 pt (radius fixed in cells for gap-free ticks).
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

    // MARK: The conversions

    /// atoms → points (the GIF-pixel atom). Use for content + instrument sizes:
    /// the preview, the field, the shutter, the ring. `gif(64) = 256`.
    @inline(__always) static func gif(_ cells: Int) -> CGFloat { CGFloat(cells) * gifPx }

    /// sub-pixels → points (the 2 pt substrate). Use for fine spacing/gutters + text.
    /// Kept named `pt` so the app's existing spacing call-sites are unchanged.
    @inline(__always) static func pt(_ subcells: Int) -> CGFloat { CGFloat(subcells) * cellPt }
}
