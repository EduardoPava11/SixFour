import SwiftUI

/// The nudge PAINT MODEL + channel metadata (Tier-2, zero-dependency). This file owns the
/// paint data structure the live decide surface paints into; the standalone `NudgePaintView`
/// demo surface was removed 2026-07-05 (superseded by `DecidePaintWidget` in `DecideSurface`,
/// the only wired paint UI) — the model and channel enum stay because that widget consumes them.
///
/// `NudgePaintModel` is the 16×16×16 control grid × 9 channel budgets
/// (`SixFour.Spec.CellNudge.CellBudget`) + the φ6 gauge (`miGauge`); its output is a
/// `SixFourModelInput` — the wireable model boundary. Neutral paint (all-zero) is the
/// deterministic floor (`lawNeutralNudgeIsAllFloor`); each painted 16³ cell governs its
/// `cellSubtreeLeaves` (= 4096) leaves (`lawCellGovernsSuperResSubtree`). Today painting is a
/// GATE (where the gene may invent) via `deviceMask`, not a colour target — see the CubeBrush
/// / MixSKI direction (`sixfour-color-substrate-direction`) for the target-paint upgrade.
///
/// The 9 channels are the `SixFour.Spec.ChannelProduct` colour×space pairs, in the spec's
/// `pairings` order (Chroma {A,B,L} × Axis {X,Y,T}):
///   0:a·x 1:a·y 2:a·t  3:b·x 4:b·y 5:b·t  6:L·x 7:L·y 8:L·t
/// The φ6 diagonal (the `DualCube` pairs A:X, B:Y, L:T) is channels {0, 4, 8}.

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

    /// THE TOUCH-ORDER CARRIER (`Spec.PaintOrderPrior`, promoted by the
    /// 2026-07-11 link ledger, wave 2): Morton cell indices in FIRST-TOUCH
    /// order. The spec's keystone is a permutation-pair property — paints
    /// [a,b] and [b,a] carry IDENTICAL budgets but must yield swapped decode
    /// depths — so this order is information the magnitude field structurally
    /// cannot carry; until now the surface discarded it, making "commit
    /// compute where the user looked first" unexpressible. Recorded here at
    /// the capture surface; the halt-prior consumption (the KL target λ_p)
    /// is the trainer-side follow-on. A cell ranks once, at its first
    /// non-zero paint; erasing later does not un-touch it.
    @Published private(set) var touchOrder: [Int] = []
    private var touched = Set<Int>()

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
    /// A first NON-ZERO paint of a cell also stamps its touch rank (`touchOrder`).
    func paint(x: Int, y: Int, z: Int, channel: Int, value: Int) {
        let cell = Self.mortonIndex(x: x, y: y, z: z)
        budget[cell][channel] = max(0, value)
        if value > 0, touched.insert(cell).inserted {
            touchOrder.append(cell)
        }
        objectWillChange.send()
    }

    /// The first-touch rank of a Morton cell (0 = touched first, deepest
    /// read under the order prior), or nil if never touched.
    func touchRank(cell: Int) -> Int? { touchOrder.firstIndex(of: cell) }

    /// Reset to the neutral floor (all channels of every cell to 0, no touches).
    func reset() {
        budget = SixFourModelIO.neutralNudge()
        touchOrder = []
        touched = []
        objectWillChange.send()
    }

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
