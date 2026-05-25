import Foundation

/// `PaletteExtractor` adapter over `KMeansPalettePipeline` (all-GPU Lloyd
/// k-means). Thin by design — the GPU work + per-`palette-kmeans` logging live
/// in the pipeline; this struct just satisfies the protocol the renderer
/// consumes, mirroring the Wu/Octree extractor→pipeline split.
struct KMeansExtractor: PaletteExtractor {
    let pipeline: KMeansPalettePipeline

    var family: ClusterStatistics.Family { .iterativeKMeans }

    /// Per-tile path — wraps the batch path with a single-element array. For
    /// one tile the GPU command-buffer overhead dominates (~0.5 ms); call
    /// `extractBatch` for the full 64-frame burst to amortize.
    func extract(tile: OKLabTile, K: Int) throws -> ClusterStatistics {
        let batch = try extractBatch(tiles: [tile], K: K)
        guard let single = batch.first else {
            throw KMeansPalettePipeline.KMeansPipelineError.commandFailed
        }
        return single
    }

    /// Batch path — one Metal command buffer for all tiles. The K-matches-
    /// pipeline precondition lives inside `KMeansPalettePipeline.extractBatch`.
    func extractBatch(tiles: [OKLabTile], K: Int) throws -> [ClusterStatistics] {
        try pipeline.extractBatch(tiles: tiles, K: K)
    }
}
