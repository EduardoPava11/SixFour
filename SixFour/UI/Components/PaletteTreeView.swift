import SwiftUI
import simd

/// Palette **structure** visualisation — the decision tool for the `16² / 4⁴ / 2⁸`
/// choice. Renders the per-frame 256-colour palette as the median-cut `SplitTree`
/// (`SplitTree.swift`, verified against the Haskell spec), collapsed to the chosen
/// branching and drawn as a nested-rectangle treemap.
///
/// The *same* 256 leaves are laid out under each branching; what changes is the
/// **nesting**: borders are drawn thicker at shallower splits, so the user can see
/// — and choose between — a flat 16×16 grid (`16²`), nested quads (`4⁴`), or
/// recursively halved cells (`2⁸`). Each border is a split plane the quantizer drew.
///
/// Animates in sync with the GIF at `frameRate` (frozen on frame 0 under
/// reduce-motion), via the shared `frameIndex` clock. Content layer only — no
/// glass (glass is chrome; see `BranchingSelector`).
struct PaletteTreeView: View {
    let palettes: [[SIMD3<UInt8>]]
    let branching: PaletteBranching
    let frameRate: Int

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(palettes: [[SIMD3<UInt8>]], branching: PaletteBranching, frameRate: Int = SFTheme.gifFrameRate) {
        self.palettes = palettes
        self.branching = branching
        self.frameRate = frameRate
    }

    var body: some View {
        Group {
            if palettes.count > 1 && !reduceMotion {
                TimelineView(.animation(minimumInterval: 1.0 / Double(frameRate))) { ctx in
                    canvas(forFrame: frameIndex(at: ctx.date.timeIntervalSinceReferenceDate, rate: frameRate, count: palettes.count))
                }
            } else {
                canvas(forFrame: 0)
            }
        }
        .pixelFrame()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Palette structure, \(branching.label) branching, 256 colours partitioned by perceptual similarity.")
    }

    private func canvas(forFrame index: Int) -> some View {
        let palette = palettes.isEmpty ? [] : palettes[min(index, palettes.count - 1)]
        let node = Self.tree(for: palette).view(branching)
        let maxDepth = branching.depth
        return Canvas { ctx, size in
            draw(node, in: CGRect(origin: .zero, size: size), depth: 0, maxDepth: maxDepth, ctx: &ctx)
        }
    }

    /// Build the median-cut tree from a frame's palette. sRGB8 → OKLab positions
    /// the split; the leaf keeps its sRGB8 for fill. Cheap (256 points, ~8 levels).
    static func tree(for palette: [SIMD3<UInt8>]) -> SplitTree {
        let ics = palette.enumerated().map { i, c -> IndexedColor in
            IndexedColor(index: i, oklab: ColorScience.srgb8ToOKLab(c.x, c.y, c.z).simd, srgb: c)
        }
        return SplitTree.build(ics)
    }

    private func draw(_ node: NaryNode, in rect: CGRect, depth: Int, maxDepth: Int, ctx: inout GraphicsContext) {
        switch node {
        case .leaf(let ic):
            ctx.fillCell(rect, srgb8: ic.srgb)
        case .branch(let kids):
            let cells = paletteSubdivide(rect, count: kids.count)
            for (cell, kid) in zip(cells, kids) {
                draw(kid, in: cell, depth: depth + 1, maxDepth: maxDepth, ctx: &ctx)
            }
            // The split planes: thicker at shallower (earlier) splits so the nesting
            // hierarchy reads. Drawn as OPAQUE filled edge rects (no AA stroke, no
            // opacity) — the flat-cell LOOK contract.
            let lw = max(0.5, min(SFTheme.treemapPlaneMaxWidth, CGFloat(maxDepth - depth) * 0.9))
            ctx.fillBorder(rect, width: lw, color: SFTheme.treemapPlane)
        }
    }
}

/// Which palette the Review structure view shows: the 64 animated per-frame palettes
/// (the NN *input*), or the one collapsed global palette (the NN *output*, editable).
enum PaletteScope: String, CaseIterable, Codable, Sendable {
    case perFrame, global
    var label: String { self == .perFrame ? "per-frame" : "global" }
}

/// Glass chrome twin of `BranchingSelector` for the per-frame ↔ global scope.
struct ScopeSelector: View {
    @Binding var selection: PaletteScope

    var body: some View {
        GlassEffectContainer(spacing: SFTheme.glassClusterSpacing) {
            HStack(spacing: SFTheme.glassClusterSpacing) {
                ForEach(PaletteScope.allCases, id: \.self) { s in
                    let isSelected = selection == s
                    Button { withAnimation(.snappy) { selection = s } } label: {
                        Text(s.label)
                            .font(SFTheme.footnoteSelector)
                            .foregroundStyle(isSelected ? Color.white : SFTheme.dimText)
                            .padding(.horizontal, SFTheme.pillHorizontalPad)
                            .padding(.vertical, SFTheme.pillVerticalPad)
                    }
                    .buttonStyle(.plain)
                    .glassEffect(isSelected ? .regular.tint(.white.opacity(0.18)).interactive() : .regular.interactive(), in: RoundedRectangle(cornerRadius: SFTheme.controlCorner))
                    .accessibilityLabel(Text(s.label))
                    .accessibilityAddTraits(isSelected ? [.isSelected] : [])
                }
            }
        }
    }
}

/// Glass chrome for picking the palette-structure branching (`16² / 4⁴ / 2⁸`).
/// Three capsules in a single `GlassEffectContainer` (so they share one sampling
/// region and morph between selections). Chrome layer — floats over the content.
struct BranchingSelector: View {
    @Binding var selection: PaletteBranching

    var body: some View {
        GlassEffectContainer(spacing: SFTheme.glassClusterSpacing) {
            HStack(spacing: SFTheme.glassClusterSpacing) {
                ForEach(PaletteBranching.allCases, id: \.self) { b in
                    let isSelected = selection == b
                    Button {
                        withAnimation(.snappy) { selection = b }
                    } label: {
                        Text(b.label)
                            .font(SFTheme.footnoteSelector)
                            .foregroundStyle(isSelected ? Color.white : SFTheme.dimText)
                            .frame(minWidth: 40)
                            .padding(.horizontal, SFTheme.pillHorizontalPad)
                            .padding(.vertical, SFTheme.pillVerticalPad)
                    }
                    .buttonStyle(.plain)
                    .glassEffect(
                        isSelected
                            ? .regular.tint(.white.opacity(0.18)).interactive()
                            : .regular.interactive(),
                        in: RoundedRectangle(cornerRadius: SFTheme.controlCorner)
                    )
                    .accessibilityLabel(Text(b.label))
                    .accessibilityAddTraits(isSelected ? [.isSelected] : [])
                }
            }
        }
    }
}
