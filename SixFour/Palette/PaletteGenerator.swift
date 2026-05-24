import Foundation
import simd
import os

/// Orchestrates Stage A (provided by GPU k-means, baked into `OKLabTile`)
/// followed by Stage B (Sinkhorn-balanced merge) and the CPU dithering pass.
///
/// Stage A: the GPU does Lloyd k-means with hard-Euclidean OKLab metric
/// inside the per-frame command buffer (`Metal/Pipeline.swift` and the
/// three `kmeansXxxKernel` functions in `Shaders.metal`). Each tile arrives
/// with `tile.palette` already populated. If a metric organ is loaded, this
/// generator refines the GPU palette with the organ's `LearnedPSDMetric` on
/// CPU via `KMeansLab.run` (5 extra iterations from the GPU centroids).
///
/// Stage B: optional cross-frame Sinkhorn merge depending on `Mode`:
///   * `.perFrame` — skip Stage B; every frame keeps its own palette.
///   * `.shared`   — direct-exp Sinkhorn at θ = 0.05 (MATH.md §3.bis).
///   * `.global`   — log-domain Sinkhorn at θ = 50 (MATH.md Theorem 2).
///
/// Dither: CPU error-diffusion (Floyd–Steinberg by default, optionally
/// serpentine) against the final palette, producing the per-frame indices
/// that the GIF encoder writes out.
struct PaletteGenerator: Sendable {

    static let logger = Logger(subsystem: "com.sixfour.SixFour", category: "palette")

    /// User-facing palette mode. Three values, each backed by executable,
    /// tested code (no `.spectrum(θ)` interior, per the project no-stubs rule).
    enum Mode: Sendable, Codable, Hashable {
        case perFrame    // θ = 0
        case shared      // θ ≈ 0.05 (direct-exp)
        case global      // θ → ∞ (log-domain)

        /// Convenience for diagnostics & UI captions.
        var thetaLabel: String {
            switch self {
            case .perFrame: return "θ = 0"
            case .shared:   return "θ ≈ 0.05"
            case .global:   return "θ → ∞"
            }
        }
    }

    var dither: Dither.ErrorKernel = .floydSteinberg
    var serpentine: Bool = false
    /// Optional learned PSD metric. When set, drives a 5-iter CPU
    /// Lloyd refinement step starting from the GPU centroids.
    var refinementMetric: LearnedPSDMetric? = nil

    /// Per-burst output. No fallback diagnostics — the merger throws on
    /// failure and the renderer surfaces it.
    struct Output: Sendable {
        let mode: Mode
        let perFramePalettes: [[SIMD3<Float>]]   // T × K (always present)
        let frameIndices: [[UInt8]]              // T × H·W indices into the active palette
        let globalPalette: [SIMD3<Float>]?       // K, populated when mode != .perFrame
        let stageAMillis: Int                    // wall-clock for the per-frame CPU work (refine + dither)
        let stageBMillis: Int?                   // nil iff mode == .perFrame
        /// θ Stage B settled on. For Shared this is the static θ; for
        /// Global this is the largest θ at which the adaptive search
        /// produced a surjective remap. Nil iff Stage B didn't run.
        let achievedTheta: Double?
        /// Number of adaptive-θ attempts Stage B made (1 = first attempt
        /// worked). Nil iff Stage B didn't run.
        let attempts: Int?
    }

    /// Throws `StageBSinkhorn.StageBError` if Stage B can't construct a
    /// surjective palette at any θ in the configured range. Callers MUST
    /// NOT silently substitute a different result on `throws` — surface
    /// the error to the user.
    func generate(tiles: [OKLabTile], mode: Mode = .perFrame) async throws -> Output {
        precondition(!tiles.isEmpty, "Need at least one frame")

        let t0 = ContinuousClock().now

        // Stage A is already done on GPU. CPU refines + dithers per frame.
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

        let t1 = ContinuousClock().now
        let stageAMs = Self.milliseconds(t1 - t0)
        Self.logger.info("[palette] Stage A CPU (×\(frameCount) frames refine+dither): \(stageAMs)ms")

        if mode == .perFrame {
            Self.logger.info("[palette] Stage B skipped (mode=.perFrame)")
            return Output(
                mode: .perFrame,
                perFramePalettes: palettes,
                frameIndices: indices,
                globalPalette: nil,
                stageAMillis: stageAMs,
                stageBMillis: nil,
                achievedTheta: nil,
                attempts: nil
            )
        }

        // Stage B Sinkhorn merge — adaptive θ; may throw if no θ in the
        // search range yields a surjective remap.
        let params: StageBSinkhorn.Params = (mode == .global) ? .global : .shared
        let merger = StageBSinkhorn(params: params)
        Self.logger.info("[palette] Stage B starting (mode=\(String(describing: mode), privacy: .public))")
        let r = try merger.mergeAdaptive(
            perFramePalettes: palettes,
            perFrameIndices: indices
        )
        let t2 = ContinuousClock().now
        let stageBMs = Self.milliseconds(t2 - t1)
        let achievedTh = r.achievedTheta
        let attemptsCt = r.attempts
        Self.logger.info(
            "[palette] Stage B done in \(stageBMs)ms (θ=\(achievedTh, privacy: .public), attempts=\(attemptsCt, privacy: .public))"
        )

        // Repartition the global witness back into per-frame slices.
        let perFrameLength = tiles[0].side * tiles[0].side
        var remapped: [[UInt8]] = []
        remapped.reserveCapacity(frameCount)
        var cursor = 0
        for _ in 0..<frameCount {
            let end = cursor + perFrameLength
            remapped.append(Array(r.witness.indices[cursor..<end]))
            cursor = end
        }
        return Output(
            mode: mode,
            perFramePalettes: palettes,
            frameIndices: remapped,
            globalPalette: r.globalPalette,
            stageAMillis: stageAMs,
            stageBMillis: stageBMs,
            achievedTheta: r.achievedTheta,
            attempts: r.attempts
        )
    }

    /// Per-frame CPU work: optional learned-metric refinement then dither.
    private static func processOneFrame(
        tile: OKLabTile,
        refinementMetric: LearnedPSDMetric?,
        kernel: Dither.ErrorKernel,
        serpentine: Bool
    ) -> ([SIMD3<Float>], [UInt8]) {
        // Start from GPU centroids. If a learned metric is loaded, refine
        // 5 Lloyd iterations on CPU with the organ's distance.
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
