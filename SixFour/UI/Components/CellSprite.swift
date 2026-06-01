import SwiftUI
import UIKit
import simd

/// A widget drawn as a square block of CELLS at the one global pitch
/// (`SFTheme.cellPt` = 2 pt), per the GRID design language (Law #1: one cell size
/// everywhere — widgets grow by more cells, never a bigger cell). Each cell's
/// colour is computed by pure math (distance / angle), baked into a tiny
/// `cols × rows` indexed bitmap, and nearest-neighbour upscaled — the same
/// discipline as `CellField` / `PixelImage`. No vectors, no AA, no glass.
enum CellBitmap {
    /// Build a `cols × rows` RGBA image (1 px per cell). `color` returns the cell's
    /// sRGB8, or `nil` for a transparent cell. `UIImage(cgImage:)` is scale 1, so
    /// `.size` is in pixels == cells.
    static func image(cols: Int, rows: Int, color: (_ col: Int, _ row: Int) -> SIMD3<UInt8>?) -> UIImage? {
        guard cols > 0, rows > 0 else { return nil }
        var px = [UInt8](repeating: 0, count: cols * rows * 4)
        for r in 0 ..< rows {
            for c in 0 ..< cols {
                guard let s = color(c, r) else { continue }   // transparent
                let i = (r * cols + c) * 4
                px[i + 0] = s.x; px[i + 1] = s.y; px[i + 2] = s.z; px[i + 3] = 255
            }
        }
        let cs = CGColorSpaceCreateDeviceRGB()
        let info = CGImageAlphaInfo.premultipliedLast.rawValue
        return px.withUnsafeMutableBytes { raw -> UIImage? in
            guard let ctx = CGContext(data: raw.baseAddress, width: cols, height: rows,
                                      bitsPerComponent: 8, bytesPerRow: cols * 4,
                                      space: cs, bitmapInfo: info),
                  let cg = ctx.makeImage() else { return nil }
            return UIImage(cgImage: cg)
        }
    }
}

/// Renders a cell bitmap at the global 2 pt pitch.
struct CellSprite: View {
    let cols: Int
    let rows: Int
    let color: (_ col: Int, _ row: Int) -> SIMD3<UInt8>?

    var body: some View {
        if let img = CellBitmap.image(cols: cols, rows: rows, color: color) {
            Image(uiImage: img)
                .interpolation(.none)
                .resizable()
                .frame(width: CGFloat(cols) * SFTheme.cellPt, height: CGFloat(rows) * SFTheme.cellPt)
        }
    }
}

// MARK: - Cell geometry (pure)

enum CellGeom {
    /// Distance from cell (c,r) centre to (cx,cy), in cells.
    @inline(__always) static func dist(_ c: Int, _ r: Int, _ cx: Double, _ cy: Double) -> Double {
        let dx = Double(c) + 0.5 - cx, dy = Double(r) + 0.5 - cy
        return (dx * dx + dy * dy).squareRoot()
    }
    /// Angle of cell (c,r) about (cx,cy): 0 at top, clockwise, normalised to [0,1).
    @inline(__always) static func turn(_ c: Int, _ r: Int, _ cx: Double, _ cy: Double) -> Double {
        let dx = Double(c) + 0.5 - cx, dy = Double(r) + 0.5 - cy
        var a = atan2(dx, -dy)
        if a < 0 { a += 2 * Double.pi }
        return a / (2 * Double.pi)
    }
}

// MARK: - HUD widgets, all on the 2 pt cell

/// The shutter — a 34×34-cell block (68 pt): a 2-cell ring band + a filled disc,
/// white idle / red busy. GRID component `CellButton` (shape only; the caller wraps
/// it in the tappable Button so hit-rect == cell-rect).
struct CellShutter: View {
    var busy: Bool = false
    private let n = 34
    var body: some View {
        let fill: SIMD3<UInt8> = busy ? SIMD3(220, 60, 60) : SIMD3(255, 255, 255)
        let cx = Double(n) / 2, cy = Double(n) / 2
        CellSprite(cols: n, rows: n) { c, r in
            let d = CellGeom.dist(c, r, cx, cy)
            if d <= 13 { return fill }            // inner disc
            if d >= 15 && d <= 17 { return fill } // ring band, 1-cell clear annulus
            return nil
        }
        .accessibilityHidden(true)
    }
}

/// The settings gear — a 24×24-cell icon (48 pt): donut hub + body ring + 8 teeth,
/// all by angle/distance math. Tinted by the live scene (chrome reflects content).
struct CellGear: View {
    var ink: SIMD3<UInt8> = SIMD3(235, 235, 235)
    private let n = 24
    var body: some View {
        let cx = Double(n) / 2, cy = Double(n) / 2
        CellSprite(cols: n, rows: n) { c, r in
            let d = CellGeom.dist(c, r, cx, cy)
            if d >= 2 && d <= 4.2 { return ink }                 // hub donut (hole < 2)
            if d >= 5 && d <= 8.5 { return ink }                 // body ring
            if d > 8.5 && d <= 10.5 {                            // 8 teeth
                let frac = (CellGeom.turn(c, r, cx, cy) * 8).truncatingRemainder(dividingBy: 1)
                if frac >= 0.33 && frac <= 0.67 { return ink }
            }
            return nil
        }
        .accessibilityHidden(true)
    }
}

/// The diversity gauge — a 60×60-cell ring (120 pt) of 64 radial ticks (one per
/// frame). `gauge` ∈ 0…1 lights ticks clockwise from top in the scene tint; unlit
/// ticks are short `ledGhost` stubs. Decorative (value spoken on the shutter).
struct CellDiversityRing: View {
    var gauge: Double
    var tint: SIMD3<UInt8>
    private let n = 60
    private let ticks = 64
    var body: some View {
        let cx = Double(n) / 2, cy = Double(n) / 2
        let lit = max(0, min(ticks, Int((gauge * Double(ticks)).rounded())))
        let ghost = SFTheme.ledGhost
        CellSprite(cols: n, rows: n) { c, r in
            let d = CellGeom.dist(c, r, cx, cy)
            guard d >= 24 && d <= 29 else { return nil }
            let a = CellGeom.turn(c, r, cx, cy)
            let idx = Int((a * Double(ticks)).rounded()) % ticks
            let center = Double(idx) / Double(ticks)
            let da = min(abs(a - center), 1 - abs(a - center))
            guard da < 0.006 else { return nil }                 // discrete tick
            if idx < lit { return tint }                         // active: full 5-cell radial
            return d >= 27 ? ghost : nil                         // inactive: short outer stub
        }
        .accessibilityHidden(true)
    }
}
