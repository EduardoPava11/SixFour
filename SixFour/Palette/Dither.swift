import Foundation
import simd

/// Error-diffusion dithering on OKLab tiles. The name `errorDiffuse`
/// reflects what the function actually does — the older
/// `floydSteinberg` name was misleading once the kernel parameter let
/// callers pick Atkinson (Apple 1984) instead. Floyd–Steinberg (Floyd
/// & Steinberg 1976) and Atkinson are both first-class `ErrorKernel`
/// values.
///
/// Generic over the distance metric so the compiler can monomorphise
/// the inner nearest-centroid loop (1 M dispatches/frame at K=256,
/// 4096 px). Existential `any DistanceMetric` would burn ~30 ns/call
/// in the value-witness table; the generic specialisation shaves that
/// to ~5 ns/call.
/// User-selectable dithering method — a creative option alongside the
/// extraction algorithm. Both methods feed `SignificantSplitFill.rescue`, so
/// either way the output is a complete 64³ voxel volume in which every slot is
/// significant (no empty slots, no count-1 outliers).
///
///   * `.errorDiffusion` — Floyd–Steinberg (default look). Sequential
///     (each pixel depends on diffused error from earlier pixels), so it
///     runs on CPU with the SIMD8 nearest-centroid search.
///   * `.blueNoise` — ordered dithering against a 3D blue-noise (STBN3D)
///     mask. Each voxel is independent → fully parallel → eligible for the
///     GPU matmul path (Phase D). Crisper, no error-diffusion "worm" artifacts.
enum DitherMethod: String, Codable, Sendable, Hashable, CaseIterable {
    case errorDiffusion
    case blueNoise

    var label: String {
        switch self {
        case .errorDiffusion: return "Diffusion"
        case .blueNoise:      return "Blue noise"
        }
    }

    /// One-word benefit shown under the selector segment title.
    var tagline: String {
        switch self {
        case .errorDiffusion: return "detail"
        case .blueNoise:      return "stable · fast"
        }
    }

    /// One-line explainer of the tradeoff, shown under the selector so the
    /// choice is communicated, not just offered. The split that matters for a
    /// 64-frame animation is detail-per-frame vs temporal stability across
    /// frames (Floyd–Steinberg ignores the time axis; the 3-D spatiotemporal
    /// blue-noise mask is decorrelated across frames).
    var blurb: String {
        switch self {
        case .errorDiffusion:
            return "Sharpest detail & texture. Each frame is dithered on its own (CPU), so fine grain can shimmer a little across the 64 frames."
        case .blueNoise:
            return "Clean gradients, steady across all 64 frames (3-D blue-noise), GPU-fast. Slightly softer on the finest texture."
        }
    }
}

/// Error-diffusion kernel choice — the residual-spectrum knob for the
/// Diffusion sampler. The kernel decides which statistical moment the
/// diffusion preserves:
///   * Floyd–Steinberg diffuses all 16/16 of the error to neighbours →
///     preserves the local **mean** (smooth gradients).
///   * Atkinson diffuses 6/8 and *absorbs* the other 25% → preserves local
///     **contrast** (crisper, punchier at a small palette).
enum DitherKernelChoice: String, Codable, Sendable, Hashable, CaseIterable {
    case floydSteinberg
    case atkinson

    var label: String {
        switch self {
        case .floydSteinberg: return "Floyd–Steinberg"
        case .atkinson:       return "Atkinson"
        }
    }

    var blurb: String {
        switch self {
        case .floydSteinberg:
            return "Diffuses all error to neighbours — preserves the local mean. Smoothest gradients."
        case .atkinson:
            return "Absorbs a quarter of the error — preserves local contrast. Crisper, punchier."
        }
    }

    /// The concrete tap kernel this choice maps to.
    var kernel: Dither.ErrorKernel {
        switch self {
        case .floydSteinberg: return .floydSteinberg
        case .atkinson:       return .atkinson
        }
    }
}

/// Temporal residual spectrum for the Blue-noise sampler across the 64 frames.
/// The STBN3D mask is decorrelated in time; this chooses whether to use that
/// time variation or freeze a single 2-D slice for every frame.
enum BlueNoiseTemporalMode: String, Codable, Sendable, Hashable, CaseIterable {
    /// Full 3-D mask: the dither pattern is decorrelated across frames →
    /// residual is white-in-time (no frozen texture; a faint shimmer).
    case spatiotemporal
    /// One 2-D slice reused every frame → residual is zero-in-time (perfectly
    /// steady, but the dither texture sits still).
    case frozen

    var label: String {
        switch self {
        case .spatiotemporal: return "Spatiotemporal"
        case .frozen:         return "Frozen"
        }
    }

    var blurb: String {
        switch self {
        case .spatiotemporal:
            return "3-D blue noise — the dot pattern is decorrelated across all 64 frames. No frozen texture; a faint shimmer."
        case .frozen:
            return "One 2-D pattern reused every frame — perfectly steady in time, but the dither texture stays put."
        }
    }
}

