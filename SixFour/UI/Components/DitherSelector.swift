import SwiftUI

/// Two-segment glass selector for the dithering method — the second creative
/// option alongside `AlgorithmSelector`. Both methods still produce a complete
/// 64×64×64 voxel volume (the per-frame surjectivity rescue runs regardless),
/// so switching is a pure look choice:
///
///   * Diffusion  — Floyd–Steinberg error diffusion (default; smooth gradients).
///   * Blue noise — parallel ordered dithering against the STBN3D mask
///     (crisper, no "worm" artifacts; the GPU-eligible path).
struct DitherSelector: View {
    @Binding var selection: DitherMethod

    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 4) {
                ForEach(DitherMethod.allCases, id: \.self) { method in
                    segment(
                        title: method.label,
                        caption: method.tagline,
                        isSelected: selection == method,
                        action: { selection = method }
                    )
                    .accessibilityLabel("\(method.label) dither, \(method.tagline). \(method.blurb)")
                    .accessibilityAddTraits(selection == method ? .isSelected : [])
                }
            }
            .padding(4)
            .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 14))
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Dither method selector")

            // Communicate the tradeoff, not just the choice: a one-line
            // explainer that updates with the selected method.
            Text(selection.blurb)
                .font(.system(.caption2, design: .rounded))
                .foregroundStyle(.white.opacity(0.7))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .transition(.opacity)
                .id(selection)
                .accessibilityHidden(true)   // already voiced via the segment label
        }
        .animation(.snappy(duration: 0.2), value: selection)
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
