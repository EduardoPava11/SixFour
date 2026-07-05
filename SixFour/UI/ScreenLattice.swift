import SwiftUI

/// THE single placement primitive (GRID v3.0 — "operations follow the grid").
///
/// A governed widget is placed on the ONE 4 pt lattice in exactly one way: by
/// claiming a rectangular block of cells — a `GridRegion` from `GridLayoutContract`,
/// whose scene `Spec.GridLayout` PROVES is contention-free (no two widgets claim the
/// same cell). There is no other sanctioned way to position a widget: a raw
/// `.position(point)`, an `.offset`, or a free `.frame(width: <pt>)` at a composition
/// site is a contract violation the grid lint rejects.
///
/// This file is the SOLE sanctioned home of `.position` (every other `.position` in a
/// composition view is a lint failure unless tagged `// LINT-ALLOW-POSITION` for a
/// genuine live-touch-point case). `place(_:)` reads the atom from the one owner
/// (`SixFourLattice.gifPx`, Law #5), so re-basing the atom re-lays the whole app with
/// zero call-site edits. `.position` sets the CENTER and is robust when a child's
/// intrinsic size differs from its region; `.offset` would silently mis-centre.
extension View {
    /// Pin this view to its `GridRegion` (screen-absolute cells → points). Use inside a
    /// `ZStack(alignment: .topLeading)` that fills the screen, so these are device-
    /// absolute coordinates.
    func place(_ region: GridRegion) -> some View {
        let atom = CGFloat(SixFourLattice.gifPx)                 // the ONE pitch (4 pt)
        let w = CGFloat(region.w) * atom
        let h = CGFloat(region.h) * atom
        let midX = (CGFloat(region.col) + CGFloat(region.w) / 2) * atom
        let midY = (CGFloat(region.row) + CGFloat(region.h) / 2) * atom
        return self
            .frame(width: w, height: h)
            .position(x: midX, y: midY)   // LINT-ALLOW-POSITION: the one sanctioned placement
    }

    /// Centre the scene canvas — the EXACT grid extent (`gridWidthPt × gridHeightPt`)
    /// — in the live screen `size`, so every absolute cell placement inside it is
    /// device-independent and the ≤ 1-atom screen bleed is split symmetrically rather
    /// than dumped bottom-right. Call with a `GeometryReader`'s `geo.size`. This is the
    /// sanctioned home of the scene-centring `.position` (the atom counts are baked; where
    /// the grid SITS is computed from the real screen, not baked).
    func gridCentered(in size: CGSize) -> some View {
        self
            .frame(width: GlobalLattice.gridWidthPt, height: GlobalLattice.gridHeightPt,
                   alignment: .topLeading)
            .position(x: size.width / 2, y: size.height / 2)   // LINT-ALLOW-POSITION: scene centring
    }

    /// Place by region NAME, looked up in a `GridLayoutContract` scene (the composer
    /// asks for "preview", "palette", …). A name absent from the proven scene is a
    /// layout bug — it traps in debug and falls back to an unplaced view in release.
    func place(_ name: String,
               in scene: [GridRegion] = GridLayoutContract.captureScene) -> some View {
        if let region = GridLayoutContract.region(name, in: scene) {
            return AnyView(place(region))
        } else {
            assertionFailure("GridLayout: no region named \"\(name)\" in the scene")
            return AnyView(self)
        }
    }
}
