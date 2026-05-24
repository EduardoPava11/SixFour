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
