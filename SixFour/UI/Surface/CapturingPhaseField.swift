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
    /// The shared widget layout, so the preview hero stays at the SAME position the live
    /// field placed it (a phase is a cell transform of the one surface, not a new screen).
    @Bindable var settings: AppSettings

    private var placement: [ColorIdentity: (col: Int, row: Int)] { settings.widgetPlacement }

    /// F2 — eased act1→act2: 0→1 over `transitionTicks` 20 fps ticks since this phase was entered.
    /// The palette's full→ghost drain and the banner fade ride this, so the tap doesn't hard-cut.
    private static let transitionTicks = 8
    private var transition: Double {
        CellEase.progress(clock.tick, since: surface.phaseEnteredTick, ticks: Self.transitionTicks)
    }

    /// Per-channel integer lerp `a→b` by `t` (UI-only; off the verified GIF path).
    private static func mix(_ a: SIMD3<UInt8>, _ b: SIMD3<UInt8>, _ t: Double) -> SIMD3<UInt8> {
        let tt = min(1, max(0, t))
        @inline(__always) func m(_ x: UInt8, _ y: UInt8) -> UInt8 {
            UInt8(min(255, max(0, (Double(x) + (Double(y) - Double(x)) * tt).rounded())))
        }
        return SIMD3(m(a.x, b.x), m(a.y, b.y), m(a.z, b.z))
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            // The influence-field ground is the ONE persistent surface in `SurfaceView` (behind
            // every phase). This phase renders only its widgets + chrome on a clear background.

            // The 64×64 preview STAYS ALIVE through the burst — the live camera tile keeps
            // feeding it, so the preview does NOT freeze (Act II). It plays backwards once
            // the GIFA cube starts streaming in `.rendering`; during the burst it is the
            // live camera. Movable in every phase that shows it (so it can be repositioned
            // right after capture) — `.movable` BEFORE `.place` (footprint-scoped gesture).
            previewHero
                .movable(.field64, settings: settings, surface: surface, clock: clock)
                .place(region(for: .field64, at: placement))

            // The palette-as-progress, at the SAME movable position the live shutter occupies
            // (`region(for:.palette16, at: placement)`), NOT a hardcoded region — so tapping to
            // capture does NOT make the palette JUMP from where the user dragged it (the "it moves!"
            // bug). The field radiates Palette16 from this same movable placement, so widget +
            // radiation stay aligned. Inert here (no `.movable`) — it's the burst progress, not a button.
            paletteProgress.place(region(for: .palette16, at: placement))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .ignoresSafeArea()
        // The phase banner cell-strip, top-aligned over the field.
        .overlay(alignment: .top) { banner }
    }

    // MARK: - The live preview hero (64 × 64 cells) — stays alive, no freeze

    /// The 64×64 preview during the burst: the live camera tile (`surface.previewTile`)
    /// through its paired palette — identical geometry to the live field, so the surface
    /// keeps painting the camera while the burst is shot (no freeze, no view swap). Falls
    /// back to the ghost ink before a frame arrives. Inert (no gesture) while capturing.
    private var previewHero: some View {
        let side = GlobalLattice.gif(GlobalLattice.previewCells)   // 64 × 4 = 256 pt
        let ghost = SIMD3<UInt8>(20, 20, 24)
        // The LATEST captured frame, shown forward. (The reverse-cursor "plays backwards build" was
        // removed: the burst's frames are NOT surfaced individually during capture — the preview
        // renderer COALESCES, keeping only the newest, so accumulating produced a jarring ~4-frame
        // loop, not a 64-frame build. The honest GIFA build is the serpentine reveal in `.rendering`,
        // where the cube exists; during the burst the hero simply shows the latest landed frame.)
        let tile = surface.previewTile
        let pal = surface.previewPalette
        return CellSprite(cols: 64, rows: 64, cellPt: side / 64) { c, r in
            let i = r * 64 + c
            guard i < tile.count, Int(tile[i]) < pal.count else { return ghost }
            return pal[Int(tile[i])]
        }
        .frame(width: side, height: side)
        .clipped()
        .allowsHitTesting(false)
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
        // (lock collapsed into .live under ABSurface; this field is unrouted)
        let captured = surface.phase == .live ? 0 : min(surface.palette.count, 256)

        // F2: unfilled cells EASE from their live colour → ghost over the transition, so the tap
        // doesn't flash the whole palette to ghost; captured cells stay solid.
        let t = transition
        return CellSprite(cols: 16, rows: 16, cellPt: GlobalLattice.gif(1)) { c, r in
            let rank = r * 16 + c
            guard rank < ordered.count else { return ghost }
            return rank < captured ? ordered[rank] : Self.mix(ordered[rank], ghost, t)
        }
        .allowsHitTesting(false)   // inert during the burst — a state is a cell transform, never a button
        .accessibilityLabel(surface.phase == .live   // (lock collapsed into .live under ABSurface; field unrouted)
                            ? "Locking exposure, focus, white balance"
                            : "Capturing sixty-four frames")
    }

    // MARK: - The phase banner strip

    /// The phase banner as a flat dark cell strip (glass retired on the HUD per GRID):
    /// names which phase of the burst the surface is in. Read straight from σ's phase.
    @ViewBuilder
    private var banner: some View {
        let label = surface.phase == .live   // (lock collapsed into .live under ABSurface; field unrouted)
            ? "Locking exposure, focus, white balance…"
            : "Capturing 64 frames…"
        CellText(label, rows: 11, ink: .white)
            .padding(.horizontal, GlobalLattice.pt(5))
            .padding(.vertical, GlobalLattice.pt(3))
            .background(Color(srgb8: SFTheme.ledGhost))
            .padding(.top, GlobalLattice.pt(4))
            .opacity(transition)        // F2: fade the banner in over the transition (chrome, not a cell)
            .allowsHitTesting(false)
    }
}
