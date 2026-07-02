import SwiftUI

/// Π — the projection. Maps the current phase of σ to the cells on screen. A phase is a
/// cell-field CONFIGURATION, not a screen: `field(for:_:)` routes each `ABPhase` to its
/// per-phase renderer, all drawing onto the ONE surface.
///
/// The lifecycle is **capture → export → done**. The post-capture A/B game was retired, so
/// the `.captured` + `.picked` phases now route to the inert `BootstrapPhaseField` placeholder
/// pending the new review surface. Routed renderers: `BootstrapPhaseField` /
/// `UnauthorizedPhaseField` / `LivePhaseField` / `ErrorPhaseField`, plus minimal exporting/done
/// fields. The cut renderers (Settings / Capturing / Browsing / Rendering / Review) are no
/// longer routed but left in place. A phase change re-draws cells on the ONE surface — no view swap.
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
        case .deciding:
            // V3.0: the 16³ decide loop (GridLayoutContract.decisionScene widgets).
            DecidingPhaseField(surface: surface)
        case .captured, .picked:
            // Post-capture REVIEW bench (A/B game retired): the captured 64³ beside its 16³
            // octree coarse, both on the Z₆₄ cursor, with EXPORT / RETAKE controls.
            CapturedReviewPhaseField(surface: surface, clock: clock)
        case .exporting:
            ExportingPhaseField(surface: surface, clock: clock)
        case .done:
            DonePhaseField(surface: surface, clock: clock, settings: settings)
        case .error:
            ErrorPhaseField(surface: surface, clock: clock)
        }
    }
}

/// Π·exporting — the minimal cell field shown for the brief transition out of `.picked`.
/// The committed base GIF is already on disk (`surface.gifURL`, set at `commit`), so this
/// phase just advances to `.done`. A flat status word on the persistent ground.
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
        .task { await export() }
    }

    /// The committed base GIF already lives at `surface.gifURL` (set at `commit`), so this
    /// phase carries no encode work: fire `.exportDone` → `.done` and let Done ship the GIF.
    private func export() async {
        surface.step(.exportDone)
    }
}

/// Π·done — the minimal terminal cell field after an export completes. The GIF is shipped;
/// the only action is Retake (back to `.live` to play again). A flat done word + a Retake
/// cell button on the persistent ground.
struct DonePhaseField: View {
    let surface: Surface
    let clock: SurfaceClock
    /// The shared AppSettings — read only for the active Look (the `.cube` LUT is the export
    /// form of the Look axis, surfaced only when a grade is on).
    @Bindable var settings: AppSettings

    /// The built `.cube` awaiting the share sheet (set by the Export LUT button). Ported out
    /// of the retired `ReviewPhaseField`: the .cube LUT export now lives on the Done screen,
    /// beside the GIF Share, so the only worked LUT path survives the Review deletion.
    @State private var lutShare: LUTShareItem?
    /// The training-data bundle awaiting the share sheet (GIF + probability-field `.npy` + contested
    /// sidecar + manifest), built from the committed burst when EXPORT is tapped.
    @State private var shareItems: [Any] = []
    @State private var showShare = false
    /// The colours the LUT grades toward: ALL frames' palettes pooled into one cloud (a
    /// clip-wide profile), falling back to the single review palette. (Ported from Review.)
    private var lutPalette: [SIMD3<UInt8>] {
        let pooled = surface.palettesPerFrame.flatMap { $0 }
        return pooled.isEmpty ? surface.palette : pooled
    }

    var body: some View {
        ZStack {
            Color.clear
            VStack(spacing: GlobalLattice.pt(9)) {
                CellText("EXPORTED", rows: 13, ink: .white)
                // EXPORT the training data: the GIF (the collapse) AND the probability-field `.npy`
                // bin (the functions) as ONE AirDrop/Files bundle. We need both, so one action ships
                // both. The bundle is built once in `.task` (it writes the .npy to tmp); if it could
                // not be built, fall back to a plain GIF share.
                if !shareItems.isEmpty {
                    Button { showShare = true } label: {
                        CellActionButton(icon: .none, title: "EXPORT",
                                         prominent: false, fillWidth: false)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Export the GIF and the probability-field training data")
                } else if let url = surface.gifURL {
                    ShareLink(item: url) {
                        CellActionButton(icon: .none, title: "SHARE GIF",
                                         prominent: false, fillWidth: false)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Share the exported GIF")
                }
                // The active Look's `.cube` LUT (only when a grade is on; it is the export form
                // of the Look axis). Ported verbatim from Review — `LUTFile.makeShareItem` + the
                // pooled `lutPalette` + the `ActivityView` sheet, all unchanged.
                if settings.captureLook != .off {
                    Button {
                        lutShare = LUTFile.makeShareItem(palette: lutPalette, look: settings.captureLook)
                    } label: {
                        CellActionButton(icon: .none, title: "EXPORT LUT",
                                         prominent: false, fillWidth: false)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Export 3D LUT for R3D")
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
        .task { if shareItems.isEmpty { shareItems = exportItems() } }
        // The flow may land (or be invalidated) AFTER this field mounts: rebuild on the
        // VERSION, not nil-ness — a stale→correct replacement is non-nil→non-nil and a
        // nil-ness trigger would silently ship the wrong time axis (device audit).
        .onChange(of: surface.v21FlowVersion) { _, _ in shareItems = exportItems() }
        .sheet(item: $lutShare) { item in
            ActivityView(items: [item.url])
        }
        .sheet(isPresented: $showShare) { ActivityView(items: shareItems) }
    }

    /// Build the EXPORT bundle once: the GIF plus the probability-field `.npy` (the functions the
    /// model trains on), the contested sidecar, and the manifest. Empty when V2.1 is off or the field
    /// cannot be built (then the body offers a plain GIF share instead).
    private func exportItems() -> [Any] {
        guard Feature.v21Capture, let built = builtField() else { return [] }
        return V21Export.shareItems(field: built.field, source: built.source, gifURL: surface.gifURL,
                                    flow: surface.v21Flow)
    }

    /// The probability field from the committed burst, tagged with its provenance. Prefer the GPU
    /// camera-box field (`surface.v21Counts`, the true fine-grid histogram pooled over the burst);
    /// fall back to the index-cube temporal proxy. The source travels into the AirDrop manifest.
    private func builtField() -> (field: V21FieldData, source: V21FieldSource)? {
        let side = surface.cubeSide
        if let counts = surface.v21Counts, counts.count == side * side * 3 * 256 {
            return (V21FieldData(side: side, nLevels: 256, counts: counts), .cameraBox)
        }
        if let f = V21FieldData.fromCapture(indexCube: surface.indexCube,
                                            palettesPerFrame: surface.palettesPerFrame,
                                            side: side) {
            return (f, .temporalProxy)
        }
        return nil
    }
}
