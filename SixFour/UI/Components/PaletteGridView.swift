import SwiftUI
import simd

/// The **coordinate** palette view — "the flat 16×16 grid where the user chooses
/// what x and y MEAN." Each of the 256 colours is placed by `GridLayout` (Swift
/// port of `SixFour.Spec.GridAxis`, golden-verified) onto the two axes the user
/// assigns (e.g. x = OKLab a, y = lightness). This answers *which colour shows up
/// where* in colour space — distinct from `PaletteTreeView`, which shows median-cut
/// *nesting*.
///
/// Rank/sort placement fills every cell exactly once (no holes, no collisions), so
/// the whole palette is always visible. Animates in sync with the GIF at
/// `frameRate` (frozen on frame 0 under reduce-motion), mirroring `PaletteTreeView`.
/// Content layer only — no glass (glass is chrome; see `GridAxisSelector`).
struct PaletteGridView: View {
    let palettes: [[SIMD3<UInt8>]]
    let xAxis: GridAxis
    let yAxis: GridAxis
    let frameRate: Int
    /// Shared brushed slot (IndexedColor.index), set by the cloud / address picker.
    /// When non-nil this cell stays full and the rest recede via an opaque darker
    /// index step — so one colour lights the same across every palette view.
    let brushedIndex: Int?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(palettes: [[SIMD3<UInt8>]], xAxis: GridAxis, yAxis: GridAxis,
         frameRate: Int = 20, brushedIndex: Int? = nil) {
        self.palettes = palettes
        self.xAxis = xAxis
        self.yAxis = yAxis
        self.frameRate = frameRate
        self.brushedIndex = brushedIndex
    }

    /// Opaque darker index step for de-emphasised cells — never alpha (GRID Law #2).
    private static func darkenStep(_ c: SIMD3<UInt8>) -> SIMD3<UInt8> {
        SIMD3<UInt8>(UInt8(Int(c.x) * 35 / 100),
                     UInt8(Int(c.y) * 35 / 100),
                     UInt8(Int(c.z) * 35 / 100))
    }

    var body: some View {
        Group {
            if palettes.count > 1 && !reduceMotion {
                TimelineView(.animation(minimumInterval: 1.0 / Double(frameRate))) { ctx in
                    gridView(forFrame: frameIndex(at: ctx.date.timeIntervalSinceReferenceDate, rate: frameRate, count: palettes.count))
                }
            } else {
                gridView(forFrame: 0)
            }
        }
        .pixelFrame()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Palette grid, 256 colours, x axis \(xAxis.label), y axis \(yAxis.label).")
    }

    /// Place the frame's 256 colours via `GridLayout` (spec-verified) and render
    /// them with the shared `PixelGrid` primitive — which owns the integer cell
    /// math, the single `Color(srgb8:)` fill, and the Y-up `.bottomLeft` flip
    /// (row 0 = smallest Y sits at the bottom, e.g. lighter colours rise when y = L).
    private func gridView(forFrame index: Int) -> some View {
        let palette = palettes.isEmpty ? [] : palettes[min(index, palettes.count - 1)]
        let ics: [IndexedColor] = palette.enumerated().map { i, c in
            IndexedColor(index: i, oklab: ColorScience.srgb8ToOKLab(c.x, c.y, c.z).simd, srgb: c)
        }
        let layout = GridLayout.layout(x: xAxis, y: yAxis, colors: ics)
        let brushed = brushedIndex
        return PixelGrid(cells: layout.count, origin: .bottomLeft) { r, c in
            guard layout.indices.contains(r), layout[r].indices.contains(c) else { return nil }
            let slot = layout[r][c]
            guard palette.indices.contains(slot) else { return nil }
            let color = palette[slot]
            // Shared brush: selected slot full; others recede (opaque step).
            if let b = brushed, b != slot { return Self.darkenStep(color) }
            return color
        }
    }
}

