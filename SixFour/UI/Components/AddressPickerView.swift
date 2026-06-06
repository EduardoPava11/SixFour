import SwiftUI
import simd

/// Glass multi-component picker for operable address-based navigation of the median-cut
/// SplitTree. Displays N wheels (N = PaletteBranching.depth: 2/4/8) in a horizontal row,
/// each selecting one radix-factor digit of the binary tree address. Each wheel is LABELLED
/// with the (SplitAxis, pos) split it controls — read from the actual SplitTree collapse,
/// never hardcoded. Turning any wheel updates the brushedIndex binding with the leaf index
/// the address points to, triggering cross-view highlight (cloud, tree, grid).
///
/// The picker is GLASS CHROME (control layer); the colours it brushes are CONTENT (opaque
/// index-step highlight, never alpha — GRID Law #2). Accessibility: each wheel labelled
/// + its value spoken; one combined summary per wheel change.
@MainActor
struct AddressPickerView: View {
    /// The canonical binary SplitTree, built once per frame.
    let splitTree: SplitTree?
    let branching: PaletteBranching
    /// The leaf index the address points to, linked across all palette views by IndexedColor.index.
    @Binding var brushedIndex: Int?

    /// One digit (0..factor-1) per wheel. Default all 0s (root).
    @State private var selectedDigits: [Int] = []
    /// Precomputed axis@pos labels for each wheel, one per digit level.
    @State private var wheelLabels: [String] = []

    var body: some View {
        VStack(spacing: GlobalLattice.pt(4)) {
            if splitTree != nil, !selectedDigits.isEmpty {
                // Flat cell container — the wheels are now pixelated cell steppers.
                HStack(spacing: GlobalLattice.pt(GlobalLattice.gutterCells)) {
                    ForEach(0..<selectedDigits.count, id: \.self) { wheelIdx in
                        wheelView(index: wheelIdx)
                    }
                    Spacer()
                }
                .padding(.horizontal, GlobalLattice.pt(6))
                .padding(.vertical, GlobalLattice.pt(4))
                .background(Color(srgb8: SFTheme.ledGhost))
            }
        }
        .task(id: treeSignature) {
            rebuildWheels()
        }
        .accessibilityElement()
        .accessibilityLabel("Palette address picker")
        .accessibilityValue(spokenSummary)
    }

    /// Cheap identity so wheels rebuild on tree change.
    private var treeSignature: Int {
        guard let tree = splitTree else { return 0 }
        var h = Hasher()
        h.combine(branching.label)
        // Shallow hash: just the root axis if it exists.
        if case .branch(let axis, _, _, _) = tree {
            h.combine(axis.rawValue)
        }
        return h.finalize()
    }

    /// Initialize the picker state: N wheels per branching, default all 0.
    /// Extract axis@pos labels by walking k=collapseK binary levels at each digit position.
    private func rebuildWheels() {
        let depth = branching.depth
        selectedDigits = Array(repeating: 0, count: depth)

        guard let tree = splitTree else {
            wheelLabels = Array(repeating: "—", count: depth)
            return
        }

        var labels: [String] = []
        let collapseK = branching.collapseK

        for digit in 0..<depth {
            // Walk from the root, following the binary path implied by digits 0..digit-1,
            // then read the split at the first binary step of the collapsed level.
            let binStart = digit * collapseK
            let binaryPath = binaryPathForDigits(Array(selectedDigits[0..<digit]))
            if let (axis, pos) = axisAndPosAtBinaryLevel(tree, path: binaryPath, level: binStart) {
                let axisStr = axisLabel(axis)
                let posStr = String(format: "%.2f", pos)
                labels.append("\(axisStr)@\(posStr)")
            } else {
                labels.append("—")
            }
        }

        wheelLabels = labels
    }

    /// The label for a SplitAxis enum.
    private func axisLabel(_ axis: SplitAxis) -> String {
        switch axis {
        case .L: return "L"
        case .a: return "a"
        case .b: return "b"
        }
    }

