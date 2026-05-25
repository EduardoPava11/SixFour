import Testing
import Foundation
import simd
@testable import SixFour

/// Property tests that hold for ANY PaletteExtractor implementation.
/// Validates the invariants every extractor's ClusterStatistics
/// output must satisfy, regardless of which processing-model family
/// produced it. Run for WuExtractor + OctreeExtractor here; the
/// GPU-backed KMeansExtractor's centroid math is already covered
/// by MetalKMeansTests.
struct ExtractorPropertyTests {

    /// A synthetic 64×64 OKLab tile built from K=12 well-separated
    /// "stamps." Designed so extractors have something to find:
    /// uniform images would collapse to one cluster regardless of
    /// algorithm and wouldn't test anything useful.
    private static func diverseTile(side: Int = 64) -> OKLabTile {
        let stamps: [SIMD3<Float>] = [
            SIMD3<Float>(0.10, -0.10,  0.05),
            SIMD3<Float>(0.20,  0.15, -0.05),
            SIMD3<Float>(0.30, -0.05,  0.15),
            SIMD3<Float>(0.40,  0.10, -0.10),
            SIMD3<Float>(0.50, -0.15,  0.10),
            SIMD3<Float>(0.55,  0.05, -0.15),
            SIMD3<Float>(0.60, -0.10,  0.20),
            SIMD3<Float>(0.65,  0.20, -0.05),
            SIMD3<Float>(0.70, -0.05,  0.05),
            SIMD3<Float>(0.75,  0.10,  0.10),
            SIMD3<Float>(0.80, -0.20,  0.00),
            SIMD3<Float>(0.85,  0.00, -0.20),
        ]
        var pixels = [SIMD3<Float>](repeating: .zero, count: side * side)
        for i in 0..<pixels.count {
            pixels[i] = stamps[i % stamps.count]
        }
        return OKLabTile(side: side, pixels: pixels, captureNanos: 0, palette: [], finalShift: 0)
    }