/// Which dimensional view the palette tool shows.
enum PaletteRepresentation: String, CaseIterable, Codable, Sendable {
    case structure   // the median-cut SplitTree treemap / global editor
    case grid        // the user-assignable 16×16 coordinate grid
    case cloud       // P4: the OKLab Temporal Cloud (3 OKLab axes + scrubbable time)
    case voxel3D     // the 64³ (x,y,t) cube; REST POSE == the 2D GIF hero, orbit reveals time

    var label: String {
        switch self {
        case .structure: return "structure"
        case .grid: return "grid"
        case .cloud: return "cloud"
        case .voxel3D: return "cube"
        }
    }
}

/// Glass chrome twin of `ScopeSelector` for the dimensional representation.
/// `cases` lets the caller hide a mode that has no data (e.g. `.voxel3D` on a
/// legacy output with no per-pixel index map).
struct RepresentationSelector: View {
    @Binding var selection: PaletteRepresentation
    var cases: [PaletteRepresentation] = PaletteRepresentation.allCases

    var body: some View {
        GlassEffectContainer(spacing: SFTheme.glassClusterSpacing) {
            HStack(spacing: SFTheme.glassClusterSpacing) {
                ForEach(cases, id: \.self) { rep in
                    let isSelected = selection == rep
                    Button { withAnimation(.snappy) { selection = rep } } label: {
                        Text(rep.label)
                            .font(SFTheme.footnoteSelector)
                            .foregroundStyle(isSelected ? Color.white : SFTheme.dimText)
                            .padding(.horizontal, SFTheme.pillHorizontalPad)
                            .padding(.vertical, SFTheme.pillVerticalPad)
                    }
                    .buttonStyle(.plain)
                    .glassEffect(isSelected ? .regular.tint(.white.opacity(0.18)).interactive() : .regular.interactive(), in: RoundedRectangle(cornerRadius: SFTheme.controlCorner))
                    .accessibilityLabel(Text(rep.label))
                    .accessibilityAddTraits(isSelected ? [.isSelected] : [])
                }
            }
        }
    }
}

/// Glass chrome for assigning the grid's two axes. Two `Menu` capsules ("X:" / "Y:").
/// If the user picks the axis already on the other axis, the two **swap** (so the
/// grid never collapses to one dimension).
struct GridAxisSelector: View {
    @Binding var xAxis: GridAxis
    @Binding var yAxis: GridAxis

    var body: some View {
        GlassEffectContainer(spacing: SFTheme.glassClusterSpacing) {
            HStack(spacing: SFTheme.glassClusterSpacing) {
                axisMenu(prefix: "X", current: xAxis) { picked in assign(picked, toX: true) }
                axisMenu(prefix: "Y", current: yAxis) { picked in assign(picked, toX: false) }
            }
        }
    }

    private func axisMenu(prefix: String, current: GridAxis, onPick: @escaping (GridAxis) -> Void) -> some View {
        Menu {
            ForEach(GridAxis.allCases, id: \.self) { axis in
                Button { withAnimation(.snappy) { onPick(axis) } } label: {
                    if axis == current { Label(axis.label, systemImage: "checkmark") } else { Text(axis.label) }
                }
            }
        } label: {
            Text("\(prefix): \(current.label)")
                .font(SFTheme.footnoteSelector)
                .foregroundStyle(.white)
                .lineLimit(1)
                .padding(.horizontal, SFTheme.pillHorizontalPad)
                .padding(.vertical, SFTheme.pillVerticalPad)
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.interactive(), in: RoundedRectangle(cornerRadius: SFTheme.controlCorner))
        .accessibilityLabel(Text("\(prefix) axis, \(current.label)"))
    }

    private func assign(_ picked: GridAxis, toX: Bool) {
        if toX {
            if picked == yAxis { yAxis = xAxis }   // swap to keep axes distinct
            xAxis = picked
        } else {
            if picked == xAxis { xAxis = yAxis }
            yAxis = picked
        }
    }
}
