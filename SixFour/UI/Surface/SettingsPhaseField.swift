import SwiftUI
import simd

/// Π for the `.settings` phase — the cell-field renderer for the configuration screen,
/// ported from the legacy `SettingsView` onto the ONE surface. A phase change is a cell
/// update, not a view swap: this field draws over the same surface as `.live`, and the
/// "Close" control returns by stepping σ with `.closeSettings` (δ: settings → live).
///
/// CELLS ONLY (GRID §6.7 / total-pixelation): every control is a `CellSelector` /
/// `CellToggle` / `CellText` at the one lattice pitch — no `Text`, no glass, no
/// SF-Symbol, no UIKit `Slider`/`Picker` on chrome. The legacy `SettingsView` kept
/// sentence-length *prose* as system `Text`; on the one surface the field is the
/// strict instrument, so the explanatory prose is dropped here (the labelled cell
/// controls carry the meaning) and only short cell taglines remain.
///
/// σ wiring: the controls bind to `σ.settings` (`SurfaceSettings`) **in place**.
/// `SurfaceSettings` currently models the one spine field `useDeterministicCore`; the
/// residual-shaping sampler choices (dither method / kernel / serpentine / temporal /
/// capture conveniences) are NOT yet on the σ spine, so they are held here as local
/// `@State` and shaped to migrate into `SurfaceSettings` in a later stage (the seam is
/// the binding, not the storage). When a field is added to `SurfaceSettings`, swap the
/// local `@State` binding for `$surface.settings.<field>` — nothing else changes.
///
/// Tier-2: SwiftUI + simd, zero third-party deps.
struct SettingsPhaseField: View {

    /// σ — the one surface. `@Bindable` so the `useDeterministicCore` toggle edits the
    /// spine in place; the close action steps δ.
    @Bindable var surface: Surface

    /// κ — the one clock. The header band stays alive (heartbeat) so the surface visibly
    /// proves it is still the live field, just in its `.settings` phase.
    let clock: SurfaceClock

    // MARK: - Sampler state not yet on the σ spine (see header note)

    @State private var ditherMethod: DitherMethod = .errorDiffusion
    @State private var ditherKernel: DitherKernelChoice = .floydSteinberg
    @State private var ditherSerpentine: Bool = false
    @State private var blueNoiseTemporal: BlueNoiseTemporalMode = .spatiotemporal
    @State private var openInPixelatedPreview: Bool = false
    @State private var autoSaveToPhotos: Bool = false

    // MARK: - Cell palette (fixed, calm — Settings is a static surface)

    private let ground = SIMD3<UInt8>(8, 8, 10)
    private let headerInk = SIMD3<UInt8>(160, 160, 160)
    private let taglineInk = SIMD3<UInt8>(120, 120, 120)
    private let accent = SIMD3<UInt8>(96, 165, 250)

    var body: some View {
        ZStack(alignment: .top) {
            Color(srgb8: ground).ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: GlobalLattice.pt(8)) {
                    Color.clear.frame(height: GlobalLattice.gif(GlobalLattice.touchFloorCells))
                    samplerGroup
                    if ditherMethod == .errorDiffusion {
                        diffusionGroup
                    } else {
                        blueNoiseGroup
                    }
                    engineGroup
                    captureGroup
                    formGroup
                }
                .padding(GlobalLattice.pt(8))
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .safeAreaInset(edge: .top) { topBar }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .ignoresSafeArea()
    }

    // MARK: - Chrome (cells only)

    /// The header band: title + a CLOSE control that steps δ back to `.live`. The
    /// heartbeat bit keeps the band a live cell field, not a static bar.
    private var topBar: some View {
        HStack {
            CellText("SETTINGS", rows: 13, ink: .white)
            Spacer()
            Button { surface.step(.closeSettings) } label: {
                CellText("CLOSE", rows: 11, ink: Color(srgb8: accent))
                    .padding(.horizontal, GlobalLattice.pt(3))
                    .frame(minHeight: GlobalLattice.gif(GlobalLattice.touchFloorCells))
                    .background(Color(srgb8: SFTheme.ledGhost))
                    .border(Color(srgb8: accent), width: GlobalLattice.pt(1))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close settings")
        }
        .padding(.horizontal, GlobalLattice.pt(8))
        .padding(.vertical, GlobalLattice.pt(4))
        .background(Color(srgb8: ground))
    }

    private func header(_ s: String) -> some View {
        CellText(s, rows: 11, ink: Color(srgb8: headerInk))
            .accessibilityAddTraits(.isHeader)
    }

    /// A short cell tagline — the §6.8 strict-instrument substitute for the legacy
    /// system-`Text` blurb. Kept short so the pixel font stays legible.
    private func tagline(_ s: String) -> some View {
        CellText(s, rows: 9, ink: Color(srgb8: taglineInk))
    }

    // MARK: - Groups (each a header + cell controls)

    private var samplerGroup: some View {
        VStack(alignment: .leading, spacing: GlobalLattice.pt(3)) {
            header("SAMPLER")
            CellSelector(options: DitherMethod.allCases.map { (value: $0, label: $0.label) },
                         selection: $ditherMethod)
            tagline(ditherMethod.tagline)
        }
    }

    private var diffusionGroup: some View {
        VStack(alignment: .leading, spacing: GlobalLattice.pt(3)) {
            header("DIFFUSION")
            CellSelector(options: DitherKernelChoice.allCases.map { (value: $0, label: $0.label) },
                         selection: $ditherKernel)
            CellToggle(label: "Serpentine scan", isOn: $ditherSerpentine)
            tagline(ditherSerpentine ? "whitens scan bias" : "raster scan")
        }
    }

    private var blueNoiseGroup: some View {
        VStack(alignment: .leading, spacing: GlobalLattice.pt(3)) {
            header("BLUE NOISE")
            CellSelector(options: BlueNoiseTemporalMode.allCases.map { (value: $0, label: $0.label) },
                         selection: $blueNoiseTemporal)
            tagline(blueNoiseTemporal == .spatiotemporal ? "white in time" : "steady in time")
        }
    }

    /// The one group bound to the σ spine: the deterministic fixed-point Zig core.
    private var engineGroup: some View {
        VStack(alignment: .leading, spacing: GlobalLattice.pt(3)) {
            header("ENGINE")
            CellToggle(label: "Deterministic core",
                       isOn: $surface.settings.useDeterministicCore)
            tagline(surface.settings.useDeterministicCore
                ? "reproducible bytes · SHA shown"
                : "GPU float · not reproducible")
        }
    }

    private var captureGroup: some View {
        VStack(alignment: .leading, spacing: GlobalLattice.pt(3)) {
            header("CAPTURE")
            CellToggle(label: "Open in 64 preview", isOn: $openInPixelatedPreview)
            CellToggle(label: "Auto-save to Photos", isOn: $autoSaveToPhotos)
        }
    }

    private var formGroup: some View {
        VStack(alignment: .leading, spacing: GlobalLattice.pt(3)) {
            header("THE FORM")
            tagline("64 frames · 64x64 · 256 sig colours")
        }
    }
}
