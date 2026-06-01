import SwiftUI

/// Centralised design tokens shared by the SixFour UI. Keeps spacing and
/// typography consistent across the capture / review / compose screens.
///
/// Why a namespace and not a custom `EnvironmentValue`? — the design here
/// is small enough (one app, two screens) that explicit references like
/// `SFTheme.pillCorner` are easier to grep for than a SwiftUI environment
/// trail. If the app grows a real design system, promote to environment.
enum SFTheme {
    // MARK: Spacing

    static let pillCorner: CGFloat = 14
    static let cardCorner: CGFloat = 10
    static let stripCorner: CGFloat = 4

    static let pillVerticalPad: CGFloat = 7
    static let pillHorizontalPad: CGFloat = 14

    static let sectionSpacing: CGFloat = 14

    // MARK: The grid render surface (8-bit graphics-engine LOOK)

    /// One GIF fat-pixel, in points. 64 × 6 = 384pt fits the iPhone 17 Pro
    /// portrait width (393–402pt) crisply. See `docs/grid-is-the-render-surface.md`.
    static let gifCellPt: CGFloat = 6
    /// The shared content canvas edge: 64 × `gifCellPt`. The palette grid uses the
    /// SAME 384pt edge (16 × 24), so a palette cell is exactly a 4×4 block of GIF
    /// cells — one commensurate surface.
    static let gifCanvasPt: CGFloat = gifCellPt * 64        // 384
    static let paletteCellPt: CGFloat = gifCellPt * 4       // 24 → 16×24 = 384
    /// The one grid-frame stroke (reconciles the old 0.5 / 0.18 inconsistency).
    static let gridFrameStroke = Color.white.opacity(0.5)

    // MARK: Cube-derived chrome lattice (docs/cube-generated-uiux-system.md)
    //
    // Every chrome dimension is n·gifCellPt, preferring multiples of
    // paletteCellPt (24 = 3×8, so the cube and Apple's 8pt grid already agree).
    // No chrome size may be a free point value.

    /// The GLOBAL cell-lattice pitch (docs/cell-lattice-widget-spec.md). gcd(402,874)=2,
    /// so a 2pt cell is the unique pitch that tiles the whole iPhone 17 Pro screen
    /// exactly → 201 × 437 cells. The preview is 64 cells = 128pt at this pitch.
    /// (`gifCellPt`/`gifCanvasPt`/`paletteCellPt` stay for the Review/palette screens.)
    static let cellPt: CGFloat = 2
    /// Opaque "off-segment" dim for unlit LED/cell elements (never opacity — the
    /// flat-cell contract; ~1.6:1 on black so it reads without reflow).
    static let ledGhost = SIMD3<UInt8>(40, 40, 40)

    /// Primary action (the shutter): 12 cells = 3 palette cells. A square.
    static let shutterSidePt: CGFloat = gifCellPt * 12        // 72
    /// The shutter's inner fill, leaving a 1-cell ring gap.
    static let shutterInnerPt: CGFloat = gifCellPt * 10       // 60
    /// Secondary square controls (gear, toggles, selector segments): 8 cells =
    /// 2 palette cells = 48pt. Clears the 44pt HIG target; visible == hit.
    static let controlSidePt: CGFloat = gifCellPt * 8         // 48
    /// Square corner radius for chrome controls — 0 = a true cube cell.
    static let controlCorner: CGFloat = 0
    /// Comfortable gutter between interactive controls.
    static let controlGutter: CGFloat = gifCellPt * 2         // 12
    /// Control-to-decoration / canvas gutter (the Swiss gutter that holds
    /// figure/ground around the blended preview).
    static let decorGutter: CGFloat = gifCellPt               // 6

    /// Opacity of the palette-driven background wash over black: the live scene's
    /// dominant hue tints the room (responds to camera input) while staying dark
    /// enough that white chrome remains readable — a flat fill, no gradient.
    static let groundWashOpacity: Double = 0.32
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
    static let titleMono = Font.system(.title2, design: .monospaced, weight: .bold)

    // MARK: Colour roles

    /// Translucent strokes used on selected segments and strip borders.
    static let hairline = Color.white.opacity(0.18)
    static let mutedFill = Color.white.opacity(0.06)
    static let mutedText = Color.white.opacity(0.85)
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

    /// Tick count for the shutter diversity gauge — the form's signature 64
    /// (frames), reused as "how full is the palette's gamut".
    static let diversityTickCount: Int = 64
    /// Diameter of the gauge ring (matches the shutter's outer stroke).
    static let diversityRingDiameter: CGFloat = 84
    /// Radial tick geometry for the gauge.
    static let diversityTickLength: CGFloat = 6
    static let diversityTickWidth: CGFloat = 2

    /// Soften a raw scene colour into a **chrome-legible accent**: blend toward
    /// white so SF symbols and the gauge ring stay readable on glass over the
    /// live camera. Hue is preserved; lightness is raised. `towardWhite = 0`
    /// is the raw colour, `1` is pure white.
    static func accent(_ c: SIMD3<UInt8>, towardWhite t: Double = 0.45) -> Color {
        @inline(__always) func lift(_ v: UInt8) -> Double { Double(v) / 255 * (1 - t) + t }
        return Color(red: lift(c.x), green: lift(c.y), blue: lift(c.z))
    }
}
