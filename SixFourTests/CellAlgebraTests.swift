import Testing
import simd
@testable import SixFour

/// Byte-exact gate for the on-device cell algebra (`SFCell` / `renderCell`) against
/// the Haskell-derived `CellContract.golden`. Proves the device honours the no-blend
/// law: render is always neutral, the sentinel, or an ACTUAL claim — never a mixture.
/// Source of truth: spec/src/SixFour/Spec/CellFiber.hs + CellGrid.hs.
struct CellAlgebraTests {

    @Test func matchesGolden() {
        for g in CellContract.golden {
            let cell = SFCell(g.claims)
            #expect(cell.claims == g.claims, "canonical claim order mismatch for \(g.name)")
            #expect(cell.render() == g.render, "render mismatch for \(g.name)")
            #expect(cell.isContested == g.contested, "contested flag mismatch for \(g.name)")
            for t in 0..<g.shimmer.count {
                #expect(cell.shimmer(at: t) == g.shimmer[t], "shimmer[\(t)] mismatch for \(g.name)")
            }
        }
    }

    @Test func noBlendOnContention() {
        // Two claims for one place => the loud sentinel, NOT a pick or a blend.
        let c1 = SFColor(10000, 2000, -3000)
        let c2 = SFColor(50000, -1000, 4000)
        let r = SFCell([c1, c2]).render()
        #expect(r == CellContract.contestedSentinel)
        #expect(r != c1 && r != c2)   // never silently shows one claimant, never averages
    }

    @Test func contentionIsDetectable() {
        #expect(SFCell([]).isContested == false)
        #expect(SFCell([SFColor(1, 2, 3)]).isContested == false)
        #expect(SFCell([SFColor(1, 2, 3), SFColor(4, 5, 6)]).isContested == true)
    }

    @Test func effectZoneShimmersElseSentinel() {
        let c1 = SFColor(10000, 2000, -3000)   // sorts first
        let c2 = SFColor(50000, -1000, 4000)
        let cell = SFCell([c1, c2])
        // Outside an effect zone: a collision is loud.
        #expect(renderCell(cell, tick: 0, inEffectZone: false) == CellContract.contestedSentinel)
        // Inside: a REAL claimant per tick, cycling on the 20fps clock — never synthesised.
        #expect(renderCell(cell, tick: 0, inEffectZone: true) == c1)
        #expect(renderCell(cell, tick: 1, inEffectZone: true) == c2)
        #expect(renderCell(cell, tick: 2, inEffectZone: true) == c1)
    }
}
