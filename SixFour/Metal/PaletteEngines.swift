/// The palette-extraction pipeline. Created once at bootstrap
/// (`CaptureViewModel`) and handed to `GIFRenderer`.
///
/// There is now a single extraction algorithm — Wu-initialized k-means
/// (`KMeansPalettePipeline` with `seed = .wuInit`), the color-quantization
/// literature's quality leader (Celebi 2011). The former per-algorithm choice
/// (Wu / Octree as standalone options) was collapsed: exposing strictly
/// higher-error quantizers in a quality-first product was a UX anti-pattern.
/// Wu lives on only as the k-means seeder (`KMeansPalettePipeline.wuSeedCentroids`).
struct PaletteEngines: Sendable {
    let kMeans: KMeansPalettePipeline
}
