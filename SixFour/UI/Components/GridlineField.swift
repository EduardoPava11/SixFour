import SwiftUI
import Foundation
import Observation
import simd

/// THE 20 fps REFRESH HEARTBEAT — one cell size, everywhere.
///
/// The capture screen is a uniform grid of the ONE atom (`gifPx = 6 pt`): the 64×64
/// preview pixel, the 16×16 palette swatch, and this background cell are the IDENTICAL
/// 6 pt square (GRID Law #1 — grow by more cells, never a bigger cell). The black ground
/// is a binary B/W checkerboard of those 6 pt cells that inverts every frame at 20 fps —
/// a visible "refresh heartbeat" proving the canvas is live. The heroes (preview /
/// palette / gear) are excluded, so the checker frames them without ever crossing.
///
/// RENDERING: the checker is CELLS, never vector strokes (docs/SIXFOUR-TOTAL-PIXELATION).
/// `GridChecker.chrome(phase:exclude:)` returns a `PlacedCellMask` spanning the whole
/// 67×145 lattice; `CellField.image(tint:chrome:)` bakes it into the ONE indexed bitmap,
/// drawn once with `.interpolation(.none)`. No `Path`/`.stroke`/`.border`, no `.opacity`,
/// no glass — opaque sRGB8 only. Off the deterministic GIF path → pure Layers 0–2.

// MARK: - The 20 fps phase clock

/// The heartbeat clock — owns ONLY the phase bit, no geometry. Toggles `phase` each
/// `1 / SFTheme.gifFrameRate` s (the canonical 20-token) on a Foundation `Timer`,
/// mirroring `PlaybackClock`'s reduce-motion + lifecycle contract.
///
/// FUTURE clock home: `DisplayContract.logicRateHz` (the "ONE `CADisplayLink` at 20"
/// canon). Written so its tick *source* can later swap from `Timer` to the shared
/// `CADisplayLink` WITHOUT touching any checker logic; we DO NOT migrate `PlaybackClock`
/// here (keep this off the 149-test unified-player surface). Tier-2 pure.
@MainActor
@Observable
final class GridHeartbeatClock {
    /// The checker inversion bit (`0`/`1`); flipping it inverts the whole B/W checker in
    /// O(1) at the view layer (a pre-baked texture swap).
    private(set) var phase: Int = 0

    /// Auto-flip suppressed (reduce-motion): phase pinned to 0 → a STATIC opaque B/W
    /// checker (the grid is still visibly rendered, but never flashes/strobes).
    var reduceMotion: Bool {
        didSet { if reduceMotion { stop(); phase = 0 } }
    }

    private(set) var beating: Bool = false
    @ObservationIgnored private var timer: Timer?

    init(reduceMotion: Bool = false) { self.reduceMotion = reduceMotion }

    /// Begin the 20 fps phase flip. No-op under reduce-motion (freeze-on-phase-0).
    func start() {
        stop()
        guard !reduceMotion else { phase = 0; return }
        beating = true
        timer = Timer.scheduledTimer(withTimeInterval: 1.0 / Double(SFTheme.gifFrameRate),
                                     repeats: true) { [weak self] _ in
            Task { @MainActor in self?.flip() }
        }
    }

    func stop() { timer?.invalidate(); timer = nil; beating = false }

    /// Invert the checker by one tick — the only mutation of `phase`.
    func flip() {
        guard !reduceMotion else { return }
        phase ^= 1
    }
}

// MARK: - The uniform checker (cell-mask producer)

enum GridChecker {
    /// White lit value — opaque, slightly under 255 so the checker reads as *cells*.
    static let white = SIMD3<UInt8>(235, 235, 235)
    /// Near-black dark value — opaque `(16,16,16)`, NOT pure 0, so the dark square stays
    /// readable as a cell rather than a void.
    static let dark = SIMD3<UInt8>(16, 16, 16)

    /// Is atom `(c, r)` inside any excluded hero region (preview / palette / gear)?
    @inline(__always)
    static func excluded(_ c: Int, _ r: Int, _ regions: [ScreenLattice.Region]) -> Bool {
        for reg in regions where c >= reg.col && c < reg.col + reg.w && r >= reg.row && r < reg.row + reg.h {
            return true
        }
        return false
    }

    /// The checker colour at atom `(c, r)` for a given `phase`: `(c + r)` parity, inverted
    /// when `phase & 1` is set. Every non-excluded atom gets a colour (a FULL checker —
    /// one cell size, no gridline-band gaps).
    @inline(__always)
    static func color(_ c: Int, _ r: Int, phase: Int) -> SIMD3<UInt8> {
        let lit = ((c + r) & 1) == 1
        let on = lit != ((phase & 1) == 1)
        return on ? white : dark
    }

    /// The chrome producer: a `PlacedCellMask` spanning the FULL 67×145 lattice. For each
    /// atom: `nil` if inside an excluded hero region; else the opaque checker colour. The
    /// heroes draw ON TOP via `.latticeRegion`, so excluding them here frames them.
    static func chrome(phase: Int, exclude: [ScreenLattice.Region]) -> PlacedCellMask {
        PlacedCellMask(originCol: 0, originRow: 0,
                       cols: GlobalLattice.cols, rows: GlobalLattice.rows) { c, r in
            excluded(c, r, exclude) ? nil : color(c, r, phase: phase)
        }
    }
}

// MARK: - The live grid view (O(1)-flip)

/// The capture screen's living black ground: a full 6 pt B/W checker with the 20 fps
/// heartbeat baked in.
///
/// PERF: the two checker phases are pre-baked into TWO `UIImage`s (phase 0 and its
/// inverse) ONCE — the checker covers the whole ground, so it is independent of the live
/// camera tint (baked against black). Each 20 fps tick is then a `UIImage` SWAP (the GPU
/// samples the other texture), NOT a ~9.7k-cell re-bake.
struct GridRefreshFieldView: View {
    /// The 20 fps phase bit from `GridHeartbeatClock`; selects which pre-baked image shows.
    let phase: Int
    let exclude: [ScreenLattice.Region]

    /// The pre-baked (phase 0, phase 1) image pair. Baked once (no live-tint dependence).
    @State private var pair: (UIImage?, UIImage?)? = nil

    private func ensurePair() -> (UIImage?, UIImage?) {
        if let p = pair { return p }
        let base = SIMD3<UInt8>(0, 0, 0)   // fully covered by the checker; black is moot
        let p = (CellField.image(tint: base, chrome: [GridChecker.chrome(phase: 0, exclude: exclude)]),
                 CellField.image(tint: base, chrome: [GridChecker.chrome(phase: 1, exclude: exclude)]))
        pair = p
        return p
    }

    var body: some View {
        let (i0, i1) = ensurePair()
        let img = (phase & 1) == 1 ? i1 : i0
        return Group {
            if let img {
                Image(uiImage: img)
                    .interpolation(.none)
                    .resizable()
                    .frame(width: GlobalLattice.gif(CellField.cols),
                           height: GlobalLattice.gif(CellField.rows))
            } else {
                Color.black
            }
        }
        // PIN TOP-LEFT — the field's cell (0,0) coincides with the widgets' (0,0).
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color.black)
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }
}
