import Foundation
import Observation
import simd

/// σ — the ONE surface state. Every UI lifecycle "screen" is a phase of this single
/// field (`SixFour.Spec.Display.lawPhaseIsCellGrid`): capture → render → review are
/// cell updates on the one surface, never view swaps. The phase FSM is ported
/// bit-for-bit from `Generated/DisplayContract.swift` (`SixFourDisplay.phases` /
/// `.events`) and MUST reproduce `SixFourDisplay.goldenHappyPathTrace`. Review is
/// reachable ONLY via `.committed` (`lawReviewExplicit`).
///
/// Tier-2 pure: Foundation + Observation + simd only.

// MARK: - Phases (Σ)

/// The UI-lifecycle phases — the exact `SixFourDisplay.phases` tokens, one case each.
/// The rendering pipeline is its five sub-stages so the surface can show *which*
/// verified Zig kernel is running as a cell transform.
enum SurfacePhase: Equatable {
    case bootstrap
    case unauthorized
    case live
    case settings
    case locking
    case capturing
    case review
    case error
    case rendering(RenderStage)

    /// The five deterministic-core stages, in order — the `rendering:*` token suffixes.
    enum RenderStage: String, CaseIterable, Equatable {
        case quantize, dither, significance, palette, encode
    }

    /// The contract token for this phase — MUST be one of `SixFourDisplay.phases`.
    var token: String {
        switch self {
        case .bootstrap:        return "bootstrap"
        case .unauthorized:     return "unauthorized"
        case .live:             return "live"
        case .settings:         return "settings"
        case .locking:          return "locking"
        case .capturing:        return "capturing"
        case .review:           return "review"
        case .error:            return "error"
        case .rendering(let s): return "rendering:\(s.rawValue)"
        }
    }
}

// MARK: - Events (the FSM transition triggers)

/// The FSM events — the exact `SixFourDisplay.events` tokens. Out-of-band data
/// (palette bytes, the rendered GIF, progress) lives in Σ's fields, never here.
enum SurfaceEvent: Equatable {
    case sessionReady
    case authDenied
    case shutterTap
    case openSettings
    case closeSettings
    case lockComplete
    case burstComplete
    case committed
    case retake
    case fault
    case stageDone(SurfacePhase.RenderStage)

    /// The contract token — MUST be one of `SixFourDisplay.events`.
    var token: String {
        switch self {
        case .sessionReady:    return "sessionReady"
        case .authDenied:      return "authDenied"
        case .shutterTap:      return "shutterTap"
        case .openSettings:    return "openSettings"
        case .closeSettings:   return "closeSettings"
        case .lockComplete:    return "lockComplete"
        case .burstComplete:   return "burstComplete"
        case .committed:       return "committed"
        case .retake:          return "retake"
        case .fault:           return "fault"
        case .stageDone(let s): return "stageDone:\(s.rawValue)"
        }
    }
}

// MARK: - δ — the transition function

/// The pure FSM step `δ: (phase, event) → phase`, ported from the Display spec.
/// Total: any unmodelled (phase, event) pair is a no-op (stays in `phase`), so an
/// out-of-band event never derails the surface. `.fault` from any phase → `.error`.
/// Review is entered ONLY by `.committed` (`lawReviewExplicit`).
func surfaceStep(_ phase: SurfacePhase, _ event: SurfaceEvent) -> SurfacePhase {
    // A fault from anywhere drops to the error field.
    if case .fault = event { return .error }

    switch (phase, event) {
    case (.bootstrap, .sessionReady):   return .live
    case (.bootstrap, .authDenied):     return .unauthorized

    case (.live, .shutterTap):          return .locking
    case (.live, .openSettings):        return .settings
    case (.settings, .closeSettings):   return .live

    case (.locking, .lockComplete):     return .capturing
    case (.capturing, .burstComplete):  return .rendering(.quantize)

    // The verified Zig pipeline advances stage by stage.
    case (.rendering(.quantize), .stageDone(.quantize)):           return .rendering(.dither)
    case (.rendering(.dither), .stageDone(.dither)):               return .rendering(.significance)
    case (.rendering(.significance), .stageDone(.significance)):   return .rendering(.palette)
    case (.rendering(.palette), .stageDone(.palette)):             return .rendering(.encode)
    // The last stage completing does NOT enter review — only an explicit commit does
    // (`lawReviewExplicit`). encode stays on the encode field until `.committed`.
    case (.rendering(.encode), .stageDone(.encode)):               return .rendering(.encode)

    case (.rendering(.encode), .committed): return .review
    case (.review, .retake):                return .live

    default:
        return phase   // unmodelled pair → no-op
    }
}

