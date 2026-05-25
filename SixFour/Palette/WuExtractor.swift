import Foundation

/// `PaletteExtractor` adapter over `WuPalettePipeline` (GPU moment histogram +
/// CPU greedy core). Thin by design — the work + per-`palette-wu` logging live
/// in the pipeline. The pure-CPU correctness oracle is `WuReference`.
struct WuExtractor: PaletteExtractor {
    let pipeline: WuPalettePipeline

    var family: ClusterStatistics.Family { .recursiveBipartitionWu }

    func extract(tile: OKLabTile, K: Int) throws -> ClusterStatistics {
        let batch = try extractBatch(tiles: [tile], K: K)
        guard let single = batch.first else {
            throw WuPalettePipeline.WuPipelineError.commandFailed
        }
        return single
    }

    func extractBatch(tiles: [OKLabTile], K: Int) throws -> [ClusterStatistics] {
        try pipeline.extractBatch(tiles: tiles, K: K)
    }
}
