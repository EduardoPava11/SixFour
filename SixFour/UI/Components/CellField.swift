import SwiftUI
import UIKit
import simd

/// The background CELL FIELD — the whole screen tiled with cells on the locked
/// 201×437 @2pt lattice (docs/cell-lattice-widget-spec.md). Every non-widget cell
/// is a darkened, camera-responsive shade of the live scene tint, with a subtle
/// 4×4 Bayer two-shade texture so the lattice is visibly *tiled* (not a flat wall).
///
/// Rendering model (the locked perf contract): the field is one small indexed
/// bitmap written byte-by-byte into a pixel buffer, then drawn ONCE via
/// `.interpolation(.none)` and upscaled to fill the screen — never thousands of
/// per-cell `Canvas` fills (`fillCell` is scoped to the ≤256-cell palette only).
enum CellField {
    static let cols = 201
    static let rows = 437

    /// 4×4 Bayer matrix (0…15) — the ordered-dither threshold that makes the cell
    /// texture visible without gridline noise.
    private static let bayer: [[Int]] = [
        [0, 8, 2, 10], [12, 4, 14, 6], [3, 11, 1, 9], [15, 7, 13, 5],
    ]

    /// Build the `cols × rows` indexed bitmap for a given live scene tint. Each
    /// cell = the tint darkened to a dark ground, with half the cells one shade
    /// deeper (Bayer) so the grid reads as tiles. `UIImage(cgImage:)` is scale 1,
    /// so `.size` is in pixels == cells.
    static func image(tint: SIMD3<UInt8>) -> UIImage? {
        @inline(__always) func scale(_ v: UInt8, _ f: Double) -> UInt8 {
            UInt8(max(0, min(255, (Double(v) * f).rounded())))
        }
        // Dark ground (low lightness → white widgets stay readable); two shades.
        let groundF = 0.24, deepF = groundF * 0.82
        let r0 = scale(tint.x, groundF), g0 = scale(tint.y, groundF), b0 = scale(tint.z, groundF)
        let r1 = scale(tint.x, deepF), g1 = scale(tint.y, deepF), b1 = scale(tint.z, deepF)

        var px = [UInt8](repeating: 0, count: cols * rows * 4)
        for y in 0 ..< rows {
            let by = bayer[y & 3]
            for x in 0 ..< cols {
                let deep = by[x & 3] >= 8
                let i = (y * cols + x) * 4
                px[i + 0] = deep ? r1 : r0
                px[i + 1] = deep ? g1 : g0
                px[i + 2] = deep ? b1 : b0
                px[i + 3] = 255
            }
        }

        let cs = CGColorSpaceCreateDeviceRGB()
        let info = CGImageAlphaInfo.premultipliedLast.rawValue
        return px.withUnsafeMutableBytes { raw -> UIImage? in
            guard let ctx = CGContext(
                data: raw.baseAddress, width: cols, height: rows, bitsPerComponent: 8,
                bytesPerRow: cols * 4, space: cs, bitmapInfo: info
            ), let cg = ctx.makeImage() else { return nil }
            return UIImage(cgImage: cg)
        }
    }
}

/// Full-screen tiled cell field, nearest-neighbour upscaled so each source cell is
/// a hard 2pt (6 device-px) tile. Recomputes only when the live tint changes.
struct CellFieldView: View {
    let tint: SIMD3<UInt8>

    var body: some View {
        GeometryReader { geo in
            if let img = CellField.image(tint: tint) {
                Image(uiImage: img)
                    .interpolation(.none)
                    .resizable()
                    .frame(width: geo.size.width, height: geo.size.height)
            } else {
                Color.black
            }
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }
}
