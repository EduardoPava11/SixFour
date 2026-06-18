import Foundation

/// The TARGET lifecycle FSM — the Swift port of `SixFour.Spec.ABSurface` (`abStep`),
/// pinned bit-for-bit to `Generated/ABSurfaceContract.swift` (`SixFourABSurface`). This is
/// the capture → A/B → export machine the 2026-06-18 shift adopts (see
/// `docs/SIXFOUR-AB-GENOME-SHIFT-WORKFLOW.md`): no browse / pick-4 / visible 5-stage render.
/// `pickA`/`pickB` both land in `.picked`, where the A/B *infinite game* self-loops while
/// the taste θ folds; `.exporting` is entered ONLY from `.picked` (export gated on a prior
/// pick); lock + burst are INTERNAL to `.live` (no visible sub-phases — this is also the
/// Live→Capture smoothness fix).
///
/// NOT yet the live surface FSM — `Surface` still runs the Display machine (`surfaceStep`).
/// This is the proven foundation the P1 swap re-points the live surface onto, kept additive
/// so the swap lands as one coherent, build-green chunk with the real A/B wiring (P2).
///
/// Tier-2 pure: Foundation only. The `rawValue` tokens ARE the generated
/// `SixFourABSurface.phases` / `.events` tokens, so the parity fold below is exact.

// MARK: - Phases (Σ) — the 8 `SixFourABSurface.phases` tokens

enum ABPhase: String, Equatable, CaseIterable {
    case bootstrap, unauthorized, live, captured, picked, exporting, done, error
}

// MARK: - Events — the 11 `SixFourABSurface.events` tokens

enum ABEvent: String, Equatable, CaseIterable {
    case sessionReady, authDenied, shutterTap, lockComplete, burstComplete
    case pickA, pickB, exportFamily, exportDone, retake, fault
}

// MARK: - δ — the transition function (bit-for-bit `ABSurface.abStep`)

/// The total transition `δ: (phase, event) → phase`, a bit-for-bit mirror of the spec's
/// `abStep`. `.fault` from anywhere → `.error`; `pickA`/`pickB` from `.captured` → `.picked`
/// (and self-loop there — the infinite game); `.exporting` only from `.picked` via
/// `.exportFamily`; `.retake` bails captured/picked/done back to `.live`; any unmodelled
/// pair self-loops (lock/shutter are internal to `.live`, so they no-op at the FSM level).
func abStep(_ phase: ABPhase, _ event: ABEvent) -> ABPhase {
    if event == .fault { return .error }
    switch (phase, event) {
    case (.bootstrap, .sessionReady):  return .live
    case (.bootstrap, .authDenied):    return .unauthorized
    case (.live, .burstComplete):      return .captured       // lock + burst internal to live
    case (.captured, .pickA):          return .picked
    case (.captured, .pickB):          return .picked
    case (.picked, .exportFamily):     return .exporting
    case (.exporting, .exportDone):    return .done
    case (.captured, .retake),
         (.picked, .retake),
         (.done, .retake):             return .live           // bail back to live
    default:                           return phase           // catch-all self-loop
    }
}

// MARK: - Spec parity gate (debug)

extension ABPhase {
    /// Re-derives the golden phase trace by folding `abStep` over the generated golden
    /// event tokens from `.bootstrap`, and asserts it matches
    /// `SixFourABSurface.goldenHappyPathTrace` token-for-token — the live Swift↔Haskell
    /// parity pin for the A/B FSM (mirrors `Surface.assertSpecParity` for the Display FSM).
    /// Also runs the contract's own `selfCheck()`. Debug-only.
    static func assertSpecParity() {
        #if DEBUG
        assert(SixFourABSurface.selfCheck(), "SixFourABSurface.selfCheck() failed")

        var phase = ABPhase.bootstrap
        var trace = [phase.rawValue]
        for token in SixFourABSurface.goldenHappyPathEvents {
            guard let event = ABEvent(rawValue: token) else {
                assertionFailure("unknown AB golden event token: \(token)")
                return
            }
            phase = abStep(phase, event)
            trace.append(phase.rawValue)
        }
        assert(trace == SixFourABSurface.goldenHappyPathTrace,
               "abStep trace \(trace) != golden \(SixFourABSurface.goldenHappyPathTrace)")

        // Alphabet cross-pin: the Swift enums reproduce the generated token sets exactly.
        assert(ABPhase.allCases.map(\.rawValue) == SixFourABSurface.phases,
               "ABPhase tokens != SixFourABSurface.phases")
        assert(ABEvent.allCases.map(\.rawValue) == SixFourABSurface.events,
               "ABEvent tokens != SixFourABSurface.events")
        #endif
    }
}
