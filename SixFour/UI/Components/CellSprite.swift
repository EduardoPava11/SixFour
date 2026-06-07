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

/// Renders a cell bitmap at a cell pitch. Defaults to the global 2 pt CAPTURE pitch
/// (`GlobalLattice.cellPt`); the Review-surface transport passes `cellPt:
/// SFTheme.gifCellPt` (6 pt) so the whole Review screen stays ONE pitch (GRID Law #5,
/// docs/SIXFOUR-UNIFIED-PLAYER.md decision 1). The pitch is the ONLY thing that
/// changes — the cell math, the no-AA upscale, and the bitmap are identical.
struct CellSprite: View {
    let cols: Int
    let rows: Int
    /// Points per cell. Default = the 2 pt capture lattice; pass `SFTheme.gifCellPt`
    /// for the 6 pt Review surface.
    var cellPt: CGFloat = GlobalLattice.pt(1)
    let color: (_ col: Int, _ row: Int) -> SIMD3<UInt8>?

    var body: some View {
        if let img = CellBitmap.image(cols: cols, rows: rows, color: color) {
            Image(uiImage: img)
                .interpolation(.none)
                .resizable()
                .frame(width: cellPt * CGFloat(cols), height: cellPt * CGFloat(rows))
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
        // Rendered at the gifPx ATOM (12·6 = 72 pt) — the shutter's pixels are the GIF's.
        CellSprite(cols: n, rows: n, cellPt: GlobalLattice.gifPx) { c, r2 in
            let d = CellGeom.dist(c, r2, cx, cy)
            let onShape = d <= r || (d > r && d <= r + t)   // filled disc + 1-cell ring
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
    /// Points per cell. Default = the 2 pt capture lattice; Review chrome passes
    /// `SFTheme.gifCellPt` (6 pt) for a chunky icon, or stays 2 pt for fine chrome.
    var cellPt: CGFloat = GlobalLattice.pt(1)
    let mask: (_ col: Int, _ row: Int, _ cx: Double, _ cy: Double) -> Bool
    var body: some View {
        let cx = Double(box) / 2, cy = Double(box) / 2
        CellSprite(cols: box, rows: box, cellPt: cellPt) { c, r in
            mask(c, r, cx, cy) ? ink : nil
        }
        .accessibilityHidden(true)
    }
}

extension CellIcon {
    /// The Share glyph: an up-arrow (stem + chevron) rising out of an open tray —
    /// the cell mirror of `square.and.arrow.up`.
    static func share(box: Int = 12, ink: SIMD3<UInt8> = SIMD3(235, 235, 235),
                      cellPt: CGFloat = GlobalLattice.pt(1)) -> CellIcon {
        CellIcon(box: box, ink: ink, cellPt: cellPt) { c, r, cx, _ in
            let midX = Int(cx)
            // Arrow stem (top half, centred 2 cells wide).
            if r >= 1 && r <= box / 2 && (c == midX - 1 || c == midX) { return true }
            // Chevron head at the very top.
            if r == 1 && (c == midX - 2 || c == midX + 1) { return true }
            if r == 2 && (c == midX - 3 || c == midX + 2) { return true }
            // Open tray: left/right walls + bottom, lower half.
            let trayTop = box / 2 + 1
            if r >= trayTop && (c == 2 || c == box - 3) { return true }
            if r == box - 2 && c >= 2 && c <= box - 3 { return true }
            return false
        }
    }

    /// The contact-sheet glyph: a 3×3 grid of square dots — the cell mirror of
    /// `square.grid.3x3`.
    static func grid3x3(box: Int = 12, ink: SIMD3<UInt8> = SIMD3(235, 235, 235),
                        cellPt: CGFloat = GlobalLattice.pt(1)) -> CellIcon {
        CellIcon(box: box, ink: ink, cellPt: cellPt) { c, r, _, _ in
            // Three dot bands at cells {2,3},{6,7} relative cols/rows → a 3×3 lattice.
            func band(_ v: Int) -> Bool { let m = v % 4; return (m == 1 || m == 2) && v >= 1 && v <= box - 2 }
            return band(c) && band(r)
        }
    }

    /// The Retake glyph: a near-closed circular arrow (an arc with a head) — the cell
    /// mirror of a refresh / re-shoot symbol.
    static func retake(box: Int = 12, ink: SIMD3<UInt8> = SIMD3(235, 235, 235),
                       cellPt: CGFloat = GlobalLattice.pt(1)) -> CellIcon {
        CellIcon(box: box, ink: ink, cellPt: cellPt) { c, r, cx, cy in
            let d = CellGeom.dist(c, r, cx, cy)
            let onRing = d >= Double(box) / 2 - 2.2 && d <= Double(box) / 2 - 0.8
            let turn = CellGeom.turn(c, r, cx, cy)        // 0 at top, clockwise
            // Ring with a gap at the top-right; a small arrowhead at the gap.
            if onRing && !(turn > 0.05 && turn < 0.20) { return true }
            if (c == Int(cx) + 2 || c == Int(cx) + 3) && r == 1 { return true }   // arrowhead
            return false
        }
    }

    /// The "all significant" seal: a filled disc (the cell mirror of
    /// `checkmark.seal.fill`). Tinted green by the caller.
    static func seal(box: Int = 12, ink: SIMD3<UInt8> = SIMD3(235, 235, 235),
                     cellPt: CGFloat = GlobalLattice.pt(1)) -> CellIcon {
        CellIcon(box: box, ink: ink, cellPt: cellPt) { c, r, cx, cy in
            CellGeom.dist(c, r, cx, cy) <= Double(box) / 2 - 0.6
        }
    }

    /// The warning glyph: a filled upward triangle (the cell mirror of
    /// `exclamationmark.triangle.fill`). Tinted yellow by the caller.
    static func warn(box: Int = 12, ink: SIMD3<UInt8> = SIMD3(235, 235, 235),
                     cellPt: CGFloat = GlobalLattice.pt(1)) -> CellIcon {
        CellIcon(box: box, ink: ink, cellPt: cellPt) { c, r, cx, _ in
            guard r >= 1 && r <= box - 2 else { return false }
            let t = Double(r - 1) / Double(box - 3)              // 0 apex … 1 base
            let halfW = t * (Double(box) / 2 - 1)
            return abs(Double(c) + 0.5 - cx) <= halfW
        }
    }
}

extension CellIcon {
    /// The settings gear: donut hub + body ring + 8 teeth, by angle/distance math.
    /// Fine chrome (v2.0): the gear mask needs 24 cells of detail, so it renders at the
    /// `subPt` sub-pixel — 24 × 2 = 48 pt, exactly its `gif(controlCells)` = 48 pt touch
    /// target. (A gear in 8 fat atoms would be a featureless blob.)
    static func gear(ink: SIMD3<UInt8> = SIMD3(235, 235, 235)) -> CellIcon {
        CellIcon(box: 24, ink: ink, cellPt: GlobalLattice.subPt) { c, r, cx, cy in
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
    private let n = GlobalLattice.ringCells     // 20
    private let ticks = GlobalLattice.ringTicks // 64
    /// Tick stub runs from `rOuter - 2` to `rOuter`; derived so it scales with the
    /// gauge size (v2.0: Ø20 atom ring → stub r7…r9).
    private var rInner: Double { CellShapes.ringTickRadius - 2 }
    var body: some View {
        let lit = max(0, min(ticks, Int((gauge * Double(ticks)).rounded())))
        let ghost = SFTheme.ledGhost
        let rOuter = CellShapes.ringTickRadius   // 9 (golden, ringCells/2 - 1)

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
                if rad >= rOuter - 1 { outer.insert(key) }
            }
            rad += 1
        }

        // Rendered at the gifPx ATOM (20·6 = 120 pt) — the gauge's pixels are the GIF's.
        return CellSprite(cols: n, rows: n, cellPt: GlobalLattice.gifPx) { c, r in
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

// The `DiversityRing` ColorWidget (the on-surface gauge) was removed — it read poorly on
// the surface. `CellRing`/`CellDiversityRing` remain as components for any future use; the
// `ColorIdentity.diversityRing` spec member is kept reserved (its dock is held but nothing
// renders) until a better diversity affordance is designed.
