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
///   3. **Significance split-fill** — every frame must use all `K` colours AND
///      every slot must be backed by ≥ `minPopulation` pixels (never a count-1
///      outlier), so it can join a `SignificantVoxelVolume`.
///
/// One palette behaviour: per-frame. Each of the 64 frames keeps its own
/// 256-colour palette → the GIF is a complete, all-significant 64×64×64 volume.
struct PaletteGenerator: Sendable {

    static let logger = Logger(subsystem: "com.sixfour.SixFour", category: "palette")

    var dither: Dither.ErrorKernel = .floydSteinberg
    var serpentine: Bool = false
    /// Which dithering method to apply (user option).
    var ditherMethod: DitherMethod = .errorDiffusion
    /// Blue-noise temporal residual spectrum: `.spatiotemporal` uses the full
    /// 3-D mask (decorrelated across frames); `.frozen` reuses one 2-D slice on
    /// every frame (steady, no temporal noise). Only consulted for `.blueNoise`.
    var blueNoiseTemporal: BlueNoiseTemporalMode = .spatiotemporal
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
    /// DORMANT: nothing assigns this today (the deferred look-NN metric organ is
    /// unwired — its `GeneStore.loadMetric` loader was removed as dead code 2026-06-03),
    /// so the refinement branch at `generate(...)` is currently unreachable. It stays
    /// as the seam the trained metric organ will plug into.
    var refinementMetric: LearnedPSDMetric? = nil

    /// Per-burst output: one 256-colour palette per frame plus the per-frame
    /// indices the GIF encoder writes out.
    struct Output: Sendable {
        let perFramePalettes: [[SIMD3<Float>]]   // T × K
        let frameIndices: [[UInt8]]              // T × H·W indices into that frame's palette
        /// T × K significance cells (mean, per-axis σ, population, provenance)
        /// — the per-slot OKLab ranges. After split-fill every slot is
        /// significant (count ≥ minPopulation); the GIFRenderer turns these
        /// into a `SignificantVoxelVolume`.
        let perFrameCells: [[SixFourSignificantCell]]
        let stageAMillis: Int                    // wall-clock for refine + dither + split-fill
        /// Human-readable dither summary for the GIF metadata comment,
        /// e.g. "blueNoise/GPU 4ms" or "errorDiffusion/CPU 33ms".
        let ditherSummary: String
    }

    /// Refine + dither + significance split-fill for every tile.
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
        var ditherSummary: String
        let ditherStart = ContinuousClock().now
        if ditherMethod == .blueNoise, let mask {
            // Spatiotemporal: each frame gets its own 3-D mask slice (residual
            // decorrelated in time). Frozen: reuse slice 0 on every frame
            // (residual zero-in-time — steady pattern).
            let thresholds: [[UInt8]]
            switch blueNoiseTemporal {
            case .frozen:
                let slice0 = Array(mask[0..<perFrame])
                thresholds = Array(repeating: slice0, count: frameCount)
            case .spatiotemporal:
                thresholds = (0..<frameCount).map { Array(mask[($0 * perFrame)..<(($0 + 1) * perFrame)]) }
            }
            (indices, ditherSummary) = ditherBlueNoise(tiles: tiles, palettes: palettes, thresholds: thresholds)
            ditherSummary += " \(blueNoiseTemporal.rawValue)"
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
            let edMs = Self.milliseconds(ContinuousClock().now - ditherStart)
            let scan = useSerpentine ? "serpentine" : "raster"
            ditherSummary = "errorDiffusion/\(scan)/CPU \(edMs)ms"
            Self.logger.debug("[bench] dither errorDiffusion (CPU SIMD8, ×\(frameCount)): \(edMs)ms")
        }

        // Phase 3: significance split-fill — guarantees every frame uses all K
        // colours (CompleteVoxelVolume) AND that every slot is statistically
        // significant (≥ minPopulation pixels, in-range donors, never a worst-
        // fit outlier). Then derive the per-slot cells (OKLab ranges) for the
        // SignificantVoxelVolume brand. Applies to BOTH dither methods.
        var frameCells = [[SixFourSignificantCell]](repeating: [], count: frameCount)
        for i in 0..<frameCount {
            let (pal, idx) = SignificantSplitFill.rescue(
                palette: palettes[i], indices: indices[i], pixels: tiles[i].pixels
            )
            palettes[i] = pal
            indices[i] = idx
            frameCells[i] = SignificantSplitFill.cells(
                palette: pal, indices: idx, pixels: tiles[i].pixels
            )
        }

        let stageAMs = Self.milliseconds(ContinuousClock().now - t0)
        Self.logger.debug("[palette] refine+dither+split-fill (×\(frameCount) frames): \(stageAMs)ms")
        return Output(perFramePalettes: palettes, frameIndices: indices,
                      perFrameCells: frameCells,
                      stageAMillis: stageAMs, ditherSummary: ditherSummary)
    }

    /// Blue-noise dither for all frames. Runs on GPU when available (operational
    /// result); when `benchmarkDither` is set, also runs the CPU path purely to
    /// log a CPU-vs-GPU comparison. Returns the operational indices.
    private func ditherBlueNoise(
        tiles: [OKLabTile],
        palettes: [[SIMD3<Float>]],
        thresholds: [[UInt8]]
    ) -> (indices: [[UInt8]], summary: String) {
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
            Self.logger.debug("[bench] dither blueNoise CPU=\(cpu.ms)ms (no GPU pipeline)")
            return (cpu.result, "blueNoise/CPU \(cpu.ms)ms")
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
                Self.logger.debug("[bench] dither blueNoise CPU=\(cpu.ms)ms GPU=\(gpuMs)ms (\(String(format: "%.2f", ratio))× CPU/GPU, batched ×\(frameCount))")
                return (gpuResult, "blueNoise/GPU \(gpuMs)ms (cpu \(cpu.ms)ms)")
            } else {
                Self.logger.debug("[bench] dither blueNoise GPU=\(gpuMs)ms (batched ×\(frameCount))")
                return (gpuResult, "blueNoise/GPU \(gpuMs)ms")
            }
        } catch {
            Self.logger.error("[bench] blueNoise GPU failed (\(String(describing: error))); CPU fallback")
            let cpu = runCPU()
            return (cpu.result, "blueNoise/CPU \(cpu.ms)ms (gpu failed)")
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
