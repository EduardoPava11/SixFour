import Foundation

/// GPU-backed iterative refinement (k-means / Lloyd) palette extractor.
///
/// Wraps the existing `MetalPipeline.runStageAKMeansBatch` GPU pipeline
/// behind the `PaletteExtractor` protocol so the rest of the app can
/// treat it interchangeably with future Wu and Octree implementations.
/// The GPU pipeline itself is unchanged: uniform-stride seed →
/// 15 Lloyd iterations → kmeansFinalizeStatsKernel → readback.
///
/// **Why this struct is thin** — all real work happens in the Metal
/// pipeline. This is the seam that lets the higher layer pick an
/// algorithm without knowing about Metal vs CPU implementations.
struct KMeansExtractor: PaletteExtractor {
    let pipeline: MetalPipeline

    var family: ClusterStatistics.Family { .iterativeKMeans }

    /// Per-tile path — wraps the batch path with a single-element
    /// array. For one tile the GPU command-buffer overhead dominates
    /// (~0.5 ms); call `extractBatch` for the full 64-frame burst
    /// to amortize.
    func extract(tile: OKLabTile, K: Int) throws -> ClusterStatistics {
        let batch = try extractBatch(tiles: [tile], K: K)
        guard let single = batch.first else {
            throw MetalPipeline.MetalPipelineError.commandFailed
        }
        return single
    }

    /// Batch path — single Metal command buffer containing all 64
    /// tiles' k-means + covariance kernels. Returns one
    /// `ClusterStatistics` per input tile, in the same order.
    /// Memory: 64 × (centroids ~4 KB + bins ~10 KB + assignments
    /// 8 KB + covariances ~6 KB) ≈ 1.8 MB scratch, allocated once
    /// per burst and released when the command buffer completes.
    func extractBatch(tiles: [OKLabTile], K: Int) throws -> [ClusterStatistics] {
        // K is currently fixed at the pipeline's kMeansK setting
        // (256 by default). The protocol takes K for testability +
        // the future "K = 64 / 128 / 256" UI picker; until that
        // ships we forward to the pipeline as-is.
        precondition(K == pipeline.kMeansK,
                     "KMeansExtractor: K=\(K) doesn't match pipeline.kMeansK=\(pipeline.kMeansK). " +
                     "Reconstruct MetalPipeline with the new K to change palette size.")
        return try pipeline.runStageAKMeansBatch(tiles: tiles)
    }
}
