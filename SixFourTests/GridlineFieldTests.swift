import Testing
import Foundation
import simd
@testable import SixFour

/// Cheap pure-function guards for the 20 fps B/W refresh checker (Layer 1, no codegen —
/// UI off the deterministic GIF path). ONE cell size: every non-hero atom is a 6 pt
/// checker cell, the heroes are excluded, and flipping the phase inverts every cell.
struct GridlineFieldTests {

    private let heroes: [ScreenLattice.Region] = [
        ScreenLattice.preview, ScreenLattice.palette, ScreenLattice.gear,
    ]

    /// The chrome mask returns nil for EVERY cell inside an excluded hero region.
    @Test func maskIsNilInsideEveryHero() {
        for phase in 0...1 {
            let mask = GridChecker.chrome(phase: phase, exclude: heroes)
            for reg in heroes {
                for r in reg.row ..< (reg.row + reg.h) {
                    for c in reg.col ..< (reg.col + reg.w) {
                        #expect(mask.cell(c, r) == nil, "cell (\(c),\(r)) inside hero must be nil")
                    }
                }
            }
        }
    }

    /// EVERY non-hero atom is a checker cell (white or dark) — one size, no gaps.
    @Test func everyNonHeroAtomIsACheckerCell() {
        let mask = GridChecker.chrome(phase: 0, exclude: heroes)
        for r in 0 ..< GlobalLattice.rows {
            for c in 0 ..< GlobalLattice.cols {
                if GridChecker.excluded(c, r, heroes) {
                    #expect(mask.cell(c, r) == nil)
                } else {
                    let v = mask.cell(c, r)
                    #expect(v == GridChecker.white || v == GridChecker.dark,
                            "non-hero cell (\(c),\(r)) must be an opaque checker cell")
                }
            }
        }
    }

    /// Flipping the phase inverts EVERY non-hero cell (white ↔ dark) and leaves hero cells
    /// nil in both phases.
    @Test func phaseFlipInvertsEveryCheckerCell() {
        let m0 = GridChecker.chrome(phase: 0, exclude: heroes)
        let m1 = GridChecker.chrome(phase: 1, exclude: heroes)
        for r in 0 ..< GlobalLattice.rows {
            for c in 0 ..< GlobalLattice.cols {
                let a = m0.cell(c, r), b = m1.cell(c, r)
                if a == nil {
                    #expect(b == nil, "hero cell (\(c),\(r)) changed across phase")
                } else {
                    #expect(b != nil && b != a, "checker cell (\(c),\(r)) did not invert")
                    if a == GridChecker.white { #expect(b == GridChecker.dark) }
                    else { #expect(b == GridChecker.white) }
                }
            }
        }
    }

    /// True `(c + r)` parity checker: orthogonally-adjacent cells are opposite colours,
    /// and a phase flip swaps the whole field.
    @Test func adjacentCellsAlternateAndPhaseSwaps() {
        #expect(GridChecker.color(0, 0, phase: 0) != GridChecker.color(1, 0, phase: 0))
        #expect(GridChecker.color(0, 0, phase: 0) != GridChecker.color(0, 1, phase: 0))
        #expect(GridChecker.color(5, 7, phase: 0) != GridChecker.color(5, 7, phase: 1))
        #expect(GridChecker.color(5, 7, phase: 0) == GridChecker.color(6, 7, phase: 1))
    }
}
