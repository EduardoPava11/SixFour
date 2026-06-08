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

    var body: some View {
        PhaseField.field(for: surface.phase, surface, clock, engine.settings)
            // The rounded play boundary is an INVISIBLE constraint (open screen = just the
            // preview + palette + checker, nothing else): widgets are kept inside it by
            // `Boundary.footprintFits` (the move's nearest-free search), so the square 64×64
            // can never be dragged where the curved screen would crop it; any saved position
            // outside it is re-homed on launch (`normalizePlacement`). No drawn frame.
            .ignoresSafeArea()
            // The shutter (a σ event) kicks the engine. σ moves to `.locking` on
            // `.shutterTap`; here we observe that edge and start the real burst.
            .environment(surface)
            .task { await engine.bootstrap() }
            .onAppear {
                Surface.assertSpecParity()
                normalizePlacement()   // re-home any widget stranded outside the boundary
                clock.reduceMotion = reduceMotion
                // The ONE per-tick action: advance the Z₆₄ playback cursor. Per-phase
                // engine progress is folded into σ via `.onChange` below, not the tick.
                clock.onTick = { [weak surface] in
                    guard let surface else { return }
                    // Act II: while building the GIFA the preview does NOT freeze — it
                    // sweeps backwards. Forward (normal loop) everywhere else.
                    switch surface.phase {
                    case .capturing, .rendering:
                        surface.advanceCursorReverse()
                    default:
                        surface.advanceCursor()
                    }
                }
                if scenePhase == .active { clock.start() }
            }
            .onDisappear { clock.stop() }
            .onChange(of: reduceMotion) { _, newValue in clock.reduceMotion = newValue }
            .onChange(of: scenePhase) { _, newValue in
                if newValue == .active { clock.start() } else { clock.stop() }
            }
            // σ.phase → engine command. The only place the surface reaches the engine:
            // a `.shutterTap` (σ now `.locking`) fires the burst; a `.retake` (σ now
            // `.live`) resets the engine for the next shot.
            .onChange(of: surface.phase) { old, new in
                switch (old, new) {
                case (.live, .locking):
                    Task { await engine.capture() }
                case (.review, .live):
                    engine.reset()
                default:
                    break
                }
            }
            // engine.phase → σ event. The engine drives the lifecycle forward; σ.step
            // maps each engine edge onto the verified FSM.
            .onChange(of: engine.phase) { _, new in mapEnginePhase(new) }
            // engine.deterministicStage → σ stage-done events. The verified Zig pipeline
            // surfaces its current stage as a string token; advance σ's rendering sub-phase.
            .onChange(of: engine.deterministicStage) { _, stage in mapStage(stage) }
            // Live palette → σ.palette (the live/capturing field paints from σ).
            .onChange(of: engine.livePalette) { _, pal in
                if surface.phase == .live || surface.phase == .locking || surface.phase == .capturing {
                    surface.palette = pal
                }
            }
            // Live camera tile → σ (indexed cells + paired palette). The live hero paints
            // the REAL camera through the cell grid, replacing the synthetic palette scroll.
            .onChange(of: engine.previewIndexTile) { _, tile in
                if surface.phase == .live || surface.phase == .locking || surface.phase == .capturing {
                    surface.previewTile = tile
                    surface.previewPalette = engine.previewPalette
                }
            }
            // Streamed render partials → σ. The deterministic core surfaces the REAL
            // per-stage buffers (quantize→dither→significance→palette) in true colour; fold
            // them into σ so `RenderingPhaseField`'s serpentine sweep reveals the actual
            // GIFA-in-progress, not an empty placeholder. Only while `.rendering`.
            .onChange(of: engine.renderPartialCube) { _, cube in
                if case .rendering = surface.phase {
                    surface.palette = engine.renderPartialPalette
                    surface.indexCube = cube
                }
            }
            // The finished GIFA → σ (palette + index cube), then the explicit commit
            // (`lawReviewExplicit`: review is reached ONLY via `.committed`).
            .onChange(of: engine.primaryOutput) { _, out in
                if let out { commit(out) }
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

    /// Translate one engine `Phase` edge into the σ FSM event that advances it. The
    /// engine sets its phase synchronously through bootstrap → idle and through the
    /// burst; σ.step is total (an unmodelled pair is a no-op), so an out-of-order edge
    /// never derails the surface.
    private func mapEnginePhase(_ p: CaptureViewModel.Phase) {
        switch p {
        case .unauthorized:
            surface.step(.authDenied)
        case .idle:
            // Session ready: bootstrap → live. (Re-entry from a finished render is a
            // no-op by δ, so this is safe to fire on every idle edge.)
            surface.step(.sessionReady)
        case .configuring:
            break   // still on bootstrap; no event yet
        case .locking:
            break   // σ already entered `.locking` on the shutter tap that started this
        case .capturing:
            // The AE/AWB lock completed and the burst is in flight.
            surface.step(.lockComplete)
        case .renderingStageA, .renderingEncode:
            // The burst finished; the render pipeline is running. `.burstComplete` moves
            // σ into `.rendering(.quantize)`; the granular stages ride `deterministicStage`.
            surface.step(.burstComplete)
        case .done:
            // Handled by the `primaryOutput` commit path (`lawReviewExplicit`).
            break
        case .failed:
            surface.step(.fault)
        }
    }

    // MARK: - engine.deterministicStage → σ stage-done

    /// Advance σ's rendering sub-phase to track the verified Zig kernel currently running.
    /// The engine reports the stage it has STARTED; σ models stage COMPLETION, so seeing
    /// stage N+1 start means stage N is done. We drive σ forward to the reported stage's
    /// sub-phase by stepping the chain of `.stageDone` events up to it.
    private func mapStage(_ stage: String?) {
        guard let stage, let target = SurfacePhase.RenderStage(rawValue: stage) else { return }
        // Step `.stageDone` events until σ's rendering sub-phase reaches `target`. Each
        // step is a δ no-op unless it is the modelled next transition, so this converges
        // monotonically to the reported stage and never overshoots.
        let order = SurfacePhase.RenderStage.allCases
        guard let targetIdx = order.firstIndex(of: target) else { return }
        var guardCount = 0
        while case let .rendering(cur) = surface.phase,
              let curIdx = order.firstIndex(of: cur),
              curIdx < targetIdx,
              guardCount < order.count {
            surface.step(.stageDone(cur))
            guardCount += 1
        }
    }

    // MARK: - commit (engine output → σ, then explicit review)

    /// Fold the finished GIFA into σ (the global palette + the flat 64³ index cube) and
    /// fire the ONE event that may enter review (`lawReviewExplicit`). The engine's
    /// `CaptureOutput` carries the per-frame palettes + per-pixel indices; σ holds a
    /// single global palette for review, so we take frame-0's palette as the display
    /// palette (the deterministic-global path replicates one palette across all frames;
    /// the per-frame path uses frame 0 as the representative) and pack the indices into
    /// the flat `t,y,x` cube `ReviewPhaseField` reads.
    private func commit(_ out: CaptureOutput) {
        // Carry the FULL per-frame palette series so review shows the real per-frame GIFA;
        // keep frame-0 on `surface.palette` for the `cellGlobal` accessor / loading reads.
        surface.palettesPerFrame = out.palettesForDisplay
        if let pal = out.palettesForDisplay.first {
            surface.palette = pal
        }
        if let frames = out.frameIndicesForVoxels {
            var cube = [UInt8]()
            cube.reserveCapacity(frames.count * SixFourShape.pixelsPerFrame)
            for f in frames { cube.append(contentsOf: f) }
            surface.indexCube = cube
        }
        surface.settings.useDeterministicCore = out.deterministic
        // First drive σ to the encode sub-phase if the render edges were missed (the
        // engine can finish faster than the phase observer fires), then commit.
        finishRendering()
        surface.step(.committed)
    }

    /// Ensure σ has walked the full rendering chain to `.rendering(.encode)` before the
    /// commit, so `.committed` is a modelled transition even if intermediate stage edges
    /// arrived out of order or were coalesced.
    private func finishRendering() {
        guard case .rendering = surface.phase else {
            // Not in the rendering family (e.g. the engine raced ahead). Re-walk from
            // capturing only if σ is somewhere on the capture path; otherwise leave it.
            return
        }
        let order = SurfacePhase.RenderStage.allCases
        var guardCount = 0
        while case let .rendering(cur) = surface.phase, cur != .encode, guardCount < order.count {
            surface.step(.stageDone(cur))
            guardCount += 1
        }
    }
}
