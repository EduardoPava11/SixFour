import Foundation
import Testing
@testable import SixFour

/// `Spec.PaintOrderPrior`'s capture half (2026-07-11 link-ledger wave 2): the
/// paint surface must CARRY first-touch order, because the spec's keystone is
/// a permutation-pair property — identical budgets painted in swapped order
/// must rank swapped, which no magnitude-only reading can express.
struct PaintOrderPriorTests {

    @Test @MainActor func firstTouchOrderIsCarriedAndStable() {
        let model = NudgePaintModel()
        model.paint(x: 3, y: 1, z: 2, channel: 0, value: 5)
        model.paint(x: 8, y: 8, z: 8, channel: 2, value: 1)
        let a = NudgePaintModel.mortonIndex(x: 3, y: 1, z: 2)
        let b = NudgePaintModel.mortonIndex(x: 8, y: 8, z: 8)
        #expect(model.touchOrder == [a, b])
        #expect(model.touchRank(cell: a) == 0 && model.touchRank(cell: b) == 1)
        // Repainting (even another channel) never re-ranks; erasing never un-touches.
        model.paint(x: 3, y: 1, z: 2, channel: 4, value: 9)
        model.paint(x: 8, y: 8, z: 8, channel: 2, value: 0)
        #expect(model.touchOrder == [a, b])
        // A zero-value paint is not a touch.
        model.paint(x: 0, y: 0, z: 0, channel: 0, value: 0)
        #expect(model.touchOrder.count == 2)
        // Reset clears the order with the budgets.
        model.reset()
        #expect(model.touchOrder.isEmpty && model.touchRank(cell: a) == nil)
    }

    @Test @MainActor func permutationPairKeystoneIsExpressible() {
        // The spec's structural falsification of magnitude-only policies,
        // witnessed on the app model: [a,b] and [b,a] end with IDENTICAL
        // budgets but SWAPPED touch orders — the carrier distinguishes what
        // the magnitude field cannot.
        let ab = NudgePaintModel()
        ab.paint(x: 1, y: 0, z: 0, channel: 0, value: 3)
        ab.paint(x: 0, y: 1, z: 0, channel: 0, value: 3)
        let ba = NudgePaintModel()
        ba.paint(x: 0, y: 1, z: 0, channel: 0, value: 3)
        ba.paint(x: 1, y: 0, z: 0, channel: 0, value: 3)
        #expect(ab.budget == ba.budget)                    // magnitudes identical
        #expect(ab.touchOrder == ba.touchOrder.reversed()) // order swapped
        #expect(ab.touchOrder != ba.touchOrder)
    }
}
