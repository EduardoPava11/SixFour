import SwiftUI

/// THE single mounted view. `SixFourApp`'s `WindowGroup` hosts exactly this. It owns σ
/// (`Surface`) and κ (`SurfaceClock`), and its body is the phase-field projection Π of σ:
/// `PhaseField.field(for: σ.phase, σ, κ)`. A phase change re-draws cells on this same
/// surface — there is no view swap, no modal cover, no `NavigationStack`. capture →
/// render → review are phases of the one field.
///
/// Lifecycle: the clock runs while the window is active and stops when it backgrounds
/// (zero idle battery). Reduce-motion is forwarded to the clock (heartbeat pinned, link
/// still ticking). On first appearance the Swift↔Haskell phase-FSM parity is asserted
/// (debug only).
struct SurfaceView: View {
    @State private var surface = Surface()
    @State private var clock = SurfaceClock()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        PhaseField.field(for: surface.phase, surface, clock)
            .onAppear {
                Surface.assertSpecParity()
                clock.reduceMotion = reduceMotion
                // The ONE per-tick action: advance the Z₆₄ playback cursor. Future
                // per-phase logic (capture intake, stage stepping) hangs off the same tick.
                clock.onTick = { [weak surface] in surface?.advanceCursor() }
                if scenePhase == .active { clock.start() }
            }
            .onDisappear { clock.stop() }
            .onChange(of: reduceMotion) { _, newValue in clock.reduceMotion = newValue }
            .onChange(of: scenePhase) { _, newValue in
                if newValue == .active { clock.start() } else { clock.stop() }
            }
    }
}
