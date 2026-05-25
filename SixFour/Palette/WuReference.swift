import Foundation

/// Pure-CPU Wu quantizer: the correctness oracle for `WuPalettePipeline` and
/// the implementation the `ExtractorPropertyTests` validate. Builds the
/// 10-moment histogram on CPU, then runs the shared `WuQuantizer` core (the
/// exact same code the GPU pipeline uses after its histogram).
struct WuReference: PaletteExtractor {
    var family: ClusterStatistics.Family { .recursiveBipartitionWu }

    func extract(tile: OKLabTile, K: Int) throws -> ClusterStatistics {
        let started = ContinuousClock().now
        let histogram = WuQuantizer.buildHistogramCPU(pixels: tile.pixels)
        let r = WuQuantizer.quantize(histogram, pixels: tile.pixels, K: K)
        let ms = Self.millis(ContinuousClock().now - started)
        return ClusterStatistics(
            clusters: r.clusters,
            assignments: r.assignments,
            provenance: ClusterStatistics.Provenance(
                family: .recursiveBipartitionWu,
                parameters: .wu(histogramBinsPerAxis: WuQuantizer.binsPerAxis),
                extractMillis: ms,
                mse: r.mse
            )
        )
    }

    static func millis(_ d: Duration) -> Int {
        let (s, attos) = d.components
        return Int(s) * 1_000 + Int(attos / 1_000_000_000_000_000)
    }
}
