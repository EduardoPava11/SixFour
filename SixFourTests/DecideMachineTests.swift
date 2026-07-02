import Testing
@testable import SixFour

/// Swift↔Haskell parity for the V3.0 decide loop in the phase FSM
/// (`ABSurfaceMachine` vs the generated `SixFourABSurface` decide golden).
struct DecideMachineTests {

    @Test func contractCarriesTheDecideAlphabet() {
        #expect(SixFourABSurface.selfCheck())
        #expect(SixFourABSurface.phases.contains("deciding"))
        for e in ["beginDecide", "decideAccept", "decideAgain"] {
            #expect(SixFourABSurface.events.contains(e), "missing \(e)")
        }
    }

    /// The Swift `abStep` reproduces the generated decide-path golden trace
    /// token-for-token (the same fold `ABPhase.assertSpecParity()` runs in
    /// debug, here as a CI gate).
    @Test func swiftStepReproducesTheDecideGolden() throws {
        var phase = ABPhase.bootstrap
        var trace = [phase.token]
        for token in SixFourABSurface.goldenDecidePathEvents {
            let event = try #require(ABEvent(rawValue: token), "unknown token \(token)")
            phase = abStep(phase, event)
            trace.append(phase.token)
        }
        #expect(trace == SixFourABSurface.goldenDecidePathTrace)
    }

    /// The decide edges and their gating, in Swift (mirrors `lawDecideEntryGated`
    /// + `lawDecideVerdictsResolve`).
    @Test func decideEdgesResolveAndEntryIsGated() {
        #expect(abStep(.captured, .beginDecide) == .deciding)
        #expect(abStep(.deciding, .decideAccept) == .picked)   // a decide-accept IS a pick
        #expect(abStep(.deciding, .decideAgain) == .live)
        #expect(abStep(.deciding, .retake) == .live)
        #expect(abStep(.deciding, .fault) == .error)
        // Entry gated: beginDecide anywhere else self-loops.
        for phase in ABPhase.allCases where phase != .captured {
            #expect(abStep(phase, .beginDecide) == (phase == .deciding ? .deciding : phase))
        }
        // Export stays pick-gated: no direct deciding → exporting edge.
        #expect(abStep(.deciding, .exportFamily) == .deciding)
    }
}
