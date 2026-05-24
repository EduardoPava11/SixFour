import Foundation

/// Per-frame palette extraction primitive. Each conforming type
/// represents a single processing-model family (`ClusterStatistics.Family`)
/// for turning a 64×64 OKLab tile into a K-entry palette plus the
/// per-cluster statistics consumers need (Dither needs only the means,
/// editing tools need the covariances + counts + assignments).
///
/// All three first-class implementations (`KMeansExtractor`,
/// `WuExtractor`, `OctreeExtractor`) produce the same
/// `ClusterStatistics` shape regardless of how they got there. That
/// uniformity is the whole point: downstream code branches on data,
/// not on algorithm identity.
///
/// Threading: implementations are `Sendable` so they can be reused
/// across the burst (one extractor instance, 64 sequential or
/// concurrent calls). The GPU implementation serializes internally
/// via its command queue; CPU implementations are stateless aside
/// from optional scratch buffers, which they must guard themselves.
protocol PaletteExtractor: Sendable {
    /// Which processing-model family this extractor implements.
    /// Used by `ClusterStatistics.Provenance.family` and surfaced
    /// in the UI picker.
    var family: ClusterStatistics.Family { get }

    /// Produce `K` clusters + per-pixel assignments + provenance
    /// for one tile. K is always 256 in production (the GIF GCT
    /// max) but the parameter is kept for testability + the future
    /// per-edit "K=64 / 128 / 256" picker.
    ///
    /// Throws if the extractor cannot honor the input (e.g., GPU
    /// command-buffer failure for the K-means GPU implementation).
    /// Throwing here surfaces as a render error; the user sees
    /// `FailureView` with the underlying error description.
    func extract(tile: OKLabTile, K: Int) throws -> ClusterStatistics

    /// Batch variant — extracts statistics for every tile in `tiles`,
    /// returning a same-length array of `ClusterStatistics`. The
    /// default implementation iterates `extract(tile:K:)` per tile;
    /// the GPU-backed `KMeansExtractor` overrides this to dispatch
    /// all 64 tiles in one Metal command buffer (preserves the ~3 ms
    /// total burst budget vs. ~64 × command-buffer overhead).
    func extractBatch(tiles: [OKLabTile], K: Int) throws -> [ClusterStatistics]
}

extension PaletteExtractor {
    /// Default batch implementation — serial iteration. CPU
    /// extractors (Wu, Octree) pick this up unchanged; their
    /// per-tile cost is low enough that batching offers no win.
    /// GPU extractors override for command-buffer batching.
    func extractBatch(tiles: [OKLabTile], K: Int) throws -> [ClusterStatistics] {
        try tiles.map { try extract(tile: $0, K: K) }
    }
}
