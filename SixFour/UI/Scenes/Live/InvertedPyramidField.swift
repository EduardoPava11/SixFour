import SwiftUI
import Foundation
import UIKit
import simd

/// THE LIVE CAPTURE FACE — the inverted-pyramid three-view.
///
/// The user opens the phone and sees the world at all THREE granularities of the isotropic
/// 2×2×2 ladder at once: 64² (top, widest), 32² (middle), 16² (the point). The 16² vertex
/// IS the shutter — tapping it fires the 64-frame burst. Tapping the 64² meters that point.
/// The three tiles are not three captures; they are three resolutions of ONE live feed,
/// pooled here for display by the SHIPPED exact kernel (`ColorHead.poolSpatial2`, 64→32→16),
/// exactly the ladder the device derives (64@20 / 32@10 / 16@5 fps). Each tile is shown at
/// its own DIGITAL EV (a per-tile sRGB gain) — the burst itself stays one locked exposure;
/// the "different EVs" are a display ladder (v2 promotes them to real optical EV).
///
/// LAYOUT: at the ONE 4 pt cell atom the tiles self-size to 256 / 128 / 64 pt, so the funnel
/// is the pooling factor drawn to scale — coarser view = smaller footprint = the shutter.
/// The unit self-centers (`.frame(maxWidth:.infinity…)`, no `.position`/`.offset`), so it is
/// grid-lint clean without needing a `GridLayoutContract` region.
///
/// This view is σ-agnostic: it takes plain data + closures. `LivePhaseField` owns σ and the
/// gating (it passes `shutterEnabled = phase == .live && !stage.active` so a mid-burst tap is
/// inert) and reuses the existing `onShutter` (→ `engine.capture()`) and `onMeter` hooks, so
/// the shipped capture/GIF path is untouched.
struct InvertedPyramidField: View {
    /// The live 64×64 index tile (`surface.previewTile`): one palette index per GIF pixel.
    let tile64: [UInt8]
    /// The 256-colour palette those indices resolve through (`surface.previewPalette`).
    let palette: [SIMD3<UInt8>]

    /// LIVE-LADDER (Feature.liveLadder): the REAL device ladder rungs realized to sRGB8 by
    /// the preview `ColorHead` — 32² (1024 RGB) and 16² (256 RGB), pre-meaned means (not
    /// index/palette). Read for the 32²/16² tiles when `useLiveLadder` is on AND they are
    /// non-empty; otherwise the pyramid pools the 64² in-view verbatim (today's path).
    var tile32: [SIMD3<UInt8>] = []
    var tile16: [SIMD3<UInt8>] = []
    /// Whether to read the real ladder (`tile32`/`tile16`) for the 32²/16² rungs. `false`
    /// (default) ⇒ the in-view `poolSpatial2` path, byte-identical to today.
    var useLiveLadder: Bool = false

    /// OPTICAL-EV (Feature.opticalEV): three REAL exposures, one per tile (64²=base /
    /// 32²=+1 stop / 16²=+2 stops by default — the light ladder), already realized to sRGB8 by the preview
    /// `ColorHead`. When `useOptical` is on AND all three are present, EVERY tile renders its
    /// real exposure with NO digital gain (gainStops 0). Takes precedence over live-ladder /
    /// in-view. Empty ⇒ falls through to those paths.
    var opticalTile64: [SIMD3<UInt8>] = []
    var opticalTile32: [SIMD3<UInt8>] = []
    var opticalTile16: [SIMD3<UInt8>] = []
    var useOptical: Bool = false

    /// Per-tile DIGITAL exposure in STOPS (display gain). Coarse rungs lift a touch, matching
    /// "more colour-time ⇒ can carry the brighter exposure". Not the optical burst exposure.
    var ev64: Float = 0
    var ev32: Float = 0.5
    var ev16: Float = 1.0

    /// Shutter progress-fill (mirrors the retired palette-shutter): while a stage is active the
    /// 16² fills cell-by-cell, completed cells at full colour, pending dimmed.
    var stageActive: Bool = false
    var shutterProgress: Double = 0
    /// Whether a tap on the 16² should fire. `LivePhaseField` sets this to
    /// `phase == .live && !stage.active`, so a busy surface never advertises a dead verb.
    var shutterEnabled: Bool = true