// MARK: - σ — the observable surface

@MainActor
@Observable
final class Surface {

    // MARK: phase (Σ)

    /// The current lifecycle phase — ι = `.bootstrap`. A phase change is a cell
    /// update, never a view swap.
    private(set) var phase: SurfacePhase = .bootstrap

    // MARK: the field's data (out-of-band Σ)

    /// The current 256-colour palette (sRGB8) the surface paints — the live per-frame
    /// palette during capture, the global palette in review.
    var palette: [SIMD3<UInt8>] = []

    /// The 64×64×64 index cube (row-major `t,y,x`), populated once a GIFA exists.
    /// Empty until review. A flat buffer keeps the value type cheap to carry.
    var indexCube: [UInt8] = []

    /// The Z₆₄ playback cursor — the current frame `0..<64`. Advanced by κ each tick.
    var cursor: Int = 0

    /// The cube pose for the 3D review hero, packed integers (yaw, pitch) in degrees.
    var pose: SIMD2<Int32> = .zero

    /// 0 = flat (2D GIF hero), 1 = cube (3D voxel hero). The review render mode.
    var playerMode: Int = 0

    /// The surface settings (dither / deterministic-core toggles), integer-encoded.
    var settings: SurfaceSettings = .init()

    // MARK: δ

    /// Apply one event — the single mutation point for the phase. Mirrors
    /// `surfaceStep` and is the only writer of `phase`.
    func step(_ event: SurfaceEvent) {
        phase = surfaceStep(phase, event)
    }

    // MARK: κ-fed cursor advance (Z₆₄)

    /// Advance the playback cursor one frame mod 64 — routed through the spec-pinned
    /// `SixFourPlaybackClock.frameAfter` (the ONE κ math). Called by `SurfaceClock`.
    func advanceCursor() {
        cursor = SixFourPlaybackClock.frameAfter(cursor, count: SixFourPlaybackClock.frameCount)
    }
}

/// Integer-encoded surface settings (no floats on the state spine). Expanded as
/// the per-phase renderers wire real options through.
struct SurfaceSettings: Equatable {
    /// Whether the deterministic fixed-point Zig core (vs the GPU float path) renders.
    var useDeterministicCore: Bool = true
}

// MARK: - Spec parity gate (debug)

extension Surface {
    /// Re-derives the golden happy-path trace by folding `surfaceStep` over the
    /// generated `SixFourDisplay.goldenHappyPathEvents`, and asserts it matches
    /// `SixFourDisplay.goldenHappyPathTrace` token-for-token — the live Swift↔Haskell
    /// parity pin for the phase FSM. Also runs the contract's own `selfCheck()`.
    /// Debug-only; release builds compile this to nothing.
    static func assertSpecParity() {
        #if DEBUG
        assert(SixFourDisplay.selfCheck(), "SixFourDisplay.selfCheck() failed")

        // Fold our step over the golden event tokens, starting at bootstrap.
        var phase = SurfacePhase.bootstrap
        var trace = [phase.token]
        for token in SixFourDisplay.goldenHappyPathEvents {
            guard let event = SurfaceEvent.fromToken(token) else {
                assertionFailure("unknown golden event token: \(token)")
                return
            }
            phase = surfaceStep(phase, event)
            trace.append(phase.token)
        }
        assert(trace == SixFourDisplay.goldenHappyPathTrace,
               "Surface.step trace \(trace) != golden \(SixFourDisplay.goldenHappyPathTrace)")
        #endif
    }
}

extension SurfaceEvent {
    /// Parse a contract event token back to an event (for the parity gate). The
    /// `stageDone:*` family carries its stage suffix.
    static func fromToken(_ token: String) -> SurfaceEvent? {
        switch token {
        case "sessionReady":  return .sessionReady
        case "authDenied":    return .authDenied
        case "shutterTap":    return .shutterTap
        case "openSettings":  return .openSettings
        case "closeSettings": return .closeSettings
        case "lockComplete":  return .lockComplete
        case "burstComplete": return .burstComplete
        case "committed":     return .committed
        case "retake":        return .retake
        case "fault":         return .fault
        default:
            guard token.hasPrefix("stageDone:"),
                  let stage = SurfacePhase.RenderStage(rawValue: String(token.dropFirst("stageDone:".count)))
            else { return nil }
            return .stageDone(stage)
        }
    }
}