    /// Sum of per-cluster counts must equal the tile's pixel count.
    /// Every pixel is assigned to exactly one cluster.
    @Test func wuClusterCountSumEqualsPixels() throws {
        let tile = Self.diverseTile()
        let extractor = WuReference()
        let stats = try extractor.extract(tile: tile, K: 256)
        let total = stats.clusters.reduce(0) { $0 + Int($1.count) }
        #expect(total == tile.side * tile.side,
                "Wu: cluster-count sum \(total) != pixel count \(tile.side * tile.side)")
    }

    @Test func octreeClusterCountSumEqualsPixels() throws {
        let tile = Self.diverseTile()
        let extractor = OctreeReference()
        let stats = try extractor.extract(tile: tile, K: 256)
        let total = stats.clusters.reduce(0) { $0 + Int($1.count) }
        #expect(total == tile.side * tile.side,
                "Octree: cluster-count sum \(total) != pixel count \(tile.side * tile.side)")
    }

    /// Assignments array must have exactly pixel-count entries and
    /// every index must be in [0, K).
    @Test func wuAssignmentsAreInRange() throws {
        let tile = Self.diverseTile()
        let extractor = WuReference()
        let stats = try extractor.extract(tile: tile, K: 256)
        #expect(stats.assignments.count == tile.side * tile.side)
        for a in stats.assignments {
            #expect(a < 256, "Wu: assignment \(a) out of range [0, 256)")
        }
    }

    @Test func octreeAssignmentsAreInRange() throws {
        let tile = Self.diverseTile()
        let extractor = OctreeReference()
        let stats = try extractor.extract(tile: tile, K: 256)
        #expect(stats.assignments.count == tile.side * tile.side)
        for a in stats.assignments {
            #expect(a < 256, "Octree: assignment \(a) out of range [0, 256)")
        }
    }

    /// Per-cluster covariance must be PSD: trace ≥ 0 and determinant ≥ 0.
    /// For 3×3 symmetric Σ this is necessary (eigenvalues real ≥ 0).
    /// We skip empty clusters (count == 0) — their sentinel covariance
    /// is `matrix_identity_float3x3 * 1e-6` which is PSD by construction
    /// but the test asserts non-empty clusters specifically.
    @Test func wuCovariancesArePSD() throws {
        let tile = Self.diverseTile()
        let extractor = WuReference()
        let stats = try extractor.extract(tile: tile, K: 256)
        for (k, cluster) in stats.clusters.enumerated() where cluster.count > 0 {
            let s = cluster.covariance
            let trace = s[0, 0] + s[1, 1] + s[2, 2]
            #expect(trace >= -1e-5,
                    "Wu cluster \(k): trace=\(trace) should be ≥ 0 (Σ is PSD)")
            // simd_float3x3 determinant.
            let det = simd_determinant(s)
            #expect(det >= -1e-5,
                    "Wu cluster \(k): det=\(det) should be ≥ 0 (Σ is PSD)")
        }
    }

    @Test func octreeCovariancesArePSD() throws {
        let tile = Self.diverseTile()
        let extractor = OctreeReference()
        let stats = try extractor.extract(tile: tile, K: 256)
        for (k, cluster) in stats.clusters.enumerated() where cluster.count > 0 {
            let s = cluster.covariance
            let trace = s[0, 0] + s[1, 1] + s[2, 2]
            #expect(trace >= -1e-5,
                    "Octree cluster \(k): trace=\(trace) should be ≥ 0 (Σ is PSD)")
            let det = simd_determinant(s)
            #expect(det >= -1e-5,
                    "Octree cluster \(k): det=\(det) should be ≥ 0 (Σ is PSD)")
        }
    }

    /// MSE must be non-negative and finite. Lower bound 0 (perfect
    /// quantization on a single-color image); upper bound depends
    /// on the input but for our 12-stamp tile we expect << 1.0.
    @Test func wuMSEIsFinite() throws {
        let tile = Self.diverseTile()
        let extractor = WuReference()
        let stats = try extractor.extract(tile: tile, K: 256)
        #expect(stats.provenance.mse >= 0,
                "Wu MSE \(stats.provenance.mse) must be ≥ 0")
        #expect(stats.provenance.mse.isFinite,
                "Wu MSE \(stats.provenance.mse) must be finite")
    }

    @Test func octreeMSEIsFinite() throws {
        let tile = Self.diverseTile()
        let extractor = OctreeReference()
        let stats = try extractor.extract(tile: tile, K: 256)
        #expect(stats.provenance.mse >= 0,
                "Octree MSE \(stats.provenance.mse) must be ≥ 0")
        #expect(stats.provenance.mse.isFinite,
                "Octree MSE \(stats.provenance.mse) must be finite")
    }

    /// Provenance.family must match the extractor's reported family.
    @Test func provenanceFamilyMatchesExtractor() throws {
        let tile = Self.diverseTile()
        let wu = WuReference()
        let oct = OctreeReference()
        let ws = try wu.extract(tile: tile, K: 256)
        let os = try oct.extract(tile: tile, K: 256)
        #expect(ws.provenance.family == .recursiveBipartitionWu)
        #expect(os.provenance.family == .hierarchicalOctree)
    }

    /// Clusters list must have exactly K entries (padded with empty
    /// clusters if the extractor terminated early on a low-diversity
    /// input). Required for the GIF encoder which expects a 256-entry
    /// Local Color Table per frame.
    @Test func clustersAlwaysHaveKEntries() throws {
        let tile = Self.diverseTile()
        let wu = WuReference()
        let oct = OctreeReference()
        let ws = try wu.extract(tile: tile, K: 256)
        let os = try oct.extract(tile: tile, K: 256)
        #expect(ws.clusters.count == 256)
        #expect(os.clusters.count == 256)
    }
}
