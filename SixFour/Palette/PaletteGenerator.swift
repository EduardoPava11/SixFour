import Foundation
import simd
import os

/// Per-frame palette finishing pass. Stage A (the chosen extractor's GPU/CPU
/// quantization) has already populated each `tile.palette`; this generator does
/// the CPU work that turns those centroids into the final per-frame indices:
///
///   1. Optional learned-metric refinement — 5 Lloyd iterations on CPU with the
///      organ's `LearnedPSDMetric`, starting from the extractor's centroids.
///   2. Error-diffusion dither (Floyd–Steinberg by default, optionally
///      serpentine) against the final palette → per-frame indices.
///   3. **Strict per-frame surjectivity rescue** — every frame must use all
///      `K` colours so it can join a `CompleteVoxelVolume`. Dithering can leave
///      dead palette slots on low-variance frames; `PerFrameSurjectivity`
///      relocates them onto worst-fit donor pixels (guaranteed to succeed since
///      `pixelsPerFrame ≥ K`).
///
/// There is exactly one palette behaviour: per-frame. Each of the 64 frames
/// keeps its own 256-colour palette, so the emitted GIF is a complete
/// 64×64×64 voxel volume with no empty slots. (The former cross-frame Sinkhorn
/// merge — `.shared` / `.global` modes collapsing all frames onto a single
/// global palette — has been removed; it was the opposite of "full of colours".)
struct PaletteGenerator: Sendable {

    static let logger = Logger(subsystem: "com.sixfour.SixFour", category: "palette")

    var dither: Dither.ErrorKernel = .floydSteinberg
    var serpentine: Bool = false
    /// Optional learned PSD metric. When set, drives a 5-iter CPU
    /// Lloyd refinement step starting from the extractor centroids.
    var refinementMetric: LearnedPSDMetric? = nil

    /// Per-burst output: one 256-colour palette per frame plus the per-frame
    /// indices the GIF encoder writes out.
    struct Output: Sendable {
        let perFramePalettes: [[SIMD3<Float>]]   // T × K
        let frameIndices: [[UInt8]]              // T × H·W indices into that frame's palette
        let stageAMillis: Int                    // wall-clock for the per-frame CPU work (refine + dither + rescue)
    }

    /// Refine + dither + per-frame surjectivity rescue for every tile.
    func generate(tiles: [OKLabTile]) async -> Output {
        precondition(!tiles.isEmpty, "Need at least one frame")

        let t0 = ContinuousClock().now

        let frameCount = tiles.count
        var palettes: [[SIMD3<Float>]] = Array(repeating: [], count: frameCount)
        var indices: [[UInt8]] = Array(repeating: [], count: frameCount)

        let metric = self.refinementMetric
        let kernel = self.dither
        let useSerpentine = self.serpentine

        await withTaskGroup(of: (Int, [SIMD3<Float>], [UInt8]).self) { group in
            for (i, tile) in tiles.enumerated() {
                group.addTask {
                    let (pal, idx) = Self.processOneFrame(
                        tile: tile,
                        refinementMetric: metric,
                        kernel: kernel,
                        serpentine: useSerpentine
                    )
                    return (i, pal, idx)
                }
            }
            while let (i, pal, idx) = await group.next() {
                palettes[i] = pal
                indices[i] = idx
            }
        }

        // Strict per-frame surjectivity: every frame must use all K colours so
        // it can join a CompleteVoxelVolume. Dithering can leave dead palette
        // slots on low-variance frames; the rescue relocates them onto
        // worst-fit donor pixels (guaranteed to succeed since
        // pixelsPerFrame ≥ K). See PerFrameSurjectivity.
        for i in 0..<frameCount {
            let (pal, idx) = PerFrameSurjectivity.rescue(
                palette: palettes[i],
                indices: indices[i],
                pixels: tiles[i].pixels
            )
            palettes[i] = pal
            indices[i] = idx
        }

        let stageAMs = Self.milliseconds(ContinuousClock().now - t0)
        Self.logger.info("[palette] per-frame refine+dither+rescue (×\(frameCount) frames): \(stageAMs)ms")

        return Output(
            perFramePalettes: palettes,
            frameIndices: indices,
            stageAMillis: stageAMs
        )
    }

    /// Per-frame CPU work: optional learned-metric refinement then dither.
    private static func processOneFrame(
        tile: OKLabTile,
        refinementMetric: LearnedPSDMetric?,
        kernel: Dither.ErrorKernel,
        serpentine: Bool
    ) -> ([SIMD3<Float>], [UInt8]) {
        // Start from the extractor centroids. If a learned metric is loaded,
        // refine 5 Lloyd iterations on CPU with the organ's distance.
        var palette = tile.palette
        if let m = refinementMetric {
            let refined = KMeansLab.run(
                samples: tile.pixels,
                seeds: palette,
                metric: m,
                maxIterations: 5,
                shiftTolerance: 1e-5
            )
            palette = refined.centroids
        }
        let idx: [UInt8]
        if serpentine {
            idx = Dither.errorDiffuseSerpentine(
                tile: tile, palette: palette,
                metric: EuclideanOKLabMetric(), kernel: kernel
            )
        } else {
            idx = Dither.errorDiffuse(
                tile: tile, palette: palette,
                metric: EuclideanOKLabMetric(), kernel: kernel
            )
        }
        return (palette, idx)
    }

    /// Rounded milliseconds from a `Duration`.
    static func milliseconds(_ d: Duration) -> Int {
        let (s, attos) = d.components
        return Int(s) * 1_000 + Int(attos / 1_000_000_000_000_000)
    }
}
