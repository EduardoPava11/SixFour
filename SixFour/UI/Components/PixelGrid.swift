import SwiftUI
import UIKit
import simd

/// The **8-bit graphics-engine render surface** — the content-layer primitives that
/// make "the grid is the render surface" a hard contract, not a style. See
/// `docs/grid-is-the-render-surface.md`.
///
/// The LOOK contract these enforce: integer-scaled cells, no interpolation, no
/// anti-aliasing, no shading/gradient/opacity on a cell — a cell is exactly one
/// indexed sRGB8 colour. Flatness is intrinsic: the residual ("shading") is shaped
/// across the (x, y, t) temporal-dither axis, never within a frame's cell.
///
/// Scope (perf): the **64×64 GIF is a bitmap** (`PixelImage`, `.interpolation(.none)`),
/// never 4096 Canvas fills. `PixelGrid` Canvas drawing is for the 256-cell palette only.
/// Tier-2 pure: SwiftUI + simd, zero third-party deps.

// MARK: - One colour conversion

extension Color {
    /// The single sRGB8 → `Color` conversion for the whole app. EXPLICIT `.sRGB`
    /// space (not extended/displayP3) so on-screen colour matches the GIF's sRGB
    /// colour table byte-for-byte. Replaces every inline `Double(c.x)/255`.
    init(srgb8 c: SIMD3<UInt8>) {
        self.init(.sRGB, red: Double(c.x) / 255, green: Double(c.y) / 255, blue: Double(c.z) / 255)
    }
}

// MARK: - One clock
//
// The old `frameIndex(at:rate:count:)` wall-clock indexer was REMOVED: every Review
// surface (the unified player, the status line, and the palette analyzers) now reads
// the shared `PlaybackClock` (an ObservableObject), so there is no longer a Date-based
// indexer to drift. See docs/SIXFOUR-UNIFIED-PLAYER.md and `PlaybackClock.swift`.

// MARK: - Bitmap upscale (GIF playback + live preview)

/// A nearest-neighbour, integer-edge bitmap — the GIF and the live preview. Owns
/// the view-layer half of the no-interpolation contract (`.interpolation(.none)`
/// + an exact square `.frame`, never `.scaledToFit`/`.scaledToFill`, which resample
/// to a fractional scale and blur). The CGImage half (`shouldInterpolate = false`)
/// lives where the image is built (`CaptureViewModel`).
struct PixelImage: View {
    let image: UIImage
    /// Integer-snapped square edge in points (see `SFTheme.canvasEdge`).
    let edge: CGFloat

    var body: some View {
        Image(uiImage: image)
            .interpolation(.none)
            .resizable()
            .frame(width: edge, height: edge)
    }
}

// MARK: - The 256-cell palette grid

/// Where row 0 / col 0 sits. The coordinate grid is Y-up (`.bottomLeft`); the GIF
/// and treemap are top-left. The per-surface flip is a configured value, not a
/// re-implementation hidden in each view.
enum PixelGridOrigin { case topLeft, bottomLeft }

/// A `cells × cells` grid of flat indexed cells, drawn as a single `Canvas`. For
/// the palette (≤ 256 cells) only — never the 64×64 GIF. `colorAt` returns the
/// cell's sRGB8 (or `nil` to leave it unpainted). No interpolation, no stroke, no
/// shading — the flat-cell LOOK contract.
struct PixelGrid: View {
    let cells: Int
    let origin: PixelGridOrigin
    let colorAt: (_ row: Int, _ col: Int) -> SIMD3<UInt8>?

    var body: some View {
        Canvas { ctx, size in
            guard cells > 0 else { return }
            let cw = size.width / CGFloat(cells)
            let ch = size.height / CGFloat(cells)
            for r in 0 ..< cells {
                // Row 0 at the bottom for a Y-up coordinate grid.
                let screenRow = origin == .bottomLeft ? (cells - 1 - r) : r
                for c in 0 ..< cells {
                    guard let srgb = colorAt(r, c) else { continue }
                    let rect = CGRect(x: CGFloat(c) * cw, y: CGFloat(screenRow) * ch, width: cw, height: ch)
                    ctx.fillCell(rect, srgb8: srgb)
                }
            }
        }
    }
}

extension GraphicsContext {
    /// The one flat cell fill — solid, no interpolation, no stroke. Shared by
    /// `PixelGrid` and the (non-uniform) treemap leaves.
    @inline(__always)
    func fillCell(_ rect: CGRect, srgb8 c: SIMD3<UInt8>) {
        fill(Path(rect), with: .color(Color(srgb8: c)))
    }

    /// A split-plane border drawn as four OPAQUE filled edge rects — NOT
    /// `stroke` (edge-centred + anti-aliased) and NOT opacity. The flat-cell LOOK
    /// forbids AA/opacity on the content layer, so the treemap's nesting lines
    /// become solid inset gaps instead of soft strokes.
    func fillBorder(_ rect: CGRect, width w: CGFloat, color: Color) {
        let p = GraphicsContext.Shading.color(color)
        fill(Path(CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: w)), with: p)             // top
        fill(Path(CGRect(x: rect.minX, y: rect.maxY - w, width: rect.width, height: w)), with: p)         // bottom
        fill(Path(CGRect(x: rect.minX, y: rect.minY, width: w, height: rect.height)), with: p)            // left
        fill(Path(CGRect(x: rect.maxX - w, y: rect.minY, width: w, height: rect.height)), with: p)        // right
    }
}

// MARK: - Chrome frame + n-ary tiling (shared by every grid surface)

extension View {
    /// The chrome frame around a content grid: a hard square with one opaque
    /// `gridFrameStroke` border and NO corner rounding (rounding would clip the
    /// outermost indexed cells — an AA-on-content violation). Uses an INSET `.border`
    /// (not an edge-centred `Rectangle().stroke`, which straddles + anti-aliases the
    /// boundary cells) with a flat opaque ink (not opacity) — GRID Law #2.
    func pixelFrame() -> some View {
        aspectRatio(1, contentMode: .fit)
            .border(SFTheme.gridFrameStroke, width: 1)
    }
}

/// Tile a rect into `count` cells — the ONE implementation shared by the treemap
/// draw AND `GlobalPaletteEditorView`'s hit-test (so layout and tap targets can never
/// desync). Perfect squares (16, 4) tile as a grid; 2 splits the longer side
/// (k-d-tree style) so cells stay roughly square.
func paletteSubdivide(_ rect: CGRect, count: Int) -> [CGRect] {
    if count == 2 {
        if rect.width >= rect.height {
            let w = rect.width / 2
            return [CGRect(x: rect.minX, y: rect.minY, width: w, height: rect.height),
                    CGRect(x: rect.minX + w, y: rect.minY, width: w, height: rect.height)]
        }
        let h = rect.height / 2
        return [CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: h),
                CGRect(x: rect.minX, y: rect.minY + h, width: rect.width, height: h)]
    }
    let s = Int(Double(count).squareRoot().rounded())
    let cols = s * s == count ? s : Int(Double(count).squareRoot().rounded(.up))
    let rows = Int((Double(count) / Double(cols)).rounded(.up))
    let cw = rect.width / CGFloat(cols), ch = rect.height / CGFloat(rows)
    return (0 ..< count).map { i in
        let r = i / cols, c = i % cols
        return CGRect(x: rect.minX + CGFloat(c) * cw, y: rect.minY + CGFloat(r) * ch, width: cw, height: ch)
    }
}
