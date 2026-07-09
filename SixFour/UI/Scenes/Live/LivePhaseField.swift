import SwiftUI
import UIKit
import Foundation
import simd

/// Π for the `live` family of phases (`.live`, `.locking`, `.capturing`) — the capture
/// face of the ONE surface. The composition is the INVERTED-PYRAMID THREE-VIEW
/// (`InvertedPyramidField`) at HONEST CADENCE: 64² (widest, 20 Hz) over 32² (a true
/// 2-frame integral at 10 Hz) over the 16² point (a true 4-frame integral at 5 Hz), with
/// intake tallies in the pyramid's gutters making the 4-into-1 pour countable
/// (`Spec.ColorTimeDisplay`). The 16² vertex IS the shutter, wearing the D1 control
/// BRACKETS; tapping the 64² meters (with a 3×3 inverted crosshair).
///
/// THE FOUR VERBS OF LIVE (THE DESIGN): DRAG the ground = grade (horizontal = LOOK strip,
/// vertical = EV rail — the instrument rails materialize under the live gesture and
/// dematerialize after); TAP the 64² = meter; TAP the 16² = fire; everything else watches.
///
/// This is the seam fulfilment for `PhaseField`: a pure `(Surface, SurfaceClock) -> View`
/// that reads σ and emits CELLS only — no `Text`, no glass, no SF-Symbol. The pyramid is
/// TOP-PINNED at the `field64` contract row (never center-derived — stack growth must not
/// drift it off the proven bands); the rails are placed on the spec-proven `liveScene`
/// regions (`evRail`, `lookStrip`, `fluxBar`), hit-testing OFF, so the ground gestures
/// are never intercepted.
///
/// What it reads from σ:
///   - `surface.previewTile` / `surface.previewPalette` — the live 64×64 index tile + its
///     256 colours; during a burst the SAME publish path streams the landed frames (the
///     burst is the show — never a freeze, THE DESIGN E7).
///   - `surface.phase`    — `.live` is tappable; a busy surface stops advertising the verb
///     (`shutterEnabled`), and the bracket face carries the state (busy/disabled as cell
///     states, never opacity).
///   - `clock.tick`       — THE one 20 Hz clock every cadence on this face derives from.
struct LivePhaseField: View {
    let surface: Surface
    let clock: SurfaceClock
    /// The ONE shared widget layout (the three global ColorWidget positions) + persistence.
    @Bindable var settings: AppSettings
    /// The direct engine `capture()` kick — lock + burst are internal to `.live` under
    /// ABSurface, so the shutter starts the burst itself; σ STAYS `.live` until the
    /// engine finishes (then `.done` → `burstComplete` → `.captured`).
    var onShutter: () -> Void = {}
    /// PRE-LOCK exposure expression (QoL 2026-07-03). `onMeter`: tap the hero to
    /// one-shot meter that point (normalized 0..1). `onExposureBias`: vertical drag
    /// sets an absolute EV bias (up = brighter, 1 EV per 200 pt). The burst then LOCKS
    /// the AE the user placed — the lock invariant is untouched, the choice is theirs.
    var onMeter: (CGPoint) -> Void = { _ in }
    var onExposureBias: (Float) -> Void = { _ in }
    var exposureBias: Float = 0
    /// THE VISIBLE COMPUTATION: the engine's pipeline stage. While active, the stage
    /// label rides the top cell, the 16² becomes the BANKED LEDGER (exact landed-frame
    /// cells, never float progress), and the "banked window" readout steps 5 cs per
    /// landed frame. σ stays `.live` throughout (render state only, FSM untouched).
    var stage: EngineStage = .idle

    /// The EV the current vertical drag started from (nil = no EV drag in flight).
    @State private var evDragBase: Float?
    /// The in-flight horizontal LOOK-swipe translation (nil = no look swipe live). Drives
    /// the LOOK strip's materialization + its tentative selection frame — render state
    /// only; the commit still happens on gesture end, exactly as before.
    @State private var lookDragDx: CGFloat?

