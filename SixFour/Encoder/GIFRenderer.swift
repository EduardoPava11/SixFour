import Foundation
import simd
import os

/// End-to-end orchestrator: OKLab tiles (without palettes yet) +
/// composition → .gif on disk.
///
/// Pipeline (see `spec/MATH.md` for the framework):
///   1. Resolve the optional metric organ from the composition.
///   2. `composition.makeExtractor(engines:).extractBatch(tiles:)` — per-frame
///      palette extraction via the chosen algorithm's `PalettePipeline`
///      (K-means GPU / Wu / Octree), on all 64 tiles after the burst is done
///      (per the no-fallback / device-stability fix; folding GPU work into
///      `submitAsync` caused frame drops).
///   3. `PaletteGenerator.generate(tiles)` — CPU refine + dither + strict
///      per-frame surjectivity rescue (every frame ends up using all 256
///      colours → a complete 64×64×64 voxel volume).
///   4. Convert OKLab → sRGB UInt8.
///   5. Encode GIF89a with per-frame Local Color Tables, gated on a
///      `CompleteVoxelVolume`.
struct GIFRenderer {
    static let logger = Logger(subsystem: "com.sixfour.SixFour", category: "renderer")

    /// Coarse stage label for the UI's phase banner.
    enum RenderPhase: Sendable, Equatable {
        case stageA   // per-frame extraction + CPU refine+dither+rescue
        case encode   // GIF89a emit + disk write
    }

    /// Metadata returned by `render(...)`. Consumed by `CaptureOutput`.
    struct Report: Sendable {
        let stageAMillis: Int
        let encodeMillis: Int
        let totalMillis: Int
        let fileSize: Int
        /// sRGB palette stack for the UI's PaletteStripView.
        let palettesForDisplay: [[SIMD3<UInt8>]]
        /// Per-frame extraction MSE in OKLab units² — the universal
        /// quality metric for comparing extractors on the same scene.
        /// Lower = tighter quantization. We surface the mean across
        /// frames here; per-frame values live in
        /// `perFrameStatistics[i].provenance.mse`.
        let meanExtractMSE: Float
        /// 64 ClusterStatistics, one per tile. The CaptureViewModel
        /// stitches this into a CaptureBundle for downstream editing
        /// tools (re-run extraction, χ²-significance tests, etc.).
        let perFrameStatistics: [ClusterStatistics]
    }

    let composition: Composition
    let store: GeneStore
    let engines: PaletteEngines

    init(composition: Composition, store: GeneStore, engines: PaletteEngines) {
        self.composition = composition
        self.store = store
        self.engines = engines
    }

