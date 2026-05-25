import SwiftUI

/// The primary creative control: a three-segment glass selector for the
/// per-frame palette-extraction algorithm. Each segment is one
/// `Composition.ExtractorChoice` — the three processing-model families that
/// decide which 256 colours each of the 64 frames gets:
///
///   * K-means — iterative Lloyd refinement (GPU, fast)
///   * Wu      — recursive variance-minimizing bipartition (rich statistics)
///   * Octree  — hierarchical count-based merging (predictable, flat content)
///
/// Every choice produces a complete per-frame 64×64×64 voxel volume (strict
/// per-frame surjectivity, no empty slots). This control replaced the old
/// palette-MODE selector (Per-frame / Shared / Global) when the cross-frame
/// Sinkhorn merge was removed — there is now one mode (per-frame) and the
/// user's meaningful choice is *which algorithm* fills it.
struct AlgorithmSelector: View {
    @Binding var selection: Composition.ExtractorChoice

    /// One-word family descriptor shown under each algorithm name.
    private func caption(_ choice: Composition.ExtractorChoice) -> String {
        switch choice {
        case .kMeans: return "iterative"
        case .wu:     return "variance"
        case .octree: return "hierarchical"
        }
    }

    var body: some View {
        HStack(spacing: 4) {
            ForEach(Composition.ExtractorChoice.allCases, id: \.self) { choice in
                segment(
                    title: choice.label,
                    caption: caption(choice),
                    isSelected: selection == choice,
                    action: { selection = choice }
                )
                .accessibilityLabel("\(choice.label) palette algorithm, \(caption(choice))")
                .accessibilityAddTraits(selection == choice ? .isSelected : [])
            }
        }
        .padding(4)
        // The selector is one glass surface; the per-segment highlight
        // (a solid white-opacity fill) sits *on* it as content, which is
        // fine — only sibling glass shapes must share a container.
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 14))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Palette extraction algorithm selector")
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
