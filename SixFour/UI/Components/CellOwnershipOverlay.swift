import SwiftUI
import UIKit
import simd

/// **Debug-only** full-lattice ownership overlay — the IDENTITY layer made visible.
///
/// Paints the entire 100×218 capture lattice with `OwnershipContract.fieldColorAt`:
/// each cell wears its owner's reserved OKLab-Q16 badge, and a genuine (non-fused)
/// contention shows the loud `contestedSentinel`. It is the ground/field itself —
/// not a placed sub-widget — so it deliberately does NOT call `.place()` (that API
/// frames a rectangular sub-claim; the overlay is full-bleed).
///
/// PERF: the field is clock-invariant, so the bitmap is baked EXACTLY ONCE and
/// cached in `@State`. The bake is one `fieldColorAt` sweep over 21 800 cells → one
/// `SixFourNative.paletteToSRGB8` batch (k = 21 800) → one `CellBitmap` CGImage,
/// drawn once with `.interpolation(.none)` — the same cost class as
/// `TintedCheckerField`, never a per-cell `Canvas` fill (GRID Law #2).
///
/// LAYER: CONTENT, so FLAT — no glass, no AA, no opacity-on-a-cell (Law #2). The
/// Q16 OKLab → sRGB8 swing goes through the deterministic Zig kernel so screen
/// colour matches the contract byte-for-byte. Tier-2 pure (SwiftUI/UIKit/simd).
///
/// The `Cell*` filename lands this on `lint-grid.sh`'s `is_primitive` allowlist, so
/// its raw `Image(uiImage:)` draw vocab is sanctioned; every dimension routes through
/// `GlobalLattice.gif()` so it passes LINT-SINGLE-PITCH even if reclassified.
struct CellOwnershipOverlay: View {
    @State private var baked: UIImage?

    var body: some View {
        let img = ensure()
        return Group {
            if let img {
                Image(uiImage: img)
                    .interpolation(.none)
                    .resizable()
                    .frame(width: GlobalLattice.gif(SixFourLattice.cols),
                           height: GlobalLattice.gif(SixFourLattice.rows))
            } else {
                Color.black
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    /// Return the cached bitmap, baking exactly once (the field is static, so a
    /// second bake would be byte-identical work).
    private func ensure() -> UIImage? {
        if let baked { return baked }
        #if DEBUG
        assert(OwnershipContract.selfCheck(), "OwnershipContract laws failed")
        #endif
        let img = Self.bake()
        DispatchQueue.main.async { baked = img }
        return img
    }

    /// One sweep → one batch → one bitmap. Mirrors `TintedCheckerField.image` and
    /// `ContestedCellGridView.renderedSRGB`: row-major top-left (matching
    /// `OwnershipContract.selfCheck`'s `for r in 0..<218 { for c in 0..<100 }`).
    private static func bake() -> UIImage? {
        let cols = SixFourLattice.cols
        let rows = SixFourLattice.rows
        let n = cols * rows
        var oklab = [Int32](); oklab.reserveCapacity(n * 3)
        for r in 0 ..< rows {
            for c in 0 ..< cols {
                let q = OwnershipContract.fieldColorAt(col: c, row: r)
                oklab.append(q.x); oklab.append(q.y); oklab.append(q.z)
            }
        }
        guard let flat = SixFourNative.paletteToSRGB8(centroidsQ16: oklab, k: n),
              flat.count == n * 3 else {
            // Deterministic core unavailable — neutral fallback so the draw is total.
            return CellBitmap.image(cols: cols, rows: rows) { _, _ in
                SIMD3<UInt8>(127, 127, 127)
            }
        }
        return CellBitmap.image(cols: cols, rows: rows) { c, r in
            let i = (r * cols + c) * 3
            return SIMD3<UInt8>(flat[i], flat[i + 1], flat[i + 2])
        }
    }
}
