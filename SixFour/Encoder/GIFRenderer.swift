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
///   3. `PaletteGenerator.generate(tiles)` — CPU refine + dither + significance
///      split-fill (every frame uses all 256 colours AND every slot is backed
///      by ≥ minPopulation pixels → a complete, all-significant 64×64×64 volume).
///   4. Convert OKLab → sRGB UInt8.
///   5. Encode GIF89a with per-frame Local Color Tables, gated on a
///      `SignificantVoxelVolume` (which wraps the `CompleteVoxelVolume`).
struct GIFRenderer {
    static let logger = Logger(subsystem: "com.sixfour.SixFour", category: "renderer")

    /// Coarse stage label for the UI's phase banner.
    enum RenderPhase: Sendable, Equatable {
        case stageA   // per-frame extraction + CPU refine+dither+significance split-fill
        case encode   // GIF89a emit + disk write
    }

    /// Metadata returned by `render(...)`. Consumed by `CaptureOutput`.
    struct Report: Sendable {
        let stageAMillis: Int
        let encodeMillis: Int
        let totalMillis: Int
        let fileSize: Int
        /// sRGB palette stack for the UI's Review palette views.
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
        /// Per-frame palette cells (256 each) — the significance result made
        /// visible: mean, per-axis σ (range), population, provenance. Length T.
        let perFrameCells: [[SixFourSignificantCell]]
        /// Per-frame count of significant slots (each should be K = 256 — the
        /// guarantee, surfaced so the UI can *prove* it). Length T.
        let perFrameSignificant: [Int]
        /// Per-frame occupied 16³ OKLab bins (single-frame coverage). Length T.
        let perFrameCoverage: [Int]
        /// Per-frame extraction MSE (OKLab units²). Length T.
        let perFrameMSE: [Float]
    }

    /// The residual-shaping sampler configuration (method · kernel · serpentine
    /// · temporal), assembled from `AppSettings`. The only render-recipe input —
    /// the extractor is fixed at Wu+KM.
    let dither: DitherConfig
    let engines: PaletteEngines
    /// When true, also run a uniform-stride extraction to log + stamp a Wu+KM
    /// vs uniform seed MSE comparison (one extra full extraction per capture).
    /// On-device measurement aid; flip false for production once the real-scene
    /// quality delta is known.
    var benchmarkSeed: Bool = true

    init(dither: DitherConfig, engines: PaletteEngines) {
        self.dither = dither
        self.engines = engines
    }

    /// Mean per-frame extraction MSE across a burst's `ClusterStatistics`.
    static func meanMSE(_ stats: [ClusterStatistics]) -> Float {
        let sum = stats.reduce(Float(0)) { $0 + $1.provenance.mse }
        return sum / Float(max(1, stats.count))
    }

