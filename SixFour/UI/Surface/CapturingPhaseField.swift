import SwiftUI
import simd

/// Π for the `.capturing` (and `.locking`) phase — the burst-in-flight field.
///
/// This is the LIVE field with the burst overlaid AS the palette: the 256-cell live
/// palette (the GIF's first abstraction, and on the live screen the capture button)
/// here becomes the PROGRESS BAR — the captured fraction of the 256 cells fills in
/// rank order, the rest dim to ghost. A capture state is a CELL TRANSFORM, never a
/// spinner or an opacity fade. A `locking`/`capturing` banner cell-strip names the
/// phase. Ported from `CaptureView.latticeScene` + `paletteButton`'s capture-progress
/// fill + `phaseBanner`.
///
/// READS σ ONLY: `surface.palette` (the live per-frame palette, which grows as the
/// burst is ingested) and `surface.phase` (locking vs capturing → the banner + whether
/// the progress fill is partial). The clock supplies the 20 fps heartbeat so the ground
/// checker stays live. The captured fraction is read straight from how much of the
/// palette σ currently carries — `min(palette.count, 256) / 256` — so the fill IS a
/// projection of σ, not a separate animation clock. Emits cells only
/// (`GridRefreshFieldView` / `CellSprite` / `CellText`); no `Text`/glass/SF-Symbol.
struct CapturingPhaseField: View {
    let surface: Surface
    let clock: SurfaceClock

    var body: some View {
        ZStack(alignment: .topLeading) {
            // The living ground: the full-screen B/W checker of the ONE atom, inverting
            // at 20 fps off the single clock's heartbeat. The opaque heroes draw on top.
            GridRefreshFieldView(phase: clock.heartbeat)
                .ignoresSafeArea()

            // The palette-as-progress hero, placed by the proven capture-scene layout
            // (the same region the live shutter occupies — capture is a cell transform
            // of the live field, not a new screen).
            paletteProgress.place("palette")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .ignoresSafeArea()
        // The phase banner cell-strip, top-aligned over the field.
        .overlay(alignment: .top) { banner }
    }

    // MARK: - The 256-cell capture-progress fill

    /// The 16×16 live palette rendered as the burst progress bar: the captured fraction
    /// of the 256 cells is painted in rank order (the centralized `GridScript.capture`
    /// row-major order, no per-frame re-sort jitter), the remainder dim to a ghost cell.
    /// During `.locking` nothing is captured yet (fraction 0 → all ghost); during
    /// `.capturing` the fill tracks how much palette σ has accrued.
    private var paletteProgress: some View {
        let ghost = SIMD3<UInt8>(20, 20, 24)
        // Pad σ's palette to a full 256 so the order is a total permutation; ghost-fill
        // the unpopulated tail. Both render backends resolve a cell through this one
        // `surfaceColors`, so the layout cannot diverge (Spec.GridScript).
        let padded: [SIMD3<UInt8>] = (0 ..< 256).map { $0 < surface.palette.count ? surface.palette[$0] : ghost }
        let ordered = GridScript.capture(side: 16).surfaceColors(palette: padded)
        // Captured fraction read straight from σ: how many of the 256 slots are backed
        // by a real palette colour. `.locking` carries no palette yet → 0 filled.
        let captured = surface.phase == .locking ? 0 : min(surface.palette.count, 256)

        return CellSprite(cols: 16, rows: 16, cellPt: GlobalLattice.gif(1)) { c, r in
            let rank = r * 16 + c
            guard rank < ordered.count else { return ghost }
            return rank < captured ? ordered[rank] : ghost
        }
        .allowsHitTesting(false)   // inert during the burst — a state is a cell transform, never a button
        .accessibilityLabel(surface.phase == .locking
                            ? "Locking exposure, focus, white balance"
                            : "Capturing sixty-four frames")
    }

    // MARK: - The phase banner strip

    /// The phase banner as a flat dark cell strip (glass retired on the HUD per GRID):
    /// names which phase of the burst the surface is in. Read straight from σ's phase.
    @ViewBuilder
    private var banner: some View {
        let label = surface.phase == .locking
            ? "Locking exposure, focus, white balance…"
            : "Capturing 64 frames…"
        CellText(label, rows: 11, ink: .white)
            .padding(.horizontal, GlobalLattice.pt(5))
            .padding(.vertical, GlobalLattice.pt(3))
            .background(Color(srgb8: SFTheme.ledGhost))
            .padding(.top, GlobalLattice.pt(4))
            .allowsHitTesting(false)
    }
}