    /// Given a sequence of digits (radix factor), expand to a binary path
    /// (sequence of 0/1 choices at each binary level).
    private func binaryPathForDigits(_ digits: [Int]) -> [Int] {
        var binary: [Int] = []
        for digit in digits {
            let collapseK = branching.collapseK
            for bit in (0..<collapseK).reversed() {
                binary.append((digit >> bit) & 1)
            }
        }
        return binary
    }

    /// Extract the (SplitAxis, pos) at the first binary split of level `binStart`
    /// along the given binary path. Returns nil if the path is exhausted or the node is a leaf.
    private func axisAndPosAtBinaryLevel(_ tree: SplitTree, path: [Int], level: Int) -> (SplitAxis, Float)? {
        var current = tree
        // Follow the binary path up to `level`.
        for i in 0..<min(level, path.count) {
            switch current {
            case .leaf:
                return nil
            case .branch(let axis, let pos, let lo, let hi):
                current = path[i] == 0 ? lo : hi
            }
        }
        // Read the axis and pos at the current node (first split of the collapsed level).
        switch current {
        case .leaf:
            return nil
        case .branch(let axis, let pos, _, _):
            return (axis, pos)
        }
    }

    /// The picker UI for one digit wheel.
    // PIXELATED wheel: a cell STEPPER (chevron-up · CellDigits value · chevron-down)
    // replacing the native AA `Picker(.wheel)`. Wrapping the digit mod `factor` keeps
    // the "wheel" feel; `accessibilityAdjustableAction` preserves the VoiceOver
    // adjustability the native wheel had (the critique's a11y must-fix).
    @ViewBuilder
    private func wheelView(index: Int) -> some View {
        let factor = branching.factor
        VStack(spacing: GlobalLattice.pt(2)) {
            if index < wheelLabels.count {
                CellText(wheelLabels[index], rows: 7, ink: Color(srgb8: SIMD3(210, 210, 210)))
            }
            stepButton(systemName: "chevron.up") {
                updateDigit(index: index, value: (selectedDigits[index] + 1) % factor)
            }
            CellDigits(value: selectedDigits[index], width: 2, lit: SIMD3(96, 165, 250))
            stepButton(systemName: "chevron.down") {
                updateDigit(index: index, value: (selectedDigits[index] - 1 + factor) % factor)
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement()
        .accessibilityLabel("Digit \(index + 1) of \(branching.depth)")
        .accessibilityValue("\(selectedDigits[index]) of 0 to \(factor - 1)")
        .accessibilityAdjustableAction { dir in
            switch dir {
            case .increment: updateDigit(index: index, value: (selectedDigits[index] + 1) % factor)
            case .decrement: updateDigit(index: index, value: (selectedDigits[index] - 1 + factor) % factor)
            default: break
            }
        }
    }

    private func stepButton(systemName: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            CellSymbol(systemName: systemName, box: 8, ink: .white)
                .frame(width: GlobalLattice.gif(12), height: GlobalLattice.gif(8))   // 48×32 at 4 pt (width clears the 44 pt floor; preserves the v2.0 footprint)
                .background(Color(srgb8: SIMD3(55, 55, 55)))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHidden(true)
    }

    /// Called when a wheel value changes: update the digit, rebuild labels, compute leaf index.
    private func updateDigit(index: Int, value: Int) {
        selectedDigits[index] = value
        // Rebuild wheel labels (future wheels' labels may change based on path).
        rebuildWheels()
        // Compute the leaf index for the new address and update the binding.
        if let tree = splitTree {
            brushedIndex = leafIndexForAddress(selectedDigits, tree: tree)
        }
    }

    /// Convert the radix-factor address (digits in selectedDigits) to a leaf index
    /// by expanding to binary, following the path, and finding the in-order position.
    private func leafIndexForAddress(_ digits: [Int], tree: SplitTree) -> Int? {
        let binaryPath = binaryPathForDigits(digits)
        var current = tree
        // Follow the binary path.
        for step in binaryPath {
            switch current {
            case .leaf:
                break
            case .branch(_, _, let lo, let hi):
                current = step == 0 ? lo : hi
            }
        }
        // Find the in-order position of the reached leaf in the original tree's leaves.
        let allLeaves = tree.leaves
        if case .leaf(let ic) = current {
            return allLeaves.firstIndex(where: { $0.index == ic.index })
        }
        return nil
    }

    /// One spoken summary (spoken on every wheel change). Gives context without focusable dots.
    private var spokenSummary: String {
        let digitsStr = selectedDigits.map(String.init).joined(separator: "")
        let leafIdx = splitTree.flatMap { leafIndexForAddress(selectedDigits, tree: $0) } ?? -1
        return "Address picker, \(branching.label), digit sequence \(digitsStr), leaf index \(leafIdx)."
    }
}

// MARK: - Preview (synthetic tree)

#if DEBUG
#Preview("Address Picker — binary 2⁸") {
    struct Host: View {
        @State var brushed: Int? = nil
        var body: some View {
            // Synthetic 256-colour tree for preview.
            let tree = makeSyntheticAddressTree()
            VStack(spacing: 16) {
                AddressPickerView(splitTree: tree, branching: .b2, brushedIndex: $brushed)
                    .padding()
                
                HStack(spacing: 8) {
                    Text("Brushed leaf:")
                        .foregroundStyle(.white.opacity(0.7))
                    Text(brushed.map(String.init) ?? "—")
                        .font(.headline)
                        .monospacedDigit()
                        .foregroundStyle(.white)
                }
                .padding(.horizontal)
                
                Spacer()
            }
            .background(Color.black)
            .preferredColorScheme(.dark)
        }
    }
    return Host()
}

#Preview("Address Picker — 4⁴") {
    struct Host: View {
        @State var brushed: Int? = nil
        var body: some View {
            let tree = makeSyntheticAddressTree()
            VStack(spacing: 16) {
                AddressPickerView(splitTree: tree, branching: .b4, brushedIndex: $brushed)
                    .padding()
                
                HStack(spacing: 8) {
                    Text("Brushed leaf:")
                        .foregroundStyle(.white.opacity(0.7))
                    Text(brushed.map(String.init) ?? "—")
                        .font(.headline)
                        .monospacedDigit()
                        .foregroundStyle(.white)
                }
                .padding(.horizontal)
                
                Spacer()
            }
            .background(Color.black)
            .preferredColorScheme(.dark)
        }
    }
    return Host()
}

