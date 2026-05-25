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
    /// GPU blue-noise assignment, used when the dither method is `.blueNoise`.
    /// Optional so the app still runs if the pipeline fails to build (falls
    /// back to the CPU blue-noise path).
    let blueNoise: BlueNoisePalettePipeline?
}
