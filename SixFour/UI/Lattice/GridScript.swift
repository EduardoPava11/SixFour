import Foundation
import simd

/// The form-follows-function spine, Swift side: ONE grid FORM, parameterized by a
/// `GridScript` the calling scene supplies. The FORM is the cell grid; the FUNCTION
/// is this value (which ORDER, over how many cells). Port of
/// `SixFour.Spec.GridScript`; `cabal test` (`Properties.GridScript`) proves the laws
/// — including RENDER EQUIVALENCE (the bitmap and Canvas backends produce
/// byte-identical cells).
///
/// The unification is structural, not hoped-for: both the `PixelImage` bitmap
/// backend and the `PixelGrid` Canvas backend resolve a cell by calling the SAME
/// `surfaceColors(palette:)` here, which consults the centralized `Order`
/// (`OrderContract.swift`). They cannot diverge because there is one slot→rank map.
/// (Phase 2 wires the two backends onto this; Phase 1 lands the contract + golden.)
public struct GridScript: Equatable, Sendable {
    public let name: String
    /// Grid side: the carrier is `side × side` cells.
    public let side: Int
    /// The bound ORDER (slot → screen rank) — the only part the layout law needs.
    public let order: Order

    public init(name: String, side: Int, order: Order) {
        self.name = name
        self.side = side
        self.order = order
    }

    /// Capture/preview script: row-major order (rank = slot) over a `side×side` grid.
    public static func capture(side: Int) -> GridScript {
        GridScript(name: "capture", side: side, order: .rowMajor(side * side))
    }

    /// Review script: a precomputed 2-axis order (e.g. from `GridLayout`/`Order.fromGrid`).
    public static func review(side: Int, order: Order) -> GridScript {
        GridScript(name: "review", side: side, order: order)
    }

    /// THE single surface function both render backends call: the palette permuted
    /// into screen-rank order. Position `rank` shows `palette[order.slotAt(rank)]` —
    /// a pure permutation, no synthesis/blend (matches `Spec.CellFiber.lawNoSynthesis`).
    public func surfaceColors(palette: [SIMD3<UInt8>]) -> [SIMD3<UInt8>] {
        guard order.count == palette.count else { return palette }
        return (0 ..< palette.count).map { palette[order.slotAt($0)] }
    }

    /// Re-asserts the Haskell goldens (`Properties.GridScript`) at runtime:
    /// `fromGrid [[0,3],[2,1]]` places `[a,b,c,d]` → `[a,d,c,b]`; capture is identity.
    public static func selfCheck() -> Bool {
        let pal: [SIMD3<UInt8>] = [
            SIMD3(10, 0, 0), SIMD3(20, 0, 0), SIMD3(30, 0, 0), SIMD3(40, 0, 0),
        ]
        let review = GridScript(name: "g", side: 2, order: Order.fromGrid([[0, 3], [2, 1]]))
        let placed = review.surfaceColors(palette: pal)
        let wantPermuted = placed == [SIMD3(10, 0, 0), SIMD3(40, 0, 0), SIMD3(30, 0, 0), SIMD3(20, 0, 0)]
        let captureIsIdentity = GridScript.capture(side: 2).surfaceColors(palette: pal) == pal
        return wantPermuted && captureIsIdentity && Order.selfCheck()
    }
}
