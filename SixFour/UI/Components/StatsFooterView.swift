import SwiftUI

/// Bottom pill that summarises one rendered GIF: extractor · file size ·
/// render time · witness status. Surfaces the math state of the capture
/// without requiring a separate Inspector — every field traces back to a
/// named object in `spec/MATH.md`.
struct StatsFooterView: View {
    let output: CaptureOutput

    var body: some View {
        // Two rows: top = identity (extractor, mode, runtime
        // pipeline metrics); bottom = quality (MSE, κ, admission
        // rate). Keeps the line lengths readable on a 64×64-
        // aspect-ratio screen.
        VStack(spacing: 2) {
            HStack(spacing: 8) {
                label(extractorText, mono: false)
                dot
                label(sizeText, mono: true)
                dot
                label(timeText, mono: true)
                dot
                label(witnessText, mono: true)
                    .foregroundStyle(witnessTint)
            }
            HStack(spacing: 8) {
                label(mseText, mono: true)
                dot
                label(kappaText, mono: true)
                dot
                label(admissionText, mono: true)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(.ultraThinMaterial, in: Capsule())
        .accessibilityElement(children: .combine)
        .accessibilityLabel(voiceOverDescription)
    }

    /// Dither method label (Diffusion / Blue noise) — the one creative
    /// variable now that the extractor is fixed at Wu+KM. First field so the
    /// user sees immediately which look produced the visible GIF.
    private var extractorText: String { output.ditherMethod.label }

    /// Mean extraction MSE in OKLab units². Lower = tighter
    /// quantization. Surfaced so users can A/B compare extractors
    /// on the same scene without external tooling.
    private var mseText: String {
        // OKLab values are small (mostly ≤ 1.0); MSE is usually
        // 0.0001..0.01. Use 5 significant digits in scientific
        // notation so the comparison is readable across scales.
        String(format: "MSE %.4f", output.meanExtractMSE)
    }

    /// Mean centroid condition number κ across 64 frames. κ ≈ 1 →
    /// orthogonal centroids; κ ≫ 1 → near-collinear (palette has
    /// wasted slots). Editing-tool refill heuristic candidate.
    private var kappaText: String {
        if output.meanCentroidConditionNumber.isFinite {
            return String(format: "κ %.2f", output.meanCentroidConditionNumber)
        } else {
            return "κ ∞"
        }
    }

    /// Fraction of clusters admitted by χ²₃ at α=0.05 (averaged
    /// over 64 frames). Higher = more statistically real palette
    /// slots; lower = palette is dominated by noise/empty bins.
    private var admissionText: String {
        let pct = output.meanAdmissionRateAt05 * 100
        return String(format: "χ² %.0f%%", pct)
    }

    // MARK: - Field projections

    private var sizeText: String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(output.fileSize))
    }

    private var timeText: String {
        if output.renderMillis < 1_000 {
            return "\(output.renderMillis) ms"
        }
        return String(format: "%.2f s", Double(output.renderMillis) / 1_000.0)
    }

    private var witnessText: String {
        // Every emitted GIF is a SignificantVoxelVolume: each of the 64 frames
        // uses all 256 palette slots AND every slot is statistically
        // significant — backed by ≥ minPopulation pixels (never a donated
        // outlier), enforced by SignificantSplitFill + the encoder's
        // `SignificantVoxelVolume` gate. A volume that fails either invariant
        // can't reach here, so the witness is always clean.
        "✓"
    }

    private var witnessTint: Color { .green }

    private var voiceOverDescription: String {
        "\(extractorText) dither, \(sizeText), rendered in \(timeText)."
    }

    // MARK: - Building blocks

    @ViewBuilder
    private func label(_ text: String, mono: Bool) -> some View {
        Text(text)
            .font(mono
                  ? .system(.caption, design: .monospaced, weight: .medium)
                  : .system(.caption, weight: .semibold))
            .foregroundStyle(.white)
    }

    private var dot: some View {
        Text("·")
            .font(.system(.caption, design: .monospaced))
            .foregroundStyle(.white.opacity(0.45))
    }
}
