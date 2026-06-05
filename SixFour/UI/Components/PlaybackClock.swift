import Foundation
import Observation

/// THE single playback clock for the Review screen — the one source of truth that
/// the unified 2D/3D player (`GIFPlayer`), the status line, and every palette
/// analyzer read "the current frame" through. It replaces the four uncoordinated
/// clocks that used to drift (the 2D `GIFCanvas` `Timer`, the status-line
/// `TimelineView`, and the cloud / voxel 60 Hz publishers). See
/// `docs/SIXFOUR-UNIFIED-PLAYER.md`.
///
/// All cyclic arithmetic is delegated to `SixFourPlaybackClock` (generated from
/// `SixFour.Spec.PlaybackClock`, gated by `cabal test`), so this class owns only
/// state + the 20 fps timer, never the math. Mutation goes through `togglePlay` /
/// `scrub`; consumers read `frame` (live) or `settledFrame` (pause/scrub-only).
///
/// Tier-2 pure: Foundation + Observation only.
@MainActor
@Observable
final class PlaybackClock {
    /// The loop length (always `SixFourShape.T` = 64 for a SixFour GIF).
    let count: Int

    /// Auto-advance suppressed (reduce-motion): the cursor is pinned to frame 0 and
    /// only discrete `scrub` may move it (motion is suppressed, input is not).
    var reduceMotion: Bool {
        didSet { if reduceMotion { stop(); frame = 0; settledFrame = 0 } }
    }

    /// The live cursor `0..<count` — the frame every continuous consumer (the 2D
    /// image, the 3D front face, the status line, the grid/tree/cloud analyzers)
    /// renders as "now".
    private(set) var frame: Int = 0

    /// Whether the clock is auto-advancing at 20 fps.
    private(set) var playing: Bool = true

    /// The cursor that EXPENSIVE analyzers follow — the median-cut rebuilders
    /// (`AddressPickerView`, `Quad4DrillView`) whose ~256-leaf tree rebuild must not
    /// run 20×/sec. Updated ONLY on pause/scrub, so trees re-sync when the user
    /// settles on a frame, never mid-playback (docs decision 2).
    private(set) var settledFrame: Int = 0

    @ObservationIgnored private var timer: Timer?

    init(count: Int = SixFourPlaybackClock.frameCount, reduceMotion: Bool = false) {
        self.count = max(1, count)
        self.reduceMotion = reduceMotion
    }

    // The owning view invalidates the timer via `stop()` in `.onDisappear` (the
    // `GIFCanvas` pattern); a `@MainActor` class can't touch `timer` in its
    // nonisolated `deinit`, and there is nothing else to clean up.

    // MARK: Lifecycle (the view starts/stops the single timer)

    /// Begin auto-advance at `SFTheme.gifFrameRate`. No-op under reduce-motion or
    /// when paused, so freeze-on-frame-0 is enforced in exactly one place and
    /// propagates to every consumer.
    func start() {
        stop()
        guard !reduceMotion, playing else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 1.0 / Double(SFTheme.gifFrameRate),
                                     repeats: true) { [weak self] _ in
            Task { @MainActor in self?.advance() }
        }
    }

    func stop() { timer?.invalidate(); timer = nil }

    // MARK: Transport

    /// Advance exactly one frame, mod N — routed through the spec-pinned contract.
    func advance() {
        guard !reduceMotion, playing else { return }
        frame = SixFourPlaybackClock.frameAfter(frame, count: count)
    }

    /// Toggle play/pause. Pausing settles the expensive analyzers on the current
    /// frame; playing restarts the single timer.
    func togglePlay() {
        playing.toggle()
        if playing { start() } else { stop(); settle() }
    }

    /// Scrub to an arbitrary (e.g. drag) index, clamped into `[0, count)`. Pauses and
    /// settles. Allowed under reduce-motion — a scrub is discrete input, not motion.
    func scrub(to i: Int) {
        playing = false
        stop()
        frame = SixFourPlaybackClock.clampFrame(i, count: count)
        settle()
    }

    private func settle() { settledFrame = frame }

    // MARK: Derived (the 2D≡3D agreement invariant, made callable)

    /// The 3D cube front-face (depth z = N-1) frame for the current cursor. Equals
    /// `frame` by the kernel reduction — exposed so the cube and tests can assert
    /// that FLAT and CUBE never disagree.
    var frontFaceFrame: Int { SixFourPlaybackClock.threeDFrontFace(frame, count: count) }
}
