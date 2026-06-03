import SwiftUI

/// Centralised design tokens shared by the SixFour UI. Keeps spacing and
/// typography consistent across the capture / review / compose screens.
///
/// Why a namespace and not a custom `EnvironmentValue`? — the design here
/// is small enough (one app, two screens) that explicit references like
/// `SFTheme.cardCorner` are easier to grep for than a SwiftUI environment
/// trail. If the app grows a real design system, promote to environment.
enum SFTheme {
    // MARK: Spacing

    static let cardCorner: CGFloat = 10

    static let pillVerticalPad: CGFloat = 7
    static let pillHorizontalPad: CGFloat = 14

    // MARK: The grid render surface (8-bit graphics-engine LOOK)

    /// The GIF's cell count per side — the spec-canonical 64 (`SixFourShape.W`,
    /// generated from `Spec/Shape.hs` and shared byte-exact with the Zig core's
    /// `kernels.SIDE`). The ONE definition every GIF-content surface sizes from,
    /// so 2D (the `PixelImage` hero) and 3D (the voxel cube) render the same grid.
    static let gifSideCells: Int = SixFourShape.W           // 64
    /// The GIF playback cadence — 64 frames at **20 fps** (a cube-language constant).
    /// The SINGLE source for every clock: the `frameIndex(at:rate:count:)` indexer, the
    /// render `fps:`, and the scrubbable-cursor views' tick stride (`60 / gifFrameRate`).
    static let gifFrameRate: Int = 20
    /// One GIF fat-pixel, in points. 64 × 6 = 384pt fits the iPhone 17 Pro
    /// portrait width (393–402pt) crisply. See `docs/grid-is-the-render-surface.md`.
    static let gifCellPt: CGFloat = 6
    /// The shared content canvas edge = `gifSideCells × gifCellPt` (the GIF's cell
    /// count drives it, not a literal). The palette grid uses the SAME 384pt edge
    /// (16 × 24), so a palette cell is exactly a 4×4 block of GIF cells.
    static let gifCanvasPt: CGFloat = gifCellPt * CGFloat(gifSideCells)   // 384
    /// The one grid-frame border — OPAQUE (GRID Law #2: opacity is shading, forbidden on
    /// a content surface). `(128,128,128)` reads as the old white@0.5-on-black hairline but
    /// is a flat opaque ink; applied as an INSET `.border` (not an edge-centred AA stroke).
    static let gridFrameStroke = Color(srgb8: SIMD3<UInt8>(128, 128, 128))

    // MARK: Cube-derived chrome lattice (docs/cube-generated-uiux-system.md)
    //
    // Every chrome dimension is n·gifCellPt, preferring multiples of
    // 24 (= 3×8, so the cube and Apple's 8pt grid already agree).
    // No chrome size may be a free point value.
    //
    // The 2pt CAPTURE lattice (cellPt, 201×437, widget cell-counts) is owned by
    // `GlobalLattice` (GRID Law #5). `gifCellPt`/`gifCanvasPt` here are the 6pt
    // Review/palette pitch (EXEMPT-REVIEW-PITCH); the two pitches never share a screen.

    /// Opaque "off-segment" dim for unlit LED/cell elements (never opacity — the
    /// flat-cell contract; ~1.6:1 on black so it reads without reflow).
    static let ledGhost = SIMD3<UInt8>(40, 40, 40)

    /// Square corner radius for chrome controls — 0 = a true cube cell.
    static let controlCorner: CGFloat = 0

    /// Treemap split-plane colour — OPAQUE (drawn as filled inset gaps, never an
    /// AA'd/translucent stroke), replacing the old `.black.opacity(0.55)`.
    static let treemapPlane = Color.black
    /// Split-plane width at the shallowest split (scaled by depth in the treemap).
    static let treemapPlaneMaxWidth: CGFloat = 2.5

    /// Snap an available edge to the largest integer multiple of `cells` that fits,
    /// so source rows never split unevenly across device pixels (no blur). The
    /// enforceable form of "INTEGER SCALE ONLY".
    static func canvasEdge(forAvailable w: CGFloat, cells n: Int) -> CGFloat {
        guard n > 0, w > 0 else { return 0 }
        return (w / CGFloat(n)).rounded(.down) * CGFloat(n)
    }

    // MARK: Typography

    static let captionMono = Font.system(.caption, design: .monospaced, weight: .medium)
    static let footnoteSelector = Font.system(.footnote, weight: .semibold)

    // MARK: Colour roles

    /// Translucent strokes used on selected segments and strip borders.
    static let hairline = Color.white.opacity(0.18)
    static let dimText   = Color.white.opacity(0.6)

    // MARK: Liquid Glass (iOS 26)

    /// Diameter of a circular glass icon button. 44pt is Apple's minimum
    /// comfortable hit target — keep new toolbar buttons on this size so
    /// the floating control cluster stays visually + tonally uniform.
    static let glassIconButtonSize: CGFloat = gifCellPt * 8   // 48 = 2 palette cells

    /// Spacing passed to `GlassEffectContainer`. It is the distance within
    /// which sibling glass shapes share one sampling region and morph into
    /// one another; tune it to roughly the gap between clustered controls.
    static let glassClusterSpacing: CGFloat = gifCellPt * 2   // 12 = 2 cells

    // MARK: Live diversity instrument

    /// Soften a raw scene colour into a **chrome-legible accent**: blend toward
    /// white so SF symbols and the gauge ring stay readable on glass over the
    /// live camera. Hue is preserved; lightness is raised. `towardWhite = 0`
    /// is the raw colour, `1` is pure white.
    static func accent(_ c: SIMD3<UInt8>, towardWhite t: Double = 0.45) -> Color {
        @inline(__always) func lift(_ v: UInt8) -> Double { Double(v) / 255 * (1 - t) + t }
        return Color(red: lift(c.x), green: lift(c.y), blue: lift(c.z))
    }
}
