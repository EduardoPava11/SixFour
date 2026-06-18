import Testing
@testable import SixFour

/// Gate for the preference-training kill-switch (`GLRM`, the Swift port of
/// `SixFour.Spec.GLRM`). The OLS summation order matches the spec, so the `Double`
/// arithmetic is bit-identical; these goldens were captured from the Haskell spec
/// via `cabal repl`. Pins `fit`/`shouldTrain`/`pairWeight` (debt
/// `glrm-wired-but-unused`).
struct GLRMGoldenTests {

    private let feats: [GLRM.Features] = [
        (0.1, 0.2, 0.3), (0.4, 0.5, 0.6), (0.7, 0.1, 0.9), (0.2, 0.8, 0.4), (0.9, 0.3, 0.1),
    ]

    /// OLS recovers an exactly-linear signal: `R² = 1`, train.
    @Test func recoversLinearSignal() {
        let beta = [1.0, 2.0, 3.0, 4.0]
        let samples = feats.map { f -> (GLRM.Features, Double) in
            (f, beta[0] + beta[1] * f.coverage + beta[2] * f.beauty + beta[3] * f.chromaSq)
        }
        guard let fit = GLRM.fit(samples) else { Issue.record("fit nil"); return }
        #expect(abs(fit.r2 - 1.0) < 1e-12)
        #expect(GLRM.shouldTrain(samples))
    }

    /// A noisy set reproduces the Haskell golden coefficients + R² byte-for-byte.
    @Test func noiseFitMatchesHaskellGolden() {
        let y = [0.3, 0.9, 0.1, 0.7, 0.5]
        let samples = zip(feats, y).map { ($0, $1) }
        guard let fit = GLRM.fit(samples) else { Issue.record("fit nil"); return }
        #expect(abs(fit.r2 - 0.6534381139489194) < 1e-12)
        let golden = [0.1359135559921422, 0.10098231827111936, 0.9390962671905687, -0.08526522593320264]
        #expect(fit.coeffs.count == golden.count)
        for (a, b) in zip(fit.coeffs, golden) { #expect(abs(a - b) < 1e-12) }
        #expect(GLRM.shouldTrain(samples)) // R² = 0.65 ≥ r2Floor
    }

    /// No signal blocks: identical feature rows (singular design) ⇒ `fit` nil ⇒
    /// `shouldTrain` false, however the outcomes vary.
    @Test func noVarianceDesignBlocks() {
        let f: GLRM.Features = (0.1, 0.2, 0.3)
        let samples: [(GLRM.Features, Double)] = [(f, 1), (f, 0), (f, 1), (f, 0), (f, 1)]
        #expect(GLRM.fit(samples) == nil)
        #expect(!GLRM.shouldTrain(samples))
    }

    /// Too-few-samples blocks (fewer than `nParams`).
    @Test func tooFewSamplesBlocks() {
        let samples: [(GLRM.Features, Double)] = [((0.1, 0.2, 0.3), 1), ((0.4, 0.5, 0.6), 0)]
        #expect(GLRM.fit(samples) == nil)
        #expect(!GLRM.shouldTrain(samples))
    }

    /// A degenerate (identical-embedding) pair carries zero training weight.
    @Test func pairWeightGatesDegeneratePairs() {
        #expect(GLRM.pairWeight([1, 2, 3], [1, 2, 3]) == 0)
        #expect(GLRM.pairWeight([1, 2, 3], [1, 2, 4]) == 1)
    }
}
