import SwiftUI
import simd

/// The cell algebra, made visible. A flat `cells × cells` grid where each place is
/// an `SFCell` (a set of colour claims) rendered by `renderCell` — the on-device
/// port of `SixFour.Spec.CellGrid.renderGridAt`, verified byte-for-byte against
/// `CellContract.golden` (`SixFourTests/CellAlgebraTests.swift`).
///
/// The NO-BLEND contract, on screen:
///   • a clean cell shows its one claim, verbatim;
///   • a **contested** cell (two widgets claimed it) OUTSIDE an effect-zone shows
///     the loud `contestedSentinel` magenta — an overlap you cannot miss;
///   • a contested cell INSIDE an effect-zone **shimmers** its claimants on the
///     20 fps `PlaybackClock` (`shimmerAt tick`) — the opt-in effect, never a blend.
///
/// LAYER: this is CONTENT, so it is FLAT (GRID Law #2 — no glass, no AA, no opacity
/// on a cell; mirrors `PixelGrid`). Glass, if any, is reserved for surrounding chrome.
/// Q16 OKLab → sRGB8 goes through the deterministic Zig kernel
/// (`SixFourNative.paletteToSRGB8`) so on-screen colour matches the GIF byte-for-byte.
///
/// Scope (perf): `Canvas` drawing is for palette-scale grids (≤ 256 cells), exactly
/// like `PixelGrid`. The 64×64 GIF hero stays a bitmap (`PixelImage`).
///
/// Tier-2 pure: SwiftUI + simd + the in-module Zig bridge; zero third-party deps.
struct ContestedCellGridView: View {
    /// Grid side. Keep `cells² ≤ 256` for the Canvas path.
    let cells: Int
    /// Row/col origin (Y-up palette vs top-left GIF), matching `PixelGrid`.
    var origin: PixelGridOrigin = .topLeft
    /// The single 20 fps clock — drives the shimmer of contested effect-zone cells.
    let clock: PlaybackClock
    /// The cell (set of claims) at each place.
    let cellAt: (_ row: Int, _ col: Int) -> SFCell
    /// Which places treat overlap as an EFFECT (shimmer) vs a bug (loud sentinel).
    var effectZone: (_ row: Int, _ col: Int) -> Bool = { _, _ in false }

    var body: some View {
        // Reading `clock.frame` here makes the view recompute each tick (@Observable),
        // so contested effect-zone cells shimmer; clean cells are tick-invariant.
        let rgb = renderedSRGB(tick: clock.frame)
        return Canvas { ctx, size in
            guard cells > 0, !rgb.isEmpty else { return }
            let cw = size.width / CGFloat(cells)
            let ch = size.height / CGFloat(cells)
            for r in 0 ..< cells {
                let screenRow = origin == .bottomLeft ? (cells - 1 - r) : r
                for c in 0 ..< cells {
                    let rect = CGRect(x: CGFloat(c) * cw, y: CGFloat(screenRow) * ch,
                                      width: cw, height: ch)
                    ctx.fillCell(rect, srgb8: rgb[r * cells + c])
                }
            }
        }
        .accessibilityLabel(Text("Cell grid, \(cells) by \(cells)"))
    }

    /// Render every place's `SFCell` to one OKLab-Q16 colour (no blend), then swing
    /// the whole grid to sRGB8 in one deterministic Zig batch call. Row-major.
    private func renderedSRGB(tick: Int) -> [SIMD3<UInt8>] {
        let n = cells * cells
        guard n > 0 else { return [] }
        var oklab = [Int32](); oklab.reserveCapacity(n * 3)
        for r in 0 ..< cells {
            for c in 0 ..< cells {
                let col = renderCell(cellAt(r, c), tick: tick, inEffectZone: effectZone(r, c))
                oklab.append(col.x); oklab.append(col.y); oklab.append(col.z)
            }
        }
        guard let flat = SixFourNative.paletteToSRGB8(centroidsQ16: oklab, k: n),
              flat.count == n * 3 else {
            // Deterministic core unavailable — fall back to the neutral anchor so the
            // view is still total (never an empty/garbled draw).
            return Array(repeating: SIMD3<UInt8>(127, 127, 127), count: n)
        }
        // Explicit types/locals — keep the SIMD3 init off the inference slow path.
        var out = [SIMD3<UInt8>](); out.reserveCapacity(n)
        for i in 0 ..< n {
            let b: Int = i * 3
            let px = SIMD3<UInt8>(flat[b], flat[b + 1], flat[b + 2])
            out.append(px)
        }
        return out
    }
}

#if DEBUG
#Preview("Contested cells — sentinel vs shimmer") {
    // A 4×4 demo grid: a clean diagonal, plus two contested cells. Column 0 is an
    // EFFECT-ZONE (its contested cell shimmers on the clock); the other contested
    // cell is unzoned, so it shows the loud magenta sentinel.
    let clock = PlaybackClock()
    let blue  = SFColor(45000,  -8000, -18000)
    let green = SFColor(52000, -18000,  12000)
    let red   = SFColor(40000,  20000,   9000)

    ContestedCellGridView(
        cells: 4,
        clock: clock,
        cellAt: { r, c in
            if r == 1 && c == 0 { return SFCell([blue, green]) } // contested, zoned → shimmer
            if r == 2 && c == 2 { return SFCell([red, green]) }  // contested, unzoned → sentinel
            if r == c           { return SFCell([blue]) }        // clean diagonal
            return SFCell()                                      // ⊥ → neutral
        },
        effectZone: { _, col in col == 0 }
    )
    .pixelFrame()
    .frame(width: 256, height: 256)
    .padding()
    .onAppear { clock.start() }
}
#endif
