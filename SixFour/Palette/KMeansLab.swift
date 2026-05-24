import Foundation
import simd

/// Lloyd's algorithm in OKLab, generic over a concrete `DistanceMetric`.
///
/// Used only by the *organ-driven refinement* path — the default Stage A
/// runs entirely on the GPU (see `MetalPipeline.encodeKMeans` +
/// `Shaders.metal` k-means kernels) where the distance is hard-coded
/// Euclidean for speed. When a metric organ is loaded, this CPU path
/// re-runs Lloyd's starting from the GPU-computed centroids using the
/// organ's `LearnedPSDMetric`. Making `run` generic over `M: DistanceMetric`
/// (rather than `any DistanceMetric`) lets the compiler specialise the
/// inner loop per concrete metric — Euclidean and PSD both fall through
/// to SIMD-tight ~30 ns/call inner loops.
enum KMeansLab {

    struct Result: Sendable {
        let centroids: [SIMD3<Float>]
        let assignments: [UInt16]  // per-sample index into centroids
        let iterations: Int
        let finalShift: Float       // L2 movement summed across centroids last step
    }

    /// Run Lloyd's k-means on OKLab samples until convergence or `maxIterations`.
    /// `seeds.count` defines K. Generic over the metric type so the inner
    /// loop is monomorphised — no existential dispatch.
    static func run<M: DistanceMetric>(
        samples: [SIMD3<Float>],
        seeds: [SIMD3<Float>],
        metric: M,
        maxIterations: Int = 20,
        shiftTolerance: Float = 1e-5
    ) -> Result {
        let k = seeds.count
        precondition(k > 0 && k <= UInt16.max)
        var centroids = seeds
        var assignments = [UInt16](repeating: 0, count: samples.count)

        var sums = [SIMD3<Float>](repeating: .zero, count: k)
        var counts = [Int](repeating: 0, count: k)

        var lastShift: Float = .infinity
        var iter = 0
        while iter < maxIterations {
            // Assign.
            for i in 0..<samples.count {
                let s = samples[i]
                var bestK: Int = 0
                var bestD: Float = .infinity
                for j in 0..<k {
                    let d = metric.distanceSquared(s, centroids[j])
                    if d < bestD { bestD = d; bestK = j }
                }
                assignments[i] = UInt16(bestK)
            }

            // Update.
            for j in 0..<k { sums[j] = .zero; counts[j] = 0 }
            for i in 0..<samples.count {
                let j = Int(assignments[i])
                sums[j] += samples[i]
                counts[j] += 1
            }

            var shift: Float = 0
            for j in 0..<k {
                let new: SIMD3<Float>
                if counts[j] > 0 {
                    new = sums[j] / Float(counts[j])
                } else {
                    // Empty cluster: keep the old centroid (matches GPU kmeansFinalize).
                    new = centroids[j]
                }
                let d = new - centroids[j]
                shift += simd_dot(d, d)
                centroids[j] = new
            }

            iter += 1
            lastShift = shift
            if shift < shiftTolerance { break }
        }

        return Result(centroids: centroids, assignments: assignments, iterations: iter, finalShift: lastShift)
    }

    /// Default-metric overload that preserves the existing test API.
    /// Compiler specialises to `EuclideanOKLabMetric` automatically.
    static func run(
        samples: [SIMD3<Float>],
        seeds: [SIMD3<Float>],
        maxIterations: Int = 20,
        shiftTolerance: Float = 1e-5
    ) -> Result {
        run(samples: samples,
            seeds: seeds,
            metric: EuclideanOKLabMetric(),
            maxIterations: maxIterations,
            shiftTolerance: shiftTolerance)
    }
}
