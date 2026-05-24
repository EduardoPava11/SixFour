import SwiftUI

/// Three-segment palette-mode selector — one button per honest endpoint of
/// the Sinkhorn spectrum. Each segment is backed by executable, tested code
/// (per the project no-stubs rule):
///
///   * Per-frame — θ = 0     (MATH.md Theorem 1)
///   * Shared    — θ ≈ 0.05  (MATH.md §3.bis Definition 9.bis)
///   * Global    — θ → ∞     (MATH.md Theorem 2, log-domain Sinkhorn)
struct ModeSelector: View {
    @Binding var selection: PaletteGenerator.Mode

    var body: some View {
        HStack(spacing: 4) {
            segment(
                title: "Per-frame",
                caption: "θ = 0",
                isSelected: selection == .perFrame,
                action: { selection = .perFrame }
            )
            .accessibilityLabel("Per-frame palette mode, theta zero, full per-frame fidelity")
            .accessibilityAddTraits(selection == .perFrame ? .isSelected : [])

            segment(
                title: "Shared",
                caption: "θ ≈ 0.05",
                isSelected: selection == .shared,
                action: { selection = .shared }
            )
            .accessibilityLabel("Shared palette mode, theta approximately zero point zero five")
            .accessibilityAddTraits(selection == .shared ? .isSelected : [])

            segment(
                title: "Global",
                caption: "θ → ∞",
                isSelected: selection == .global,
                action: { selection = .global }
            )
            .accessibilityLabel("Global palette mode, theta infinity, log-domain Sinkhorn rank-one limit")
            .accessibilityAddTraits(selection == .global ? .isSelected : [])
        }
        .padding(4)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Palette mode selector")
    }

    @ViewBuilder
    private func segment(
        title: String,
        caption: String,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 1) {
                Text(title)
                    .font(.system(.footnote, weight: .semibold))
                Text(caption)
                    .font(.system(.caption2, design: .monospaced))
                    .opacity(0.7)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(isSelected ? Color.white.opacity(0.18) : .clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(isSelected ? Color.white.opacity(0.35) : .clear, lineWidth: 1)
            )
            .foregroundStyle(isSelected ? .white : .white.opacity(0.85))
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
    }
}
