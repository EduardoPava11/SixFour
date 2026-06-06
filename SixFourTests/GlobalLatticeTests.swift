import Testing
import Foundation
@testable import SixFour

/// Pins the GRID Law #5 lattice invariants. The capture screen is the single `gifPx`
/// (6 pt atom) lattice that tiles the iPhone 17 Pro screen, and every interactive widget
/// clears the 44 pt HIG touch floor (8 atoms = 48 pt). These mirror the generated
/// `SixFourLattice` contract (source of truth: Haskell `Spec.Lattice`, cabal-gated);
/// they assert the relationships the `GlobalLattice` Swift facade must preserve.
struct GlobalLatticeTests {

    /// v2.0 gifPx inversion: the atom is the GIF pixel = 6 pt; `subPt = 2 pt = gifPx/3`
    /// is the commensurate sub-pixel for fine spacing/text. The screen tiles in ATOMS —
    /// `cols·gifPx = 402` exactly — NOT in subPt. (Was 201×437 @ 2 pt pre-inversion.)
    @Test func latticeTilesTheScreenExactly() {
        #expect(GlobalLattice.gifPx == 6)
        #expect(GlobalLattice.subPt == 2 && GlobalLattice.cellPt == 2)
        #expect(GlobalLattice.cols == 67 && GlobalLattice.rows == 145)
        #expect(GlobalLattice.gif(GlobalLattice.cols) == 402)   // width tiles exactly
        #expect(GlobalLattice.gif(GlobalLattice.rows) == 870)   // 145·6; + 4 pt bleed = 874
        // The generated contract re-asserts every geometry law (defense-in-depth); tying
        // the test to it means a future Spec.Lattice change can't silently drift past here.
        #expect(SixFourLattice.selfCheck())
    }

    /// The two conversions: `pt(_:)` is sub-pixels × subPt (2 pt); `gif(_:)` is atoms ×
    /// gifPx (6 pt). Fine spacing uses `pt`, content/instrument sizes use `gif`.
    @Test func conversionsAreCellsTimesPitch() {
        for n in [0, 1, 8, 22, 34, 64, 67] {
            #expect(GlobalLattice.pt(n) == CGFloat(n) * GlobalLattice.cellPt)
            #expect(GlobalLattice.gif(n) == CGFloat(n) * GlobalLattice.gifPx)
        }
    }

    /// Every interactive widget is ≥ the touch floor (8 atoms = 48 pt ≥ 44 pt HIG);
    /// widgets grow by more atoms, never a bigger atom (Law #1 / RULE-A11Y-VISIBLEISHIT).
    @Test func interactiveWidgetsClearTheTouchFloor() {
        #expect(GlobalLattice.gif(GlobalLattice.touchFloorCells) >= 44)      // 8·6 = 48 ≥ 44
        #expect(GlobalLattice.shutterCells >= GlobalLattice.touchFloorCells) // 12 ≥ 8
        #expect(GlobalLattice.controlCells >= GlobalLattice.touchFloorCells) // 8 ≥ 8
        // The diversity ring is decorative, but its tick count is the GIF's frame count.
        #expect(GlobalLattice.ringTicks == 64)
    }
}
