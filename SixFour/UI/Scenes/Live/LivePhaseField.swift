import SwiftUI
import UIKit
import Foundation
import simd

/// Π for the `live` family of phases (`.live`, `.locking`, `.capturing`) — the capture
/// face of the ONE surface. The composition is the INVERTED-PYRAMID THREE-VIEW
/// (`InvertedPyramidField`): 64² (widest) over 32² over the 16² point, each pooled from the
/// ONE live camera tile via the shipped `ColorHead.poolSpatial2` (64→32→16) and shown at its
/// own DIGITAL EV. The 16² vertex IS the shutter (tapping it fires the burst); tapping the
/// 64² meters. All three are three resolutions of one live feed, so the funnel is the pooling
/// factor drawn to scale at the ONE 4 pt atom.
///
/// LIVE-LADDER (Feature.liveLadder): when on, the 32²/16² rungs read the REAL device ladder
/// (`surface.previewTile32/16`, realized from the persistent preview `ColorHead` via the
/// inverse-EOTF kernel) instead of view-pooling the 64². OFF (default) ⇒ those tiles are empty
/// and the pyramid pools the 64² in-view, byte-identical to today. The 64² stays the GPU
/// index-palette preview either way (the meter-tap normalization needs it).
///
/// This is the seam fulfilment for `PhaseField`: a pure `(Surface, SurfaceClock) -> View`
/// that reads σ and emits CELLS only — no `Text`, no glass, no SF-Symbol, no UIKit
/// `Slider`/`Picker` on chrome. The pyramid SELF-CENTERS (`.frame(maxWidth:.infinity…)`, no
/// `.position`/`.offset`), so it is grid-lint clean without a `GridLayoutContract` region —
/// the surface keeps its single uniform 4 pt lattice.
///
/// What it reads from σ:
///   - `surface.previewTile` / `surface.previewPalette` — the live 64×64 index tile + its 256
///                          colours the engine publishes each frame; the pyramid pools these.
///   - `surface.phase`    — `.live` is tappable (fires the shutter); `.locking` / `.capturing`
///                          are inert (a state is a cell transform, never an opacity fade —
///                          the shutter simply stops being tappable via `shutterEnabled`).
///   - `clock.heartbeat`  — the 20 fps inversion bit that proves the canvas is live.
///
/// The digital EVs are display-only (the burst stays one locked exposure); v2 promotes them
/// to real optical EV. LOOK-swipe / EV-drag stay on the clear ground layer behind the tiles.
/// NOTE (resolved 2026-07-08): the ground influence-field's LIVE sources now anchor to the
/// spec-proven `liveScene` pyramid bands (field64/field16 regions) — the glow tracks the
/// centered pyramid; the retired movable anchors remain only for the non-live acts.
struct LivePhaseField: View {
    let surface: Surface
    let clock: SurfaceClock
    /// The ONE shared widget layout (the three global ColorWidget positions) + persistence.
    @Bindable var settings: AppSettings
    /// The direct engine `capture()` kick — lock + burst are internal to `.live` under
    /// ABSurface (no `.locking` phase), so the shutter starts the burst itself; σ STAYS
    /// `.live` until the engine finishes (then `.done` → `burstComplete` → `.captured`).
    var onShutter: () -> Void = {}
    /// PRE-LOCK exposure expression (QoL 2026-07-03). `onMeter`: tap the hero to
    /// one-shot meter that point (normalized 0..1). `onExposureBias`: vertical drag
    /// sets an absolute EV bias (up = brighter, 1 EV per 200 pt). The burst then LOCKS
    /// the AE the user placed — the lock invariant is untouched, the choice is theirs.
    var onMeter: (CGPoint) -> Void = { _ in }
    var onExposureBias: (Float) -> Void = { _ in }
    var exposureBias: Float = 0
    /// THE VISIBLE COMPUTATION (QoL 2026-07-03): the engine's pipeline stage. While
    /// active, the stage label rides the top cell and the palette-as-shutter becomes
    /// the PROGRESS FIELD (cells fill as work completes) — the surface always shows
    /// the function it is performing; a busy surface is never a frozen one. σ stays
    /// `.live` throughout (the FSM is untouched; this is render state only).
    var stage: EngineStage = .idle

    /// The EV the current vertical drag started from (nil = no EV drag in flight).
    @State private var evDragBase: Float?

