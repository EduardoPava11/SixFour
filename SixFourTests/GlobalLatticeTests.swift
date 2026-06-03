import Testing
import Foundation
@testable import SixFour

/// Pins the GRID Law #5 lattice invariants (interim, until the Haskell `Spec.Lattice`
/// golden ships). The capture HUD is the single 2 pt lattice that tiles the iPhone 17
/// Pro screen exactly, and every interactive widget clears the 22-cell touch floor.
struct GlobalLatticeTests {

    /// 2 pt is the unique pitch that tiles 402 × 874 with no remainder (gcd = 2):
    /// 201 cols × 437 rows. If any of these drift, the field resamples to blurry cells.
    @Test func latticeTilesTheScreenExactly() {
        #expect(GlobalLattice.cellPt == 2)
        #expect(GlobalLattice.cols == 201 && GlobalLattice.rows == 437)
        #expect(GlobalLattice.pt(GlobalLattice.cols) == 402)   // screen width  @ anchor
        #expect(GlobalLattice.pt(GlobalLattice.rows) == 874)   // screen height @ anchor
    }

    /// `pt(_:)` is the one conversion: cells × cellPt.
    @Test func ptConversionIsCellsTimesPitch() {
        for n in [0, 1, 22, 34, 64, 201] {
            #expect(GlobalLattice.pt(n) == CGFloat(n) * GlobalLattice.cellPt)
        }
    }

    /// Every interactive widget is ≥ 22 cells (44 pt HIG floor); widgets grow by more
    /// cells, never a bigger cell (Law #1 / RULE-A11Y-VISIBLEISHIT).
    @Test func interactiveWidgetsClearTheTouchFloor() {
        #expect(GlobalLattice.shutterCells >= 22)   // 34 = 68 pt
        #expect(GlobalLattice.controlCells >= 22)   // 24 = 48 pt
        // The diversity ring is decorative, but its tick count is the GIF's frame count.
        #expect(GlobalLattice.ringTicks == 64)
    }
}
