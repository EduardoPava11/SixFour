import Foundation
import simd

/// User-assignable 2-axis coordinate grid — the navigable structure behind the
/// Review screen's `PaletteGridView` ("the flat 16×16 grid where the user chooses
/// what x and y MEAN").
///
/// Swift port of `SixFour.Spec.GridAxis` (Haskell source of truth, `cabal test`
/// green). Same rank/sort placement, same pinned `(scalar, index)` tie-break, so it
/// reproduces the spec's golden vector:
///
///   side = 2, x = L, y = a, four colours → `[[0, 3], [2, 1]]`.
///
/// Placement (no collisions, no holes — every cell filled exactly once):
///   1. sort all `side²` colours by `(xScalar, index)` → `side` columns of `side`;
///   2. within each column, sort by `(yScalar, index)` → the rows (row 0 = min Y).
///
/// Distinct from `SplitTree`: that view shows median-cut *nesting*; this lays the
/// 256 colours on two independent axes the user picks. Reuses `IndexedColor`
/// (`SplitTree.swift`). Pure value type — no Metal, no UIKit. (Tier-2: zero deps.)

/// The dimension a grid axis encodes. `CaseIterable` drives the axis picker.
enum GridAxis: String, CaseIterable, Codable, Sendable {
    case L, a, b, chroma, hue, index

    var label: String {
        switch self {
        case .L:      "L (light)"
        case .a:      "a (green–red)"
        case .b:      "b (blue–yellow)"
        case .chroma: "chroma"
        case .hue:    "hue"
        case .index:  "palette index"
        }
    }

    /// The scalar this axis projects a colour onto — used only as a sort KEY, so no
    /// normalisation is needed (magnitude and origin don't affect the ranking).
    /// Mirrors `SixFour.Spec.GridAxis.gridScalar`.
    @inline(__always) func scalar(_ ic: IndexedColor) -> Float {
        switch self {
        case .L:      return ic.oklab.x
        case .a:      return ic.oklab.y
        case .b:      return ic.oklab.z
        case .chroma: return (ic.oklab.y * ic.oklab.y + ic.oklab.z * ic.oklab.z).squareRoot()
        case .hue:    return atan2(ic.oklab.z, ic.oklab.y)   // origin +a; circular (red seam at ±π)
        case .index:  return Float(ic.index)
        }
    }
}

enum GridLayout {
    /// The pinned grid side (16 → a 16×16 = 256-cell grid for the full palette).
    static let side = 16

    /// The full 16×16 layout for the 256-colour palette, addressed `result[row][col]`.
    static func layout(x: GridAxis, y: GridAxis, colors: [IndexedColor]) -> [[Int]] {
        layoutN(side: side, x: x, y: y, colors: colors)
    }

    /// Lay `side²` colours into a `side × side` grid of slot indices. If the input
    /// length is not exactly `side²` the result is empty (callers pass a full
    /// palette; the spec-checked contract assumes `count == side²`).
    static func layoutN(side: Int, x: GridAxis, y: GridAxis, colors: [IndexedColor]) -> [[Int]] {
        guard side >= 1, colors.count == side * side else { return [] }

        // Total order by an axis, then the pinned `index` tie-break.
        func ordered(_ xs: [IndexedColor], by axis: GridAxis) -> [IndexedColor] {
            xs.sorted { (lhs: IndexedColor, rhs: IndexedColor) -> Bool in
                let sl: Float = axis.scalar(lhs)
                let sr: Float = axis.scalar(rhs)
                return sl != sr ? (sl < sr) : (lhs.index < rhs.index)
            }
        }

        // 1. X-ordered, chunked into `side` columns of `side`.
        let byX: [IndexedColor] = ordered(colors, by: x)
        // 2. Each column sorted by Y → its rows (row 0 = smallest Y).
        var colRows: [[Int]] = []
        colRows.reserveCapacity(side)
        for c in 0 ..< side {
            let column: [IndexedColor] = Array(byX[(c * side) ..< (c * side + side)])
            colRows.append(ordered(column, by: y).map { $0.index })
        }
        // 3. Address by [row][col]: transpose the column-major arrangement.
        var grid: [[Int]] = []
        grid.reserveCapacity(side)
        for r in 0 ..< side {
            var row: [Int] = []
            row.reserveCapacity(side)
            for c in 0 ..< side { row.append(colRows[c][r]) }
            grid.append(row)
        }
        return grid
    }
}