    /// Fired by a tap on the 16² vertex — the shutter kick (`engine.capture()`).
    var onShutter: () -> Void = {}
    /// Fired by a tap on the 64² — one-shot meter that point (normalized 0..1 over the tile).
    var onMeter64: (CGPoint) -> Void = { _ in }

    /// PERF 2026-07-08: the pooling + three bitmap bakes used to run inside `body`
    /// on MAIN for EVERY surface publish (fresh 96 KB sums, two `poolSpatial2`
    /// passes, three CGContext bakes at up to ~20 Hz during a burst, zero caching).
    /// The bakes now live in @State keyed by the actual inputs: a pixel-input
    /// change rebakes all three ONCE; a progress-only change (the burst fill)
    /// rebakes ONLY the 256-cell 16² shutter overlay — and only when the FILLED
    /// CELL COUNT steps, not per progress float. Rendered bytes are identical.
    @State private var baked = Baked()

    private struct Baked {
        var img64: UIImage?
        var img32: UIImage?
        var img16: UIImage?
        /// The 16²'s gain-applied base colours — the shutter rebake redims these
        /// 256 cells without re-pooling the pyramid.
        var base16: [SIMD3<UInt8>] = []
    }

    /// One fingerprint over every input that changes the PIXELS (not the shutter
    /// fill). Hashing ~20 KB per body evaluation is microseconds; it is what lets
    /// a progress-only evaluation skip the pyramid entirely.
    private var pixelKey: Int {
        var h = Hasher()
        h.combine(tile64); h.combine(palette)
        h.combine(tile32); h.combine(tile16); h.combine(useLiveLadder)
        h.combine(opticalTile64); h.combine(opticalTile32); h.combine(opticalTile16)
        h.combine(useOptical)
        h.combine(ev64); h.combine(ev32); h.combine(ev16)
        return h.finalize()
    }

    /// The shutter fill state, quantized to the cell grid: -1 when inactive, else
    /// the filled-cell count 0…256 — the same rounding the fill overlay draws.
    private var shutterKey: Int {
        stageActive ? Int((min(max(shutterProgress, 0), 1) * 256).rounded()) : -1
    }