#Preview("Address Picker — 16²") {
    struct Host: View {
        @State var brushed: Int? = nil
        var body: some View {
            let tree = makeSyntheticAddressTree()
            VStack(spacing: 16) {
                AddressPickerView(splitTree: tree, branching: .b16, brushedIndex: $brushed)
                    .padding()
                
                HStack(spacing: 8) {
                    Text("Brushed leaf:")
                        .foregroundStyle(.white.opacity(0.7))
                    Text(brushed.map(String.init) ?? "—")
                        .font(.headline)
                        .monospacedDigit()
                        .foregroundStyle(.white)
                }
                .padding(.horizontal)
                
                Spacer()
            }
            .background(Color.black)
            .preferredColorScheme(.dark)
        }
    }
    return Host()
}

/// Build a synthetic 256-colour tree for preview (hue-based, deterministic).
private func makeSyntheticAddressTree() -> SplitTree {
    let k = 256
    var ics: [IndexedColor] = []
    ics.reserveCapacity(k)
    for i in 0..<k {
        let hue = Float(i) / Float(k)
        let r = UInt8((0.5 + 0.5 * sin(hue * 6.28318)) * 255)
        let g = UInt8((0.5 + 0.5 * sin((hue + 0.33) * 6.28318)) * 255)
        let b = UInt8((0.5 + 0.5 * sin((hue + 0.66) * 6.28318)) * 255)
        let oklab = ColorScience.srgb8ToOKLab(r, g, b).simd
        ics.append(IndexedColor(index: i, oklab: oklab, srgb: SIMD3<UInt8>(r, g, b)))
    }
    return SplitTree.build(ics)
}
#endif
