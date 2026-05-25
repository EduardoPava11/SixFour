import Foundation

/// Pure-CPU Octree quantizer: the correctness oracle for `OctreePalettePipeline`
/// and the implementation the `ExtractorPropertyTests` validate. Runs the shared
/// `OctreeQuantizer` sequential core (insert + greedy merge → assignments), then
/// computes per-cluster stats on CPU — the same assignments the GPU pipeline
/// feeds to `octreeStatsKernel`.
struct OctreeReference: PaletteExtractor {
    var family: ClusterStatistics.Family { .hierarchicalOctree }

    func extract(tile: OKLabTile, K: Int) throws -> ClusterStatistics {
        let started = ContinuousClock().now
        let (assignments, _) = OctreeQuantizer.assign(pixels: tile.pixels, K: K)
        let (clusters, mse) = OctreeQuantizer.statsCPU(pixels: tile.pixels, assignments: assignments, K: K)
        let ms = Self.millis(ContinuousClock().now - started)
        return ClusterStatistics(
            clusters: clusters,
            assignments: assignments,
            provenance: ClusterStatistics.Provenance(
                family: .hierarchicalOctree,
                parameters: .octree(maxDepth: OctreeQuantizer.maxDepth),
                extractMillis: ms,
                mse: mse
            )
        )
    }

    static func millis(_ d: Duration) -> Int {
        let (s, attos) = d.components
        return Int(s) * 1_000 + Int(attos / 1_000_000_000_000_000)
    }
}
