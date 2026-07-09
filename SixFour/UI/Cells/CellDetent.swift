import SwiftUI

/// FRAME-LOCKED CELL DETENT — the one reusable detent flush for every drag widget.
///
/// A dragged cell widget owes one `cellTick` haptic per cell boundary it crosses, but the
/// felt ticks MUST be coalesced to the 20 fps cell-field refresh: at most one Taptic per
/// frame regardless of drag speed (`Spec.CellMechanics.lawTicksFrameMonotone` — one cell =
/// one frame = one tick = one repaint). This modifier IS that contract, applied at the view
/// layer: on each `tick` (the `SurfaceClock` 20 fps heartbeat) it fires exactly ONE
/// `Haptics.play(1)` if `position` has crossed `>= every` cells since the last flushed frame,
/// then re-anchors. `position` returns `nil` when no drag is active, so the anchor resets and
/// a fresh drag starts clean (no burst on (re)open).
///
/// This replaces per-touch-event haptic firing (a fast `DragGesture.onChanged` can fire many
/// times per frame). It is the SINGLE detent mechanism used by the Review motion-threshold
/// slider AND the movable ColorWidgets, so the feel is identical and provably frame-locked
/// everywhere — `cellsCrossed`/`tickEvery` come from the generated `SixFourCellMechanics`
/// spec contract.
extension View {
    func cellDetent(tick: Int, every: Int = 1,
                    position: @escaping () -> (col: Int, row: Int)?) -> some View {
        modifier(CellDetentModifier(tick: tick, every: every, position: position))
    }
}

private struct CellDetentModifier: ViewModifier {
    /// The 20 fps heartbeat counter (`SurfaceClock.tick`) — the flush cadence.
    let tick: Int
    /// Fire a tick every `every` cells crossed (1 = every cell; the movable widgets use the
    /// coarser `SixFourCellMechanics.tickEvery`).
    let every: Int
    /// The detent's current cell, or `nil` when no drag is active.
    let position: () -> (col: Int, row: Int)?

    /// The cell at the last flushed frame. `nil` ⇒ no drag in progress / not yet anchored.
    @State private var anchor: (col: Int, row: Int)?

    func body(content: Content) -> some View {
        content.onChange(of: tick) { _, _ in
            guard let now = position() else { anchor = nil; return }   // drag ended → reset
            guard let a = anchor else { anchor = now; return }         // drag start → anchor, no tick
            let crossed = SixFourCellMechanics.cellsCrossed((col: a.col, row: a.row),
                                                            (col: now.col, row: now.row))
            if crossed >= max(1, every) {
                Haptics.play(1)        // cellTick — exactly one per frame (coalesced)
                anchor = now           // re-anchor: the next stride measures from here
            }
        }
    }
}
