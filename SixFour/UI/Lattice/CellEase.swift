import Foundation

/// Shared per-tick easing for cell-grid fluidity — UI presentation only (off the verified GIF
/// path). EVERY animation is driven by the ONE 20 fps κ tick: a progress `(tick − startTick) /
/// durationTicks`, shaped by smoothstep, so each tick is a small, coherent step and nothing cuts
/// hard. No new clock, no rate change. (docs/SIXFOUR-CELL-FLUIDITY-WORKFLOW.md §2.)
enum CellEase {
    /// Linear progress 0…1 from `startTick`, over `ticks` 20 fps ticks (clamped).
    static func linear(_ tick: Int, since startTick: Int, ticks: Int) -> Double {
        guard ticks > 0 else { return 1 }
        return min(1, max(0, Double(tick - startTick) / Double(ticks)))
    }

    /// Smoothstep-eased progress 0…1 (an S-curve: flat at both ends ⇒ no jarring edge on a
    /// transition's start or finish). `smoothstep(p) = p²(3 − 2p)`.
    static func progress(_ tick: Int, since startTick: Int, ticks: Int) -> Double {
        let p = linear(tick, since: startTick, ticks: ticks)
        return p * p * (3 - 2 * p)
    }
}