    var body: some View {
        ZStack(alignment: .topLeading) {
            // The influence-field ground is the ONE persistent surface hoisted to `SurfaceView`
            // (behind every phase) — not drawn here, so it is never recreated per phase. This phase
            // renders only its widgets + chrome on a CLEAR background over it.

            // LOOK swipe ground: a clear full-screen layer BEHIND the widgets. A horizontal
            // swipe cycles `settings.captureLook` (the data-driven OKLab grade that recolours
            // the hero + palette and is what Export LUT bakes). The hero passes touches through
            // (`allowsHitTesting(false)`), so swipes over it reach here; the palette keeps its
            // own tap-to-shoot / hold-to-move. Only a render param changes — nothing moves, so
            // the 4 pt cell grid is intact.
            Color.clear
                .contentShape(Rectangle())
                .gesture(lookSwipeAndExposureDrag)

            // THE THREE-VIEW: 64² (widest) / 32² / 16² (the point = the shutter), each pooled
            // from the ONE live tile via ColorHead.poolSpatial2 and shown at its own digital EV.
            // Self-centering (no .place) — the funnel is the pooling factor at the ONE 4 pt atom.
            // Tap the 16² to fire the burst; tap the 64² to meter; the ground behind still
            // LOOK-swipes / EV-drags. Reuses the shipped onShutter (→ engine.capture()) + onMeter.
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
                shutterProgress: stage.progress ?? 0,
                shutterEnabled: surface.phase == .live && !stage.active,
                onShutter: onShutter,
                onMeter64: onMeter
            )

            // THE GRID MIRRORS THE LADDER (Feature.rungTelemetry): the liveScene
            // instrument flanks — per-rung arrival pulse / exposure state / √N
            // significance / independence health beside each pyramid band, plus the
            // system machine ring (tick CPU vs 50 ms, v21 buffer lifecycle, thermal)
            // below. Placed via the spec-proven liveScene regions; hit-testing is OFF
            // inside so the ground LOOK-swipe / EV-drag and the 16² shutter are never
            // intercepted. `.equatable()` gates the body to the ≤ 5 Hz telemetry
            // cadence, not the 20 fps preview publish (the pyramid bake discipline).
            RungTelemetryFlanks(telemetry: surface.rungTelemetry,
                                system: surface.systemTelemetry)
                .equatable()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .ignoresSafeArea()
        // The open screen is JUST the preview + palette on the checker ground — no build
        // stamp / status text (the grey writing read as distracting clutter). The ONE
        // exception is a transient LOOK name, shown only when a grade is active (default
        // `.off` ⇒ the screen is unchanged), so the swipe is legible without clutter.
        .overlay(alignment: .top) {
            if stage.active {
                // The computation announces itself: LOCK / BURST n/64 / REFINE / ENCODE.
                CellText(stage.label, cell: GlobalLattice.gif(1))
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
        // The EV readout (QoL 2026-07-03): shown ONLY when the user has biased exposure
        // (0 = silent, the uncluttered default) — same transient-cell idiom as the LOOK
        // name, so the pre-lock exposure choice is legible without chrome.
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

    /// ONE ground drag, two verbs by dominant axis (QoL 2026-07-03):
    ///   * HORIZONTAL swipe (on end, 6-cell minimum) cycles the LOOK — unchanged.
    ///   * VERTICAL drag (continuous) sets the EV bias: up = brighter, 1 EV per 200 pt,
    ///     absolute from the drag's starting bias (`evDragBase`), engine-clamped ±2.
    /// Both only write render/exposure params — never a position, so the cell grid is
    /// never disturbed. Gated to `.live` (a busy surface neither grades nor meters).
    private var lookSwipeAndExposureDrag: some Gesture {
        DragGesture(minimumDistance: GlobalLattice.gif(2))
            .onChanged { value in
                guard surface.phase == .live, !stage.active else { return }
                let dx = value.translation.width
                let dy = value.translation.height
                guard abs(dy) > abs(dx) else { return }        // vertical-dominant = EV
                if evDragBase == nil { evDragBase = exposureBias }
                onExposureBias((evDragBase ?? 0) + Float(-dy / 200))
            }
            .onEnded { value in
                defer { evDragBase = nil }
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
/// `DemoScene` (no camera needed). Tune `InfluenceField`'s `static` constants and watch it here;
/// run the full interactive app (draggable widgets) with the `-demoScene` launch argument.
/// (docs/SIXFOUR-TESTABLE-ACT1-WORKFLOW.md)
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