    func render(
        tiles: [OKLabTile],
        to url: URL,
        fps: Int = 20,
        onPhase: (@Sendable (RenderPhase) -> Void)? = nil
    ) async throws -> Report {
        precondition(!tiles.isEmpty)

        onPhase?(.stageA)
        // Per-frame palette extraction (Wu-initialized k-means). Returns
        // `[ClusterStatistics]` (one per tile) carrying per-cluster (μ, Σ,
        // count) + per-pixel assignment + provenance. We stitch the centroids
        // back into each OKLabTile.palette for the downstream Dither + encoder;
        // the rich statistics flow through Report.perFrameStatistics for the
        // CaptureBundle / editing tools.
        // The one extraction algorithm: Wu-initialized k-means (Celebi 2011).
        let extractor = KMeansExtractor(pipeline: engines.kMeans)
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
        let meanExtractMSE = Self.meanMSE(perFrameStats)
        let wuSeedMillis = engines.kMeans.lastWuSeedMillis
        // Primary metric: LAB gamut COVERAGE — how much colour the 64 frames
        // sampled (the diversity objective), not reconstruction fidelity.
        let coverage = ClusterStatisticsOps.gamutCoverage(perFrame: perFrameStats)
        Self.logger.notice("[bench] coverage occupiedBins=\(coverage.occupiedBins) (\(String(format: "%.1f%%", coverage.fraction * 100)) of 16³)  meanMSE=\(meanExtractMSE)")

        // Seed A/B on COVERAGE (the right yardstick): does raw farthest-point
        // (maximin, diversity-maximizing) capture MORE of the gamut than the
        // current Wu+KM default? Run an FPS pass with NO Lloyd (iterations = 0,
        // so the spread isn't pulled back to density), compare occupied-bin
        // coverage, stamp the delta. Gated by `benchmarkSeed`; flip false once
        // the default is chosen.
        var seedComparison: String? = nil
        if benchmarkSeed {
            let origSeed = engines.kMeans.seed
            let origIters = engines.kMeans.kMeansIterations
            engines.kMeans.seed = .farthestPoint
            // 1 iteration: just enough to populate per-cluster counts (the
            // assign pass) while barely settling the FPS spread — 0 would leave
            // counts empty so coverage can't be measured.
            engines.kMeans.kMeansIterations = 1
            if let fps = try? engines.kMeans.extractBatch(tiles: tiles, K: SixFourShape.K) {
                let fpsCov = ClusterStatisticsOps.gamutCoverage(perFrame: fps)
                let deltaPct = coverage.fraction > 0
                    ? (fpsCov.fraction - coverage.fraction) / coverage.fraction * 100 : 0
                seedComparison = String(
                    format: "wuKMCoverage=%d fpsCoverage=%d bins (FPS %+.1f%% vs Wu+KM); wuMSE=%.6f fpsMSE=%.6f",
                    coverage.occupiedBins, fpsCov.occupiedBins, deltaPct,
                    meanExtractMSE, Self.meanMSE(fps)
                )
                Self.logger.notice("[bench] seed \(seedComparison!, privacy: .public)")
            }
            engines.kMeans.seed = origSeed
            engines.kMeans.kMeansIterations = origIters
        }

        var generator = PaletteGenerator()
        generator.ditherMethod = dither.method
        generator.dither = dither.kernel.kernel
        generator.serpentine = dither.serpentine
        generator.blueNoiseTemporal = dither.temporal
        generator.blueNoiseGPU = engines.blueNoise

        let output = await generator.generate(tiles: tilesWithPalettes)

        onPhase?(.encode)
        let encodeStart = ContinuousClock().now
        let encoder = GIFEncoder(width: tiles[0].side, height: tiles[0].side, fps: fps)

        let srgbPalettes: [[SIMD3<UInt8>]] = output.perFramePalettes.map { palette in
            palette.map { ColorScience.okLabToSRGB8(OKLab($0)) }
        }
        // Completeness gate: the split-fill in PaletteGenerator guarantees this
        // succeeds. If it ever returns nil, an empty-slot GIF was about to ship
        // — fail loud, never silently emit an incomplete voxel volume.
        guard let volume = CompleteVoxelVolume(checkingFrames: output.frameIndices) else {
            throw GIFEncoderError.incompleteVoxelVolume
        }
        // Significance gate: every per-frame palette slot must be statistically
        // significant — backed by ≥ SixFourSignificance.minPopulation pixels,
        // never a donated outlier — with mass conservation. The split-fill
        // guarantees this on the SixFour shape (4096 ≥ 2·256); if the brand
        // ever rejects, fail loud rather than ship an outlier-backed palette.
        guard let significant = SignificantVoxelVolume(complete: volume, cells: output.perFrameCells) else {
            throw GIFEncoderError.insignificantVoxelVolume
        }
        let provenanceSummary = Self.significanceSummary(significant.cells)
        // The chosen residual-shaping sampler, so the artifact records exactly
        // which estimator + knobs produced it (read with `exiftool file.gif`).
        let samplerSummary: String = {
            switch dither.method {
            case .errorDiffusion:
                return "diffusion/\(dither.kernel.rawValue)/\(dither.serpentine ? "serpentine" : "raster")"
            case .blueNoise:
                return "blueNoise/\(dither.temporal.rawValue)"
            }
        }()
        // Stamp the render + benchmark metadata into the GIF as a Comment
        // Extension so an AirDropped file carries its own stats (read with
        // `exiftool file.gif` or `strings`) — no copy-pasting Console.
        let metadata = Self.renderComment(
            tiles: tiles,
            coverage: coverage,
            meanMSE: meanExtractMSE,
            wuSeedMillis: wuSeedMillis,
            ditherSummary: output.ditherSummary,
            stageAMillis: output.stageAMillis,
            seedComparison: seedComparison
        ) + "\nsampler=\(samplerSummary)\nsignificance=\(provenanceSummary)"
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

        // Per-frame numbers, surfaced so the Review screen can show (and the
        // user can verify) every figure the pipeline computed per frame.
        let perFrameSignificant = output.perFrameCells.map { $0.filter(\.isSignificant).count }
        let perFrameCoverage = perFrameStats.map {
            ClusterStatisticsOps.gamutCoverage(perFrame: [$0]).occupiedBins
        }
        let perFrameMSE = perFrameStats.map { $0.provenance.mse }

        return Report(
            stageAMillis: output.stageAMillis,
            encodeMillis: encodeMs,
            totalMillis: output.stageAMillis + encodeMs,
            fileSize: fileSize,
            palettesForDisplay: displayPalettes,
            meanExtractMSE: meanExtractMSE,
            perFrameStatistics: perFrameStats,
            perFrameCells: output.perFrameCells,
            perFrameSignificant: perFrameSignificant,
            perFrameCoverage: perFrameCoverage,
            perFrameMSE: perFrameMSE
        )
    }

