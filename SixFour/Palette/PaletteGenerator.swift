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
    /// Which dithering method to apply (user option). `.errorDiffusion`
    /// (default) is sequential CPU; `.blueNoise` is parallel ordered dithering
    /// against the STBN3D mask. Both feed the surjectivity rescue.
    var ditherMethod: DitherMethod = .errorDiffusion
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
        let method = self.ditherMethod

        // Blue-noise mode needs the tiled STBN3D mask (one threshold per voxel).
        // Load it once; fall back to error diffusion if it's unavailable or its
        // size doesn't match this burst (e.g. a non-64³ test fixture).
        let perFrame = tiles[0].side * tiles[0].side
        let mask: [UInt8]? = {
            guard method == .blueNoise else { return nil }
            guard let m = STBN3DMaskLoader.loadTiled(), m.count == frameCount * perFrame else { return nil }
            return m
        }()
        let effectiveMethod: DitherMethod = (method == .blueNoise && mask == nil) ? .errorDiffusion : method

        await withTaskGroup(of: (Int, [SIMD3<Float>], [UInt8]).self) { group in
            for (i, tile) in tiles.enumerated() {
                let thresholds: [UInt8]? = mask.map { Array($0[(i * perFrame)..<((i + 1) * perFrame)]) }
                group.addTask {
                    let (pal, idx) = Self.processOneFrame(
                        tile: tile,
                        refinementMetric: metric,
                        kernel: kernel,
                        serpentine: useSerpentine,
                        method: effectiveMethod,
                        thresholds: thresholds
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
        serpentine: Bool,
        method: DitherMethod,
        thresholds: [UInt8]?
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
        // The dither always uses the Euclidean OKLab metric (the learned
        // metric, if any, only steers the refine above). So we take the
        // vectorised SIMD8 path: build the palette as a struct-of-arrays
        // `CentroidSet` once, then error-diffuse with an 8-wide
        // nearest-centroid search. The generic `Dither.errorDiffuse` remains
        // the scalar parity oracle.
        let centroids = CentroidSet(palette)
        let idx: [UInt8]
        switch method {
        case .blueNoise where thresholds != nil:
            idx = Dither.blueNoiseSIMD(
                tile: tile, centroids: centroids, thresholds: thresholds!
            )
        case .errorDiffusion, .blueNoise:
            idx = Dither.errorDiffuseSIMD(
                tile: tile, centroids: centroids, kernel: kernel, serpentine: serpentine
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
