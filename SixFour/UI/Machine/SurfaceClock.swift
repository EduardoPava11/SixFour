import Foundation
import QuartzCore
import Observation

/// κ — THE ONE clock. A single `CADisplayLink` pinned to `SixFourDisplay.logicRateHz`
/// (20 Hz) via `preferredFrameRateRange`, replacing every Foundation `Timer` that used
/// to tick the surface (`GridHeartbeatClock` and `PlaybackClock`'s timer). One δ per
/// 1/f s (T1/T7).
///
/// Each tick the clock:
///   1. flips the heartbeat `phase` bit (the live-canvas inversion), and
///   2. calls the registered `onTick` closure (the surface's per-tick `step`/advance).
///
/// Reduce-motion is a per-tick NO-OP: the link still fires at 20 Hz (so `onTick`
/// observers keep receiving the env), but the heartbeat bit is pinned to 0 → a static
/// (non-strobing) canvas. The clock never stops itself; the owning view drives its
/// lifecycle (`start`/`stop`).
///
/// Tier-2 pure: QuartzCore + Foundation + Observation only.
@MainActor
@Observable
final class SurfaceClock {

    /// The 20 fps heartbeat bit (0/1) — the live-canvas checker inversion. Flipped each
    /// tick unless reduce-motion pins it to 0.
    private(set) var heartbeat: Int = 0

    /// Monotonic tick counter since `start()` — a free-running phase the field renderers
    /// can read for any per-tick animation without spawning their own clock.
    private(set) var tick: Int = 0

    /// When true, the heartbeat bit is pinned to 0 (static canvas) but the link keeps
    /// firing so `onTick` still runs every 1/f s.
    var reduceMotion: Bool {
        didSet { if reduceMotion { heartbeat = 0 } }
    }

    private(set) var running: Bool = false

    /// The per-tick closure the surface registers (advance cursor, etc.). Set by the
    /// owning view before `start()`.
    @ObservationIgnored var onTick: (() -> Void)?

    @ObservationIgnored private var link: CADisplayLink?

    init(reduceMotion: Bool = false) { self.reduceMotion = reduceMotion }

    /// Start the single display link, pinned to the logic rate.
    func start() {
        guard !running else { return }
        let link = CADisplayLink(target: SurfaceClockProxy(self), selector: #selector(SurfaceClockProxy.fire))
        link.preferredFrameRateRange = .init(minimum: Float(SixFourDisplay.logicRateHz),
                                             maximum: Float(SixFourDisplay.logicRateHz),
                                             preferred: Float(SixFourDisplay.logicRateHz))
        link.add(to: .main, forMode: .common)
        self.link = link
        running = true
    }

    func stop() {
        link?.invalidate()
        link = nil
        running = false
    }

    /// One tick — flips the heartbeat (unless reduce-motion) and runs `onTick`.
    fileprivate func fire() {
        tick &+= 1
        if !reduceMotion { heartbeat ^= 1 }
        onTick?()
    }
}

/// A tiny ObjC target so `CADisplayLink` can hold a WEAK reference to the clock
/// (the link otherwise retains its target, which would leak the `@Observable` class).
/// `@MainActor` because the link is added to `.main` runloop — its selector always
/// fires on the main actor, so no `assumeIsolated` hop is needed.
@MainActor
private final class SurfaceClockProxy: NSObject {
    weak var clock: SurfaceClock?
    init(_ clock: SurfaceClock) { self.clock = clock; super.init() }
    @objc func fire() { clock?.fire() }
}
