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
        // T4 — the atom; GIF + palette at ONE atom (Law #1), shutter (Review) at 4.
        // The 64→16→4 cascade lives in the cell COUNTS, not the cell sizes.
        #expect(SixFourDisplay.atomPt == 4)   // GRID v3.0 (was 6 pt in v2.0)
        #expect(SixFourDisplay.blockFactors == [1, 1, 4])
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
        #expect(SixFourDisplay.cellPitchPt(0) == 4)                       // GIF: 1 atom/cell (v3.0: 4 pt)
        #expect(SixFourDisplay.cellPitchPt(1) == Int(GlobalLattice.gif(1)))  // palette: 4 pt — ONE atom (Law #1)
        #expect(SixFourDisplay.cellPitchPt(2) == Int(GlobalLattice.gif(4)))  // shutter: 16 pt (dormant Review tile)
    }

    /// The Haar cascade is a cell-COUNT relation (64 → 16 → 4), NOT a cell-size one
    /// (GRID Law #1 — one atom; supersedes ADR-5's ×2-per-level cells). The two
    /// capture-scene views render at the ONE atom, so GIF = 256 (64 cells) and palette =
    /// 64 (16 cells); the dormant Review shutter (b=4) is 64 (4 cells × 4 atoms).
    @Test func cascadeIsACellCountRelation() {
        let ext = (0..<3).map {
            SixFourDisplay.gridDims[$0] * SixFourDisplay.blockFactors[$0] * SixFourDisplay.atomPt
        }
        #expect(ext == [256, 64, 64])   // v3.0 4 pt atom: 64·4, 16·4, 4·4·4
        // GIF and palette both render at one atom; the cascade lives in the cell COUNTS.
        #expect(SixFourDisplay.blockFactors[0] == 1 && SixFourDisplay.blockFactors[1] == 1)
        #expect(SixFourDisplay.gridDims == [64, 16, 4])
        // T5 — the GIF field squared is the full lattice δ_capture writes.
        #expect(SixFourDisplay.gridDims[0] * SixFourDisplay.gridDims[0]
                == SixFourDisplay.fullLatticeCount)
    }
}
