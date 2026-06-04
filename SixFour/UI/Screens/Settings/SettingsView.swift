import SwiftUI
import simd

/// The app's only configuration surface — now a **cell-based** screen (GRID §6.7):
/// every control is `CellSelector` / `CellToggle` at the one 2 pt lattice pitch, the
/// native `Form`/`UISegmentedControl`/`Toggle` retired. The long explanatory blurbs
/// stay readable **prose** (system `Text`, the §6.8 fallback) — pixel-font prose at
/// sentence length is unreadable, so the cells carry the *controls* and the text
/// carries the *explanation*.
///
/// Everything here is the **residual-shaping sampler** — how the continuous OKLab
/// pixel field is mapped onto the significant 256-cell per-frame palette — plus two
/// capture conveniences. Each option is labelled by its statistical effect, not an
/// opaque algorithm name. Bound to `AppSettings`; the capture screen reads
/// `settings.ditherConfig` fresh on every shot.
struct SettingsView: View {
    @Bindable var settings: AppSettings
    @Environment(\.dismiss) private var dismiss

    private let accent = SIMD3<UInt8>(96, 165, 250)

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: GlobalLattice.pt(8)) {
                    samplerGroup
                    if settings.defaultDitherMethod == .errorDiffusion {
                        diffusionGroup
                    } else {
                        blueNoiseGroup
                    }
                    engineGroup
                    visualizationGroup
                    captureGroup
                    formGroup
                }
                .padding(GlobalLattice.pt(8))
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .safeAreaInset(edge: .top) { topBar }
    }

    // MARK: Chrome

    private var topBar: some View {
        HStack {
            CellText("SETTINGS", rows: 13, ink: .white)
            Spacer()
            Button { dismiss() } label: {
                CellText("DONE", rows: 11, ink: Color(srgb8: accent))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Done")
        }
        .padding(.horizontal, GlobalLattice.pt(8))
        .padding(.vertical, GlobalLattice.pt(4))
        .background(Color.black)
    }

    private func header(_ s: String) -> some View {
        CellText(s, rows: 11, ink: Color(srgb8: SIMD3<UInt8>(160, 160, 160)))
            .accessibilityAddTraits(.isHeader)
    }

    /// Long explanatory prose — the §6.8 system-`Text` fallback (readable at sentence
    /// length, where a pixel font is not). Settings is not the strict capture HUD.
    private func blurb(_ s: String) -> some View {
        Text(s)
            .font(.system(.caption, design: .monospaced))
            .foregroundStyle(.white.opacity(0.55))
            .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: Groups

    private var samplerGroup: some View {
        VStack(alignment: .leading, spacing: GlobalLattice.pt(3)) {
            header("SAMPLER")
            CellSelector(options: DitherMethod.allCases.map { (value: $0, label: $0.label) },
                         selection: $settings.defaultDitherMethod)
            blurb(settings.defaultDitherMethod.blurb)
        }
    }

    private var diffusionGroup: some View {
        VStack(alignment: .leading, spacing: GlobalLattice.pt(3)) {
            header("DIFFUSION")
            CellSelector(options: DitherKernelChoice.allCases.map { (value: $0, label: $0.label) },
                         selection: $settings.ditherKernel)
            CellToggle(label: "Serpentine scan", isOn: $settings.ditherSerpentine)
            blurb(settings.ditherKernel.blurb + "\n" + (settings.ditherSerpentine
                ? "Serpentine: alternating scan direction whitens the residual’s directional bias (removes “worms”)."
                : "Raster: single left-to-right scan — can leave a faint directional texture on shallow gradients."))
        }
    }

    private var blueNoiseGroup: some View {
        VStack(alignment: .leading, spacing: GlobalLattice.pt(3)) {
            header("BLUE NOISE")
            CellSelector(options: BlueNoiseTemporalMode.allCases.map { (value: $0, label: $0.label) },
                         selection: $settings.blueNoiseTemporal)
            blurb(settings.blueNoiseTemporal.blurb)
        }
    }

    private var engineGroup: some View {
        VStack(alignment: .leading, spacing: GlobalLattice.pt(3)) {
            header("ENGINE")
            CellToggle(label: "Deterministic core", isOn: $settings.useDeterministicCore)
            blurb(settings.useDeterministicCore
                ? "Renders through the fixed-point integer pipeline (quantize → dither → significance → palette → encode). Every stage is verified against a proof, so the GIF bytes are reproducible — Review shows the SHA-256."
                : "Renders on the GPU (float). Faster, but the bytes are not bit-reproducible across runs/devices.")
        }
    }

    private var visualizationGroup: some View {
        VStack(alignment: .leading, spacing: GlobalLattice.pt(3)) {
            header("VISUALIZATION")
            CellToggle(label: "Palette structure", isOn: $settings.showPaletteTree)
            if settings.showPaletteTree {
                CellSelector(options: PaletteBranching.allCases.map { (value: $0, label: $0.label) },
                             selection: $settings.paletteBranching)
            }
            blurb(settings.showPaletteTree
                ? settings.paletteBranching.blurb
                : "Show the 256-colour palette organised as a median-cut tree beneath the GIF, to inspect how the palette covers colour space.")
        }
    }

    private var captureGroup: some View {
        VStack(alignment: .leading, spacing: GlobalLattice.pt(3)) {
            header("CAPTURE")
            CellToggle(label: "Open in 64×64 preview", isOn: $settings.openInPixelatedPreview)
            CellToggle(label: "Auto-save to Photos", isOn: $settings.autoSaveToPhotos)
        }
    }

    private var formGroup: some View {
        VStack(alignment: .leading, spacing: GlobalLattice.pt(3)) {
            header("THE FORM")
            blurb("64 frames · 64×64 · a 256-colour per-frame palette where every colour is statistically significant. The sampler above only shapes how the quantization residual is distributed across that volume — it never changes the form.")
        }
    }
}
