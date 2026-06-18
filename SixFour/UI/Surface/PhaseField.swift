import SwiftUI

/// Π — the projection. Maps the current phase of σ to the cells on screen. A phase is a
/// cell-field CONFIGURATION, not a screen: `field(for:_:)` routes each `ABPhase` to its
/// per-phase renderer, all drawing onto the ONE surface.
///
/// Under the A/B genome shift the lifecycle collapses to **capture → A/B → export**, so
/// only five renderers are routed: `BootstrapPhaseField` / `UnauthorizedPhaseField` /
/// `LivePhaseField` / the new `ABCandidatePhaseField` (the `.captured` + `.picked` A/B
/// game) / `ErrorPhaseField`, plus minimal exporting/done fields. The cut renderers
/// (Settings / Capturing / Browsing / Rendering / Review) are no longer routed but left in
/// place. A phase change re-draws cells on the ONE surface — no view swap.
enum PhaseField {

    /// Route a phase to its field renderer. `clock` carries the 20 fps heartbeat so the
    /// canvas is live; `surface` carries σ. Returns a type-erased view because the
    /// branches produce heterogeneous renderers.
    /// `onShutter` is the direct engine `capture()` kick (lock + burst are internal to
    /// `.live` under ABSurface — there is no `.locking` phase to observe), wired by
    /// `SurfaceView` and called by the LivePhaseField shutter.
    @MainActor
    @ViewBuilder
    static func field(for phase: ABPhase, _ surface: Surface, _ clock: SurfaceClock,
                      _ settings: AppSettings, onShutter: @escaping () -> Void) -> some View {
        switch phase {
        case .bootstrap:
            BootstrapPhaseField(surface: surface, clock: clock)
        case .unauthorized:
            UnauthorizedPhaseField(surface: surface, clock: clock)
        case .live:
            LivePhaseField(surface: surface, clock: clock, settings: settings, onShutter: onShutter)
        case .captured, .picked:
            // The A/B game: two orthogonal candidate GIFs; tapping one IS the pick, which
            // re-proposes a taste-shifted pair (the infinite game). Export ends it.
            ABCandidatePhaseField(surface: surface, clock: clock, settings: settings)
        case .exporting:
            ExportingPhaseField(surface: surface, clock: clock)
        case .done:
            DonePhaseField(surface: surface, clock: clock)
        case .error:
            ErrorPhaseField(surface: surface, clock: clock)
        }
    }
}

/// Π·exporting — the minimal cell field shown while the cube-ladder export family
/// {16³, 64³, 256³} is being produced (entered only from `.picked`). A flat status word on
/// the persistent ground; the real `ABExportFamily` wiring is a follow-on.
struct ExportingPhaseField: View {
    let surface: Surface
    let clock: SurfaceClock

    var body: some View {
        ZStack {
            Color.clear
            CellText("EXPORTING…", rows: 9, ink: Color(srgb8: SIMD3(190, 190, 190)))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Exporting")
        // Drive the terminal edge so `.exporting` is never a dead-end. The genome-faithful
        // cube-ladder encode (ABExportFamily {16³,64³,256³} carrying the chosen genome) is P3;
        // for now the auto-rendered GIF (`surface.gifURL`) is the shippable artifact, surfaced
        // for Share on the Done field. A brief beat, then `.exportDone` → `.done`.
        .onAppear {
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 400_000_000)
                surface.step(.exportDone)
            }
        }
    }
}

/// Π·done — the minimal terminal cell field after an export completes. The GIF is shipped;
/// the only action is Retake (back to `.live` to play again). A flat done word + a Retake
/// cell button on the persistent ground.
struct DonePhaseField: View {
    let surface: Surface
    let clock: SurfaceClock

    var body: some View {
        ZStack {
            Color.clear
            VStack(spacing: GlobalLattice.pt(9)) {
                CellText("EXPORTED", rows: 13, ink: .white)
                // The rendered GIF is the shippable artifact (the genome-faithful cube-ladder
                // is P3). Surface it for Share when present; otherwise just offer a new shot.
                if let url = surface.gifURL {
                    ShareLink(item: url) {
                        CellActionButton(icon: .none, title: "SHARE GIF",
                                         prominent: false, fillWidth: false)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Share the exported GIF")
                }
                Button { surface.step(.retake) } label: {
                    CellActionButton(icon: .none, title: "NEW SHOT",
                                     prominent: true, fillWidth: false)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Capture a new shot")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