    var body: some View {
        let atom = GlobalLattice.gif(1)   // the ONE 4 pt cell atom (cube law: 1 GIF px/cell)

        // Wide top → point bottom. Tiles are framed at atom·side, so the widths
        // (256/128/64 pt) ARE the pooling factors — the funnel is the ladder drawn to scale.
        VStack(spacing: GlobalLattice.gif(4)) {
            // 64² — the finest view; tap to meter. Location comes back in the tile's own
            // space, so normalizing by its side (atom·64) needs no origin.
            Self.spriteImage(baked.img64, side: 64, cellPt: atom)
                .contentShape(Rectangle())
                .gesture(SpatialTapGesture().onEnded { value in
                    let side = atom * 64
                    onMeter64(CGPoint(x: min(max(value.location.x / side, 0), 1),
                                      y: min(max(value.location.y / side, 0), 1)))
                    Haptics.selection()
                })

            // 32² — pure display; pass touches through so the ground still LOOK-swipes / EV-drags.
            // Live ladder (flag on + tile present) reads the real rung; else in-view pooling.
            Self.spriteImage(baked.img32, side: 32, cellPt: atom)
                .allowsHitTesting(false)

            // 16² — the vertex = the shutter. A plain tap fires the burst; the tile fills with
            // progress while the pipeline runs. No separate shutter glyph. The shutter fill +
            // progress-dim are preserved whether it reads the live ladder or the in-view pool.
            Self.spriteImage(baked.img16, side: 16, cellPt: atom)
                .contentShape(Rectangle())
                .onTapGesture { if shutterEnabled { onShutter() } }
                .accessibilityLabel(stageActive ? "Working" : "Capture 64-frame burst")
                .accessibilityHint("Tap the coarse view to capture sixty-four frames")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onChange(of: pixelKey, initial: true) { _, _ in
            rebakePyramid()
            rebakeShutter()
        }
        .onChange(of: shutterKey) { _, _ in
            rebakeShutter()
        }
    }

    /// The cached bitmap at the cell pitch — the `CellSprite` render contract
    /// (nearest-neighbour, no AA, self-framed) minus the per-evaluation bake.
    @ViewBuilder
    private static func spriteImage(_ img: UIImage?, side: Int, cellPt: CGFloat) -> some View {
        if let img {
            Image(uiImage: img)
                .interpolation(.none)
                .resizable()
                .frame(width: cellPt * CGFloat(side), height: cellPt * CGFloat(side))
        }
    }

    /// Re-resolve the source path (optical ▸ live-ladder ▸ in-view pool) and bake
    /// the 64² + 32² bitmaps plus the 16²'s base colours. Runs once per PIXEL
    /// change, not once per body evaluation. Colour math is verbatim the old
    /// per-eval sprite closures.
    private func rebakePyramid() {
        // OPTICAL-EV takes precedence: three REAL exposures, rendered with NO digital gain
        // (gainStops 0 — the exposure IS optical now). Requires all three tiles present.
        let optical = useOptical
            && opticalTile64.count == 64 * 64
            && opticalTile32.count == 32 * 32
            && opticalTile16.count == 16 * 16
        let ladder32 = useLiveLadder && tile32.count == 32 * 32
        let ladder16 = useLiveLadder && tile16.count == 16 * 16

        if optical {
            baked.img64 = Self.rgbImage(tile: opticalTile64, side: 64, gainStops: 0)
            baked.img32 = Self.rgbImage(tile: opticalTile32, side: 32, gainStops: 0)
            baked.base16 = Self.rgbBase(tile: opticalTile16, side: 16, gainStops: 0)
            return
        }

        let s64 = Self.sums64(from: tile64, palette: palette)    // 64×64×3, 1 px/cell
        let s32 = ColorHead.poolSpatial2(s64, side: 64)          // 32×32×3, 4 px/cell — the exact ladder kernel
        baked.img64 = Self.pooledImage(sums: s64, side: 64, count: 1, gainStops: ev64)
        baked.img32 = ladder32
            ? Self.rgbImage(tile: tile32, side: 32, gainStops: ev32)
            : Self.pooledImage(sums: s32, side: 32, count: 4, gainStops: ev32)
        if ladder16 {
            baked.base16 = Self.rgbBase(tile: tile16, side: 16, gainStops: ev16)
        } else {
            let s16 = ColorHead.poolSpatial2(s32, side: 32)      // 16×16×3, 16 px/cell
            baked.base16 = Self.pooledBase(sums: s16, side: 16, count: 16, gainStops: ev16)
        }
    }

    /// Bake ONLY the 16² shutter bitmap from the cached base colours: while a
    /// stage is active, cells past `progress·256` dim to a quarter — the same
    /// cell-by-cell fill the retired palette-shutter used (both are exactly 256
    /// cells). 256 cells per fill step, no pyramid work.
    private func rebakeShutter() {
        guard baked.base16.count == 16 * 16 else { baked.img16 = nil; return }
        let filled = stageActive ? Int((min(max(shutterProgress, 0), 1) * 256).rounded()) : 256
        let active = stageActive
        let base = baked.base16
        baked.img16 = CellBitmap.image(cols: 16, rows: 16) { c, r in
            let b = base[r * 16 + c]
            guard active else { return b }
            return (r * 16 + c) < filled ? b : SIMD3<UInt8>(b.x / 4, b.y / 4, b.z / 4)
        }
    }

    // MARK: - The pooling (reuses the shipped exact kernel)

    /// Resolve the 64×64 index tile into the sums carrier (`side²·3` u64, one pixel per cell
    /// so `count == 1`) that `ColorHead.poolSpatial2` consumes. Off-palette indices resolve to
    /// black. The display twin of the camera's `poolSums64`.
    static func sums64(from tile: [UInt8], palette: [SIMD3<UInt8>]) -> [UInt64] {
        var s = [UInt64](repeating: 0, count: 64 * 64 * 3)
        let n = min(tile.count, 64 * 64)
        for i in 0 ..< n {
            let idx = Int(tile[i])
            let c = idx < palette.count ? palette[idx] : SIMD3<UInt8>(0, 0, 0)
            s[i * 3] = UInt64(c.x)
            s[i * 3 + 1] = UInt64(c.y)
            s[i * 3 + 2] = UInt64(c.z)
        }
        return s
    }

    /// Realize one rung's sums into a baked bitmap: divide each bin by its pixel `count`
    /// (means don't compose, so divide only at the display boundary), apply digital EV
    /// gain (2^stops), clamp to sRGB8. `count` = pixels pooled per cell (1 / 4 / 16).
    /// Same closure the per-eval `CellSprite` ran; it now bakes once per pixel change.
    static func pooledImage(sums: [UInt64], side: Int, count: UInt64,
                            gainStops: Float) -> UIImage? {
        let gain = pow(2.0, Double(gainStops))
        let k = Double(count)
        return CellBitmap.image(cols: side, rows: side) { c, r in
            let i = (r * side + c) * 3
            let ch: (Int) -> UInt8 = { o in
                let v = (Double(sums[i + o]) / k) * gain
                return UInt8(max(0, min(255, v.rounded())))
            }
            return SIMD3<UInt8>(ch(0), ch(1), ch(2))
        }
    }

    /// The 16²'s gain-applied base colours from pooled sums (16 px/cell) — the
    /// shutter fill dims THESE, so they cache across fill steps.
    static func pooledBase(sums: [UInt64], side: Int, count: UInt64,
                           gainStops: Float) -> [SIMD3<UInt8>] {
        let gain = pow(2.0, Double(gainStops))
        let k = Double(count)
        return (0 ..< side * side).map { cell in
            let i = cell * 3
            let ch: (Int) -> UInt8 = { o in
                let v = (Double(sums[i + o]) / k) * gain
                return UInt8(max(0, min(255, v.rounded())))
            }
            return SIMD3<UInt8>(ch(0), ch(1), ch(2))
        }
    }

    // MARK: - The live-ladder realization (Feature.liveLadder)

    /// Realize one PRE-MEANED rung tile (the live `ColorHead` ladder, one `SIMD3<UInt8>`
    /// per cell already area-meaned + inverse-EOTF'd by the Zig kernel) into a baked
    /// bitmap: apply the digital EV gain (2^stops) + clamp to sRGB8. The `rgbImage`
    /// twin of `pooledImage` — no `/count` divide, since the means are already realized.
    static func rgbImage(tile: [SIMD3<UInt8>], side: Int, gainStops: Float) -> UIImage? {
        let gain = pow(2.0, Double(gainStops))
        return CellBitmap.image(cols: side, rows: side) { c, r in
            let px = tile[r * side + c]
            let ch: (UInt8) -> UInt8 = { v in
                UInt8(max(0, min(255, (Double(v) * gain).rounded())))
            }
            return SIMD3<UInt8>(ch(px.x), ch(px.y), ch(px.z))
        }
    }

    /// The 16²'s gain-applied base colours from a pre-realized tile — the live-ladder /
    /// optical twin of `pooledBase`. The shutter fill (rebakeShutter) is byte-for-byte
    /// identical to the pooled path — only the pixel source differs.
    static func rgbBase(tile: [SIMD3<UInt8>], side: Int, gainStops: Float) -> [SIMD3<UInt8>] {
        let gain = pow(2.0, Double(gainStops))
        return tile.map { px in
            let ch: (UInt8) -> UInt8 = { v in
                UInt8(max(0, min(255, (Double(v) * gain).rounded())))
            }
            return SIMD3<UInt8>(ch(px.x), ch(px.y), ch(px.z))
        }
    }
}

#if DEBUG
/// Canvas check with no camera — the synthetic `DemoScene` tile pooled to the three rungs.
#Preview("Inverted pyramid — three views (demo scene)") {
    InvertedPyramidField(tile64: DemoScene.tile(tick: 0),
                         palette: DemoScene.palette)
        .ignoresSafeArea()
}
#endif
