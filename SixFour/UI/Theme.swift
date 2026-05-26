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
    static let glassIconButtonSize: CGFloat = 44

    /// Spacing passed to `GlassEffectContainer`. It is the distance within
    /// which sibling glass shapes share one sampling region and morph into
    /// one another; tune it to roughly the gap between clustered controls.
    static let glassClusterSpacing: CGFloat = 10

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