    var body: some View {
        ZStack(alignment: .topLeading) {
            // The influence-field ground is the ONE persistent surface hoisted to `SurfaceView`
            // (behind every phase). Its named function on Live is CAPTURE ENERGY (E9): a calm
            // near-void while idle, rising with the pour ramp while photons are being banked.

            // LOOK swipe / EV drag ground: a clear full-screen layer BEHIND the widgets.
            Color.clear
                .contentShape(Rectangle())
                .gesture(lookSwipeAndExposureDrag)

            // THE THREE-VIEW at honest cadence (E1/E2/E3/E7). Top-pinned at the field64
            // contract row (horizontally self-centering to the proven cols) — the funnel
            // is the pooling factor at the ONE 4 pt atom.
            InvertedPyramidField(
                tile64: surface.previewTile,
                palette: surface.previewPalette,
                tile32: surface.previewTile32,
                tile16: surface.previewTile16,
                useLiveLadder: Feature.liveLadder,
                opticalTile64: surface.opticalTile64,
                opticalTile32: surface.opticalTile32,
                opticalTile16: surface.opticalTile16,
                useOptical: Feature.opticalEV,
                ev64: 0, ev32: 0.5, ev16: 1.0,
                stageActive: stage.active,
                landedFrames: stage.landed ?? 0,
                shutterEnabled: surface.phase == .live && !stage.active,
                tick: clock.tick,
                reduceMotion: clock.reduceMotion,
                // BOOT RESOLVE: ticks since `.live` was entered — the pyramid
                // crystallizes 16²→32²→64² on the reveal ladder (4/8/16), the pour
                // played in reverse. σ.phaseEnteredTick is stamped by SurfaceView on
                // every phase edge, so a retake replays the warm-up honestly.
                bootTicks: clock.tick - surface.phaseEnteredTick,
                // THE SCROLL entry (Feature.scrollTube): long-press the hero to enter
                // the tube — render state only, the FSM stays `.live`.
                onScrollTube: Feature.scrollTube ? { [weak surface] in
                    guard let surface, surface.phase == .live, !stage.active else { return }
                    surface.scrollTube = true
                } : nil,
                onShutter: onShutter,
                onMeter64: onMeter
            )

            // THE GRID MIRRORS THE LADDER (Feature.rungTelemetry): the liveScene
            // instrument flanks + system machine ring. `.equatable()` gates the body to
            // the ≤ 5 Hz telemetry cadence, not the 20 fps preview publish.
            RungTelemetryFlanks(telemetry: surface.rungTelemetry,
                                system: surface.systemTelemetry)
                .equatable()

            // THE INSTRUMENT RAILS (E5) — display-only faces of the two ground gestures,
            // on the spec-proven liveScene regions. Hit-testing OFF: the gesture stays on
            // the clear ground layer above; these only make it visible and confident.
            EVRail(bias: exposureBias,
                   active: evDragBase != nil,
                   tick: clock.tick)
                .allowsHitTesting(false)
                .place("evRail", in: GridLayoutContract.liveScene)

            LookStrip(look: settings.captureLook,
                      preview: previewLook,
                      dragging: lookDragDx != nil,
                      tick: clock.tick)
                .allowsHitTesting(false)
                .place("lookStrip", in: GridLayoutContract.liveScene)

            // THE FLUX BAR (E6) — the single-number wave meter under the shutter:
            // paletteW1 between consecutive ≤ 5 Hz GCTs (`s4_v21_wdist1d`), log₂-lit.
            // All-ghost until the head delivers signal. Display-only, on the spec-
            // proven fluxBar region; sampled at the mod-4 realize tick, never per publish.
            FluxBar(gct: surface.latestGCT, tick: clock.tick)
                .allowsHitTesting(false)
                .place("fluxBar", in: GridLayoutContract.liveScene)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .ignoresSafeArea()
        // The open screen is JUST the pyramid + instruments on the ground — no build
        // stamp / status text. The ONE exception is a transient stage / LOOK readout.
        .overlay(alignment: .top) {
            if stage.active {
                // The computation announces itself: LOCK / BURST n/64 / REFINE / ENCODE,
                // plus the BANKED WINDOW during the burst — "160/320cs" stepping 5 cs per
                // landed frame (`Spec.ColorTimeDisplay.bankedWindowCs`, a readout of the
                // ledger, never an animation). The EV-overlay idiom: gone when idle.
                VStack(spacing: GlobalLattice.pt(2)) {
                    CellText(stage.label, cell: GlobalLattice.gif(1))
                    if let landed = stage.landed, stage.label.hasPrefix("BURST") {
                        CellText("\(ColorTimeDisplayMath.bankedWindowCs(landed))/\(ColorTimeDisplayMath.fullWindowCs)CS",
                                 cell: GlobalLattice.pt(1))
                    }
                }
                .padding(.top, GlobalLattice.gif(4))
                .allowsHitTesting(false)
                .accessibilityLabel("Working: \(stage.label)")
            } else if settings.captureLook != .off {
                CellText(settings.captureLook.displayName, cell: GlobalLattice.gif(1))
                    .padding(.top, GlobalLattice.gif(4))
                    .allowsHitTesting(false)
                    .accessibilityLabel("Look: \(settings.captureLook.displayName)")
            }
        }
        // The EV readout: shown ONLY when the user has biased exposure (0 = silent).
        .overlay(alignment: .topTrailing) {
            if exposureBias != 0 {
                CellText(String(format: "EV %+.1f", exposureBias), cell: GlobalLattice.gif(1))
                    .padding(.top, GlobalLattice.gif(4))
                    .padding(.trailing, GlobalLattice.gif(2))
                    .allowsHitTesting(false)
                    .accessibilityLabel(String(format: "Exposure bias %+.1f EV", exposureBias))
            }
        }
    }

    /// The look the in-flight swipe would commit (the strip frames it): past the same
    /// 6-cell threshold the commit uses, swiping left goes `next`, right goes `prev`.
    private var previewLook: LookVariant? {
        guard let dx = lookDragDx, abs(dx) >= GlobalLattice.gif(6) else { return nil }
        return dx < 0 ? settings.captureLook.next : settings.captureLook.prev
    }

    /// ONE ground drag, two verbs by dominant axis (QoL 2026-07-03):
    ///   * HORIZONTAL swipe (on end, 6-cell minimum) cycles the LOOK — unchanged commit;
    ///     while live it materializes the LOOK strip (E5) and frames the tentative look.
    ///   * VERTICAL drag (continuous) sets the EV bias: up = brighter, 1 EV per 200 pt,
    ///     absolute from the drag's starting bias (`evDragBase`), engine-clamped ±2;
    ///     while live it materializes the EV rail.
    /// Both only write render/exposure params — never a position, so the cell grid is
    /// never disturbed. Gated to `.live` (a busy surface neither grades nor meters).
    private var lookSwipeAndExposureDrag: some Gesture {
        DragGesture(minimumDistance: GlobalLattice.gif(2))
            .onChanged { value in
                guard surface.phase == .live, !stage.active else { return }
                let dx = value.translation.width
                let dy = value.translation.height
                if abs(dy) > abs(dx) {                         // vertical-dominant = EV
                    lookDragDx = nil
                    if evDragBase == nil { evDragBase = exposureBias }
                    onExposureBias((evDragBase ?? 0) + Float(-dy / 200))
                } else {                                       // horizontal-dominant = LOOK
                    lookDragDx = dx
                }
            }
            .onEnded { value in
                defer { evDragBase = nil; lookDragDx = nil }
                guard surface.phase == .live, !stage.active else { return }
                let dx = value.translation.width
                let dy = value.translation.height
                guard abs(dx) > abs(dy), abs(dx) >= GlobalLattice.gif(6) else { return }
                settings.captureLook = dx < 0 ? settings.captureLook.next : settings.captureLook.prev
                Haptics.selection()   // discrete look-CHANGE confirmation — NOT a cell detent
                                      // (cellTick `play(1)` is reserved for the frame-locked .cellDetent)
            }
    }

}

#if DEBUG
/// TESTABLE ACT I in the Xcode canvas — the live influence field fed by the synthetic
/// `DemoScene` (no camera needed). Run the full interactive app with `-demoScene`.
#Preview("Act I — influence field (demo scene)") {
    let surface = Surface()
    surface.step(.sessionReady)                 // bootstrap → .live (enables the shutter gate)
    surface.previewTile = DemoScene.tile(tick: 0)
    surface.previewPalette = DemoScene.palette
    surface.palette = DemoScene.palette
    return LivePhaseField(surface: surface, clock: SurfaceClock(), settings: AppSettings())
        .ignoresSafeArea()
}
#endif
