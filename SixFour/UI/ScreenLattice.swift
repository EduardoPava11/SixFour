import SwiftUI

/// THE single screen lattice (the recurring-structural-bug fix, audit 2026-06-05).
/// The whole iPhone 17 Pro screen (402×874 pt) is ONE grid of `gifPx = 6 pt` atoms
/// — 67 cols × 145 rows — and every region is pinned to absolute cell coordinates.
/// No floating `VStack`/`Spacer`, no second pitch, no per-widget origin. Regions are
/// placed BELOW the Dynamic Island and ABOVE the home indicator by reserving fixed
/// safe rows (Q2: fixed margins, top 62 pt ≈ 11 rows, bottom 34 pt ≈ 6 rows), so the
/// preview can never bleed under the island. Sizes are atom-multiples only (Q1: one
/// 6 pt pitch — a palette cell is 2×2 atoms, a shutter cell 4×4 atoms).
///
/// Band-map (atoms): preview 64² (384 pt, 1 atom/cell) → palette 16² (96 pt, 1 atom/cell
/// — ONE size with the preview pixel, GRID Law #1; supersedes ADR-5's ×2 cells). The 4×4
/// shutter is retired from the scene; the 16×16 palette grid IS the capture button.
enum ScreenLattice {
    static let atom: CGFloat = 6                  // gifPx — the ONE pitch
    static let cols = 67
    static let rows = 145
    static let screenW: CGFloat = 402             // iPhone 17 Pro (NOT Pro Max)
    static let screenH: CGFloat = 874
    static let safeTopRows = 11                   // ⌈62/6⌉ — clears the Dynamic Island
    static let safeBottomRows = 6                 // ⌈34/6⌉ — clears the home indicator

    /// A rectangular region in ATOM units (top-left origin).
    struct Region { let col: Int; let row: Int; let w: Int; let h: Int }

    /// Horizontally-centred region at a given top row.
    static func centered(row: Int, w: Int, h: Int) -> Region {
        Region(col: (cols - w) / 2, row: row, w: w, h: h)
    }

    // The grid-first cascade, pinned to rows inside the safe band (11…138).
    static let preview = centered(row: 13, w: 64, h: 64)   // 384×384
    static let palette = centered(row: 92, w: 16, h: 16)   // 96×96 — 16 cells × 1 atom (6 pt), same cell as a preview pixel
    static let shutter = centered(row: 123, w: 16, h: 16)  // 96×96
    static let gear    = Region(col: cols - 9, row: 12, w: 8, h: 8)  // 48×48 (touch floor), top-right

    /// Region → points (top-left origin, screen-absolute).
    static func rect(_ r: Region) -> CGRect {
        CGRect(x: CGFloat(r.col) * atom, y: CGFloat(r.row) * atom,
               width: CGFloat(r.w) * atom, height: CGFloat(r.h) * atom)
    }
}

extension View {
    /// Pin a view to its assigned lattice region (absolute placement; use inside a
    /// `ZStack(alignment: .topLeading)` that fills the screen). No Spacer, no flow.
    func latticeRegion(_ region: ScreenLattice.Region) -> some View {
        let r = ScreenLattice.rect(region)
        // .position (sets the CENTER in the parent's coords) is the absolute-placement
        // API — robust even when a child's intrinsic size differs from the region;
        // .offset is render-only and silently mis-centres a smaller child. The parent
        // ZStack fills the screen (402×874), so these are device-absolute coordinates.
        return self
            .frame(width: r.width, height: r.height)
            .position(x: r.midX, y: r.midY)
    }
}
