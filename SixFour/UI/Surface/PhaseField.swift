import SwiftUI

/// Π — the projection. Maps the current phase of σ to the cells on screen. A phase is a
/// cell-field CONFIGURATION, not a screen: `field(for:_:)` routes each `SurfacePhase` to
/// its per-phase renderer, all drawing onto the ONE surface.
///
/// Each `case` routes to the real per-phase renderer authored alongside this file
/// (`LivePhaseField` / `CapturingPhaseField` / `RenderingPhaseField` / `ReviewPhaseField`
/// / `BootstrapPhaseField` / `UnauthorizedPhaseField` / `ErrorPhaseField` /
/// `SettingsPhaseField`). The dispatch shape is fixed; a phase change re-draws cells on
/// the ONE surface — no view swap.
enum PhaseField {

    /// Route a phase to its field renderer. `clock` carries the 20 fps heartbeat so the
    /// canvas is live; `surface` carries σ. Returns a type-erased view because the
    /// branches produce heterogeneous renderers.
    @MainActor
    @ViewBuilder
    static func field(for phase: SurfacePhase, _ surface: Surface, _ clock: SurfaceClock,
                      _ settings: AppSettings) -> some View {
        switch phase {
        case .bootstrap:
            BootstrapPhaseField(surface: surface, clock: clock)
        case .unauthorized:
            UnauthorizedPhaseField(surface: surface, clock: clock)
        case .live:
            LivePhaseField(surface: surface, clock: clock, settings: settings)
        case .settings:
            SettingsPhaseField(surface: surface, clock: clock)
        case .locking:
            // The lock is a cell transform of the live field — the shutter goes inert and
            // the capture-progress field names the lock (it carries no palette yet).
            CapturingPhaseField(surface: surface, clock: clock)
        case .capturing:
            CapturingPhaseField(surface: surface, clock: clock)
        case .rendering(let stage):
            RenderingPhaseField(stage: stage, surface: surface, clock: clock, settings: settings)
        case .review:
            ReviewPhaseField(surface: surface, clock: clock, settings: settings)
        case .error:
            ErrorPhaseField(surface: surface, clock: clock)
        }
    }
}
