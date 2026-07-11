import Foundation
import simd

/// The continuous OKLab Gaussian-mixture substrate — the look-NN's input,
/// hand-written twin of `SixFour.Spec.GMM` (promoted by the 2026-07-11 link
/// ledger, wave 2). A frame palette is a 256-component Gaussian mixture
/// (μ, Σ, w per cluster) — exactly the (mean, covariance, count) the device
/// already computes in `ClusterStatistics` but never assembled as a model
/// input surface. Each component becomes a fixed-width 10-double token:
/// [l, a, b, σll, σla, σlb, σaa, σab, σbb, w] (mean, the symmetric
/// covariance's upper triangle, weight) — the set-encoder row.
enum GMMToken {

    /// The fixed token width (`Spec.GMM.gmmTokenDim`).
    static let dim = 10

    /// One cluster → one token: mean, upper-triangle covariance, weight.
    static func token(mean: SIMD3<Float>, covariance: simd_float3x3, weight: Double) -> [Double] {
        [Double(mean.x), Double(mean.y), Double(mean.z),
         Double(covariance[0, 0]), Double(covariance[1, 0]), Double(covariance[2, 0]),
         Double(covariance[1, 1]), Double(covariance[2, 1]),
         Double(covariance[2, 2]),
         weight]
    }

    /// A frame's whole mixture as the token set the look-NN consumes:
    /// weights are the clusters' pixel counts normalized to sum 1 (a proper
    /// mixture measure); empty frames yield an empty set.
    static func tokens(from stats: ClusterStatistics) -> [[Double]] {
        let total = stats.clusters.reduce(0.0) { $0 + Double($1.count) }
        guard total > 0 else { return [] }
        return stats.clusters.map {
            token(mean: $0.mean, covariance: $0.covariance,
                  weight: Double($0.count) / total)
        }
    }
}
