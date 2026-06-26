import SwiftUI
import simd

/// THE single mounted view. `SixFourApp`'s `WindowGroup` hosts exactly this. It owns σ
/// (`Surface`), κ (`SurfaceClock`), AND the capture engine (`CaptureViewModel` — the
/// AVCaptureSession + burst + deterministic Zig render driver). Its body is the phase-
/// field projection Π of σ: `PhaseField.field(for: σ.phase, σ, κ)`. A phase change
/// re-draws cells on this same surface — there is no view swap, no modal cover, no
/// `NavigationStack`. capture → render → review are phases of the one field.
///
/// The engine is the ENGINE, not the router: σ.phase is the single source of truth for
/// what the surface shows. `SurfaceView` watches the engine's progress and maps it onto
/// σ through `step(_:)` events (`SessionReady`/`AuthDenied`/`LockComplete`/`BurstComplete`
/// /`StageDone`/`Committed`/`Fault`). The shutter tap (a σ event) kicks the engine's
/// `capture()`; the engine's outputs flow back into σ (palette + index cube).
///
/// Lifecycle: the clock runs while the window is active and stops when it backgrounds
/// (zero idle battery). Reduce-motion is forwarded to the clock. On first appearance the
/// Swift↔Haskell phase-FSM parity is asserted (debug only) and the engine bootstraps.
struct SurfaceView: View {
    @State private var surface = Surface()
    @State private var clock = SurfaceClock()
    @State private var engine = CaptureViewModel()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase

    #if DEBUG
    /// TESTABLE ACT I (no camera): when launched with `-demoScene`, skip the engine bootstrap,
    /// land directly in `.live`, and feed σ a synthetic drifting scene each κ tick so the
    /// influence field can be seen/tuned in the Simulator. DEBUG-only.
    /// (docs/SIXFOUR-TESTABLE-ACT1-WORKFLOW.md)
    private static let demoScene = ProcessInfo.processInfo.arguments.contains("-demoScene")
    #endif

    var body: some View {
        ZStack {
            // THE ONE PERSISTENT GROUND, hoisted ABOVE the phase router so it is created ONCE for
            // the whole app lifetime — the GPU CAMetalLayer is never torn down/rebuilt per phase
            // (the act1→act2 transition flash). Every phase field renders its widgets + chrome on a
            // CLEAR background ON TOP of this. (docs/SIXFOUR-DIMENSIONAL-FIELD-ARCHITECTURE.md S5.)
            StageGround(surface: surface, placement: engine.settings.widgetPlacement, tick: clock.tick)
                .ignoresSafeArea()
            PhaseField.field(for: surface.phase, surface, clock, engine.settings,
                             onShutter: { Task { await engine.capture() } })
        }
            // The rounded play boundary is an INVISIBLE constraint (widgets kept inside it by
            // `Boundary.footprintFits`); any saved position outside it is re-homed on launch.
            .ignoresSafeArea()
            // The shutter kicks the engine directly (`onShutter` → `engine.capture()`); σ
            // stays `.live` until the engine's `.done` folds the GIFA and fires `.burstComplete`.
            .environment(surface)
            .task {
                #if DEBUG
                // Demo scene: bypass the camera, go straight to a live, data-fed Act I.
                if Self.demoScene { surface.step(.sessionReady); return }
                #endif
                await engine.bootstrap()
            }
            .onAppear {
                Surface.assertSpecParity()
                normalizePlacement()   // re-home any widget stranded outside the boundary
                clock.reduceMotion = reduceMotion
                // The ONE per-tick action: advance the Z₆₄ playback cursor. Per-phase
                // engine progress is folded into σ via `.onChange` below, not the tick.
                clock.onTick = { [weak surface, weak clock] in
                    guard let surface else { return }
                    #if DEBUG
                    // Demo scene: write the synthetic drifting tile/palette into σ each tick
                    // (keyed off κ's monotonic counter), so the live influence field animates
                    // without a camera. Only while `.live`.
                    if Self.demoScene, let clock, surface.phase == .live {
                        surface.previewTile = DemoScene.tile(tick: clock.tick)
                        surface.previewPalette = DemoScene.palette
                        surface.palette = DemoScene.palette
                    }
                    #endif
                    // κ advances the Z₆₄ playback cursor: the A/B heroes (`.captured` /
                    // `.picked`) and the done preview (`.done`) play the 64-frame loop;
                    // `.live` (and the rest) also advances the cursor harmlessly.
                    surface.advanceCursor()
                }
                if scenePhase == .active { clock.start() }
            }
            .onDisappear { clock.stop() }
            .onChange(of: reduceMotion) { _, newValue in clock.reduceMotion = newValue }
            .onChange(of: scenePhase) { _, newValue in
                if newValue == .active { clock.start() } else { clock.stop() }
            }
            // σ.phase → engine command. The capture itself is now kicked directly by the
            // LivePhaseField shutter (`engine.capture()`); the only thing left to do on a
            // phase edge is reset the engine on a `.retake` back to `.live` for the next shot.
            .onChange(of: surface.phase) { old, new in
                // Stamp the tick the new phase was entered → the renderers ease the act-to-act
                // transition over a few 20 fps ticks (F2) instead of cutting.
                surface.phaseEnteredTick = clock.tick
                // Retake: any A/B/done phase → live resets the engine for the next burst.
                if new == .live && old != .bootstrap {
                    engine.reset()
                }
            }
            // Lift state changed → stamp the tick so the influence field RAMPS the lift-dim (F3)
            // over a few 20 fps ticks instead of snapping.
            .onChange(of: surface.liftedWidget) { _, _ in
                surface.liftChangedTick = clock.tick
            }
            // engine.phase → σ event. The engine drives the lifecycle forward; σ.step
            // maps each engine edge onto the verified A/B FSM. Lock + burst + render are all
            // internal to `.live`; the engine's `.done` folds the GIFA into σ then fires
            // `.burstComplete` (→ `.captured`, the A/B game).
            .onChange(of: engine.phase) { _, new in mapEnginePhase(new) }
            // Live palette → σ.palette (the live field paints from σ). Only while `.live`
            // (capture + render are now internal to `.live`).
            .onChange(of: engine.livePalette) { _, pal in
                if surface.phase == .live {
                    // The capture-screen LOOK re-grades the palette (swipe to cycle); the
                    // index tile is untouched, so the 16×16 shutter recolours in place.
                    surface.palette = engine.settings.captureLook.apply(to: pal)
                }
            }
            // Live camera tile → σ (indexed cells + paired palette). The live hero paints
            // the REAL camera through the cell grid, replacing the synthetic palette scroll.
            .onChange(of: engine.previewIndexTile) { _, tile in
                if surface.phase == .live {
                    surface.previewTile = tile
                    // Re-grade the hero's palette through the active LOOK (same transform
                    // as the shutter + the exported LUT); the index tile is unchanged.
                    surface.previewPalette = engine.settings.captureLook.apply(to: engine.previewPalette)
                }
            }
            // The finished GIFA → σ. If the engine's `.done` edge raced ahead of this
            // observer the commit already ran in `mapEnginePhase`; folding again is
            // idempotent (it overwrites σ with the same bytes) and `.burstComplete` is a
            // no-op once σ has left `.live`, so this is a safe belt-and-braces catch.
            .onChange(of: engine.primaryOutput) { _, out in
                if let out, surface.phase == .live { commit(out); surface.step(.burstComplete) }
            }
            // Debug-only ownership overlay (full-lattice identity-badge bitmap). The
            // outermost slot, above every phase; off by default ⇒ the branch is
            // EmptyView and the shipping chain is byte-identical. `engine.settings`
            // is the one live AppSettings (@Observable read tracks the toggle).
            .overlay(alignment: .topLeading) {
                if engine.settings.debugOwnershipOverlay { CellOwnershipOverlay() }
            }
            .preferredColorScheme(.dark)
            .statusBarHidden()
    }

