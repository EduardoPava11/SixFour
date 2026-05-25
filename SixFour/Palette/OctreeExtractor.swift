import Foundation

/// `PaletteExtractor` adapter over `OctreePalettePipeline` (CPU insert+merge +
/// GPU per-cluster stats). Thin by design — the work + per-`palette-octree`
/// logging live in the pipeline. The pure-CPU correctness oracle is
/// `OctreeReference`.
struct OctreeExtractor: PaletteExtractor {
    let pipeline: OctreePalettePipeline

    var family: ClusterStatistics.Family { .hierarchicalOctree }

    func extract(tile: OKLabTile, K: Int) throws -> ClusterStatistics {
        let batch = try extractBatch(tiles: [tile], K: K)
        guard let single = batch.first else {
            throw OctreePalettePipeline.OctreePipelineError.commandFailed
        }
        return single
    }

    func extractBatch(tiles: [OKLabTile], K: Int) throws -> [ClusterStatistics] {
        try pipeline.extractBatch(tiles: tiles, K: K)
    }
}
