import SwiftUI
import UIKit
import simd

/// A widget drawn as a square block of CELLS at the one global pitch
/// (`GlobalLattice.cellPt` = 2 pt), per the GRID design language (Law #1: one cell size
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
                .frame(width: GlobalLattice.pt(cols), height: GlobalLattice.pt(rows))
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

/// GRID component **`CellButton`** — the shutter as a 34×34-cell block (68 pt): a
/// 2-cell ring band directly abutting a filled disc, white idle / red busy. Shape
/// only; the caller wraps it in the tappable Button so hit-rect == painted cell-rect.
/// States are expressed ONLY as cell transforms (no opacity/glass/glow): idle ·
/// busy (red) · disabled (50% 2×2 checker over the block).
struct CellButton: View {
    enum State { case idle, busy, disabled }
    var state: State = .idle
    private let n = GlobalLattice.shutterCells   // 34
    var body: some View {
        // The closure law, proven in Spec.Lattice (lawShutterClosure): disc(r=15)·2 +
        // ring(t=2)·2 = 34. Disc and ring band are DIRECTLY ABUTTED — the prior
        // d<=13 / d>=15 left an unspecified annulus the spec now forbids.
        let r = Double(GlobalLattice.shutterDiscRadiusCells)      // 15
        let t = Double(GlobalLattice.shutterRingThicknessCells)   // 2
        let fill: SIMD3<UInt8> = state == .busy ? SIMD3(220, 60, 60) : SIMD3(255, 255, 255)
        let cx = Double(n) / 2, cy = Double(n) / 2
        CellSprite(cols: n, rows: n) { c, r2 in
            let d = CellGeom.dist(c, r2, cx, cy)
            let onShape = d <= r || (d > r && d <= r + t)   // filled disc + 2-cell ring
            guard onShape else { return nil }
            if state == .disabled {
                // 2×2 checker dims the block without opacity (Law #2: no alpha on a cell).
                let checkOn = ((c / 2) + (r2 / 2)) % 2 == 0
                return checkOn ? fill : SFTheme.ledGhost
            }
            return fill
        }
        .accessibilityHidden(true)
    }
}

/// Back-compat shape alias: the shutter is a `CellButton`.
struct CellShutter: View {
    var busy: Bool = false
    var disabled: Bool = false
    var body: some View {
        CellButton(state: disabled ? .disabled : (busy ? .busy : .idle))
    }
}

/// GRID component **`CellIcon`** — pixel iconography drawn as a `box×box` cell mask
/// via the `CellSprite` path. The mask is a pure `(col,row) -> Bool` predicate; `ink`
/// fills the on-cells. Even boxes give a 2-cell geometric centre.
struct CellIcon: View {
    let box: Int
    var ink: SIMD3<UInt8> = SIMD3(235, 235, 235)
    let mask: (_ col: Int, _ row: Int, _ cx: Double, _ cy: Double) -> Bool
    var body: some View {
        let cx = Double(box) / 2, cy = Double(box) / 2
        CellSprite(cols: box, rows: box) { c, r in
            mask(c, r, cx, cy) ? ink : nil
        }
        .accessibilityHidden(true)
    }
}

extension CellIcon {
    /// The settings gear: donut hub + body ring + 8 teeth, by angle/distance math.
    static func gear(ink: SIMD3<UInt8> = SIMD3(235, 235, 235)) -> CellIcon {
        CellIcon(box: GlobalLattice.controlCells, ink: ink) { c, r, cx, cy in
            let d = CellGeom.dist(c, r, cx, cy)
            if d >= 2 && d <= 4.2 { return true }                // hub donut (hole < 2)
            if d >= 5 && d <= 8.5 { return true }                // body ring
            if d > 8.5 && d <= 10.5 {                            // 8 teeth
                let frac = (CellGeom.turn(c, r, cx, cy) * 8).truncatingRemainder(dividingBy: 1)
                return frac >= 0.33 && frac <= 0.67
            }
            return false
        }
    }

    /// The diamond ◇: 4 midpoint-line edges around a 2-cell centre. A real cell icon,
    /// replacing the Unicode `◇` glyph (the count readout adopts this in the CellGlyph phase).
    static func diamond(box: Int = 12, ink: SIMD3<UInt8> = SIMD3(235, 235, 235)) -> CellIcon {
        CellIcon(box: box, ink: ink) { c, r, cx, cy in
            // |Δcol| + |Δrow| ≈ radius defines a diamond edge (Manhattan ring).
            let m = abs(Double(c) + 0.5 - cx) + abs(Double(r) + 0.5 - cy)
            let radius = Double(box) / 2 - 1
            return m >= radius - 1 && m <= radius
        }
    }
}

/// Back-compat alias: the settings gear is a `CellIcon`.
struct CellGear: View {
    var ink: SIMD3<UInt8> = SIMD3(235, 235, 235)
    var body: some View { CellIcon.gear(ink: ink) }
}

/// GRID component **`CellRing`** — the diversity gauge: a 60×60-cell ring (120 pt) of
/// 64 radial ticks (one per frame) plus a faint axis circle the ticks radiate from.
/// `gauge` ∈ 0…1 lights ticks clockwise from top in the scene tint; unlit ticks are
/// short `ledGhost` outer stubs. Decorative (value spoken on the shutter).
///
/// The tick angular positions come from the **golden** `SixFourCellShapes` table (via
/// `CellShapes.cellAtRadius`, the closed-form `θ_k` step), NOT a per-cell `atan2` scan
/// — fixing the audited "recompute θ→cell live, no golden table" drift.
struct CellRing: View {
    var gauge: Double
    var tint: SIMD3<UInt8>
    private let n = GlobalLattice.ringCells     // 60
    private let ticks = GlobalLattice.ringTicks // 64
    private let rInner = 24.0
    var body: some View {
        let lit = max(0, min(ticks, Int((gauge * Double(ticks)).rounded())))
        let ghost = SFTheme.ledGhost
        let rOuter = CellShapes.ringTickRadius   // 29 (golden)

        // Precompute tick → cells from the golden θ_k (O(ticks·radii), once per update;
        // the true Pass-A static bake awaits `setCell`, Phase 4). `tickOf` maps an
        // encoded cell to its tick index; `outer` is the cells at radius ≥ 27.
        var tickOf = [Int: Int]()
        var outer = Set<Int>()
        var rad = rInner
        while rad <= rOuter {
            for k in 0..<ticks {
                let cell = CellShapes.cellAtRadius(side: n, radius: rad, tick: k, ticks: ticks)
                guard cell.col >= 0, cell.col < n, cell.row >= 0, cell.row < n else { continue }
                let key = cell.row * n + cell.col
                tickOf[key] = k
                if rad >= 27 { outer.insert(key) }
            }
            rad += 1
        }

        return CellSprite(cols: n, rows: n) { c, r in
            let key = r * n + c
            if let k = tickOf[key] {
                if k < lit { return tint }                       // active: full radial stub
                return outer.contains(key) ? ghost : nil         // inactive: outer stub only
            }
            // The axis circle: a faint 1-cell ghost ring the ticks attach to.
            if CellShapes.inAnnulus(side: n, rInner - 1, rInner, c, r) { return ghost }
            return nil
        }
        .accessibilityHidden(true)
    }
}

/// Back-compat alias for the diversity gauge.
struct CellDiversityRing: View {
    var gauge: Double
    var tint: SIMD3<UInt8>
    var body: some View { CellRing(gauge: gauge, tint: tint) }
}