    // MARK: - boundary re-home

    /// Re-home any widget whose SAVED position no longer fits the play boundary (e.g. a
    /// position persisted before the boundary existed, leaving it stranded off-screen or in
    /// a corner) — reset it to its default dock. Runs once on appear; a no-op when every
    /// widget already fits, so a valid saved layout is preserved verbatim.
    private func normalizePlacement() {
        var p = engine.settings.widgetPlacement
        var changed = false
        for id in ColorIdentity.allCases {
            guard let pos = p[id] else { continue }
            let (w, h) = MoveContract.footprint(id)
            if !Boundary.footprintFits(col: pos.col, row: pos.row, w: w, h: h) {
                p[id] = (MoveContract.defaultCol(id), MoveContract.defaultRow(id))
                changed = true
            }
        }
        if changed { engine.settings.widgetPlacement = p }
    }

    // MARK: - engine.phase → σ event

    /// Translate one engine `Phase` edge into the σ FSM event that advances it. Under
    /// ABSurface lock + burst + the whole render pipeline are INTERNAL to `.live` (there is
    /// no `.locking` / `.capturing` / `.rendering` phase to observe) — only the engine's
    /// `.done` matters: it folds the finished GIFA into σ and fires `.burstComplete`
    /// (→ `.captured`, the A/B game). σ.step is total, so an out-of-order edge is a no-op.
    private func mapEnginePhase(_ p: CaptureViewModel.Phase) {
        switch p {
        case .unauthorized:
            surface.step(.authDenied)
        case .idle:
            // Session ready: bootstrap → live. (Re-entry from a finished shot is a δ no-op,
            // so this is safe to fire on every idle edge.)
            surface.step(.sessionReady)
        case .configuring, .locking, .capturing, .renderingStageA, .renderingEncode:
            break   // lock + burst + render are internal to `.live`; σ stays `.live`
        case .done:
            // The GIFA is finished: fold it into σ, THEN advance to the A/B game.
            if let out = engine.primaryOutput { commit(out) }
            surface.step(.burstComplete)
        case .failed:
            surface.step(.fault)
        }
    }

    // MARK: - commit (engine output → σ)

    /// Fold the finished GIFA into σ — the per-frame palette series, the GIF URL, frame-0's
    /// palette (the `surface.palette` accessor), and the flat 64³ index cube the A/B heroes read.
    /// The engine's `CaptureOutput` carries the per-frame palettes + per-pixel indices; the
    /// caller fires `.burstComplete` AFTER this (so σ already has the data when `.captured`
    /// mounts the A/B field).
    private func commit(_ out: CaptureOutput) {
        surface.palettesPerFrame = out.palettesForDisplay
        surface.gifURL = out.gifURL
        if let pal = out.palettesForDisplay.first {
            surface.palette = pal
        }
        if let frames = out.frameIndicesForVoxels {
            var cube = [UInt8]()
            cube.reserveCapacity(frames.count * SixFourShape.pixelsPerFrame)
            for f in frames { cube.append(contentsOf: f) }
            surface.indexCube = cube
        }
        // Build the 16³ octree-coarse substrate once, post-capture, for the review bench's
        // coarse tile (byte-exact VoxelReduce of the committed 64³ cube).
        surface.buildCoarseSubstrate()
    }
}
