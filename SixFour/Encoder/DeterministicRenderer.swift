import Foundation
import simd
import CryptoKit
import os

/// The deterministic render path — the byte-exact integer Zig core made the
/// visible spine of the app. Where `GIFRenderer` runs GPU float K-means + GPU
/// blue-noise (fast, but not bit-reproducible), this drives the SAME pipeline
/// through the verified fixed-point kernels, ONE STAGE AT A TIME, so each
/// progress banner the user sees is a real kernel:
///
///   quantize (maximin) → dither → significance split-fill → palette → LZW/GIF
///
/// Every stage is byte-exact against a Haskell golden, so the whole render is a
/// pure function of the captured tiles: the same burst always yields the same
/// GIF bytes (`sha256Hex`) — the determinism guarantee, surfaced in Review.
struct DeterministicRenderer {
    static let logger = Logger(subsystem: "com.sixfour.SixFour", category: "deterministic")

    /// The pipeline stages, in order — surfaced to the capture banner so the
    /// determinism work is what the user watches run.
    enum Stage: String, Sendable, CaseIterable {
        case quantize     = "Quantizing — maximin palette…"
        case dither       = "Dithering — shaping the residual…"
        case significance = "Significance — backing every colour…"
        case palette      = "Palette — OKLab → sRGB…"
        case encode       = "Encoding — LZW / GIF89a…"

        /// Short tag for compact UI (e.g. the Review pipeline trace).
        var tag: String {
            switch self {
            case .quantize: return "quantize"
            case .dither: return "dither"
            case .significance: return "significance"
            case .palette: return "palette"
            case .encode: return "encode"
            }
        }
    }

    struct Result: Sendable {
        let gifData: Data
        /// 64 frames × 4096 palette indices — for the CompleteVoxelVolume gate.
        let frameIndices: [[UInt8]]
        /// 64 × 256 sRGB palettes — for the UI palette strip + the encoder.
        let srgbPalettes: [[SIMD3<UInt8>]]
        /// 64 × 256 significance cells — for the SignificantVoxelVolume gate.
        let cells: [[SixFourSignificantCell]]
        /// Lowercase hex SHA-256 of `gifData` — the render's reproducible fingerprint.
        let sha256Hex: String
        /// Per-frame quantization MSE (OKLab units²) — assigned-pixel ↔ centroid.
        let perFrameMSE: [Float]
        /// Per-frame occupied 16³ OKLab bins among the centroids (single-frame coverage).
        let perFrameCoverage: [Int]
        /// Mean of `perFrameMSE`.
        let meanExtractMSE: Float
    }

    enum DetError: Error, CustomStringConvertible {
        case stageFailed(String)
        case maskUnavailable
        var description: String {
            switch self {
            case .stageFailed(let s): return "deterministic \(s) stage failed"
            case .maskUnavailable: return "STBN3D mask unavailable"
            }
        }
    }

    let dither: DitherConfig
    /// Lloyd refinement passes. 0 = pure maximin (max LAB diversity / coverage —
    /// the per-frame objective); >0 trades diversity for lower MSE.
    var lloydIters: Int = 0

