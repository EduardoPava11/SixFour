import SwiftUI
import UIKit
import Foundation
import simd

/// Π for the `live` family of phases (`.live`, `.locking`, `.capturing`) — the capture
/// face of the ONE surface. Ported from `CaptureView.latticeScene`: a palette-tinted
/// live checker ground + the 64-cell preview hero + the 16-cell live palette that IS the
/// shutter (tapping it fires the burst) + the build stamp.
///
/// This is the seam fulfilment for `PhaseField`: a pure `(Surface, SurfaceClock) -> View`
/// that reads σ and emits CELLS only — no `Text`, no glass, no SF-Symbol, no UIKit
/// `Slider`/`Picker` on chrome. The two heroes are `.place(_:)`-d by the proven
/// `GridLayoutContract.captureScene` (the same contention-free regions the old capture
/// scene used), so the surface keeps its single uniform 4 pt lattice.
///
/// What it reads from σ:
///   - `surface.palette`  — the 256 live colours: tints the checker AND fills the 16×16
///                          shutter (the GIF's first abstraction = the capture button).
///   - `surface.phase`    — `.live` is tappable (fires `.shutterTap`); `.locking` /
///                          `.capturing` are inert (a state is a cell transform, never an
///                          opacity fade — the grid simply stops being a `Button`).
///   - `clock.heartbeat`  — the 20 fps inversion bit that proves the canvas is live.
///
/// The 64×64 camera tile and the granular capture progress live on the camera engine
/// (`CaptureViewModel`), which a later stage folds into σ; until then the hero renders a
/// palette-derived live field from the data σ already carries. The shape (preview region
/// + palette-as-shutter) is final and the engine hook drops straight in.
struct LivePhaseField: View {
    let surface: Surface
    let clock: SurfaceClock
    /// The ONE shared widget layout (the three global ColorWidget positions) + persistence.
    @Bindable var settings: AppSettings

    /// The current shared placement (identity → position). Re-read every body so a move in
    /// any phase is visible here (one global position across phases).
    private var placement: [ColorIdentity: (col: Int, row: Int)] { settings.widgetPlacement }

    var body: some View {
        ZStack(alignment: .topLeading) {
            // The living ground: a full-screen checker of the ONE 4 pt atom that inverts at
            // 20 fps. Palette-tinted (the captured/live look), not B/W — the two checker
            // inks are pulled from σ's palette via `SurfaceColor`, so the ground wears the
            // scene's colour while still proving liveness through the heartbeat inversion.
            TintedCheckerField(palette: surface.palette, phase: clock.heartbeat)
                .ignoresSafeArea()

            // Field64 — the 64-cell preview hero, placed at its SHARED global position and
            // movable (long-press to lift). The data source is the live camera tile; the
            // POSITION is the same `field64Position` review/render read.
            // `.movable` BEFORE `.place`: `.place` ends in a greedy `.position` that fills
            // the parent, so the gesture/contentShape MUST be applied to the sized widget
            // first — else each widget's hit area becomes the whole screen and the top one
            // swallows every touch (only one widget grabbable). Scoped here to the footprint.
            previewHero
                .movable(.field64, settings: settings, surface: surface)
                .place(region(for: .field64, at: placement))

            // Palette16 — the 16-cell live palette = THE capture button, at its shared
            // position. The tap (`onTap`) and the long-press lift are ONE composed gesture
            // (no Button wrapper) so they don't fight: a clean tap fires the burst, a hold
            // lifts it to move. Both gated to `.live` (a busy palette is inert).
            paletteShutter
                .place(region(for: .palette16, at: placement))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .ignoresSafeArea()
        // The open screen is JUST the preview + palette on the checker ground — no build
        // stamp / status text (the grey writing read as distracting clutter).
    }

    // MARK: - The preview hero (64 × 64 cells)

    /// The canvas: ALWAYS a 64×64 cell tile (the cube law — 1 GIF pixel per cell), never a
    /// raw camera feed; you live inside the 64³ world. Rendered as one `CellSprite` bitmap
    /// at the gifPx atom (64 × 4 = 256 pt). Source = σ's live camera tile (`previewTile`, the
    /// real quantized 64×64 the engine produces every frame) read through its paired
    /// `previewPalette`. The camera's own ~10 fps cadence drives the liveness — no synthetic
    /// scroll, no second clock. Falls back to the ghost ink before the first frame arrives.
    /// No interpolation, no AA — flat indexed cells.
    private var previewHero: some View {
        let side = GlobalLattice.gif(GlobalLattice.previewCells)   // 64 × 4 = 256 pt
        let tile = surface.previewTile
        let pal = surface.previewPalette
        let ghost = SIMD3<UInt8>(20, 20, 24)
        return CellSprite(cols: 64, rows: 64, cellPt: side / 64) { c, r in
            let i = r * 64 + c
            guard i < tile.count, Int(tile[i]) < pal.count else { return ghost }
            return pal[Int(tile[i])]
        }
        .frame(width: side, height: side)
        .clipped()
        .allowsHitTesting(false)   // the engine's focus layer (later) sits underneath
    }

    // MARK: - The palette-as-shutter (16 × 16 cells)

    /// The 256-colour live palette as a 16×16 grid (64 pt, 4 pt/cell) — the GIF's first
    /// abstraction AND the capture button itself: tap the palette to shoot the 64-frame
    /// burst (`surface.step(.shutterTap)`). Colour + position ARE the button; there is no
    /// separate shutter glyph. The 256 colours are placed through the centralized
    /// `GridScript.capture` (row-major / identity order — no per-frame re-sort jitter), so
    /// both render backends resolve a cell via the one `surfaceColors` (Spec.GridScript).
    ///
    /// Inert when the surface is busy (`.locking` / `.capturing`): a state is a cell
    /// transform, not an opacity fade — the grid simply stops being a `Button`.
    private var paletteShutter: some View {
        let ghost = SIMD3<UInt8>(20, 20, 24)
        // Pad to a full 256 so the order is a total permutation, then permute into screen
        // rank via the capture script (identity for capture).
        let padded: [SIMD3<UInt8>] = (0 ..< 256).map { $0 < surface.palette.count ? surface.palette[$0] : ghost }
        let ordered = GridScript.capture(side: 16).surfaceColors(palette: padded)

        // ONE composed gesture (no Button): a clean TAP fires `.shutterTap`, a long-press
        // LIFTS it to move. `.movable` composes them with `.exclusively` so they never fight
        // — the prior Button-wrapping swallowed the tap. Both gated to `.live` via `enabled`
        // (a busy palette is inert: no capture, no move).
        return CellSprite(cols: 16, rows: 16, cellPt: GlobalLattice.gif(1)) { c, r in
            let rank = r * 16 + c
            return rank < ordered.count ? ordered[rank] : ghost
        }
        .movable(.palette16, settings: settings, surface: surface,
                 enabled: surface.phase == .live,
                 onTap: { surface.step(.shutterTap) })
        .accessibilityLabel("Capture 64-frame burst")
        .accessibilityHint("Tap to capture sixty-four frames; long-press to move the palette")
    }
}

// MARK: - The palette-tinted heartbeat ground

/// The capture screen's living ground, ported from `GridRefreshFieldView` but PALETTE-
/// TINTED: a full-screen checker of the ONE 4 pt atom whose two inks are pulled from σ's
/// palette (dark + light extremes), inverting every tick at 20 fps. Off the deterministic
/// GIF path → pure cell bitmap, no `Path`/`.stroke`/`.opacity`. When the palette is empty
/// (pre-bootstrap) it falls back to the canonical near-B/W `GridChecker` inks so the
/// ground is always visibly live.
///
/// Perf: both parities are pre-baked into TWO `UIImage`s (re-baked only when the palette's
/// chosen inks change), so each 20 fps tick is a texture SWAP, not a per-cell re-bake —
/// the same O(1)-flip discipline as `GridRefreshFieldView`.
private struct TintedCheckerField: View {
    let palette: [SIMD3<UInt8>]
    /// The 20 fps heartbeat bit from κ; selects the checker parity.
    let phase: Int

