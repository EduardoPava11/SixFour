import SwiftUI
import simd

/// The 4⁴ opponent-quadrant DRILL — the honest 4⁴ control (replaces the generic
/// treemap when `branching == .b4`). It navigates the Quad4 genome of the global
/// palette: at each level the node's four children `parent ± δ₁ ± δ₂` (the Hering
/// opponent quadrants, fixed `(++),(+−),(−+),(−−)` order) are shown as a 2×2 grid;
/// tap a quadrant to descend; the breadcrumb shows the chosen quadrant signs; at
/// depth 4 the selected leaf becomes the shared `brushedIndex` (so the cloud / cube
/// light up). Pure navigation in `Quad4Nav` (unit-tested); this is presentation.
struct Quad4DrillView: View {
    /// The 256-colour global palette (sRGB8) the 4⁴ genome is analysed from.
    let palette: [SIMD3<UInt8>]
    @Binding var brushedIndex: Int?

    @State private var path: [Int] = []
    @State private var tree: Quad4.Node? = nil

    private static let signs = ["+ +", "+ −", "− +", "− −"]

    var body: some View {
        VStack(spacing: 10) {
            breadcrumb
            grid
            footer
        }
        .task { buildTree() }
    }

    private func buildTree() {
        guard tree == nil, palette.count == 256 else { return }
        let oklab = palette.map { c -> SIMD3<Double> in
            let l = ColorScience.srgb8ToOKLab(c.x, c.y, c.z).simd
            return SIMD3<Double>(Double(l.x), Double(l.y), Double(l.z))
        }
        tree = Quad4.analyze(oklab)
    }

    // MARK: the 2×2 opponent-quadrant grid

    private var grid: some View {
        GeometryReader { geo in
            let edge = SFTheme.canvasEdge(forAvailable: min(geo.size.width, geo.size.height), cells: 2)
            let cell = edge / 2
            ZStack {
                if let tree {
                    let kids = Quad4Nav.nodeAndChildren(tree, path: path).children
                    let four = kids.count == 4 ? kids : Array(repeating: kids.first ?? .zero, count: 4)
                    VStack(spacing: 0) {
                        ForEach(0..<2, id: \.self) { row in
                            HStack(spacing: 0) {
                                ForEach(0..<2, id: \.self) { col in
                                    quadCell(four[row * 2 + col], q: row * 2 + col, cell: cell)
                                }
                            }
                        }
                    }
                    .frame(width: edge, height: edge)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .pixelFrame()
    }

    private func quadCell(_ oklab: SIMD3<Double>, q: Int, cell: CGFloat) -> some View {
        let rgb = ColorScience.okLabToSRGB8(OKLab(Float(oklab.x), Float(oklab.y), Float(oklab.z)))
        // At depth-1 (about to pick a leaf), a quadrant maps to a concrete leaf index.
        let leafIdx: Int? = path.count == Quad4Nav.depth - 1 ? Quad4Nav.leafIndex(path + [q]) : nil
        let isBrushed = leafIdx != nil && leafIdx == brushedIndex
        // GRID Law #2: a data cell is flat — NO anti-aliased stroke, NO opacity. The
        // separator/selection is an OPAQUE inset border (the treemap's filled-gap idiom):
        // a solid border ground behind the data colour, which is inset to reveal it. The
        // brushed cell gets a wider white border; the rest a thin black one.
        let border: SIMD3<UInt8> = isBrushed ? SIMD3(255, 255, 255) : SIMD3(0, 0, 0)
        let bw: CGFloat = isBrushed ? 2 : 1
        return ZStack(alignment: .topLeading) {
            Color(srgb8: border)                 // opaque border ground (no AA stroke)
            Color(srgb8: rgb).padding(bw)        // the data colour, inset to expose the border
            CellText(Self.signs[q], rows: 6, ink: Color(srgb8: SIMD3(235, 235, 235)))   // pixelated sign
                .padding(3)
        }
        .frame(width: cell, height: cell)
        .contentShape(Rectangle())
        .onTapGesture { descend(q) }
    }

    private func descend(_ q: Int) {
        let next = path + [q]
        if next.count >= Quad4Nav.depth {
            let leaf = Quad4Nav.leafIndex(next)
            brushedIndex = (brushedIndex == leaf) ? nil : leaf   // pick the leaf (toggle)
        } else {
            path = next
        }
    }

    // MARK: chrome

    private var breadcrumb: some View {
        let dim = SIMD3<UInt8>(140, 140, 140)
        return HStack(spacing: GlobalLattice.pt(2)) {
            CellText("4⁴", rows: 7, ink: Color(srgb8: dim))
            if path.isEmpty {
                CellText("root — tap an opponent quadrant", rows: 7, ink: Color(srgb8: dim))
            } else {
                ForEach(Array(path.enumerated()), id: \.offset) { _, q in
                    CellText(Self.signs[q], rows: 7, ink: .white)
                }
            }
            Spacer()
        }
    }

    private var footer: some View {
        HStack {
            if !path.isEmpty {
                Button { path.removeLast() } label: {
                    HStack(spacing: GlobalLattice.pt(1)) {
                        CellSymbol(systemName: "chevron.up", box: 8, ink: .white)
                        CellText("up", rows: 7, ink: .white)
                    }
                    .padding(.horizontal, GlobalLattice.pt(4))
                    .frame(minHeight: 44)
                    .background(Color(srgb8: SFTheme.ledGhost))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Up one level")
            }
            Spacer()
            // Colours covered by the current node = 256 / 4^depth.
            CellText("\(256 / (1 << (2 * path.count))) colours", rows: 7, ink: Color(srgb8: SIMD3(140, 140, 140)))
        }
    }
}
