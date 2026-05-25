import Testing
import Foundation
import simd
@testable import SixFour

/// Property tests for the `PaletteExtractor` invariants every extractor's
/// `ClusterStatistics` output must satisfy. After the algorithm collapse there
/// is one extractor — Wu-initialized k-means (`KMeansExtractor`) — so these run
/// against it. (Centroid *parity* + the Wu+KM seed are covered separately in
/// `MetalKMeansTests`; this file pins the structural invariants the GIF encoder
/// and editing tools rely on.)
struct ExtractorPropertyTests {

    /// A synthetic 64×64 OKLab tile from 12 well-separated "stamps", so the
    /// extractor has distinct clusters to find (a uniform image would collapse
    /// to one cluster and test nothing).
    private static func diverseTile(side: Int = 64) -> OKLabTile {
        let stamps: [SIMD3<Float>] = [
            SIMD3<Float>(0.10, -0.10,  0.05), SIMD3<Float>(0.20,  0.15, -0.05),
            SIMD3<Float>(0.30, -0.05,  0.15), SIMD3<Float>(0.40,  0.10, -0.10),
            SIMD3<Float>(0.50, -0.15,  0.10), SIMD3<Float>(0.55,  0.05, -0.15),
            SIMD3<Float>(0.60, -0.10,  0.20), SIMD3<Float>(0.65,  0.20, -0.05),
            SIMD3<Float>(0.70, -0.05,  0.05), SIMD3<Float>(0.75,  0.10,  0.10),
            SIMD3<Float>(0.80, -0.20,  0.00), SIMD3<Float>(0.85,  0.00, -0.20),
        ]
        var pixels = [SIMD3<Float>](repeating: .zero, count: side * side)
        for i in 0..<pixels.count { pixels[i] = stamps[i % stamps.count] }
        return OKLabTile(side: side, pixels: pixels, captureNanos: 0, palette: [], finalShift: 0)
    }

    @MainActor
    private func extract() throws -> ClusterStatistics {
        let extractor = KMeansExtractor(pipeline: try KMeansPalettePipeline(tileSide: 64))
        return try extractor.extract(tile: Self.diverseTile(), K: 256)
    }

    /// Every pixel is assigned to exactly one cluster.
    @MainActor
    @Test func clusterCountSumEqualsPixels() throws {
        let stats = try extract()
        let total = stats.clusters.reduce(0) { $0 + Int($1.count) }
        #expect(total == 64 * 64, "cluster-count sum \(total) != pixel count \(64 * 64)")
    }

    /// Assignments array has one entry per pixel, each index in [0, K).
    @MainActor
    @Test func assignmentsAreInRange() throws {
        let stats = try extract()
        #expect(stats.assignments.count == 64 * 64)
        for a in stats.assignments { #expect(a < 256, "assignment \(a) out of range") }
    }

    /// Per-cluster covariance must be PSD (trace ≥ 0, det ≥ 0). Empty clusters
    /// carry a PSD sentinel; we assert on non-empty ones specifically.
    @MainActor
    @Test func covariancesArePSD() throws {
        let stats = try extract()
        for (k, cluster) in stats.clusters.enumerated() where cluster.count > 0 {
            let s = cluster.covariance
            let trace = s[0, 0] + s[1, 1] + s[2, 2]
            #expect(trace >= -1e-5, "cluster \(k): trace=\(trace) should be ≥ 0")
            #expect(simd_determinant(s) >= -1e-5, "cluster \(k): det should be ≥ 0")
        }
    }

    /// MSE must be non-negative and finite.
    @MainActor
    @Test func mseIsFinite() throws {
        let stats = try extract()
        #expect(stats.provenance.mse >= 0)
        #expect(stats.provenance.mse.isFinite)
    }

    /// The sole extractor reports the iterative-k-means family.
    @MainActor
    @Test func provenanceFamilyIsKMeans() throws {
        #expect(try extract().provenance.family == .iterativeKMeans)
    }

    /// Clusters list always has exactly K entries (padded with empties on
    /// low-diversity input) — the GIF encoder needs a 256-entry table per frame.
    @MainActor
    @Test func clustersAlwaysHaveKEntries() throws {
        #expect(try extract().clusters.count == 256)
    }
}
