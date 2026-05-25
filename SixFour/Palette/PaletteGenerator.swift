import Foundation
import simd
import os

/// Per-frame palette finishing pass. Stage A (Wu-initialized k-means) has
/// populated each `tile.palette`; this generator turns those centroids into the
/// final per-frame indices:
///
///   1. Optional learned-metric refinement — 5 Lloyd iterations on CPU with the
///      organ's `LearnedPSDMetric`, starting from the extractor's centroids.
///   2. Dither → per-frame indices. Two methods:
///        * `.errorDiffusion` — sequential CPU (SIMD8 nearest-centroid).
///        * `.blueNoise` — parallel ordered dithering against the STBN3D mask,
///          run on the **GPU** (`BlueNoisePalettePipeline`) when available, with
///          the CPU path as fallback + benchmark comparison.
///   3. **Strict per-frame surjectivity rescue** — every frame must use all `K`
///      colours so it can join a `CompleteVoxelVolume`.
///
/// One palette behaviour: per-frame. Each of the 64 frames keeps its own
/// 256-colour palette → the GIF is a complete 64×64×64 voxel volume.
struct PaletteGenerator: Sendable {

    static let logger = Logger(subsystem: "com.sixfour.SixFour", category: "palette")

    var dither: Dither.ErrorKernel = .floydSteinberg
    var serpentine: Bool = false
    /// Which dithering method to apply (user option).
    var ditherMethod: DitherMethod = .errorDiffusion
    /// GPU blue-noise pipeline. When set and `ditherMethod == .blueNoise`, the
    /// dither runs on the GPU; otherwise the CPU path is used.
    var blueNoiseGPU: BlueNoisePalettePipeline? = nil
    /// When true, the blue-noise path also runs the *other* processor (CPU when
    /// GPU is operational) purely to log a CPU-vs-GPU timing comparison. Costs
    /// one extra dither pass on blue-noise captures.
    ///
    /// Set to **false** after the on-device verdict (A19 Pro, 2026-05-25):
    /// `CPU=6802ms GPU=4ms` for the batched 64-frame blue-noise dither — GPU
    /// wins decisively, so the CPU comparison run is no longer worth its ~6.8s
    /// tax per capture. The GPU path stays operational and still logs its time.
    /// Flip true again only to re-measure.
    var benchmarkDither: Bool = false
    /// Optional learned PSD metric. When set, drives a 5-iter CPU
    /// Lloyd refinement step starting from the extractor centroids.
    var refinementMetric: LearnedPSDMetric? = nil

    /// Per-burst output: one 256-colour palette per frame plus the per-frame
    /// indices the GIF encoder writes out.
    struct Output: Sendable {
        let perFramePalettes: [[SIMD3<Float>]]   // T × K
        let frameIndices: [[UInt8]]              // T × H·W indices into that frame's palette
        let stageAMillis: Int                    // wall-clock for refine + dither + rescue
    }