    func render(
        tiles: [OKLabTile],
        to url: URL,
        fps: Int = 20,
        onPhase: (@Sendable (RenderPhase) -> Void)? = nil
    ) async throws -> Report {
        precondition(!tiles.isEmpty)

        // Resolve optional learned metric organ.
        var refinementMetric: LearnedPSDMetric? = nil
        if let hash = composition.metric, let mo = await store.loadMetric(named: hash) {
            refinementMetric = mo.metric
        }

        onPhase?(.stageA)
        // Per-frame palette extraction via the PaletteExtractor
        // protocol. composition.makeExtractor dispatches on the
        // user's pick (K-means / Wu / Octree); the result is
        // `[ClusterStatistics]` (one per tile) carrying per-cluster
        // (μ, Σ, count) + per-pixel assignment + provenance. We
        // stitch the centroids back into each OKLabTile.palette for
        // downstream Dither + encoder back-compat; the rich
        // statistics flow through Report.perFrameStatistics so
        // CaptureViewModel can build a CaptureBundle for editing
        // tools.
        let extractor = composition.makeExtractor(engines: engines)
        let perFrameStats = try extractor.extractBatch(tiles: tiles, K: SixFourShape.K)
        let tilesWithPalettes: [OKLabTile] = zip(tiles, perFrameStats).map { tile, stats in
            OKLabTile(
                side: tile.side,
                pixels: tile.pixels,
                captureNanos: tile.captureNanos,
                palette: stats.clusters.map { $0.mean },
                finalShift: 0
            )
        }
        let meanExtractMSE: Float = {
            let sum = perFrameStats.reduce(Float(0)) { $0 + $1.provenance.mse }
            return sum / Float(max(1, perFrameStats.count))
        }()
        Self.logger.info("[renderer] extractor=wu+km meanMSE=\(meanExtractMSE)")

        var generator = PaletteGenerator()
        generator.refinementMetric = refinementMetric
        generator.ditherMethod = composition.ditherMethod
        generator.blueNoiseGPU = engines.blueNoise

        let output = await generator.generate(tiles: tilesWithPalettes)

        onPhase?(.encode)
        let encodeStart = ContinuousClock().now
        let encoder = GIFEncoder(width: tiles[0].side, height: tiles[0].side, fps: fps)

        let srgbPalettes: [[SIMD3<UInt8>]] = output.perFramePalettes.map { palette in
            palette.map { ColorScience.okLabToSRGB8(OKLab($0)) }
        }
        // Completeness gate: the per-frame surjectivity rescue in
        // PaletteGenerator guarantees this succeeds. If it ever returns
        // nil, an empty-slot GIF was about to ship — fail loud, never
        // silently emit an incomplete voxel volume.
        guard let volume = CompleteVoxelVolume(checkingFrames: output.frameIndices) else {
            throw GIFEncoderError.incompleteVoxelVolume
        }
        // Stamp the render + benchmark metadata into the GIF as a Comment
        // Extension so an AirDropped file carries its own stats (read with
        // `exiftool file.gif` or `strings`) — no copy-pasting Console.
        let metadata = Self.renderComment(
            tiles: tiles,
            meanMSE: meanExtractMSE,
            wuSeedMillis: engines.kMeans.lastWuSeedMillis,
            ditherSummary: output.ditherSummary,
            stageAMillis: output.stageAMillis
        )
        try encoder.encode(
            volume: volume,
            perFramePalettes: srgbPalettes,
            to: url,
            comment: metadata
        )
        let displayPalettes: [[SIMD3<UInt8>]] = srgbPalettes

        let encodeMs = PaletteGenerator.milliseconds(ContinuousClock().now - encodeStart)
        let fileSize = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int) ?? 0
        Self.logger.info("[renderer] encode done in \(encodeMs)ms (\(fileSize) bytes)")

        return Report(
            stageAMillis: output.stageAMillis,
            encodeMillis: encodeMs,
            totalMillis: output.stageAMillis + encodeMs,
            fileSize: fileSize,
            palettesForDisplay: displayPalettes,
            meanExtractMSE: meanExtractMSE,
            perFrameStatistics: perFrameStats
        )
    }

    /// Build the GIF metadata comment: the render + benchmark stats, embedded so
    /// the file carries its own numbers (no copy-pasting Console after AirDrop).
    /// Read it back with `exiftool file.gif` (Comment tag) or `strings file.gif`.
    private static func renderComment(
        tiles: [OKLabTile],
        meanMSE: Float,
        wuSeedMillis: Int,
        ditherSummary: String,
        stageAMillis: Int
    ) -> String {
        let ts = ISO8601DateFormatter().string(from: Date())
        let side = tiles.first?.side ?? SixFourShape.W
        return """
        SixFour \(side)×\(side)×\(tiles.count) GIF
        extractor=Wu+KM  dither=\(ditherSummary)  meanMSE=\(String(format: "%.6f", meanMSE))
        wuSeedMs=\(wuSeedMillis)  stageA(refine+dither+rescue)Ms=\(stageAMillis)  frames=\(tiles.count)  K=\(SixFourShape.K)
        rendered=\(ts)
        """
    }
}
