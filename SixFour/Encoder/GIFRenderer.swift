import Foundation
import simd
import os

/// End-to-end orchestrator: OKLab tiles (without palettes yet) +
/// composition → .gif on disk.
///
/// Pipeline (see `spec/MATH.md` for the framework):
///   1. Resolve the optional metric organ from the composition.
///   2. `MetalPipeline.runStageAKMeansBatch(tiles:)` — GPU Lloyd k-means on
///      all 64 tiles in a single command buffer, after the burst is done
///      (per the no-fallback / device-stability fix; folding this into
///      `submitAsync` caused frame drops).
///   3. `PaletteGenerator.generate(tiles, mode)` — CPU refine + dither
///      + optional Stage B Sinkhorn merge. May `throw` if Global mode
///      can't produce a surjective palette at any θ in the search range.
///   4. Convert OKLab → sRGB UInt8.
///   5. Encode GIF89a with one Global Color Table (Shared/Global) or
///      per-frame Local Color Tables (Per-frame).
struct GIFRenderer {
    static let logger = Logger(subsystem: "com.sixfour.SixFour", category: "renderer")

    /// Coarse stage label for the UI's phase banner.
    enum RenderPhase: Sendable, Equatable {
        case stageA   // batched GPU k-means + per-frame CPU refine+dither
        case stageB   // Sinkhorn-balanced global merge (only if mode != .perFrame)
        case encode   // GIF89a emit + disk write
    }

    /// Metadata returned by `render(...)`. Consumed by `CaptureOutput`.
    struct Report: Sendable {
        let mode: PaletteGenerator.Mode
        let stageAMillis: Int
        let stageBMillis: Int?
        let encodeMillis: Int
        let totalMillis: Int
        /// θ Stage B settled on (only meaningful when Stage B ran).
        let achievedTheta: Double?
        let attempts: Int?
        let fileSize: Int
        /// sRGB palette stack for the UI's PaletteStripView.
        let palettesForDisplay: [[SIMD3<UInt8>]]
    }

    let composition: Composition
    let store: GeneStore
    let pipeline: MetalPipeline

    init(composition: Composition, store: GeneStore, pipeline: MetalPipeline) {
        self.composition = composition
        self.store = store
        self.pipeline = pipeline
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
        // Batched GPU k-means on all tiles — the half of Stage A that
        // used to fold into submitAsync, hoisted here so the camera
        // delegate queue stays light during capture.
        let tilesWithPalettes = try pipeline.runStageAKMeansBatch(tiles: tiles)

        var generator = PaletteGenerator()
        generator.refinementMetric = refinementMetric

        if composition.paletteMode != .perFrame {
            onPhase?(.stageB)
        }
        let output = try await generator.generate(
            tiles: tilesWithPalettes, mode: composition.paletteMode
        )

        onPhase?(.encode)
        let encodeStart = ContinuousClock().now
        let encoder = GIFEncoder(width: tiles[0].side, height: tiles[0].side, fps: fps)

        let displayPalettes: [[SIMD3<UInt8>]]
        if output.mode == .perFrame {
            let srgbPalettes: [[SIMD3<UInt8>]] = output.perFramePalettes.map { palette in
                palette.map { ColorScience.okLabToSRGB8(OKLab($0)) }
            }
            try encoder.encode(
                frames: output.frameIndices,
                perFramePalettes: srgbPalettes,
                to: url
            )
            displayPalettes = srgbPalettes
        } else {
            guard let globalLab = output.globalPalette else {
                throw GIFEncoderError.paletteWrongSize(expected: 256, got: 0)
            }
            let srgb: [SIMD3<UInt8>] = globalLab.map { ColorScience.okLabToSRGB8(OKLab($0)) }
            try encoder.encode(
                frames: output.frameIndices,
                globalPalette: srgb,
                to: url
            )
            displayPalettes = [srgb]
        }

        let encodeMs = PaletteGenerator.milliseconds(ContinuousClock().now - encodeStart)
        let fileSize = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int) ?? 0
        Self.logger.info("[renderer] encode done in \(encodeMs)ms (\(fileSize) bytes)")

        return Report(
            mode: output.mode,
            stageAMillis: output.stageAMillis,
            stageBMillis: output.stageBMillis,
            encodeMillis: encodeMs,
            totalMillis: output.stageAMillis + (output.stageBMillis ?? 0) + encodeMs,
            achievedTheta: output.achievedTheta,
            attempts: output.attempts,
            fileSize: fileSize,
            palettesForDisplay: displayPalettes
        )
    }
}
