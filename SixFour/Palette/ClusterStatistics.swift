import Foundation
import simd

/// Per-frame palette extraction output. Produced by any conforming
/// `PaletteExtractor` (K-means GPU, Wu CPU, Octree CPU). All three
/// implementations write the same fields so downstream consumers
/// (Dither, GIFRenderer, future editing tools) don't branch on which
/// algorithm produced them.
///
/// The structure is designed for two consumer paths:
///
/// 1. **GIF encoder path** (today): only `clusters[k].mean` is read
///    via `OKLabTile.palette` for dither + LZW. The rest of the
///    fields are inert from the encoder's perspective.
/// 2. **Editing tool path** (deferred PR): consumes the rich
///    `(mean, covariance, count)` per cluster to χ²-test
///    significance (Fahmy App B–C), prune near-duplicate centroids
///    (multicollinearity, Ch 6), split high-variance clusters along
///    the principal eigenvector, or re-quantize under a
///    Mahalanobis-weighted metric. None of these consumers exist
///    yet; this type is the contract they'll bind against.
struct ClusterStatistics: Sendable, Codable {
    /// Per-cluster moments. Length == K (256 by default). Index k in
    /// this array corresponds to palette index k in the GIF.
    let clusters: [Cluster]

    /// Per-pixel cluster assignment, row-major in tile coords.
    /// Length == tile.side × tile.side (4096 for the standard 64×64
    /// tile). Each entry is the index into `clusters` that the pixel
    /// belongs to. Useful for editing tools that want to invert the
    /// quantization (which pixels share a cluster), and for computing
    /// MSE downstream without re-running the extractor.
    let assignments: [UInt16]

    /// Which algorithm produced these stats + with what parameters.
    /// Serialized for future archival (Codable) so editing tools can
    /// re-run extraction deterministically.
    let provenance: Provenance

    /// Per-cluster (mean, covariance, count). Empty clusters
    /// (count == 0) carry an identity-scaled covariance to keep
    /// consumers numerically safe; consumers MUST check `count > 0`
    /// before treating the moments as meaningful.
    ///
    /// Custom Codable because `simd_float3x3` isn't Codable. We
    /// flatten Σ to 6 floats (upper triangle: LL, La, Lb, aa, ab, bb)
    /// since the matrix is symmetric — same convention used in
    /// `kmeansFinalizeStatsKernel`'s GPU output. Halves the
    /// serialized size vs. storing all 9 floats.
    struct Cluster: Sendable, Codable {
        /// OKLab centroid; equivalent to `OKLabTile.palette[k]`.
        let mean: SIMD3<Float>
        /// Sample covariance Σ = E[xxᵀ] − μμᵀ over the assigned
        /// pixels. Always PSD by construction; eigendecomposable
        /// via the closed-form solver in ClusterStatisticsOps.
        /// Convention for empty clusters: `matrix_identity_float3x3 * 1e-6`.
        let covariance: simd_float3x3
        /// Number of pixels assigned to this cluster. Sum over all
        /// clusters equals `assignments.count` (the tile pixel count).
        let count: UInt32

        private enum CodingKeys: String, CodingKey {
            case mean, sigmaLL, sigmaLa, sigmaLb, sigmaaa, sigmaab, sigmabb, count
        }

        init(mean: SIMD3<Float>, covariance: simd_float3x3, count: UInt32) {
            self.mean = mean
            self.covariance = covariance
            self.count = count
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            self.mean = try c.decode(SIMD3<Float>.self, forKey: .mean)
            self.count = try c.decode(UInt32.self, forKey: .count)
            let LL = try c.decode(Float.self, forKey: .sigmaLL)
            let La = try c.decode(Float.self, forKey: .sigmaLa)
            let Lb = try c.decode(Float.self, forKey: .sigmaLb)
            let aa = try c.decode(Float.self, forKey: .sigmaaa)
            let ab = try c.decode(Float.self, forKey: .sigmaab)
            let bb = try c.decode(Float.self, forKey: .sigmabb)
            self.covariance = simd_float3x3(
                columns: (
                    SIMD3<Float>(LL, La, Lb),
                    SIMD3<Float>(La, aa, ab),
                    SIMD3<Float>(Lb, ab, bb)
                )
            )
        }

        func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(mean, forKey: .mean)
            try c.encode(count, forKey: .count)
            try c.encode(covariance[0, 0], forKey: .sigmaLL)
            try c.encode(covariance[0, 1], forKey: .sigmaLa)
            try c.encode(covariance[0, 2], forKey: .sigmaLb)
            try c.encode(covariance[1, 1], forKey: .sigmaaa)
            try c.encode(covariance[1, 2], forKey: .sigmaab)
            try c.encode(covariance[2, 2], forKey: .sigmabb)
        }
    }

    /// Algorithm metadata. Codable + Hashable so editing tools can
    /// uniquely identify an extraction and cache results.
    struct Provenance: Sendable, Codable, Hashable {
        /// Which processing-model family produced these stats.
        let family: Family
        /// Family-specific knobs (seed strategy, depth, iters, etc.).
        let parameters: Parameters
        /// Wall-clock time to produce these stats. Diagnostic only;
        /// not used to gate behavior.
        let extractMillis: Int
        /// Mean squared error in OKLab units²:
        ///   `Σ_i ‖tile.pixels[i] − clusters[assignments[i]].mean‖² / nPixels`
        /// Lower = tighter quantization. Surfaced in
        /// `StatsFooterView` so the user can compare algorithms on
        /// the same scene.
        let mse: Float
    }

    /// Genuinely distinct processing models. Each is a stand-in for
    /// a broader family (e.g., median-cut would also be
    /// `.recursiveBipartitionWu` if we ever added it — the family
    /// name describes the mechanism, not the specific algorithm).
    enum Family: String, Sendable, Codable, Hashable {
        /// Iterative refinement: seed K centroids, iterate Lloyd
        /// until convergence. Representative: K-means (today's default).
        case iterativeKMeans
        /// Recursive bipartition: split the densest/highest-variance
        /// region recursively until K clusters. Representative: Wu
        /// (1992) — variance-based, uses covariance eigenvector for
        /// the split direction.
        case recursiveBipartitionWu
        /// Hierarchical merging: build tree of all colors, merge
        /// similar leaves until K. Representative: Octree (1988).
        case hierarchicalOctree
    }

    /// Family-specific parameters. Each case carries the knobs
    /// relevant to that family — none cross between families.
    /// `Codable` synthesis works because all payload types are Codable.
    enum Parameters: Sendable, Codable, Hashable {
        case kMeans(seed: KMeansSeed, iterations: Int)
        case wu(histogramBinsPerAxis: Int)
        case octree(maxDepth: Int)

        enum KMeansSeed: String, Sendable, Codable, Hashable {
            /// `(k * stride) % pixels` — what shipped before this plan.
            case uniformStride
            /// D²-weighted probability sampling (Arthur & Vassilvitskii
            /// 2007). Better initial centroids; same Lloyd loop after.
            case kMeansPP
        }
    }
}

extension ClusterStatistics.Cluster {
    /// Empty-cluster sentinel covariance (tiny isotropic). Documented
    /// at the type level: consumers MUST check `count > 0`.
    static let emptyCovariance = simd_float3x3(diagonal: SIMD3<Float>(repeating: 1e-6))
}
