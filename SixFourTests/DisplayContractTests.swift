import Testing
import Foundation
@testable import SixFour

/// Parity gate for the display FSM `M = (Σ, ι, δ, λ, Π, κ)`: the generated
/// `SixFourDisplay` contract must match `SixFour.Spec.Display` (theorems T1–T9) AND
/// agree with the two sibling contracts it shares state with — `SixFourPlaybackClock`
/// (the ONE clock κ) and `SixFourLattice` (the ONE atom). The per-file `selfCheck()`
/// and the build's drift gate each check a contract in isolation; these tests check the
/// CROSS-CONTRACT seams, which is where the (camera-gated, un-drivable) clock/cell
/// refactors of FSM steps 3–5 would otherwise drift undetected.
/// Source of truth: spec/src/SixFour/Spec/Display.hs, spec/test/Properties/Display.hs.
struct DisplayContractTests {

    // MARK: generated contract <-> Haskell golden (T1,T2,T4,T5,T7 re-derived)

    @Test func contractSelfCheckPasses() {
        #expect(SixFourDisplay.selfCheck())
        // T1 — the single logic rate and the panel divisibility.
        #expect(SixFourDisplay.logicRateHz == 20)
        #expect(SixFourDisplay.panelRates == [60, 120])
        #expect(SixFourDisplay.holdCounts == [3, 6])
        // T4 — the atom and the 64→16→4 block-factor cascade.
        #expect(SixFourDisplay.atomPt == 6)
        #expect(SixFourDisplay.blockFactors == [1, 2, 4])
        #expect(SixFourDisplay.gridDims == [64, 16, 4])
        // T5 — the full lattice δ_capture writes each tick.
        #expect(SixFourDisplay.fullLatticeCount == 4096)
        #expect(SixFourDisplay.touchedIsFullLattice)
    }

    // MARK: CROSS-CONTRACT — Σ is ONE machine, so the contracts must agree

    /// T2 — δ_review IS the one clock κ: the Display cursor trace must equal
    /// `SixFourPlaybackClock.frameAfter` for every cursor, and the two contracts must
    /// agree on N. (If a future `CADisplayLink` swap changes either, this goes red.)
    @Test func deltaReviewIsThePlaybackClock() {
        #expect(SixFourDisplay.frameCount == SixFourPlaybackClock.frameCount)
        let n = SixFourDisplay.frameCount
        #expect(SixFourDisplay.goldenCursorTrace.count == n)
        for c in 0..<n {
            #expect(SixFourDisplay.goldenCursorTrace[c]
                    == SixFourPlaybackClock.frameAfter(c, count: n))
        }
    }

    /// T4 — the FSM atom IS the lattice atom: `SixFourDisplay.atomPt` must equal
    /// `SixFourLattice.gifPx`. The two generated contracts cannot disagree on the unit.
    @Test func atomMatchesLattice() {
        #expect(SixFourDisplay.atomPt == SixFourLattice.gifPx)
    }

    // MARK: T4 — pin the shipped pitches so the "delete cellPt" refactor is gated

    /// The per-view pitch is `atom × blockFactor`. These are exactly the pitches the
    /// shipped views render at TODAY (palette `gif(2)=12`, shutter `gif(4)=24`), so when
    /// FSM step 4 deletes the `cellPt` parameter and derives pitch from the contract,
    /// this test guarantees no view silently changes size — verification I cannot do by
    /// eye on a camera-less simulator.
    @Test func cellPitchMatchesShippedLattice() {
        #expect(SixFourDisplay.cellPitchPt(0) == 6)                       // GIF: 1 atom/cell
        #expect(SixFourDisplay.cellPitchPt(1) == Int(GlobalLattice.gif(2)))  // palette: 12 pt
        #expect(SixFourDisplay.cellPitchPt(2) == Int(GlobalLattice.gif(4)))  // shutter: 24 pt
    }

    /// The framed extents are `gridDim × blockFactor × atom = [384, 192, 96]` — the
    /// GIF / palette / shutter cascade (ADR-5 / capture-screen geometry), each level
    /// exactly half the one above it. Pins the contract to the self-similar layout.
    @Test func cascadeExtentsHalveEachLevel() {
        let ext = (0..<3).map {
            SixFourDisplay.gridDims[$0] * SixFourDisplay.blockFactors[$0] * SixFourDisplay.atomPt
        }
        #expect(ext == [384, 192, 96])
        #expect(ext[1] * 2 == ext[0])
        #expect(ext[2] * 2 == ext[1])
        // T5 — the GIF field squared is the full lattice δ_capture writes.
        #expect(SixFourDisplay.gridDims[0] * SixFourDisplay.gridDims[0]
                == SixFourDisplay.fullLatticeCount)
    }
}
