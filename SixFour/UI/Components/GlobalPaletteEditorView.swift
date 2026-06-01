import SwiftUI
import simd

/// Interactive editor for the GLOBAL palette — "be the look-NN by hand."
///
/// The per-frame palettes are collapsed (`GlobalPaletteCollapse.maximin`) into one global
/// palette, shown as the median-cut `SplitTree` treemap at the chosen branching. You edit
/// it by **multiresolution nudge**: pick a grain, tap a region to select that subtree, and
/// nudge it in OKLab — the whole subtree shifts. Coarse grain at the root tints everything;
/// fine grain at depth tweaks a single colour. The branching sets how many grain levels
/// exist (2⁸ = 8, 4⁴ = 4, 16² = 2), so the genome you picked *is* the editing resolution.
///
/// The edited palette is the global-palette candidate — the human occupying the
/// `PaletteCollapse` slot the trained NN will later fill (see
/// `docs/global-palette-skeleton-design.md`). v1: edits the on-screen palette; GIF re-encode
/// with the edited global table is a later phase.
struct GlobalPaletteEditorView: View {
    let palettes: [[SIMD3<UInt8>]]
    @Binding var branching: PaletteBranching

    @State private var baseline: [OKLab] = []     // maximin floor, indexed by palette slot
    @State private var current:  [OKLab] = []     // live edited palette, same indexing
    @State private var tree: SplitTree? = nil      // built once from baseline (stable layout)
    @State private var grain: Int = 0              // edit depth: 0 = whole palette … depth = one leaf
    @State private var selectedPath: [Int] = []    // base-b digits, length == grain

    private let stepL: Float = 0.05
    private let stepAB: Float = 0.04

    var body: some View {
        VStack(spacing: 10) {
            BranchingSelector(selection: $branching)

            GeometryReader { geo in
                Canvas { ctx, size in
                    guard let node = tree?.view(branching) else { return }
                    draw(node, in: CGRect(origin: .zero, size: size), depth: 0,
                         maxDepth: branching.depth, ctx: &ctx)
                    // Selection highlight — a square (not rounded) marker, matching
                    // the hard-cell LOOK; drawn over the content as a chrome affordance.
                    if grain > 0 {
                        let r = nodeRect(path: selectedPath, size: size)
                        ctx.stroke(Path(r.insetBy(dx: 1, dy: 1)), with: .color(.white), lineWidth: 2.5)
                    }
                }
                .gesture(SpatialTapGesture().onEnded { v in
                    selectedPath = path(at: v.location, size: geo.size)
                })
            }
            .pixelFrame()

            grainRow
            nudgeRow
        }
        .task { setupIfNeeded() }
        .onChange(of: branching) { _, _ in grain = min(grain, branching.depth); selectedPath = [] }
    }

    // MARK: build

    private func setupIfNeeded() {
        guard tree == nil, !palettes.isEmpty else { return }
        let global = GlobalPaletteCollapse.maximin(perFramePalettes: palettes)
        guard !global.isEmpty else { return }
        baseline = global
        current = global
        tree = SplitTree.build(global.enumerated().map { i, lab in
            IndexedColor(index: i, oklab: lab.simd, srgb: ColorScience.okLabToSRGB8(lab))
        })
    }

    // MARK: controls

    private var grainRow: some View {
        HStack {
            Stepper(value: $grain, in: 0 ... branching.depth) {
                Text("grain \(grain)").font(SFTheme.captionMono)
            }
            .onChange(of: grain) { _, _ in selectedPath = Array(selectedPath.prefix(grain)) }
            Spacer()
            let count = current.isEmpty ? 0 : current.count / Int(pow(Double(branching.factor), Double(grain)))
            Text("\(max(count, 1)) colours").font(SFTheme.captionMono).foregroundStyle(SFTheme.dimText)
        }
    }

    private var nudgeRow: some View {
        GlassToolbarCluster {
            nudge("sun.max", "Lighter") { applyDelta(stepL, 0, 0) }
            nudge("moon", "Darker")     { applyDelta(-stepL, 0, 0) }
            nudge("flame", "Warmer")    { applyDelta(0, 0, stepAB) }
            nudge("snowflake", "Cooler"){ applyDelta(0, 0, -stepAB) }
            nudge("arrow.uturn.backward", "Reset") { current = baseline }
        }
    }

    private func nudge(_ symbol: String, _ label: String, _ action: @escaping () -> Void) -> some View {
        GlassIconButton(systemImage: symbol, accessibilityLabel: label, action: action)
    }

    // MARK: editing

    private func applyDelta(_ dL: Float, _ da: Float, _ db: Float) {
        guard let node = tree?.view(branching).node(at: selectedPath) else { return }
        for leaf in node.leaves {
            let c = current[leaf.index]
            current[leaf.index] = OKLab(
                min(1, max(0, c.L + dL)),
                min(0.4, max(-0.4, c.a + da)),
                min(0.4, max(-0.4, c.b + db))
            )
        }
    }

    // MARK: drawing + hit-test

    private func draw(_ node: NaryNode, in rect: CGRect, depth: Int, maxDepth: Int, ctx: inout GraphicsContext) {
        switch node {
        case .leaf(let ic):
            let c = ColorScience.okLabToSRGB8(current.indices.contains(ic.index) ? current[ic.index] : OKLab(ic.oklab))
            ctx.fillCell(rect, srgb8: c)
        case .branch(let kids):
            let cells = paletteSubdivide(rect, count: kids.count)
            for (cell, kid) in zip(cells, kids) { draw(kid, in: cell, depth: depth + 1, maxDepth: maxDepth, ctx: &ctx) }
            let lw = max(0.5, min(SFTheme.treemapPlaneMaxWidth, CGFloat(maxDepth - depth) * 0.9))
            ctx.fillBorder(rect, width: lw, color: SFTheme.treemapPlane)
        }
    }

    private func path(at point: CGPoint, size: CGSize) -> [Int] {
        guard var n = tree?.view(branching) else { return [] }
        var rect = CGRect(origin: .zero, size: size)
        var out: [Int] = []
        for _ in 0 ..< grain {
            guard case .branch(let kids) = n else { break }
            let rects = paletteSubdivide(rect, count: kids.count)
            let idx = rects.firstIndex(where: { $0.contains(point) }) ?? 0
            out.append(idx); rect = rects[idx]; n = kids[idx]
        }
        return out
    }

    private func nodeRect(path: [Int], size: CGSize) -> CGRect {
        guard var n = tree?.view(branching) else { return .zero }
        var rect = CGRect(origin: .zero, size: size)
        for i in path {
            guard case .branch(let kids) = n, i < kids.count else { break }
            rect = paletteSubdivide(rect, count: kids.count)[i]
            n = kids[i]
        }
        return rect
    }
}

extension NaryNode {
    var children: [NaryNode] { if case .branch(let cs) = self { return cs } else { return [] } }
    func node(at path: [Int]) -> NaryNode {
        var n = self
        for i in path { let cs = n.children; guard i < cs.count else { break }; n = cs[i] }
        return n
    }
}
