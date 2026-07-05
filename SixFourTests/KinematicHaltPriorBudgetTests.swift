import Testing
@testable import SixFour

/// A1 — the KinematicHaltPrior KEYSTONE wired as a runtime training budget
/// (`lawCheapestZeroLossHaltIsCertifiedOrder`). The per-slot certified-order
/// vector from `ColorHead.haltFloor()` is not a scalar telemetry count; it is
/// the halting depth that decides whether the S_t yang head has residual worth
/// fitting. These gate tests pin that decision on synthetic order vectors, no
/// camera required (the functions are pure + static).
struct KinematicHaltPriorBudgetTests {

    @Test func budgetIsMaxCertifiedOrder() {
        #expect(ColorHead.haltingDepthBudget([0, 1, 2, 1, 0]) == 2)
        #expect(ColorHead.haltingDepthBudget([3, 1, 2]) == 3)
    }

    @Test func notYetCertifiableSlotsAreIgnored() {
        // -1 = window too short to falsify; must not poison the max.
        #expect(ColorHead.haltingDepthBudget([-1, -1, 1]) == 1)
        #expect(ColorHead.haltingDepthBudget([-1, -1, -1]) == -1)
        #expect(ColorHead.haltingDepthBudget([]) == -1)
    }

    @Test func staticOrConstantVelocitySceneSkipsTraining() {
        // Order 0 (static) and order 1 (constant velocity) are shipped EXACTLY
        // by the kinematic floor + bias — the head has nothing to learn.
        #expect(ColorHead.residualNeedsLearning([0, 0, 0]) == false)
        #expect(ColorHead.residualNeedsLearning([1, 0, 1]) == false)
        #expect(ColorHead.residualNeedsLearning([-1, -1]) == false)   // nothing certifies
    }

    @Test func accelerationAndAboveNeedsLearning() {
        // Order ≥ 2 = spatially-conditional t-band structure beyond the bias.
        #expect(ColorHead.residualNeedsLearning([0, 1, 2]) == true)
        #expect(ColorHead.residualNeedsLearning([2, 2, 2]) == true)
        #expect(ColorHead.residualNeedsLearning([-1, 3, 0]) == true)
    }
}