    /// Refine + dither + per-frame surjectivity rescue for every tile.
    func generate(tiles: [OKLabTile]) async -> Output {
        precondition(!tiles.isEmpty, "Need at least one frame")
        let t0 = ContinuousClock().now
        let frameCount = tiles.count
        let perFrame = tiles[0].side * tiles[0].side
        let metric = self.refinementMetric

        // Phase 1: per-frame palettes (extractor centroids + optional refine).
        var palettes: [[SIMD3<Float>]] = Array(repeating: [], count: frameCount)
        await withTaskGroup(of: (Int, [SIMD3<Float>]).self) { group in
            for (i, tile) in tiles.enumerated() {
                group.addTask { (i, Self.refinePalette(tile: tile, metric: metric)) }
            }
            while let (i, pal) = await group.next() { palettes[i] = pal }
        }

        // Phase 2: dither. Blue-noise needs the tiled STBN3D mask; fall back to
        // error diffusion if it's unavailable / size-mismatched (non-64³ tests).
        let mask: [UInt8]? = {
            guard ditherMethod == .blueNoise else { return nil }
            guard let m = STBN3DMaskLoader.loadTiled(), m.count == frameCount * perFrame else { return nil }
            return m
        }()

        var indices: [[UInt8]]
        let ditherStart = ContinuousClock().now
        if ditherMethod == .blueNoise, let mask {
            let thresholds = (0..<frameCount).map { Array(mask[($0 * perFrame)..<(($0 + 1) * perFrame)]) }
            indices = ditherBlueNoise(tiles: tiles, palettes: palettes, thresholds: thresholds)
        } else {
            let kernel = self.dither
            let useSerpentine = self.serpentine
            var out: [[UInt8]] = Array(repeating: [], count: frameCount)
            await withTaskGroup(of: (Int, [UInt8]).self) { group in
                for (i, tile) in tiles.enumerated() {
                    let pal = palettes[i]
                    group.addTask {
                        (i, Dither.errorDiffuseSIMD(tile: tile, centroids: CentroidSet(pal),
                                                    kernel: kernel, serpentine: useSerpentine))
                    }
                }
                while let (i, idx) = await group.next() { out[i] = idx }
            }
            indices = out
            Self.logger.notice("[bench] dither errorDiffusion (CPU SIMD8, ×\(frameCount)): \(Self.milliseconds(ContinuousClock().now - ditherStart))ms")
        }

        // Phase 3: strict per-frame surjectivity rescue — guarantees every frame
        // uses all K colours (CompleteVoxelVolume), for BOTH dither methods.
        for i in 0..<frameCount {
            let (pal, idx) = PerFrameSurjectivity.rescue(
                palette: palettes[i], indices: indices[i], pixels: tiles[i].pixels
            )
            palettes[i] = pal
            indices[i] = idx
        }

        let stageAMs = Self.milliseconds(ContinuousClock().now - t0)
        Self.logger.info("[palette] refine+dither+rescue (×\(frameCount) frames): \(stageAMs)ms")
        return Output(perFramePalettes: palettes, frameIndices: indices, stageAMillis: stageAMs)
    }

    /// Blue-noise dither for all frames. Runs on GPU when available (operational
    /// result); when `benchmarkDither` is set, also runs the CPU path purely to
    /// log a CPU-vs-GPU comparison. Returns the operational indices.
    private func ditherBlueNoise(
        tiles: [OKLabTile],
        palettes: [[SIMD3<Float>]],
        thresholds: [[UInt8]]
    ) -> [[UInt8]] {
        let frameCount = tiles.count

        func runCPU() -> (result: [[UInt8]], ms: Int) {
            let start = ContinuousClock().now
            let out = (0..<frameCount).map { i in
                Dither.blueNoiseSIMD(tile: tiles[i], centroids: CentroidSet(palettes[i]), thresholds: thresholds[i])
            }
            return (out, Self.milliseconds(ContinuousClock().now - start))
        }

        guard let gpu = blueNoiseGPU else {
            let cpu = runCPU()
            Self.logger.notice("[bench] dither blueNoise CPU=\(cpu.ms)ms (no GPU pipeline)")
            return cpu.result
        }

        do {
            let gpuStart = ContinuousClock().now
            let gpuResult = try gpu.assignBatch(
                pixels: tiles.map { $0.pixels }, centroids: palettes, thresholds: thresholds
            )
            let gpuMs = Self.milliseconds(ContinuousClock().now - gpuStart)
            if benchmarkDither {
                let cpu = runCPU()
                let ratio = gpuMs > 0 ? Double(cpu.ms) / Double(gpuMs) : 0
                Self.logger.notice("[bench] dither blueNoise CPU=\(cpu.ms)ms GPU=\(gpuMs)ms (\(String(format: "%.2f", ratio))× CPU/GPU, batched ×\(frameCount))")
            } else {
                Self.logger.notice("[bench] dither blueNoise GPU=\(gpuMs)ms (batched ×\(frameCount))")
            }
            return gpuResult
        } catch {
            Self.logger.error("[bench] blueNoise GPU failed (\(String(describing: error))); CPU fallback")
            return runCPU().result
        }
    }

    /// Extractor centroids, optionally refined 5 Lloyd iterations with a learned
    /// metric. The dither always uses Euclidean OKLab regardless.
    private static func refinePalette(tile: OKLabTile, metric: LearnedPSDMetric?) -> [SIMD3<Float>] {
        guard let m = metric else { return tile.palette }
        return KMeansLab.run(
            samples: tile.pixels, seeds: tile.palette, metric: m,
            maxIterations: 5, shiftTolerance: 1e-5
        ).centroids
    }

    /// Rounded milliseconds from a `Duration`.
    static func milliseconds(_ d: Duration) -> Int {
        let (s, attos) = d.components
        return Int(s) * 1_000 + Int(attos / 1_000_000_000_000_000)
    }
}
