import SwiftUI
import UIKit

/// Text rendered as lattice CELLS — the chrome's pixel-font primitive for the
/// total cell-lattice UI (`docs/cube-generated-uiux-system.md`,
/// `~/.claude/plans/misty-greeting-panda.md`).
///
/// v1 = the plan's documented **rasterize-and-snap fallback**: a monospaced string
/// is drawn into a 1-bit bitmap at the cell resolution with anti-aliasing OFF, then
/// nearest-neighbour upscaled (`.interpolation(.none)`) so each source pixel becomes
/// one hard cell — the same discipline as `PixelImage`. A hand-authored golden
/// `CellFont` can replace the rasteriser behind this exact API later (plan Phase 1)
/// without touching call sites.
///
/// Accessibility: the cells are decorative; the real string is exposed via
/// `accessibilityLabel`, so VoiceOver reads "SixFour", not "rectangles". (Dynamic
/// Type → integer-scale / `Text` fallback at AX sizes is a later phase.)
struct CellText: View {
    let text: String
    /// Glyph height in cells (= source bitmap pixel rows). Width follows the string.
    var rows: Int = 7
    /// Point size of one cell — the global lattice pitch.
    var cell: CGFloat = GlobalLattice.cellPt
    var ink: Color = .white

    init(_ text: String, rows: Int = 7, cell: CGFloat = GlobalLattice.cellPt, ink: Color = .white) {
        self.text = text
        self.rows = rows
        self.cell = cell
        self.ink = ink
    }

    var body: some View {
        if let mask = Self.snap(text, rows: rows) {
            Image(uiImage: mask)
                .renderingMode(.template)
                .resizable()
                .interpolation(.none)
                .frame(width: mask.size.width * cell, height: mask.size.height * cell)
                .foregroundStyle(ink)
                .accessibilityLabel(Text(text))
        } else {
            Color.clear.frame(width: 0, height: 0)
        }
    }

    /// Cache of rasterised masks, keyed by `text|rows`. The raster is a pure function
    /// of (text, rows), so memoising it makes converting dozens of chrome labels —
    /// and the 20 fps Review status line — cheap (no CGContext per body eval). Masks
    /// are small 1-bit images; `NSCache` evicts under memory pressure.
    private static let cache = NSCache<NSString, UIImage>()

    /// Rasterise `text` to a 1-bit alpha mask, one pixel per cell, AA off.
    /// `UIImage(cgImage:)` has scale 1, so `.size` is in pixels == cells. Memoised.
    static func snap(_ text: String, rows: Int) -> UIImage? {
        guard !text.isEmpty, rows > 0 else { return nil }
        let key = "\(rows)|\(text)" as NSString
        if let hit = cache.object(forKey: key) { return hit }
        let font = UIFont.monospacedSystemFont(ofSize: CGFloat(rows), weight: .bold)
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: UIColor.white]
        let ns = text as NSString
        let w = max(1, Int(ns.size(withAttributes: attrs).width.rounded(.up)))
        let h = rows

        let cs = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(
            data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
            space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        ctx.clear(CGRect(x: 0, y: 0, width: w, height: h))   // transparent paper
        ctx.setShouldAntialias(false)                         // hard cells, no fringe
        ctx.setAllowsAntialiasing(false)

        UIGraphicsPushContext(ctx)
        // CoreGraphics origin is bottom-left; flip so text reads top-down.
        ctx.translateBy(x: 0, y: CGFloat(h))
        ctx.scaleBy(x: 1, y: -1)
        ns.draw(at: .zero, withAttributes: attrs)             // white ink on clear
        UIGraphicsPopContext()

        let img = ctx.makeImage().map { UIImage(cgImage: $0) }
        if let img { cache.setObject(img, forKey: key) }
        return img
    }
}
