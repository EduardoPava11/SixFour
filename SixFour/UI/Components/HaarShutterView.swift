import SwiftUI

/// The capture shutter / abstraction tile: the palette's **Haar level-4 node
/// colours** as a 4×4 grid — the third rung of the 64→16→4 cascade
/// (`docs/SIXFOUR-UIUX-ARCHITECTURE-DECISIONS.md` ADR-5). The 16 colours are the
/// parent averages of the 256-leaf palette tree, computed by the verified Zig
/// kernel `SixFourNative.haarLevelColors` (Haskell ≡ Zig ≡ Swift). 4 cells × 24 pt
/// = 96 pt, framed to match the GIF (384) and palette (192) above it.
struct HaarShutterView: View {
    /// The 256-colour palette (sRGB8) this is the abstraction of.
    let palette: [SIMD3<UInt8>]
    /// Cell pitch; 24 pt ⇒ a 96 pt shutter (ADR-5 cascade).
    var cellPt: CGFloat = 24
    /// Optional tap action (capture screen). Nil ⇒ a static display (review).
    var onTap: (() -> Void)? = nil

    private static let frameInk = SIMD3<UInt8>(78, 78, 92)
    private static let empty = SIMD3<UInt8>(20, 20, 24)

    /// The 16 level-4 colours, via the Zig Haar kernel. Computed once per palette
    /// change (cheap: one 256-leaf analyze + a stopped reconstruct).
    private var colors: [SIMD3<UInt8>] {
        SixFourNative.haarLevelColors(palette: palette, level: 4) ?? []
    }

    var body: some View {
        let c = colors
        let grid = CellSprite(cols: 4, rows: 4, cellPt: cellPt) { col, row in
            let i = row * 4 + col
            return i < c.count ? c[i] : Self.empty
        }
        .overlay(
            Rectangle()
                .stroke(Color(srgb8: Self.frameInk), lineWidth: 1.5)
        )
        if let onTap {
            Button(action: onTap) { grid }
                .buttonStyle(.plain)
                .contentShape(Rectangle())
                .accessibilityLabel("Capture")
        } else {
            grid.accessibilityHidden(true)
        }
    }
}
