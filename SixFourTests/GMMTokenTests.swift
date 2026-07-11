import Foundation
import Testing
import simd
@testable import SixFour

/// `Spec.GMM`'s token surface on the Swift twin (2026-07-11 link-ledger
/// wave 2): a palette is a Gaussian mixture, each component a fixed-width
/// 10-double token, weights a proper measure (sum 1).
struct GMMTokenTests {

    private var testProvenance: ClusterStatistics.Provenance {
        ClusterStatistics.Provenance(
            family: .iterativeKMeans,
            parameters: .kMeans(seed: .uniformStride, iterations: 0),
            extractMillis: 0, mse: 0)
    }

    @Test func tokenLayoutAndMixtureWeights() {
        var cov = matrix_identity_float3x3
        cov[1, 0] = 0.25   // σ_la (symmetric off-diagonal)
        let a = ClusterStatistics.Cluster(mean: SIMD3(0.5, -0.1, 0.2), covariance: cov, count: 30)
        let b = ClusterStatistics.Cluster(mean: SIMD3(0.9, 0.0, 0.0),
                                          covariance: matrix_identity_float3x3, count: 10)
        let stats = ClusterStatistics(clusters: [a, b], assignments: [], provenance: testProvenance)
        let tokens = GMMToken.tokens(from: stats)
        #expect(tokens.count == 2)
        #expect(tokens.allSatisfy { $0.count == GMMToken.dim })
        // Layout: [l, a, b, σll, σla, σlb, σaa, σab, σbb, w].
        #expect(tokens[0][0] == 0.5 && abs(tokens[0][4] - 0.25) < 1e-9)
        // Weights normalize to a proper mixture measure.
        #expect(abs(tokens[0][9] - 0.75) < 1e-12 && abs(tokens[1][9] - 0.25) < 1e-12)
        #expect(abs(tokens.reduce(0.0) { $0 + $1[9] } - 1.0) < 1e-12)
        // Empty mixture yields the empty token set, never NaNs.
        let empty = ClusterStatistics(clusters: [], assignments: [], provenance: testProvenance)
        #expect(GMMToken.tokens(from: empty).isEmpty)
    }
}
