import SwiftUI
import Foundation
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

    var body: some View {
        let atom = GlobalLattice.gif(1)                          // the ONE 4 pt cell atom (cube law: 1 GIF px/cell)
        let s64 = Self.sums64(from: tile64, palette: palette)    // 64×64×3, 1 px/cell
        let s32 = ColorHead.poolSpatial2(s64, side: 64)          // 32×32×3, 4 px/cell — the exact ladder kernel
        let s16 = ColorHead.poolSpatial2(s32, side: 32)          // 16×16×3, 16 px/cell

        // LIVE-LADDER: read the real realized rungs only when the flag is on AND the tiles
        // are present (right shape). Either guard false ⇒ the in-view pooling path verbatim.
        // OPTICAL-EV takes precedence: three REAL exposures, rendered with NO digital gain
        // (gainStops 0 — the exposure IS optical now). Requires all three tiles present.
        let optical = useOptical
            && opticalTile64.count == 64 * 64
            && opticalTile32.count == 32 * 32
            && opticalTile16.count == 16 * 16
        let ladder32 = useLiveLadder && tile32.count == 32 * 32
        let ladder16 = useLiveLadder && tile16.count == 16 * 16

        let sprite64 = optical
            ? Self.rgbSprite(tile: opticalTile64, side: 64, gainStops: 0, cellPt: atom)
            : Self.pooledSprite(sums: s64, side: 64, count: 1, gainStops: ev64, cellPt: atom)
        let sprite32 = optical
            ? Self.rgbSprite(tile: opticalTile32, side: 32, gainStops: 0, cellPt: atom)
            : (ladder32 ? Self.rgbSprite(tile: tile32, side: 32, gainStops: ev32, cellPt: atom)
                        : Self.pooledSprite(sums: s32, side: 32, count: 4, gainStops: ev32, cellPt: atom))
        let sprite16 = optical
            ? Self.rgbShutterSprite(tile16: opticalTile16, gainStops: 0, cellPt: atom,
                                    active: stageActive, progress: shutterProgress)
            : (ladder16 ? Self.rgbShutterSprite(tile16: tile16, gainStops: ev16, cellPt: atom,
                                                active: stageActive, progress: shutterProgress)
                        : Self.shutterSprite(sums16: s16, gainStops: ev16, cellPt: atom,
                                             active: stageActive, progress: shutterProgress))

        // Wide top → point bottom. Tiles self-size (CellSprite frames itself), so the widths
        // (256/128/64 pt) ARE the pooling factors — the funnel is the ladder drawn to scale.
        VStack(spacing: GlobalLattice.gif(4)) {
            // 64² — the finest view; tap to meter. Location comes back in the tile's own
            // space, so normalizing by its side (atom·64) needs no origin.
            sprite64
                .contentShape(Rectangle())
                .gesture(SpatialTapGesture().onEnded { value in
                    let side = atom * 64
                    onMeter64(CGPoint(x: min(max(value.location.x / side, 0), 1),
                                      y: min(max(value.location.y / side, 0), 1)))
                    Haptics.selection()
                })

            // 32² — pure display; pass touches through so the ground still LOOK-swipes / EV-drags.
            // Live ladder (flag on + tile present) reads the real rung; else in-view pooling.
            sprite32
                .allowsHitTesting(false)

            // 16² — the vertex = the shutter. A plain tap fires the burst; the tile fills with
            // progress while the pipeline runs. No separate shutter glyph. The shutter fill +
            // progress-dim are preserved whether it reads the live ladder or the in-view pool.
            sprite16
                .contentShape(Rectangle())
                .onTapGesture { if shutterEnabled { onShutter() } }
                .accessibilityLabel(stageActive ? "Working" : "Capture 64-frame burst")
                .accessibilityHint("Tap the coarse view to capture sixty-four frames")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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

    /// Realize one rung's sums into a `CellSprite`: divide each bin by its pixel `count` (means
    /// don't compose, so divide only at the display boundary), apply digital EV gain (2^stops),
    /// clamp to sRGB8. `count` = pixels pooled per cell (1 / 4 / 16).
    static func pooledSprite(sums: [UInt64], side: Int, count: UInt64,
                             gainStops: Float, cellPt: CGFloat) -> CellSprite {
        let gain = pow(2.0, Double(gainStops))
        let k = Double(count)
        return CellSprite(cols: side, rows: side, cellPt: cellPt) { c, r in
            let i = (r * side + c) * 3
            let ch: (Int) -> UInt8 = { o in
                let v = (Double(sums[i + o]) / k) * gain
                return UInt8(max(0, min(255, v.rounded())))
            }
            return SIMD3<UInt8>(ch(0), ch(1), ch(2))
        }
    }

    /// The 16² shutter sprite: the coarsest pooled view (16 px/cell) with the progress-fill
    /// overlaid. While `active`, cells past `progress·256` dim to a quarter — the same
    /// cell-by-cell fill the retired palette-shutter used (both are exactly 256 cells).
    static func shutterSprite(sums16: [UInt64], gainStops: Float, cellPt: CGFloat,
                              active: Bool, progress: Double) -> CellSprite {
        let gain = pow(2.0, Double(gainStops))
        let filled = active ? Int((min(max(progress, 0), 1) * 256).rounded()) : 256
        return CellSprite(cols: 16, rows: 16, cellPt: cellPt) { c, r in
            let i = (r * 16 + c) * 3
            let ch: (Int) -> UInt8 = { o in
                let v = (Double(sums16[i + o]) / 16.0) * gain
                return UInt8(max(0, min(255, v.rounded())))
            }
            let base = SIMD3<UInt8>(ch(0), ch(1), ch(2))
            guard active else { return base }
            return (r * 16 + c) < filled ? base : SIMD3<UInt8>(base.x / 4, base.y / 4, base.z / 4)
        }
    }

    // MARK: - The live-ladder realization (Feature.liveLadder)

    /// Realize one PRE-MEANED rung tile (the live `ColorHead` ladder, one `SIMD3<UInt8>`
    /// per cell already area-meaned + inverse-EOTF'd by the Zig kernel) into a `CellSprite`:
    /// apply the digital EV gain (2^stops) + clamp to sRGB8. The `rgbSprite` twin of
    /// `pooledSprite` — no `/count` divide, since the means are already realized.
    static func rgbSprite(tile: [SIMD3<UInt8>], side: Int, gainStops: Float,
                          cellPt: CGFloat) -> CellSprite {
        let gain = pow(2.0, Double(gainStops))
        return CellSprite(cols: side, rows: side, cellPt: cellPt) { c, r in
            let px = tile[r * side + c]
            let ch: (UInt8) -> UInt8 = { v in
                UInt8(max(0, min(255, (Double(v) * gain).rounded())))
            }
            return SIMD3<UInt8>(ch(px.x), ch(px.y), ch(px.z))
        }
    }

    /// The live-ladder 16² shutter: `rgbSprite` + the SAME progress-fill overlay as
    /// `shutterSprite` (cells past `progress·256` dim to a quarter while `active`), so the
    /// shutter fill is byte-for-byte identical to the pooled path — only the pixel source
    /// (the pre-realized `tile16` vs the in-view pooled sums) differs.
    static func rgbShutterSprite(tile16: [SIMD3<UInt8>], gainStops: Float, cellPt: CGFloat,
                                 active: Bool, progress: Double) -> CellSprite {
        let gain = pow(2.0, Double(gainStops))
        let filled = active ? Int((min(max(progress, 0), 1) * 256).rounded()) : 256
        return CellSprite(cols: 16, rows: 16, cellPt: cellPt) { c, r in
            let px = tile16[r * 16 + c]
            let ch: (UInt8) -> UInt8 = { v in
                UInt8(max(0, min(255, (Double(v) * gain).rounded())))
            }
            let base = SIMD3<UInt8>(ch(px.x), ch(px.y), ch(px.z))
            guard active else { return base }
            return (r * 16 + c) < filled ? base : SIMD3<UInt8>(base.x / 4, base.y / 4, base.z / 4)
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
