import SwiftUI
import simd

/// GRID component **`CellDigits`** — a fixed-width two-ink 7-segment number, the
/// count readout's digit field (design language §6.9). Each digit is a 10×18 glyph
/// from the golden `SixFourSevenSeg` register: lit segments in white, the rest of the
/// "8" footprint in opaque `ledGhost`. Because every digit (and a blanked leading
/// digit) paints the identical 96-cell footprint, the count **never reflows** — the
/// reflow + single-ink bug the audit flagged on the old `CellText` count.
struct CellDigits: View {
    let value: Int
    var width: Int = 3
    var lit: SIMD3<UInt8> = SIMD3(255, 255, 255)
    var ghost: SIMD3<UInt8> = SFTheme.ledGhost
    /// Points per cell. Default = the 2 pt capture lattice; the Review player's frame
    /// counter passes `SFTheme.gifCellPt` (6 pt) to stay on the single Review pitch.
    var cellPt: CGFloat = GlobalLattice.pt(1)

    var body: some View {
        let digits = Self.fixedDigits(value, width: width)
        HStack(spacing: cellPt) {
            ForEach(0 ..< width, id: \.self) { i in
                DigitGlyph(digit: digits[i], lit: lit, ghost: ghost, cellPt: cellPt)
            }
        }
        .accessibilityHidden(true)
    }

    /// Decompose `value` into `width` digits, MSB first. Leading positions are `nil`
    /// (a ghost-blanked digit, NOT a literal 0), so "42" in a 3-wide field is ` 42`,
    /// never "042" and never a width that shifts as the value grows.
    static func fixedDigits(_ value: Int, width: Int) -> [Int?] {
        let maxV = Int(pow(10.0, Double(width))) - 1
        let v = max(0, min(value, maxV))
        var out = [Int?](repeating: nil, count: width)
        if v == 0 { out[width - 1] = 0; return out }    // a single significant 0
        var n = v, i = width - 1
        while n > 0 && i >= 0 { out[i] = n % 10; n /= 10; i -= 1 }
        return out
    }
}

/// One 7-segment digit (or a ghost-blanked slot when `digit == nil`). The ghost "8"
/// footprint and the lit cells both come from the golden `SixFourSevenSeg` table.
private struct DigitGlyph: View {
    let digit: Int?
    let lit: SIMD3<UInt8>
    let ghost: SIMD3<UInt8>
    var cellPt: CGFloat = GlobalLattice.pt(1)
    private let cols = SixFourSevenSeg.digitBoxCols
    private let rows = SixFourSevenSeg.digitBoxRows

    /// `row * cols + col` keys for a cell list — concrete-typed helper so the SwiftUI
    /// body doesn't trigger a type-checker blowup on an inline `Set(map { … })`.
    private static func encoded(_ cells: [SIMD2<Int>]) -> Set<Int> {
        var s = Set<Int>()
        for cell in cells { s.insert(cell.y * SixFourSevenSeg.digitBoxCols + cell.x) }
        return s
    }

    /// The ghost "8" footprint is identical for every digit — cache it once.
    private static let ghostSet: Set<Int> = encoded(SixFourSevenSeg.allSegmentCells)

    var body: some View {
        let litSet: Set<Int> = digit == nil ? [] : Self.encoded(SixFourSevenSeg.digitLitCells[digit!])
        let ghostSet = Self.ghostSet
        return CellSprite(cols: cols, rows: rows, cellPt: cellPt) { c, r in
            let key = r * cols + c
            if litSet.contains(key) { return lit }       // lit segment
            if ghostSet.contains(key) { return ghost }   // unlit "8" footprint
            return nil
        }
    }
}
