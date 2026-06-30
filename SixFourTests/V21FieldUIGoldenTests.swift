import Testing
@testable import SixFour

/// Byte-exact gate for the `V21FieldUI` Swift port (the V2.1 UI cell-count layer).
///
/// The pinned values are computed from `SixFour.Spec.V21FieldUI` directly (via `runghc`), so the Swift
/// port rides the same drift gate as the Zig kernels: spec is the source of truth, the port must match
/// it bit-for-bit. The law tests mirror the QuickCheck laws in `Properties.V21FieldUI`, so the port is
/// held to the same invariants (conservation, opposition, grid-alignment) as the spec.
struct V21FieldUIGoldenTests {

    private typealias UI = V21FieldUI

    // MARK: Pinned spec goldens

    /// The Morton interleave matches the spec: `mortonKey(1,2,3) = 53`.
    @Test func mortonKeyMatchesSpec() {
        #expect(UI.mortonKey((1, 2, 3)) == 53)
        #expect(UI.mortonKey((0, 0, 0)) == 0)
    }

    /// Exact Hamilton apportionment matches the spec (`30·[30,10,20] -> [15,5,10]`, even tie -> [4,3,3]).
    @Test func apportionMatchesSpec() {
        #expect(UI.apportion(30, [30, 10, 20]) == [15, 5, 10])
        #expect(UI.apportion(10, [1, 1, 1]) == [4, 3, 3])
        #expect(UI.apportion(7, []) == [])
        #expect(UI.apportion(0, [3, 1]) == [0, 0])
    }

    /// THE OPPOSITION GOLDEN: distinct counts, saliency-ranked, summing to the total.
    @Test func allocateWidgetsMatchesSpec() {
        // saliencies 30 > 20 > 10 over total 30 -> [11, 9, 10] (input order), sum 30, all distinct.
        #expect(UI.allocateWidgets(30, [(30, 0), (10, 1), (20, 2)]) == [11, 9, 10])
        // exactly at the feasibility floor (k=4 -> 6): the tight staircase permutation {0,1,2,3}.
        #expect(UI.allocateWidgets(6, [(10, 0), (20, 1), (30, 2), (40, 3)]) == [0, 1, 2, 3])
        // one below the floor: opposition waived, falls back to plain apportion (counts may tie).
        #expect(UI.allocateWidgets(5, [(10, 0), (10, 1), (10, 2), (10, 3)]) == [2, 1, 1, 1])
    }

    /// `budgetCells` over an 8×8 single frame with `n=16` yields 16 plots summing to 16 (spec golden).
    @Test func budgetCellsMatchesSpec() {
        let region = UI.Region(xLo: 0, xHi: 8, yLo: 0, yHi: 8, tLo: 0, tHi: 1)
        let ps = UI.budgetCells(demoWeight, region, 16)
        #expect(ps.count == 16)
        #expect(ps.reduce(0) { $0 + $1.cells } == 16)
    }

    // MARK: The laws (mirror Properties.V21FieldUI)

    /// `disagree` is zero on a spike, positive on spread (saliency twin of `lawHistUniformIsSpike`).
    @Test func disagreeZeroOnSpike() {
        #expect(UI.disagree([0, 0, 7, 0]) == 0)
        #expect(UI.disagree([3, 4, 0]) == 3)
        #expect(UI.disagree([5, 5]) == 5)
        #expect(UI.disagree([]) == 0)
    }

    /// `budgetCells` conserves: every cell lands in exactly one plot, over varied regions and budgets.
    @Test func budgetConserves() {
        for n in [0, 1, 5, 16, 64, 130] {
            for (w, h) in [(1, 1), (3, 5), (8, 8), (16, 9), (64, 64)] {
                let region = UI.Region(xLo: 0, xHi: w, yLo: 0, yHi: h, tLo: 0, tHi: 1)
                let ps = UI.budgetCells(demoWeight, region, n)
                #expect(ps.reduce(0) { $0 + $1.cells } == n)
                #expect(ps.allSatisfy { $0.region.aligned && $0.region.subRegionOf(region) && $0.cells > 0 })
            }
        }
    }

    /// THE OPPOSITION LAW: when the budget is feasible, the per-widget counts are pairwise distinct and
    /// sum to the total (even when saliencies tie, the Morton/index rank break makes them distinct).
    @Test func widgetsOpposeEqualCounts() {
        let cases: [(Int, [(sal: Int, morton: Int)])] = [
            (96, [(10, 0), (10, 1)]),                       // tied saliency, 2 widgets
            (50, [(30, 7), (30, 3), (30, 9)]),              // all tied, 3 widgets
            (200, [(5, 0), (90, 1), (40, 2), (40, 3)]),     // mixed, with a tie
            (15, [(1, 0), (2, 1), (3, 2), (4, 3), (5, 4), (6, 5)]),  // exactly k=6 floor
        ]
        for (total, ws) in cases {
            let counts = UI.allocateWidgets(total, ws)
            #expect(counts.reduce(0, +) == total)                 // partition
            #expect(Set(counts).count == counts.count)            // pairwise distinct
        }
    }

    /// Saliency orders the budget: the most uncertain widget owns the most cells.
    @Test func salienceOrdersBudget() {
        let c = UI.allocateWidgets(30, [(30, 0), (10, 1), (20, 2)])
        #expect(c[0] > c[2] && c[2] > c[1])
    }

    // MARK: helpers

    /// The spec's `demoWeight`: a Morton-varying region weight, so `budgetCells` splits non-uniformly.
    private func demoWeight(_ r: V21FieldUI.Region) -> Int {
        1 + (V21FieldUI.mortonKey(r.loCorner) % 7)
    }
}
