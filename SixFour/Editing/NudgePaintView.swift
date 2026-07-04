import SwiftUI

/// The nudge PAINT surface (Tier-2, zero-dependency SwiftUI) — the hand-written paint tool
/// `NEXT-STEPS.md` Step 1 calls for. The user paints into the 16×16×16 control grid × 9
/// channel budgets (`SixFour.Spec.CellNudge.CellBudget`), toggles the φ6 gauge
/// (`miGauge`), and the result is a `SixFourModelInput` — the wireable model boundary.
///
/// Neutral paint (all-zero) is the deterministic floor (`lawNeutralNudgeIsAllFloor`); each
/// painted 16³ cell governs its `cellSubtreeLeaves` (= 4096) leaves of the 256³ output
/// (`lawCellGovernsSuperResSubtree`). The 9 channels are the `SixFour.Spec.ChannelProduct`
/// colour×space pairs, in the spec's `pairings` order (Chroma {A,B,L} × Axis {X,Y,T}):
///   0:a·x 1:a·y 2:a·t  3:b·x 4:b·y 5:b·t  6:L·x 7:L·y 8:L·t
/// The φ6 diagonal (the `DualCube` pairs A:X, B:Y, L:T) is channels {0, 4, 8}.
///
/// The live INVENTED preview (palette[index] via `ModelRender`) wires in once the Swift
/// `Upscale256` floor builder and the trained weights land; until then the surface renders
/// the NUDGE FIELD itself (where, and how hard, you are painting) over a neutral floor — an
/// honest paint UX that does not fake an invented image.

// MARK: - Channel metadata (the 9 ChannelProduct colour×space pairs, in `pairings` order)

enum NudgeChannel {
    /// Labels in the spec's `pairings` index order (Chroma {A,B,L} × Axis {X,Y,T}).
    static let labels: [String] = ["a·x", "a·y", "a·t", "b·x", "b·y", "b·t", "L·x", "L·y", "L·t"]
    /// The three φ6-fixed diagonal pairs (A:X, B:Y, L:T) = `SixFour.Spec.DualCube`.
    static let phi6Diagonal: Set<Int> = [0, 4, 8]
    /// A stable hue per channel for the grid swatches (colour axis a/b/L → hue family).
    static func tint(_ ch: Int) -> Color {
        switch ch / 3 {            // 0:a  1:b  2:L
        case 0:  return .pink
        case 1:  return .teal
        default: return .yellow
        }
    }
}

// MARK: - Paint model (the CellBudget + gauge state)

/// Observable nudge state: the 16³×9 `CellBudget` and the φ6 gauge. Mirrors the spec's
/// `paintCellPair` (a per-(cell, channel) budget, clamped ≥ 0) and `neutralNudge`.
final class NudgePaintModel: ObservableObject {
    /// Outer = cells (Morton-ordered 16³), inner = `paintChannelsPerCell` budgets. Neutral = floor.
    @Published var budget: [[Int]] = SixFourModelIO.neutralNudge()
    /// The φ6 gauge (`miGauge`): colour-by-space vs the dual pairing.
    @Published var gauge: Bool = false

    static let side = SixFourModelIO.controlGridSide               // 16
    static let channels = SixFourModelIO.paintChannelsPerCell      // 9

    /// Morton (Z-order) index of grid cell (x, y, z) — the spec's flattened cell order. 4 bits/axis.
    static func mortonIndex(x: Int, y: Int, z: Int) -> Int {
        var idx = 0
        for b in 0 ..< 4 {
            idx |= ((x >> b) & 1) << (3 * b)
            idx |= ((y >> b) & 1) << (3 * b + 1)
            idx |= ((z >> b) & 1) << (3 * b + 2)
        }
        return idx
    }

    /// The current budget of cell (x, y, z) on `channel`.
    func value(x: Int, y: Int, z: Int, channel: Int) -> Int {
        budget[Self.mortonIndex(x: x, y: y, z: z)][channel]
    }

    /// Paint a budget into (cell, channel) — the spec's `paintCellPair` (clamped ≥ 0).
    func paint(x: Int, y: Int, z: Int, channel: Int, value: Int) {
        let cell = Self.mortonIndex(x: x, y: y, z: z)
        budget[cell][channel] = max(0, value)
        objectWillChange.send()
    }

    /// Reset to the neutral floor (all channels of every cell to 0).
    func reset() { budget = SixFourModelIO.neutralNudge(); objectWillChange.send() }

    /// Count of cells with any non-zero budget (the painted footprint).
    var paintedCellCount: Int { budget.reduce(0) { $0 + ($1.contains { $0 != 0 } ? 1 : 0) } }

    /// `Spec.ModelForward.paintMask` in Swift, re-ordered for the engine: the 16³ paint
    /// gate in DEVICE (t,r,c) order over this model's MORTON-ordered `CellBudget`
    /// (this file owns the Morton order, so the conversion lives here). A cell is live
    /// iff any of its 9 channel budgets is nonzero — the same `sum bs != 0` gate as the
    /// spec's `cellDetail`. Returns nil when NOTHING is painted: callers treat nil as
    /// the whole-volume shortcut (gene invents everywhere, the pre-W1 arm).
    static func deviceMask(budget: [[Int]]) -> [Bool]? {
        let s = side
        var any = false
        var mask = [Bool](repeating: false, count: s * s * s)
        for z in 0 ..< s {
            for y in 0 ..< s {
                for x in 0 ..< s {
                    let cell = mortonIndex(x: x, y: y, z: z)
                    let painted = cell < budget.count && budget[cell].contains { $0 != 0 }
                    if painted {
                        any = true
                        mask[(z * s + y) * s + x] = true   // device order: t=z, row=y, col=x
                    }
                }
            }
        }
        return any ? mask : nil
    }

