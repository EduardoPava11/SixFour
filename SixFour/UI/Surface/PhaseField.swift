import SwiftUI

/// Π — the projection. Maps the current phase of σ to the cells on screen. A phase is a
/// cell-field CONFIGURATION, not a screen: `field(for:_:)` routes each `SurfacePhase` to
/// its per-phase renderer, all drawing onto the ONE surface.
///
/// STAGE 2: every phase routes to `PhaseStubField`, the existing live B/W checker (so the
/// spine compiles end to end). Each `case` below is the SEAM a real per-phase renderer
/// will fill next stage — one `(Surface, SurfaceClock) -> some View` function per file
/// (e.g. `LiveField`, `ReviewField`, `RenderingField`). Replace the stub call in a case
/// with that renderer; the dispatch shape stays fixed.
enum PhaseField {

    /// Route a phase to its field renderer. `clock` carries the 20 fps heartbeat so the
    /// canvas is live; `surface` carries σ. Returns a type-erased view because the
    /// branches will produce heterogeneous renderers.
    @MainActor
    @ViewBuilder
    static func field(for phase: SurfacePhase, _ surface: Surface, _ clock: SurfaceClock) -> some View {
        switch phase {
        case .bootstrap:
            // SEAM → BootstrapField (skeleton). Stub: live checker.
            PhaseStubField(label: "bootstrap", clock: clock)
        case .unauthorized:
            // SEAM → UnauthorizedField. Stub: live checker.
            PhaseStubField(label: "unauthorized", clock: clock)
        case .live:
            // SEAM → LiveField (preview hero + palette shutter). Stub: live checker.
            PhaseStubField(label: "live", clock: clock)
        case .settings:
            // SEAM → SettingsField. Stub: live checker.
            PhaseStubField(label: "settings", clock: clock)
        case .locking:
            // SEAM → LiveField with AE/AF-lock banner. Stub: live checker.
            PhaseStubField(label: "locking", clock: clock)
        case .capturing:
            // SEAM → LiveField with the 256-cell capture progress. Stub: live checker.
            PhaseStubField(label: "capturing", clock: clock)
        case .rendering(let stage):
            // SEAM → RenderingField (serpentine resolve sweep over the GIFA). Stub: checker.
            PhaseStubField(label: "rendering:\(stage.rawValue)", clock: clock)
        case .review:
            // SEAM → ReviewField (GIF/cube hero + pose + actions). Stub: live checker.
            PhaseStubField(label: "review", clock: clock)
        case .error:
            // SEAM → ErrorField (failure cells). Stub: live checker.
            PhaseStubField(label: "error", clock: clock)
        }
    }
}

/// The Stage-2 placeholder field: the existing live B/W checker (a `GridRefreshFieldView`
/// driven by the ONE clock's heartbeat) with the phase token printed as cells, so the
/// surface visibly proves which phase it's in while the real renderers are unbuilt.
struct PhaseStubField: View {
    let label: String
    let clock: SurfaceClock

    var body: some View {
        ZStack(alignment: .topLeading) {
            GridRefreshFieldView(phase: clock.heartbeat)
                .ignoresSafeArea()
            CellText(label, rows: 11, ink: .white)
                .padding(.horizontal, GlobalLattice.pt(5))
                .padding(.vertical, GlobalLattice.pt(3))
                .background(Color(srgb8: SIMD3<UInt8>(20, 20, 24)))
                .padding(.top, GlobalLattice.pt(36))
                .padding(.leading, GlobalLattice.pt(3))
                .allowsHitTesting(false)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .ignoresSafeArea()
    }
}
