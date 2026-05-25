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

    private func caption(_ m: DitherMethod) -> String {
        switch m {
        case .errorDiffusion: return "sequential"
        case .blueNoise:      return "parallel"
        }
    }

    var body: some View {
        HStack(spacing: 4) {
            ForEach(DitherMethod.allCases, id: \.self) { method in
                segment(
                    title: method.label,
                    caption: caption(method),
                    isSelected: selection == method,
                    action: { selection = method }
                )
                .accessibilityLabel("\(method.label) dither, \(caption(method))")
                .accessibilityAddTraits(selection == method ? .isSelected : [])
            }
        }
        .padding(4)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 14))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Dither method selector")
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
