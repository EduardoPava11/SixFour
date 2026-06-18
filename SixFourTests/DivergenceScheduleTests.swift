import Testing
@testable import SixFour

/// The Swift `DivergenceSchedule` port must satisfy the same laws as
/// `SixFour.Spec.DivergenceSchedule` (CI-proven in `Properties.DivergenceSchedule`). Double-valued
/// search guidance, so the contract is the LAWS (not a byte golden); equality laws use 1e-9.
struct DivergenceScheduleTests {
    private let s = DivergenceSchedule.default
    private let ns = [0, 1, 2, 5, 8, 20, 100, 1000]

    @Test func startsWide() {
        #expect(abs(s.divergence(0) - s.deltaMax) < 1e-9)
    }

    @Test func monotoneNonIncreasing() {
        for n in ns { #expect(s.divergence(n + 1) <= s.divergence(n)) }
    }

    @Test func boundedBelow() {
        for n in ns { #expect(s.divergence(n) >= s.deltaMin) }
    }

    @Test func ratiosStraddleCenter() {
        for n in ns {
            #expect(s.ratioB(n) <= s.ratioCenter)
            #expect(s.ratioCenter <= s.ratioA(n))
        }
    }

    @Test func gapIsDivergence() {
        for n in ns { #expect(abs((s.ratioA(n) - s.ratioB(n)) - s.divergence(n)) < 1e-9) }
    }

    @Test func ratiosStayInUnit() {
        for n in ns {
            #expect(s.ratioB(n) >= 0)
            #expect(s.ratioA(n) <= 1)
        }
    }
}
