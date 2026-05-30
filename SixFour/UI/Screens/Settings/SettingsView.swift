import SwiftUI

/// The app's only configuration surface. Everything here is the
/// **residual-shaping sampler** — how the continuous OKLab pixel field is
/// mapped onto the significant 256-cell per-frame palette — plus two capture
/// conveniences. Each option is labelled by its *statistical* effect, not an
/// opaque algorithm name, because that is what the choice actually controls:
/// the power spectrum of the quantization residual over the 64×64×64 volume.
///
/// Bound to `AppSettings` via `@Bindable`; the capture screen reads
/// `settings.ditherConfig` fresh on every shot, so changes here apply to the
/// next capture with no extra plumbing.
struct SettingsView: View {
    @Bindable var settings: AppSettings
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                samplerSection
                if settings.defaultDitherMethod == .errorDiffusion {
                    diffusionSection
                } else {
                    blueNoiseSection
                }
                engineSection
                captureSection
                formSection
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    /// The estimator family: where the quantization residual goes.
    private var samplerSection: some View {
        Section {
            Picker("Sampler", selection: $settings.defaultDitherMethod) {
                ForEach(DitherMethod.allCases, id: \.self) { Text($0.label).tag($0) }
            }
            .pickerStyle(.segmented)
        } header: {
            Text("Sampler")
        } footer: {
            Text(settings.defaultDitherMethod.blurb)
        }
    }

    /// Error-diffusion knobs: which moment the diffusion preserves, and
    /// whether the scan direction is whitened.
    private var diffusionSection: some View {
        Section {
            Picker("Kernel", selection: $settings.ditherKernel) {
                ForEach(DitherKernelChoice.allCases, id: \.self) { Text($0.label).tag($0) }
            }
            .pickerStyle(.segmented)
            Toggle("Serpentine scan", isOn: $settings.ditherSerpentine)
        } header: {
            Text("Diffusion")
        } footer: {
            Text(settings.ditherKernel.blurb + "\n" + (settings.ditherSerpentine
                ? "Serpentine: alternating scan direction whitens the residual’s directional bias (removes “worms”)."
                : "Raster: single left-to-right scan — can leave a faint directional texture on shallow gradients."))
        }
    }

    /// Blue-noise knob: the temporal residual spectrum across the 64 frames.
    private var blueNoiseSection: some View {
        Section {
            Picker("Temporal", selection: $settings.blueNoiseTemporal) {
                ForEach(BlueNoiseTemporalMode.allCases, id: \.self) { Text($0.label).tag($0) }
            }
            .pickerStyle(.segmented)
        } header: {
            Text("Blue noise")
        } footer: {
            Text(settings.blueNoiseTemporal.blurb)
        }
    }

    /// The render engine: the deterministic fixed-point core (the verified Zig
    /// pipeline, byte-reproducible) vs the GPU float path. Surfaces the work as a
    /// product choice the user can see and toggle.
    private var engineSection: some View {
        Section {
            Toggle("Deterministic core", isOn: $settings.useDeterministicCore)
        } header: {
            Text("Engine")
        } footer: {
            Text(settings.useDeterministicCore
                ? "Renders through the fixed-point integer pipeline (quantize → dither → significance → palette → encode). Every stage is verified against a proof, so the GIF bytes are reproducible — Review shows the SHA-256."
                : "Renders on the GPU (float). Faster, but the bytes are not bit-reproducible across runs/devices.")
        }
    }

    private var captureSection: some View {
        Section("Capture") {
            Toggle("Open in 64×64 preview", isOn: $settings.openInPixelatedPreview)
            Toggle("Auto-save to Photos", isOn: $settings.autoSaveToPhotos)
        }
    }

    /// The invariant the sampler can never change — stated so the user sees
    /// what is fixed vs what is configurable.
    private var formSection: some View {
        Section("The form") {
            Label {
                Text("64 frames · 64×64 · a 256-colour per-frame palette where every colour is statistically significant.")
                    .font(.callout)
            } icon: {
                Image(systemName: "cube")
            }
            Text("The sampler above only shapes how the quantization residual is distributed across that volume — it never changes the form.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
