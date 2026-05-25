import Foundation

/// A per-frame palette-extraction pipeline. One concrete pipeline per
/// algorithm family — `KMeansPalettePipeline` (all-GPU), `WuPalettePipeline`
/// and `OctreePalettePipeline` (GPU parallel stages + CPU greedy core). Each
/// owns its own `GPUContext` (labeled queue) and `os.Logger`, so its GPU work
/// and timings can be attributed and debugged independently.
///
/// Mirrors the producing half of `PaletteExtractor`; the thin `…Extractor`
/// structs adapt a pipeline to the `PaletteExtractor` protocol that
/// `Composition.makeExtractor` and `GIFRenderer` consume.
protocol PalettePipeline: AnyObject, Sendable {
    /// Which processing-model family this pipeline implements.
    var family: ClusterStatistics.Family { get }

    /// Extract one `ClusterStatistics` per input tile (256 clusters each),
    /// in the same order. Throws on GPU command-buffer failure.
    func extractBatch(tiles: [OKLabTile], K: Int) throws -> [ClusterStatistics]
}
