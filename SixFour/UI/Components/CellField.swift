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
/// A static-chrome cell mask placed at an absolute lattice origin, for the Pass-A
/// bake (GRID Law #4). `cell(localCol, localRow)` returns the opaque sRGB8 for a cell
/// of the mask, or `nil` for a transparent cell. The mask is composited into the field
/// buffer at `(originCol, originRow)` via `CellField.setCell` — the ONLY writer of a
/// HUD cell into the Pass-A bitmap.
struct PlacedCellMask {
    let originCol: Int
    let originRow: Int
    let cols: Int
    let rows: Int
    let cell: (_ localCol: Int, _ localRow: Int) -> SIMD3<UInt8>?
}

enum CellField {
    static let cols = GlobalLattice.cols   // 201 — owned by the lattice (Law #5)
    static let rows = GlobalLattice.rows   // 437

    /// 4×4 Bayer matrix (0…15) — the ordered-dither threshold that makes the cell
    /// texture visible without gridline noise.
    private static let bayer: [[Int]] = [
        [0, 8, 2, 10], [12, 4, 14, 6], [3, 11, 1, 9], [15, 7, 13, 5],
    ]

    /// GRID Law #4 — the Pass-A static-chrome byte writer. Writes one opaque cell into
    /// the field buffer at lattice `(col, row)`; out-of-bounds is a no-op. This is the
    /// *only* way a HUD cell is written into the baked bitmap (distinct from the
    /// Review-only `fillCell`).
    @inline(__always)
    static func setCell(_ px: inout [UInt8], col: Int, row: Int, _ c: SIMD3<UInt8>) {
        guard col >= 0, col < cols, row >= 0, row < rows else { return }
        let i = (row * cols + col) * 4
        px[i + 0] = c.x; px[i + 1] = c.y; px[i + 2] = c.z; px[i + 3] = 255
    }

    /// Build the `cols × rows` indexed bitmap for a given live scene tint, then
    /// composite any static `chrome` into the SAME buffer via `setCell` — one Pass-A
    /// bitmap drawn once (Law #4). Each field cell = the tint darkened to a dark
    /// ground, with half the cells one shade deeper (Bayer) so the grid reads as
    /// tiles. `UIImage(cgImage:)` is scale 1, so `.size` is in pixels == cells.
    static func image(tint: SIMD3<UInt8>, chrome: [PlacedCellMask] = []) -> UIImage? {
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

        // Pass-A: bake every static-chrome cell into the field buffer via setCell.
        for mask in chrome {
            for lr in 0 ..< mask.rows {
                for lc in 0 ..< mask.cols {
                    if let c = mask.cell(lc, lr) {
                        setCell(&px, col: mask.originCol + lc, row: mask.originRow + lr, c)
                    }
                }
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
/// a hard 2 pt (6 device-px) tile. Recomputes only when the live tint changes.
///
/// CRISP-PIXEL CONTRACT (GRID Law #2 / INTEGER SCALE ONLY): the field is drawn at the
/// EXACT locked lattice size — `GlobalLattice.pt(cols) × pt(rows)` = 402 × 874 pt = one
/// integer 2 pt cell per source pixel — then centred and bled to the screen edges. It is
/// NEVER stretched to a raw `GeometryReader` size (that yielded a non-integer scale and
/// resampled the cells to mush). Per design §2.3 the field is pinned to the iPhone 17 Pro
/// anchor and only *shifted* by whole cells for safe areas, never scaled to fit.
struct CellFieldView: View {
    let tint: SIMD3<UInt8>
    /// Optional Pass-A static chrome baked into the field bitmap via `setCell`
    /// (Law #4). Empty by default, so existing call sites are unchanged.
    var chrome: [PlacedCellMask] = []

    var body: some View {
        Group {
            if let img = CellField.image(tint: tint, chrome: chrome) {
                Image(uiImage: img)
                    .interpolation(.none)
                    .resizable()
                    .frame(width: GlobalLattice.gif(CellField.cols),    // 67·6 = 402 — exact atom pitch
                           height: GlobalLattice.gif(CellField.rows))   // 145·6 = 870 (+4 pt bleed) — no resample
            } else {
                Color.black
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)   // centre the anchored field
        .background(Color.black)                            // any sub-anchor edge sliver = black
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }
}

/// Pass-A static-chrome producers — each returns a `PlacedCellMask` positioned at its
/// absolute §7.1 band-map origin, for `CellField.image(tint:chrome:)` to bake (Law #4).
///
/// Status: this is the verified `setCell` Pass-A *primitive* with a working consumer
/// (the ring axis + inactive ticks, demonstrated below). The full live migration of
/// the HUD onto the Pass-A bake is gated on two open items recorded in
/// `docs/SIXFOUR-DESIGN-MAP.md`: (1) the §7.1 band map's wordmark/gear column overlap
/// needs design resolution, and (2) text chrome (wordmark/count/sampler) needs the
/// `CellFont` masters to bake. Geometry chrome (this) is ready now.
enum CellChrome {
    /// The diversity ring's STATIC layer — the axis circle + all 64 inactive tick
    /// outer stubs in `ledGhost` — at the ring's band-map origin (cols 70–129, rows
    /// 240–299, index-midpoint 99.5/269.5). The lit band stays a Pass-B overlay.
    static func ringAxis(originCol: Int = 70, originRow: Int = 240) -> PlacedCellMask {
        let n = GlobalLattice.ringCells          // 60
        let ticks = GlobalLattice.ringTicks      // 64
        let ghost = SFTheme.ledGhost
        // Inactive tick outer stubs (radius ≥ 27), from the golden θ_k table — no atan2.
        var stub = Set<Int>()
        var rad = 27.0
        while rad <= CellShapes.ringTickRadius {
            for k in 0 ..< ticks {
                let c = CellShapes.cellAtRadius(side: n, radius: rad, tick: k, ticks: ticks)
                if c.col >= 0, c.col < n, c.row >= 0, c.row < n { stub.insert(c.row * n + c.col) }
            }
            rad += 1
        }
        return PlacedCellMask(originCol: originCol, originRow: originRow, cols: n, rows: n) { lc, lr in
            if stub.contains(lr * n + lc) { return ghost }                 // inactive ticks
            if CellShapes.inAnnulus(side: n, 23.0, 24.0, lc, lr) { return ghost }   // axis circle
            return nil
        }
    }
}

#Preview("Pass-A bake (setCell): field + ring axis") {
    // Demonstrates the Law #4 two-pass primitive: the field + the static ring axis
    // composited into ONE indexed bitmap via setCell, drawn once.
    CellFieldView(tint: SIMD3<UInt8>(120, 140, 200), chrome: [CellChrome.ringAxis()])
}
