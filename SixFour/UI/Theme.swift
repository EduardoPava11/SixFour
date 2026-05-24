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
}