    /// Cache: the inks the current pair was baked for, and the (parity-0, parity-1) images.
    @State private var baked: (dark: SIMD3<UInt8>, light: SIMD3<UInt8>, p0: UIImage?, p1: UIImage?)? = nil

    var body: some View {
        let (dark, light) = Self.inks(palette)
        let pair = ensure(dark: dark, light: light)
        let img = (phase & 1) == 1 ? pair.1 : pair.0
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
        .background(Color.black)
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }

    /// Return the cached (parity-0, parity-1) pair, re-baking only when the inks change.
    private func ensure(dark: SIMD3<UInt8>, light: SIMD3<UInt8>) -> (UIImage?, UIImage?) {
        if let b = baked, b.dark == dark, b.light == light { return (b.p0, b.p1) }
        let p0 = Self.image(dark: dark, light: light, phase: 0)
        let p1 = Self.image(dark: dark, light: light, phase: 1)
        DispatchQueue.main.async { baked = (dark, light, p0, p1) }
        return (p0, p1)
    }

    /// Bake one parity of the tinted checker as a `cols × rows` indexed bitmap (1 px == 1
    /// cell). Mirrors `GridChecker.image`, but with palette-derived inks.
    private static func image(dark: SIMD3<UInt8>, light: SIMD3<UInt8>, phase: Int) -> UIImage? {
        CellBitmap.image(cols: SixFourLattice.cols, rows: SixFourLattice.rows) { c, r in
            let lit = ((c + r) & 1) == 1
            return (lit != ((phase & 1) == 1)) ? light : dark
        }
    }

    /// Pick the two checker inks from the live palette: the darkest and the lightest
    /// entries (by sRGB luma proxy r+g+b), so the ground wears the scene's tonal extremes.
    /// Falls back to `GridChecker`'s near-B/W when the palette is empty.
    private static func inks(_ pal: [SIMD3<UInt8>]) -> (SIMD3<UInt8>, SIMD3<UInt8>) {
        guard !pal.isEmpty else { return (GridChecker.dark, GridChecker.white) }
        @inline(__always) func luma(_ c: SIMD3<UInt8>) -> Int { Int(c.x) + Int(c.y) + Int(c.z) }
        var dark = pal[0], light = pal[0]
        var dMin = luma(pal[0]), dMax = luma(pal[0])
        for c in pal.dropFirst() {
            let l = luma(c)
            if l < dMin { dMin = l; dark = c }
            if l > dMax { dMax = l; light = c }
        }
        return (dark, light)
    }
}
