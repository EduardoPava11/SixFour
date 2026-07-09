import SwiftUI

/// RUNG + SYSTEM TELEMETRY (Feature.rungTelemetry only): folds the engine's telemetry
/// snapshots into σ so the `liveScene` instrument flanks (`RungTelemetryFlanks`) read
/// them like every other surface datum. Extracted into a `ViewModifier` — the
/// `OpticalTileFolds` precedent — because inlining more `.onChange` on `SurfaceView`'s
/// already-long body tips the SwiftUI type-checker past its expression-complexity limit.
///
/// Deliberately UN-gated on σ.phase (unlike the LOOK-graded tile folds): the burst-seam
/// FINAL snapshot is published from `finishBurst` and may race the engine's `.done` →
/// `.captured` phase fold on the main actor — dropping it would lose the most complete
/// reading of the burst. Folding while σ is elsewhere is harmless (the flanks are only
/// mounted by `LivePhaseField`), and there is no grading to apply. Flag off ⇒ the
/// callbacks never fire and these stay nil forever (zero cost).
struct RungTelemetryFolds: ViewModifier {
    let engine: CaptureViewModel
    let surface: Surface

    func body(content: Content) -> some View {
        content
            .onChange(of: engine.rungTelemetry) { _, snapshot in
                surface.rungTelemetry = snapshot
            }
            .onChange(of: engine.systemTelemetry) { _, snapshot in
                surface.systemTelemetry = snapshot
            }
            // THE FLUX BAR (E6): the ≤ 5 Hz GCT pulse rides the same instrument-fold
            // discipline (un-gated on σ.phase — only `LivePhaseField` mounts the bar).
            .onChange(of: engine.previewGCT) { _, gct in
                surface.latestGCT = gct
            }
    }
}
