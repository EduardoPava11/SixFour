import Testing
import simd
@testable import SixFour

/// Properties of the inner k-means loop. KMeansLab is pure (no actor, no
/// randomness — seeds are caller-supplied), so all tests are deterministic.
struct KMeansLabTests {

    /// Same samples + seeds → same centroids. Cheap regression gate against
    /// future refactors that might introduce ordering bugs in the assign /
    /// update steps.
    @Test func determinismOnFixedFixture() {
        let samples = gradientSamples(count: 400)
        let seeds = Array(samples.prefix(8))
        let r1 = KMeansLab.run(samples: samples, seeds: seeds, maxIterations: 10)
        let r2 = KMeansLab.run(samples: samples, seeds: seeds, maxIterations: 10)
        #expect(r1.centroids == r2.centroids)
        #expect(r1.assignments == r2.assignments)
    }

    /// Centroid count equals seed count, never deviates. Empty clusters keep
    /// the old centroid rather than collapse the array.
    @Test func centroidCountMatchesSeedCount() {
        let samples = gradientSamples(count: 50)
        // Deliberately oversubscribe k > distinct sample colors.
        let seeds = Array(samples.prefix(16))
        let result = KMeansLab.run(samples: samples, seeds: seeds, maxIterations: 5)
        #expect(result.centroids.count == 16)
        #expect(result.assignments.count == 50)
    }

    /// Convergence shrinks the inter-iteration shift to ≤ tolerance OR uses
    /// all iterations. Either way `iterations` ≤ `maxIterations`.
    @Test func convergesWithinIterationBudget() {
        let samples = gradientSamples(count: 200)
        let seeds = Array(samples.prefix(4))
        let result = KMeansLab.run(
            samples: samples, seeds: seeds, maxIterations: 20, shiftTolerance: 1e-5
        )
        #expect(result.iterations <= 20)
        if result.iterations < 20 {
            #expect(result.finalShift < 1e-5,
                    "early-stopped at iter \(result.iterations) but finalShift=\(result.finalShift)")
        }
    }

    /// Every assignment indexes a real centroid.
    @Test func assignmentsAreInRange() {
        let samples = gradientSamples(count: 100)
        let seeds = Array(samples.prefix(7))
        let result = KMeansLab.run(samples: samples, seeds: seeds, maxIterations: 5)
        for a in result.assignments {
            #expect(Int(a) < result.centroids.count)
        }
    }

    /// Synthetic data: a 1D OKLab L-channel gradient — predictable + easy
    /// to eyeball if a test ever flakes.
    private func gradientSamples(count: Int) -> [SIMD3<Float>] {
        (0..<count).map { i in
            let t = Float(i) / Float(count - 1)
            return SIMD3<Float>(t, 0, 0)
        }
    }
}
