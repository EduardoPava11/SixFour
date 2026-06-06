import SwiftUI
import UIKit
import Foundation
import Observation
import simd

/// THE 20 fps REFRESH HEARTBEAT — a full-screen B/W checkerboard of the ONE atom
/// (`gifPx` = 4 pt) that inverts every frame at 20 fps, proving the canvas is
/// live. Every checker cell is the SAME size as a preview pixel and a palette swatch — one
/// uniform grid. The preview / palette / gear are opaque and drawn ON TOP, so the checker
/// simply tiles the whole screen behind them.
///
/// RENDERING: the checker is CELLS, never vector strokes — one indexed bitmap baked at the
/// lattice resolution (`SixFourLattice.cols × rows`) and drawn once `.interpolation(.none)`,
/// upscaled by the integer cell size. Opaque sRGB8 only; no `Path`/`.stroke`/`.opacity`.
/// Off the deterministic GIF path → pure Layers 0–2.

// MARK: - The uniform checker
//
// The 20 fps heartbeat is owned by the ONE κ clock (`SurfaceClock`). `GridHeartbeatClock`
// (a private Foundation `Timer`) was removed when the one-surface spine collapsed every
// clock onto the single `CADisplayLink`. The checker view below now reads κ's `heartbeat`
// bit directly. `GridChecker` (the parity math) + `GridRefreshFieldView` (the O(1)-flip
// texture-swap view) are reused by the live / capturing / rendering phase fields.

enum GridChecker {
    /// Opaque white, slightly under 255 so it reads as *cells*, not a flat field.
    static let white = SIMD3<UInt8>(235, 235, 235)
    /// Near-black, NOT pure 0, so the dark square stays a readable cell.
    static let dark = SIMD3<UInt8>(16, 16, 16)

    /// The checker colour at cell `(c, r)` for a `phase`: `(c + r)` parity, inverted when
    /// `phase & 1` is set.
    @inline(__always)
    static func color(_ c: Int, _ r: Int, phase: Int) -> SIMD3<UInt8> {
        let lit = ((c + r) & 1) == 1
        return (lit != ((phase & 1) == 1)) ? white : dark
    }

    /// Bake the full-screen checker as one `cols × rows` indexed bitmap (1 px == 1 cell).
    static func image(phase: Int) -> UIImage? {
        let cols = SixFourLattice.cols, rows = SixFourLattice.rows
        var px = [UInt8](repeating: 0, count: cols * rows * 4)
        for y in 0 ..< rows {
            for x in 0 ..< cols {
                let c = color(x, y, phase: phase)
                let i = (y * cols + x) * 4
                px[i + 0] = c.x; px[i + 1] = c.y; px[i + 2] = c.z; px[i + 3] = 255
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

// MARK: - The live grid view (O(1)-flip)

/// The capture screen's living ground: a full 4 pt B/W checker with the 20 fps heartbeat.
/// The two phases are pre-baked into TWO `UIImage`s once; each tick is a `UIImage` SWAP
/// (the GPU samples the other texture), not a per-cell re-bake.
struct GridRefreshFieldView: View {
    /// The 20 fps phase bit from `GridHeartbeatClock`; selects which pre-baked image shows.
    let phase: Int

    @State private var pair: (UIImage?, UIImage?)? = nil

    private func ensurePair() -> (UIImage?, UIImage?) {
        if let p = pair { return p }
        let p = (GridChecker.image(phase: 0), GridChecker.image(phase: 1))
        pair = p
        return p
    }

    var body: some View {
        let (i0, i1) = ensurePair()
        let img = (phase & 1) == 1 ? i1 : i0
        return Group {
            if let img {
                Image(uiImage: img)
                    .interpolation(.none)
                    .resizable()
                    .frame(width: GlobalLattice.gif(SixFourLattice.cols),
                           height: GlobalLattice.gif(SixFourLattice.rows))
            } else {
                Color.black
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color.black)
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }
}
