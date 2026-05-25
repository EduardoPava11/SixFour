/// The set of palette-extraction pipelines, one per algorithm family. Created
/// once at bootstrap (`CaptureViewModel`) and handed to `GIFRenderer`;
/// `Composition.makeExtractor(engines:)` picks the right one for the user's
/// chosen `ExtractorChoice`.
///
struct PaletteEngines: Sendable {
    let kMeans: KMeansPalettePipeline
    let wu: WuPalettePipeline
    let octree: OctreePalettePipeline
}
