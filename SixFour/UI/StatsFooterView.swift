import SwiftUI

/// Bottom pill that summarises one rendered GIF: mode · file size ·
/// render time · witness status. Surfaces the math state of the capture
/// without requiring a separate Inspector — every field traces back to a
/// named object in `spec/MATH.md`.
struct StatsFooterView: View {
    let output: CaptureOutput

    var body: some View {
        HStack(spacing: 8) {
            label(extractorText, mono: false)
            dot
            label(modeText, mono: false)
            dot
            label(mseText, mono: true)
            dot
            label(sizeText, mono: true)
            dot
            label(timeText, mono: true)
            dot
            label(witnessText, mono: true)
                .foregroundStyle(witnessTint)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(.ultraThinMaterial, in: Capsule())
        .accessibilityElement(children: .combine)
        .accessibilityLabel(voiceOverDescription)
    }

    /// Extractor family label (K-means / Wu / Octree). First field
    /// in the footer so the user sees immediately which algorithm
    /// produced the visible GIF.
    private var extractorText: String { output.extractorChoice.label }

    /// Mean extraction MSE in OKLab units². Lower = tighter
    /// quantization. Surfaced so users can A/B compare extractors
    /// on the same scene without external tooling.
    private var mseText: String {
        // OKLab values are small (mostly ≤ 1.0); MSE is usually
        // 0.0001..0.01. Use 5 significant digits in scientific
        // notation so the comparison is readable across scales.
        String(format: "MSE %.4f", output.meanExtractMSE)
    }

    // MARK: - Field projections

    private var modeText: String {
        switch output.mode {
        case .perFrame: return "Per-frame"
        case .shared:   return "Shared"
        case .global:   return "Global"
        }
    }

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
        // Non-surjective outputs no longer reach the renderer — Stage B
        // throws and `CaptureViewModel` surfaces the error through
        // `FailureView` instead. Every output that reaches us here has
        // a clean Surjective256 witness.
        "✓"
    }

    private var witnessTint: Color { .green }

    private var voiceOverDescription: String {
        let stage = output.stageBMillis.map { ", Stage B took \($0) milliseconds" } ?? ""
        let θNote: String
        if let θ = output.achievedTheta, let n = output.attempts {
            θNote = ", θ=\(θ) after \(n) attempt\(n == 1 ? "" : "s")"
        } else {
            θNote = ""
        }
        return "\(modeText) mode, \(sizeText), rendered in \(timeText)\(stage)\(θNote)."
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