    func render(
        tiles: [OKLabTile],
        comment: String?,
        onStage: @Sendable (Stage) -> Void
    ) throws -> Result {
        precondition(!tiles.isEmpty)
        let k = SixFourShape.K
        let side = tiles[0].side
        let perFrame = side * side
        let minPop = SixFourSignificance.minPopulation

        // Per-frame OKLab pixels → Q16 once (the deterministic integer domain).
        let q16Frames = tiles.map { SixFourNative.oklabToQ16($0.pixels) }

        // Map the sampler config to the kernel's dither mode + STBN need.
        let (mode, needStbn): (Int, Bool) = {
            switch dither.method {
            case .errorDiffusion:
                return (dither.kernel == .floydSteinberg ? 0 : 1, false)
            case .blueNoise:
                return (dither.temporal == .frozen ? 3 : 2, true)
            }
        }()
        var stbn: [UInt8]? = nil
        if needStbn {
            guard let m = STBN3DMaskLoader.loadTiled(), m.count == tiles.count * perFrame else {
                throw DetError.maskUnavailable
            }
            stbn = m
        }

        // Per-stage timing — surfaced so the cost of each verified kernel (and the
        // effect of any optimization) is visible in Console, not guessed at.
        let clk = ContinuousClock()
        var mark = clk.now
        func lap() -> Int { let ms = Self.milliseconds(clk.now - mark); mark = clk.now; return ms }

        // ── Stage 1: quantize (maximin seed + optional Lloyd) ─────────────────
        onStage(.quantize)
        var centroidsPerFrame: [[Int32]] = []
        centroidsPerFrame.reserveCapacity(tiles.count)
        for q in q16Frames {
            guard let r = SixFourNative.quantizeFrame(oklabQ16: q, k: k, lloydIters: lloydIters) else {
                throw DetError.stageFailed("quantize")
            }
            centroidsPerFrame.append(r.centroids)
        }
        let qMs = lap()

        // ── Stage 2: dither ───────────────────────────────────────────────────
        onStage(.dither)
        var indicesPerFrame: [[UInt8]] = []
        indicesPerFrame.reserveCapacity(tiles.count)
        for (f, q) in q16Frames.enumerated() {
            let slice: [UInt8]? = needStbn ? Array(stbn![(f * perFrame)..<((f + 1) * perFrame)]) : nil
            guard let idx = SixFourNative.ditherFrame(
                oklabQ16: q, centroids: centroidsPerFrame[f], k: k,
                mode: mode, serpentine: dither.serpentine, stbnSlice: slice
            ) else { throw DetError.stageFailed("dither") }
            indicesPerFrame.append(idx)
        }
        let dMs = lap()

        // ── Stage 3: significance split-fill ──────────────────────────────────
        onStage(.significance)
        var cellsPerFrame: [[SixFourSignificantCell]] = []
        cellsPerFrame.reserveCapacity(tiles.count)
        for (f, q) in q16Frames.enumerated() {
            guard let r = SixFourNative.significanceFill(
                oklabQ16: q, centroids: centroidsPerFrame[f], k: k,
                minPop: minPop, indices: indicesPerFrame[f]
            ) else { throw DetError.stageFailed("significance") }
            indicesPerFrame[f] = r.indices
            cellsPerFrame.append(Self.cells(from: r.cellStats, k: k, minPop: minPop))
        }
        let sMs = lap()

        // ── Stage 4: palette → sRGB8 ──────────────────────────────────────────
        onStage(.palette)
        var palettesRGBFlat: [UInt8] = []
        palettesRGBFlat.reserveCapacity(tiles.count * k * 3)
        var srgbPalettes: [[SIMD3<UInt8>]] = []
        srgbPalettes.reserveCapacity(tiles.count)
        for f in 0..<tiles.count {
            guard let rgb = SixFourNative.paletteToSRGB8(centroidsQ16: centroidsPerFrame[f], k: k) else {
                throw DetError.stageFailed("palette")
            }
            palettesRGBFlat.append(contentsOf: rgb)
            var pal: [SIMD3<UInt8>] = []
            pal.reserveCapacity(k)
            for j in 0..<k { pal.append(SIMD3(rgb[j * 3], rgb[j * 3 + 1], rgb[j * 3 + 2])) }
            srgbPalettes.append(pal)
        }
        let pMs = lap()

        // Per-frame diagnostics (quantization MSE + gamut coverage), computed in
        // the same Q16 integer domain so the Review numbers match the bytes.
        var perFrameMSE = [Float]()
        var perFrameCoverage = [Int]()
        perFrameMSE.reserveCapacity(tiles.count)
        perFrameCoverage.reserveCapacity(tiles.count)
        for f in 0..<tiles.count {
            let cents = centroidsPerFrame[f]
            let idx = indicesPerFrame[f]
            let q = q16Frames[f]
            var acc: Int64 = 0
            for i in 0..<perFrame {
                let c = Int(idx[i]) * 3
                let dl = Int64(q[i * 3 + 0] - cents[c + 0])
                let da = Int64(q[i * 3 + 1] - cents[c + 1])
                let db = Int64(q[i * 3 + 2] - cents[c + 2])
                acc += dl * dl + da * da + db * db
            }
            perFrameMSE.append(Float(Double(acc) / Double(perFrame) / (65536.0 * 65536.0)))
            // Distinct 16³ OKLab bins among the centroids (matches Spec.Coverage).
            var bins = Set<Int>()
            for j in 0..<k {
                let bL = min(15, max(0, (Int(cents[j * 3 + 0]) * 16) >> 16))
                let bA = min(15, max(0, ((Int(cents[j * 3 + 1]) + 32768) * 16) >> 16))
                let bB = min(15, max(0, ((Int(cents[j * 3 + 2]) + 32768) * 16) >> 16))
                bins.insert(bL * 256 + bA * 16 + bB)
            }
            perFrameCoverage.append(bins.count)
        }
        let meanMSE = perFrameMSE.isEmpty ? 0 : perFrameMSE.reduce(0, +) / Float(perFrameMSE.count)

        // ── Stage 5: LZW / GIF89a ─────────────────────────────────────────────
        onStage(.encode)
        let flatIndices = indicesPerFrame.flatMap { $0 }
        guard let gif = SixFourNative.gifAssemble(
            indices: flatIndices, palettesRGB: palettesRGBFlat,
            frameCount: tiles.count, side: side, k: k, delayCs: 5, comment: comment
        ) else { throw DetError.stageFailed("encode") }

        let sha = SHA256.hash(data: gif).map { String(format: "%02x", $0) }.joined()
        let eMs = lap()
        let totalMs = qMs + dMs + sMs + pMs + eMs
        // One surfaced line: where every millisecond went + the reproducible
        // fingerprint. Pairs with the Zig per-kernel logs (category native.zig).
        // .notice (not .info) so this headline proof PERSISTS to the unified log
        // store — findable after the fact via `log show`, not live-stream-only.
        Self.logger.notice(
            "[deterministic] \(tiles.count)f → \(gif.count)B in \(totalMs)ms [quant \(qMs) · dither \(dMs) · signif \(sMs) · palette \(pMs) · encode \(eMs)] sha256 \(sha.prefix(12), privacy: .public)…"
        )

        return Result(
            gifData: gif,
            frameIndices: indicesPerFrame,
            srgbPalettes: srgbPalettes,
            cells: cellsPerFrame,
            sha256Hex: sha,
            perFrameMSE: perFrameMSE,
            perFrameCoverage: perFrameCoverage,
            meanExtractMSE: meanMSE
        )
    }

    static func milliseconds(_ d: Duration) -> Int {
        let (s, attos) = d.components
        return Int(s) * 1_000 + Int(attos / 1_000_000_000_000_000)
    }

    /// Convert the kernel's k×7 Q16 cell stats into typed significance cells.
    private static func cells(from stats: [Int32], k: Int, minPop: Int) -> [SixFourSignificantCell] {
        (0..<k).map { j in
            let b = j * 7
            let mean = SIMD3<Float>(Float(stats[b + 0]) / 65536, Float(stats[b + 1]) / 65536, Float(stats[b + 2]) / 65536)
            let std = SIMD3<Float>(Float(stats[b + 3]) / 65536, Float(stats[b + 4]) / 65536, Float(stats[b + 5]) / 65536)
            let n = Int(stats[b + 6])
            let prov: SixFourProvenance = n >= minPop ? .extracted : .degenerate
            return SixFourSignificantCell(mean: mean, stdDev: std, count: n, provenance: prov)
        }
    }
}