/// The full residual-shaping sampler configuration. This is the entire
/// creative-but-statistical surface of the pipeline — read from `AppSettings`
/// and threaded into `PaletteGenerator`/`GIFRenderer`. `.default` reproduces
/// the shipping look (Floyd–Steinberg, raster, spatiotemporal blue noise).
struct DitherConfig: Sendable, Hashable {
    var method: DitherMethod
    var kernel: DitherKernelChoice
    var serpentine: Bool
    var temporal: BlueNoiseTemporalMode

    static let `default` = DitherConfig(
        method: .errorDiffusion,
        kernel: .floydSteinberg,
        serpentine: false,
        temporal: .spatiotemporal
    )
}

enum Dither {

    /// Per-pixel index buffer for one frame. Indices are 0...palette.count-1.
    /// Direction is left-to-right raster (the original 1976 paper). For the
    /// serpentine variant, see `errorDiffuseSerpentine`.
    static func errorDiffuse<M: DistanceMetric>(
        tile: OKLabTile,
        palette: [SIMD3<Float>],
        metric: M = EuclideanOKLabMetric(),
        kernel: ErrorKernel = .floydSteinberg
    ) -> [UInt8] {
        precondition(palette.count <= 256, "Palette must fit in UInt8")
        let side = tile.side
        var buf = tile.pixels  // mutable working copy
        var out = [UInt8](repeating: 0, count: side * side)

        for y in 0..<side {
            for x in 0..<side {
                let idx = y * side + x
                let here = buf[idx]
                var bestK = 0
                var bestD: Float = .infinity
                for j in 0..<palette.count {
                    let d = metric.distanceSquared(here, palette[j])
                    if d < bestD { bestD = d; bestK = j }
                }
                out[idx] = UInt8(bestK)
                let quant = palette[bestK]
                let err = here - quant
                for tap in kernel.taps {
                    let nx = x + tap.dx
                    let ny = y + tap.dy
                    if nx < 0 || nx >= side || ny < 0 || ny >= side { continue }
                    let nidx = ny * side + nx
                    buf[nidx] += err * tap.weight
                }
            }
        }
        return out
    }

    /// Serpentine raster: even rows go left→right, odd rows right→left.
    /// Reduces the visible "worm" artifact that pure-raster Floyd–Steinberg
    /// can show on shallow gradients (Ulichney 1987 §6.2). Tap dx values are
    /// mirrored on right-to-left rows automatically.
    static func errorDiffuseSerpentine<M: DistanceMetric>(
        tile: OKLabTile,
        palette: [SIMD3<Float>],
        metric: M = EuclideanOKLabMetric(),
        kernel: ErrorKernel = .floydSteinberg
    ) -> [UInt8] {
        precondition(palette.count <= 256, "Palette must fit in UInt8")
        let side = tile.side
        var buf = tile.pixels
        var out = [UInt8](repeating: 0, count: side * side)

        for y in 0..<side {
            let leftToRight = (y % 2 == 0)
            let xs: [Int] = leftToRight ? Array(0..<side) : Array((0..<side).reversed())
            for x in xs {
                let idx = y * side + x
                let here = buf[idx]
                var bestK = 0
                var bestD: Float = .infinity
                for j in 0..<palette.count {
                    let d = metric.distanceSquared(here, palette[j])
                    if d < bestD { bestD = d; bestK = j }
                }
                out[idx] = UInt8(bestK)
                let quant = palette[bestK]
                let err = here - quant
                for tap in kernel.taps {
                    // Mirror dx on right-to-left passes so error propagates *ahead* of the scan.
                    let dx = leftToRight ? tap.dx : -tap.dx
                    let nx = x + dx
                    let ny = y + tap.dy
                    if nx < 0 || nx >= side || ny < 0 || ny >= side { continue }
                    let nidx = ny * side + nx
                    buf[nidx] += err * tap.weight
                }
            }
        }
        return out
    }

    /// Euclidean SIMD8 error-diffusion — the production path. Equivalent to
    /// `errorDiffuse`/`errorDiffuseSerpentine` with `EuclideanOKLabMetric`,
    /// but the per-pixel nearest-centroid search runs vectorised over 8
    /// centroids at a time via `CentroidSet.nearest` (the always-on hot loop).
    /// The error-diffusion sweep itself stays sequential (its inter-pixel
    /// dependency is irreducible); only the 256-wide centroid search is
    /// vectorised. Pass `serpentine: true` for the boustrophedon sweep.
    ///
    /// The generic `errorDiffuse(tile:palette:metric:kernel:)` above remains
    /// the scalar parity oracle (and the path for non-Euclidean metrics).
    static func errorDiffuseSIMD(
        tile: OKLabTile,
        centroids: CentroidSet,
        kernel: ErrorKernel = .floydSteinberg,
        serpentine: Bool = false
    ) -> [UInt8] {
        precondition(centroids.count <= 256, "Palette must fit in UInt8")
        let side = tile.side
        var buf = tile.pixels
        var out = [UInt8](repeating: 0, count: side * side)

        // Acquire the SoA pointers ONCE for the whole frame — never per pixel.
        centroids.withProbe { probe in
            for y in 0..<side {
                let leftToRight = !serpentine || (y % 2 == 0)
                let xStart = leftToRight ? 0 : side - 1
                let xEnd = leftToRight ? side : -1
                let xStep = leftToRight ? 1 : -1
                var x = xStart
                while x != xEnd {
                    let idx = y * side + x
                    let here = buf[idx]
                    let bestK = probe.nearest(here)
                    out[idx] = UInt8(bestK)
                    let err = here - probe.color(bestK)
                    for tap in kernel.taps {
                        // Mirror dx on right-to-left passes so error propagates ahead of the scan.
                        let dx = leftToRight ? tap.dx : -tap.dx
                        let nx = x + dx
                        let ny = y + tap.dy
                        if nx < 0 || nx >= side || ny < 0 || ny >= side { continue }
                        let nidx = ny * side + nx
                        buf[nidx] += err * tap.weight
                    }
                    x += xStep
                }
            }
        }
        return out
    }