    /// One-line significance accounting for the GIF metadata: how many of the
    /// T·K palette slots are statistically significant (backed by
    /// ≥ minPopulation pixels) and the minimum slot population observed across
    /// the burst. On a real capture this reads `significant=16384/16384
    /// minPop=…`; a value below the total would mean an outlier-backed slot
    /// slipped past (it cannot, given the brand gated the encode).
    private static func significanceSummary(_ cells: [[SixFourSignificantCell]]) -> String {
        let total = cells.reduce(0) { $0 + $1.count }
        let significant = cells.reduce(0) { $0 + $1.filter { $0.isSignificant }.count }
        let minPop = cells.flatMap { $0 }.map { $0.count }.min() ?? 0
        return "significant=\(significant)/\(total) minPop=\(minPop) nMin=\(SixFourSignificance.minPopulation)"
    }

    /// Build the GIF metadata comment: the render + benchmark stats, embedded so
    /// the file carries its own numbers (no copy-pasting Console after AirDrop).
    /// Read it back with `exiftool file.gif` (Comment tag) or `strings file.gif`.
    private static func renderComment(
        tiles: [OKLabTile],
        coverage: (occupiedBins: Int, fraction: Float),
        meanMSE: Float,
        wuSeedMillis: Int,
        ditherSummary: String,
        stageAMillis: Int,
        seedComparison: String?
    ) -> String {
        let ts = ISO8601DateFormatter().string(from: Date())
        let side = tiles.first?.side ?? SixFourShape.W
        let seedLine = seedComparison.map { "\nseedAB=\($0)" } ?? ""
        // Coverage (LAB diversity captured) is the headline; MSE is secondary.
        return """
        SixFour \(side)×\(side)×\(tiles.count) GIF
        labCoverage=\(coverage.occupiedBins)/4096 bins (\(String(format: "%.1f%%", coverage.fraction * 100)) of OKLab 16³)
        extractor=Wu+KM  dither=\(ditherSummary)  meanMSE=\(String(format: "%.6f", meanMSE))
        wuSeedMs=\(wuSeedMillis)  stageA(refine+dither+splitFill)Ms=\(stageAMillis)  frames=\(tiles.count)  K=\(SixFourShape.K)\(seedLine)
        rendered=\(ts)
        """
    }
}
