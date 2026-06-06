import Foundation
import Observation

/// The Z₆₄ playback-cursor value type, retained for the Review component family
/// (`VoxelCubeView` / `PaletteCloudView` / `ContestedCellGridView` / their previews).
///
/// ONE-SURFACE NOTE: the surface itself no longer drives auto-advance through this class
/// — κ (`SurfaceClock`, the single `CADisplayLink`) owns the only 20 fps tick and writes
/// `σ.cursor`. So this class's private Foundation `Timer` + `start()` / `stop()` are GONE
/// (T1/T7: one δ per 1/f s). What remains is the spec-pinned cursor MATH
/// (`SixFourPlaybackClock.frameAfter` / `.clampFrame`) plus discrete transport
/// (`togglePlay` / `scrub` / `advance`) — input, not motion — so the reused components
/// keep their `clock.frame` / `clock.scrub` / `clock.togglePlay` surface.
///
/// All cyclic arithmetic is delegated to `SixFourPlaybackClock` (generated from
/// `SixFour.Spec.PlaybackClock`, gated by `cabal test`), so this class owns only state,
/// never the math. Consumers read `frame` (live) or `settledFrame` (pause/scrub-only).
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
        didSet { if reduceMotion { frame = 0; settledFrame = 0 } }
    }

    /// The live cursor `0..<count` — the frame every continuous consumer (the 2D
    /// image, the 3D front face, the status line, the grid/tree/cloud analyzers)
    /// renders as "now".
    private(set) var frame: Int = 0

    /// Whether the cursor is in the play (vs paused) transport state. The actual
    /// auto-advance is driven externally by κ; this is the discrete intent flag the
    /// reused components read to label the transport.
    private(set) var playing: Bool = true

    /// The cursor that EXPENSIVE analyzers follow — the median-cut rebuilders
    /// (`AddressPickerView`, `Quad4DrillView`) whose ~256-leaf tree rebuild must not
    /// run 20×/sec. Updated ONLY on pause/scrub, so trees re-sync when the user
    /// settles on a frame, never mid-playback (docs decision 2).
    private(set) var settledFrame: Int = 0

    init(count: Int = SixFourPlaybackClock.frameCount, reduceMotion: Bool = false) {
        self.count = max(1, count)
        self.reduceMotion = reduceMotion
    }

    // MARK: Transport (discrete cursor math — no Timer; κ drives auto-advance)

    /// Advance exactly one frame, mod N — routed through the spec-pinned contract. Kept
    /// for any external tick source that still drives this cursor (the surface uses
    /// `σ.cursor` directly via κ; this stays for the reused component family).
    func advance() {
        guard !reduceMotion, playing else { return }
        frame = SixFourPlaybackClock.frameAfter(frame, count: count)
    }

    /// Toggle play/pause. Pausing settles the expensive analyzers on the current frame.
    func togglePlay() {
        playing.toggle()
        if !playing { settle() }
    }

    /// Scrub to an arbitrary (e.g. drag) index, clamped into `[0, count)`. Pauses and
    /// settles. Allowed under reduce-motion — a scrub is discrete input, not motion.
    func scrub(to i: Int) {
        playing = false
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
