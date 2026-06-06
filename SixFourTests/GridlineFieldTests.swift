import Testing
import Foundation
import simd
@testable import SixFour

/// Guards for the 20 fps refresh checker (`GridChecker` / `GridRefreshFieldView`) and the
/// uniform 4 pt atom it tiles. Layer 1 (no codegen — UI off the deterministic GIF path).
///
/// NOTE (one-surface unification, 2026-06-06): the old `CaptureGrid` layout enum these
/// tests once guarded was removed — the capture screen is now the `.live` / `.capturing`
/// phases of the single `SurfaceView`, laid out via `GlobalLattice` + the proven
/// `GridLayoutContract` (whose disjointness is gated by `Spec.GridLayout` / `GridLayoutTests`).
/// What still lives here and needs guarding is the checker itself and the atom.
struct GridlineFieldTests {

    /// The ONE atom is 4 pt, and the live preview hero is 64 cells = 256 pt — a whole
    /// number of atoms (widgets grow by cell COUNT, never a bigger cell).
    @Test func previewIsWholeAtoms() {
        #expect(GlobalLattice.gifPx == 4)
        #expect(GlobalLattice.previewCells == 64)
        #expect(GlobalLattice.gif(GlobalLattice.previewCells) == 256)
    }

    /// True `(c + r)` parity checker that inverts on phase, opaque B/W only.
    @Test func checkerAlternatesAndInvertsOnPhase() {
        #expect(GridChecker.color(0, 0, phase: 0) != GridChecker.color(1, 0, phase: 0))
        #expect(GridChecker.color(0, 0, phase: 0) != GridChecker.color(0, 1, phase: 0))
        #expect(GridChecker.color(5, 7, phase: 0) != GridChecker.color(5, 7, phase: 1))
        #expect(GridChecker.color(5, 7, phase: 0) == GridChecker.color(6, 7, phase: 1))
        let v = GridChecker.color(3, 4, phase: 0)
        #expect(v == GridChecker.white || v == GridChecker.dark)
    }

    /// Both phase bitmaps bake to a non-nil full-lattice image (the O(1)-flip pair the
    /// `GridRefreshFieldView` swaps between at 20 fps).
    @Test func checkerBakesBothPhases() {
        #expect(GridChecker.image(phase: 0) != nil)
        #expect(GridChecker.image(phase: 1) != nil)
    }
}
