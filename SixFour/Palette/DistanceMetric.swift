import Foundation
import simd

/// Pluggable distance function over OKLab triplets.
/// Implementations: `EuclideanOKLabMetric` (default), `LearnedPSDMetric` (organ).
/// Implementations must be value-semantic and Sendable — k-means may call them on any thread.
protocol DistanceMetric: Sendable {
    /// Squared distance only — k-means inner loop never takes sqrt.
    func distanceSquared(_ a: SIMD3<Float>, _ b: SIMD3<Float>) -> Float
}

struct EuclideanOKLabMetric: DistanceMetric {
    @inline(__always)
    func distanceSquared(_ a: SIMD3<Float>, _ b: SIMD3<Float>) -> Float {
        let d = a - b
        return simd_dot(d, d)
    }
}

/// Learned positive-semidefinite metric: d²(a, b) = (a-b)ᵀ M (a-b), where M = LLᵀ.
/// The 9 stored floats are the row-major upper triangle of M.
/// Falls back to Euclidean when m is identity.
struct LearnedPSDMetric: DistanceMetric {
    let m00: Float, m01: Float, m02: Float
    let m11: Float, m12: Float
    let m22: Float

    init(matrix: simd_float3x3) {
        m00 = matrix[0, 0]; m01 = matrix[0, 1]; m02 = matrix[0, 2]
        m11 = matrix[1, 1]; m12 = matrix[1, 2]
        m22 = matrix[2, 2]
    }

    @inline(__always)
    func distanceSquared(_ a: SIMD3<Float>, _ b: SIMD3<Float>) -> Float {
        let d = a - b
        let mdx = m00 * d.x + m01 * d.y + m02 * d.z
        let mdy = m01 * d.x + m11 * d.y + m12 * d.z
        let mdz = m02 * d.x + m12 * d.y + m22 * d.z
        return d.x * mdx + d.y * mdy + d.z * mdz
    }
}
