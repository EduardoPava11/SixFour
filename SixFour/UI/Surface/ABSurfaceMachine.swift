import Foundation

/// The simplified capture → A/B → export lifecycle FSM — the user story after the
/// per-frame genome A/B shift. The whole multi-phase Surface (browse, refine, palette
/// explorers, movable tools, 5-stage render) collapses to **capture → A/B → export**.
///
/// This is the Swift port of `SixFour.Spec.ABSurface` (`ABPhase` / `ABEvent` / `abStep`),
/// pinned bit-for-bit to `Generated/ABSurfaceContract.swift` (`SixFourABSurface`) and
/// asserted live by `ABPhase.assertSpecParity()`. It REPLACES only the phase-FSM half of
/// the old Display machine (`SurfacePhase` / `SurfaceEvent` / `surfaceStep`, deleted); the
/// CLOCK half (the 20 fps κ, the Z₆₄ cursor, the projections) is unchanged.
///
/// == Phases and events
///
///     Phase = bootstrap | unauthorized | live | captured | deciding | picked | exporting | done | error
///     Event = sessionReady | authDenied | shutterTap | lockComplete | burstComplete
///           | beginDecide | decideAccept | decideAgain
///           | pickA | pickB | exportFamily | exportDone | retake | fault
///
/// Lock + burst are INTERNAL to `.live` (the camera freezes; not visible sub-phases).
/// `pickA` / `pickB` are BOTH live edges out of `.captured`, both landing in `.picked`
/// (the user "plays the game": repeated picks self-loop in `.picked` while θ folds).
/// Export is gated on a prior pick (`.exporting` is entered ONLY from `.picked`). `.retake`
/// bails from `.captured` / `.picked` / `.done` back to `.live`. δ is total with a catch-all
/// self-loop; `.fault` from any phase lands in `.error`.
///
/// Tier-2 pure: Foundation only.

// MARK: - Phases (Σ)

/// The UI-lifecycle phases — the exact `SixFourABSurface.phases` tokens, one case each.
enum ABPhase: String, Equatable, CaseIterable {
    case bootstrap
    case unauthorized
    case live
    case captured
    case deciding
    case picked
    case exporting
    case done
    case error

    /// The contract token for this phase — MUST be one of `SixFourABSurface.phases`.
    var token: String { rawValue }
}

// MARK: - Events (the FSM transition triggers)

/// The FSM events — the exact `SixFourABSurface.events` tokens. Out-of-band data
/// (palette bytes, the rendered GIF, the learned taste θ) lives in σ's fields, never here.
enum ABEvent: String, Equatable, CaseIterable {
    case sessionReady
    case authDenied
    case shutterTap
    case lockComplete
    case burstComplete
    case beginDecide
    case decideAccept
    case decideAgain
    case pickA
    case pickB
    case exportFamily
    case exportDone
    case retake
    case fault

    /// The contract token — MUST be one of `SixFourABSurface.events`.
    var token: String { rawValue }
}

// MARK: - δ — the transition function

/// The pure FSM step `δ: (phase, event) → phase`, ported from `SixFour.Spec.ABSurface.abStep`.
/// Total: any unmodelled (phase, event) pair is a catch-all self-loop (stays in `phase`), so
/// an out-of-band event never derails the surface. `.fault` from any phase → `.error`.
/// Lock + burst are internal to `.live`; repeated `.pickA` / `.pickB` self-loop in `.picked`.
func abStep(_ phase: ABPhase, _ event: ABEvent) -> ABPhase {
    // A fault from anywhere drops to the error field.
    if event == .fault { return .error }

    switch (phase, event) {
    case (.bootstrap, .sessionReady):   return .live
    case (.bootstrap, .authDenied):     return .unauthorized

    case (.live, .burstComplete):       return .captured   // lock + burst are internal to live

    case (.captured, .beginDecide):     return .deciding   // V3.0: the 16³ decide loop
    case (.deciding, .decideAccept):    return .picked     // a decide-accept IS a committed pick
    case (.deciding, .decideAgain):     return .live       // reject: back to live

    case (.captured, .pickA):           return .picked
    case (.captured, .pickB):           return .picked     // both picks land in picked

    case (.picked, .exportFamily):      return .exporting   // export gated on a prior pick
    case (.exporting, .exportDone):     return .done

    // Retake bails back to live from captured / picked / done (mid-A/B bail allowed).
    case (.captured, .retake),
         (.deciding, .retake),
         (.picked, .retake),
         (.done, .retake),
         (.error, .retake):       // recovery: a fault must not brick the surface
        return .live

    default:
        return phase   // catch-all self-loop (e.g. repeated pickA/pickB in picked)
    }
}

// MARK: - Spec parity gate (debug)

extension ABPhase {
    /// Re-derives the golden happy-path trace by folding `abStep` over the generated
    /// `SixFourABSurface.goldenHappyPathEvents`, and asserts it matches
    /// `SixFourABSurface.goldenHappyPathTrace` token-for-token — the live Swift↔Haskell
    /// parity pin for the A/B phase FSM. Also runs the contract's own `selfCheck()`.
    /// Debug-only; release builds compile this to nothing.
    static func assertSpecParity() {
        #if DEBUG
        assert(SixFourABSurface.selfCheck(), "SixFourABSurface.selfCheck() failed")

        // Fold our step over the golden event tokens, starting at bootstrap.
        var phase = ABPhase.bootstrap
        var trace = [phase.token]
        for token in SixFourABSurface.goldenHappyPathEvents {
            guard let event = ABEvent(rawValue: token) else {
                assertionFailure("unknown golden A/B event token: \(token)")
                return
            }
            phase = abStep(phase, event)
            trace.append(phase.token)
        }
        assert(trace == SixFourABSurface.goldenHappyPathTrace,
               "abStep trace \(trace) != golden \(SixFourABSurface.goldenHappyPathTrace)")

        // The V3.0 decide golden: the same fold over the decide-path events.
        var dPhase = ABPhase.bootstrap
        var dTrace = [dPhase.token]
        for token in SixFourABSurface.goldenDecidePathEvents {
            guard let event = ABEvent(rawValue: token) else {
                assertionFailure("unknown golden decide event token: \(token)")
                return
            }
            dPhase = abStep(dPhase, event)
            dTrace.append(dPhase.token)
        }
        assert(dTrace == SixFourABSurface.goldenDecidePathTrace,
               "abStep decide trace \(dTrace) != golden \(SixFourABSurface.goldenDecidePathTrace)")
        #endif
    }
}
