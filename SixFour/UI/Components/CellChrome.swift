import SwiftUI
import UIKit
import simd

/// An SF Symbol rendered as lattice CELLS — the icon twin of `CellText`. The symbol
/// is rasterised into a `box×box` 1-bit mask with anti-aliasing OFF, then
/// nearest-neighbour upscaled (`.interpolation(.none)`) so each source pixel becomes
/// one hard cell. This pixelates EVERY glass icon button at once (no hand-authored
/// mask per symbol). `accessibilityLabel` is supplied by the wrapping control.
struct CellSymbol: View {
    let systemName: String
    /// Cells per side (the symbol is fit inside this square).
    var box: Int = 12
    /// Points per cell (2 pt master default; pass `SFTheme.gifCellPt` for chunky).
    var cell: CGFloat = GlobalLattice.pt(1)
    var ink: Color = .white

    var body: some View {
        if let mask = Self.snap(systemName, box: box) {
            Image(uiImage: mask)
                .renderingMode(.template)
                .resizable()
                .interpolation(.none)
                .frame(width: CGFloat(box) * cell, height: CGFloat(box) * cell)
                .foregroundStyle(ink)
        } else {
            Color.clear.frame(width: CGFloat(box) * cell, height: CGFloat(box) * cell)
        }
    }

    private static let cache = NSCache<NSString, UIImage>()

    /// Rasterise an SF Symbol to a `box×box` alpha mask, one pixel per cell, AA off.
    static func snap(_ name: String, box: Int) -> UIImage? {
        guard box > 0 else { return nil }
        let key = "\(box)|\(name)" as NSString
        if let hit = cache.object(forKey: key) { return hit }
        let cfg = UIImage.SymbolConfiguration(pointSize: CGFloat(box) * 0.82, weight: .semibold)
        guard let sym = UIImage(systemName: name, withConfiguration: cfg)?
                .withTintColor(.white, renderingMode: .alwaysOriginal) else { return nil }

        let cs = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(data: nil, width: box, height: box, bitsPerComponent: 8,
                                  bytesPerRow: 0, space: cs,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.clear(CGRect(x: 0, y: 0, width: box, height: box))
        ctx.setShouldAntialias(false)
        ctx.setAllowsAntialiasing(false)
        ctx.interpolationQuality = .none

        // Fit the symbol's aspect inside the box, centred.
        let s = sym.size
        let k = min(CGFloat(box) / max(s.width, 1), CGFloat(box) / max(s.height, 1))
        let w = s.width * k, h = s.height * k
        let rect = CGRect(x: (CGFloat(box) - w) / 2, y: (CGFloat(box) - h) / 2, width: w, height: h)

        UIGraphicsPushContext(ctx)
        ctx.translateBy(x: 0, y: CGFloat(box))   // flip to top-down
        ctx.scaleBy(x: 1, y: -1)
        sym.draw(in: rect)
        UIGraphicsPopContext()

        let img = ctx.makeImage().map { UIImage(cgImage: $0) }
        if let img { cache.setObject(img, forKey: key) }
        return img
    }
}

/// A GRID **action button** — the cell replacement for the glass Share / Retake /
/// contact-sheet pills (GIFReviewView actionRow). A flat opaque cell ground
/// (`controlCorner = 0`, NO glass, NO AA, GRID Law #2) carrying an optional
/// `CellIcon` + optional `CellText` label, all rendered at the 2 pt master pitch
/// (commensurate with the 6 pt GIF content). The caller wraps it in a
/// `Button`/`ShareLink` so the hit-rect equals the painted cell-rect; the visible
/// touch floor is pinned in POINTS (≥ 44 pt), not cells.
struct CellActionButton: View {
    enum Icon { case share, grid3x3, retake, none }
    var icon: Icon = .none
    var title: String? = nil
    /// Filled light ground + dark ink (the old `.glassProminent` Share). Otherwise a
    /// `ledGhost` ground + light ink (the old `.glass` buttons).
    var prominent: Bool = false
    /// Expand to fill the row (Share/Retake) vs hug the icon (contact sheet).
    var fillWidth: Bool = true

    private var ground: SIMD3<UInt8> { prominent ? SIMD3(245, 245, 245) : SFTheme.ledGhost }
    private var fg: SIMD3<UInt8> { prominent ? SIMD3(20, 20, 20) : SIMD3(235, 235, 235) }

    var body: some View {
        HStack(spacing: GlobalLattice.pt(3)) {
            iconView
            if let title { CellText(title, rows: 11, ink: Color(srgb8: fg)) }
        }
        .padding(.horizontal, GlobalLattice.pt(6))
        .frame(minHeight: 44)                            // touch floor in POINTS
        .frame(maxWidth: fillWidth ? .infinity : nil)
        .frame(minWidth: 44)                             // icon-only buttons stay tappable
        .background(Color(srgb8: ground))                // flat opaque cell ground, square corners
        .accessibilityHidden(true)                       // the caller supplies the real label
    }

    @ViewBuilder private var iconView: some View {
        switch icon {
        case .share:   CellIcon.share(ink: fg)
        case .grid3x3: CellIcon.grid3x3(ink: fg)
        case .retake:  CellIcon.retake(ink: fg)
        case .none:    EmptyView()
        }
    }
}

/// A GRID **slider** — the cell replacement for `Slider`. A flat `ledGhost` baseline
/// track with a single lit knob cell at the value's position; drag maps x → value
/// (quantised to `step`). The ONE genuinely-new primitive of total pixelation — it is
/// a discrete cell stepper drawn as a track, NOT a faked smooth knob, and it keeps
/// `accessibilityAdjustableAction` so VoiceOver can still nudge it.
struct CellSlider: View {
    @Binding var value: Double
    let range: ClosedRange<Double>
    var step: Double = 1
    var tint: SIMD3<UInt8> = SIMD3(96, 165, 250)
    /// Track length in cells.
    var cols: Int = 56
    var cell: CGFloat = GlobalLattice.pt(1)
    private let rows = 6

    private var span: Double { max(range.upperBound - range.lowerBound, 0.0001) }

    var body: some View {
        let frac = (value - range.lowerBound) / span
        let knob = max(0, min(cols - 1, Int((frac * Double(cols - 1)).rounded())))
        let ghost = SFTheme.ledGhost
        CellSprite(cols: cols, rows: rows, cellPt: cell) { c, r in
            if c == knob { return tint }                                   // the knob column
            return (r == rows / 2 - 1 || r == rows / 2) ? ghost : nil      // baseline track
        }
        .frame(width: cell * CGFloat(cols), height: cell * CGFloat(rows))
        .frame(minHeight: 44)                                             // touch floor (points)
        .contentShape(Rectangle())
        .gesture(DragGesture(minimumDistance: 0).onChanged { v in
            let f = max(0, min(1, v.location.x / (cell * CGFloat(cols))))
            set(range.lowerBound + f * span)
        })
        .accessibilityElement()
        .accessibilityValue(Text("\(Int(value))"))
        .accessibilityAdjustableAction { dir in
            switch dir {
            case .increment: set(value + step)
            case .decrement: set(value - step)
            default: break
            }
        }
    }

    private func set(_ raw: Double) {
        let stepped = (raw / step).rounded() * step
        value = min(range.upperBound, max(range.lowerBound, stepped))
    }
}