    /// Blue-noise (ordered) dithering against a 3D STBN mask — the parallel
    /// alternative to error diffusion. For each pixel we find its two nearest
    /// centroids and pick between them by where the pixel sits on the line
    /// between them (`s ∈ [0,1]`) versus the per-voxel blue-noise threshold.
    /// No error buffer, no inter-pixel dependency, so every pixel is
    /// independent — this is what makes the whole-frame GPU matmul path
    /// possible (Phase D). `thresholds[i] ∈ 0...255` is this frame's slice of
    /// the tiled STBN3D mask (`STBN3DMaskLoader.loadTiled`).
    ///
    /// Significance is NOT guaranteed here (a flat frame may touch only a few
    /// centroids); the caller MUST follow with `SignificantSplitFill.rescue`,
    /// exactly as the error-diffusion path does.
    static func blueNoiseSIMD(
        tile: OKLabTile,
        centroids: CentroidSet,
        thresholds: [UInt8]
    ) -> [UInt8] {
        precondition(centroids.count <= 256, "Palette must fit in UInt8")
        let n = tile.side * tile.side
        precondition(thresholds.count == n, "thresholds must be one per pixel")
        var out = [UInt8](repeating: 0, count: n)
        let pixels = tile.pixels

        centroids.withProbe { probe in
            for i in 0..<n {
                let p = pixels[i]
                let (i0, i1) = probe.nearest2(p)
                if i0 == i1 {
                    out[i] = UInt8(i0)
                    continue
                }
                let c0 = probe.color(i0)
                let c1 = probe.color(i1)
                // Position of p along c0→c1, clamped to [0,1]. 0 = exactly at
                // the nearest centroid, →1 = toward the second.
                let axis = c1 - c0
                let denom = simd_dot(axis, axis)
                let s: Float = denom > 0
                    ? min(max(simd_dot(p - c0, axis) / denom, 0), 1)
                    : 0
                // Blue-noise threshold in (0,1); pick the farther centroid when
                // the pixel leans past the threshold toward it.
                let t = (Float(thresholds[i]) + 0.5) / 256.0
                out[i] = UInt8(s > t ? i1 : i0)
            }
        }
        return out
    }

    struct Tap: Sendable {
        let dx: Int
        let dy: Int
        let weight: Float
    }

    struct ErrorKernel: Sendable {
        let taps: [Tap]

        /// Floyd & Steinberg (1976), 7/3/5/1 forward weights.
        ///
        ///         [x]  7/16
        ///   3/16  5/16  1/16
        ///
        /// All 16/16 of the residual is preserved (only mean intensity is
        /// pegged exactly; high frequencies blur slightly).
        static let floydSteinberg = ErrorKernel(taps: [
            Tap(dx:  1, dy: 0, weight: 7.0 / 16.0),
            Tap(dx: -1, dy: 1, weight: 3.0 / 16.0),
            Tap(dx:  0, dy: 1, weight: 5.0 / 16.0),
            Tap(dx:  1, dy: 1, weight: 1.0 / 16.0),
        ])

        /// Atkinson (Apple, 1984): 6 taps × 1/8. Total diffused = 6/8 = 75 %;
        /// the remaining 25 % of error is *intentionally* absorbed —
        /// preserving local contrast at the cost of mean intensity, which is
        /// why Atkinson dithers look crisper at small palettes.
        ///
        ///         [x]  1/8  1/8
        ///   1/8  1/8  1/8
        ///         1/8
        static let atkinson = ErrorKernel(taps: [
            Tap(dx:  1, dy: 0, weight: 1.0 / 8.0),
            Tap(dx:  2, dy: 0, weight: 1.0 / 8.0),
            Tap(dx: -1, dy: 1, weight: 1.0 / 8.0),
            Tap(dx:  0, dy: 1, weight: 1.0 / 8.0),
            Tap(dx:  1, dy: 1, weight: 1.0 / 8.0),
            Tap(dx:  0, dy: 2, weight: 1.0 / 8.0),
        ])
    }
}