    /// The live paint's device-order mask (nil = unpainted = whole-volume shortcut).
    func deviceMask() -> [Bool]? { Self.deviceMask(budget: budget) }

    /// The wireable model boundary for inference (zero paint ⇒ the byte-exact floor).
    func modelInput(captureHandle: Int) -> SixFourModelInput {
        SixFourModelInput(captureHandle: captureHandle, nudge: budget, gauge: gauge)
    }
}

// MARK: - One painted cell (extracted so the grid body type-checks fast)

/// A single control-grid cell swatch: fill alpha tracks the budget on the selected channel; a
/// white border marks a φ6-diagonal channel when the gauge is on.
private struct NudgeCellView: View {
    let value: Int
    let tint: Color
    let diagonalHighlight: Bool
    let size: CGFloat

    private var fillOpacity: Double {
        value > 0 ? min(1.0, 0.2 + Double(value) / 128.0) : 0.06
    }

    var body: some View {
        Rectangle()
            .fill(tint.opacity(fillOpacity))
            .overlay(Rectangle().stroke(Color.gray.opacity(0.18), lineWidth: 0.5))
            .overlay(Rectangle().stroke(Color.white.opacity(diagonalHighlight ? 0.5 : 0.0),
                                        lineWidth: diagonalHighlight ? 1 : 0))
            .frame(width: size, height: size)
    }
}

// MARK: - The paint view

struct NudgePaintView: View {
    @StateObject private var model = NudgePaintModel()
    @State private var layer: Int = 0          // the temporal z-slice (0..15) of the 16³ grid
    @State private var channel: Int = 8        // default L·t (the φ6 diagonal value-over-time pair)
    @State private var brush: Double = 32       // the budget magnitude a stroke paints

    private let side = NudgePaintModel.side

    var body: some View {
        VStack(spacing: 14) {
            header
            grid
            controls
        }
        .padding()
    }

    private var header: some View {
        VStack(spacing: 2) {
            Text("Nudge").font(.headline)
            Text("16³ × 9 paint · cell → 4096-leaf 256³ subtree")
                .font(.caption2).foregroundStyle(.secondary)
            Text("\(model.paintedCellCount) cells painted · \(model.gauge ? "φ6 dual" : "colour×space") gauge")
                .font(.caption2).foregroundStyle(.secondary)
        }
    }

    /// The 16×16 cells of the selected temporal layer. Tap/drag paints the brush into the
    /// selected channel; the swatch alpha tracks the cell's budget on that channel. The per-cell
    /// view is extracted (`NudgeCellView`) so each sub-expression type-checks independently.
    private var grid: some View {
        GeometryReader { geo in
            let cellSize = geo.size.width / CGFloat(side)
            ZStack(alignment: .topLeading) {
                ForEach(0 ..< side, id: \.self) { y in
                    ForEach(0 ..< side, id: \.self) { x in
                        NudgeCellView(
                            value: model.value(x: x, y: y, z: layer, channel: channel),
                            tint: NudgeChannel.tint(channel),
                            diagonalHighlight: model.gauge && NudgeChannel.phi6Diagonal.contains(channel),
                            size: cellSize
                        )
                        .offset(x: CGFloat(x) * cellSize, y: CGFloat(y) * cellSize)
                    }
                }
            }
            .contentShape(Rectangle())
            .gesture(paintGesture(cellSize: cellSize))
        }
        .aspectRatio(1, contentMode: .fit)
    }

    private func paintGesture(cellSize: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { g in
                let x = Int(g.location.x / cellSize)
                let y = Int(g.location.y / cellSize)
                guard x >= 0, x < side, y >= 0, y < side else { return }
                model.paint(x: x, y: y, z: layer, channel: channel, value: Int(brush))
            }
    }

    private var controls: some View {
        VStack(spacing: 10) {
            // Channel picker (the 9 colour×space pairs).
            Picker("Channel", selection: $channel) {
                ForEach(0 ..< NudgeChannel.labels.count, id: \.self) { i in
                    Text(NudgeChannel.labels[i]).tag(i)
                }
            }
            .pickerStyle(.segmented)

            HStack {
                Text("Layer t=\(layer)").font(.caption).frame(width: 70, alignment: .leading)
                Slider(value: Binding(get: { Double(layer) },
                                      set: { layer = Int($0.rounded()) }),
                       in: 0 ... Double(side - 1), step: 1)
            }
            HStack {
                Text("Brush \(Int(brush))").font(.caption).frame(width: 70, alignment: .leading)
                Slider(value: $brush, in: 0 ... 127, step: 1)
            }
            HStack {
                Toggle("φ6 gauge", isOn: $model.gauge).font(.caption)
                Spacer()
                Button("Reset to floor") { model.reset() }
                    .font(.caption).buttonStyle(.bordered)
            }
        }
    }
}

#if DEBUG
struct NudgePaintView_Previews: PreviewProvider {
    static var previews: some View { NudgePaintView() }
}
#endif
