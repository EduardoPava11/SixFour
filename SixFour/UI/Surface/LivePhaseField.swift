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
            // The influence-field ground is the ONE persistent surface hoisted to `SurfaceView`
            // (behind every phase) — not drawn here, so it is never recreated per phase. This phase
            // renders only its widgets + chrome on a CLEAR background over it.

            // LOOK swipe ground: a clear full-screen layer BEHIND the widgets. A horizontal
            // swipe cycles `settings.captureLook` (the data-driven OKLab grade that recolours
            // the hero + palette and is what Export LUT bakes). The hero passes touches through
            // (`allowsHitTesting(false)`), so swipes over it reach here; the palette keeps its
            // own tap-to-shoot / hold-to-move. Only a render param changes — nothing moves, so
            // the 4 pt cell grid is intact.
            Color.clear
                .contentShape(Rectangle())
                .gesture(lookSwipe)

            // Field64 — the 64-cell preview hero, placed at its SHARED global position and
            // movable (long-press to lift). The data source is the live camera tile; the
            // POSITION is the same `field64Position` review/render read.
            // `.movable` BEFORE `.place`: `.place` ends in a greedy `.position` that fills
            // the parent, so the gesture/contentShape MUST be applied to the sized widget
            // first — else each widget's hit area becomes the whole screen and the top one
            // swallows every touch (only one widget grabbable). Scoped here to the footprint.
            previewHero
                .movable(.field64, settings: settings, surface: surface, clock: clock)
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
        // stamp / status text (the grey writing read as distracting clutter). The ONE
        // exception is a transient LOOK name, shown only when a grade is active (default
        // `.off` ⇒ the screen is unchanged), so the swipe is legible without clutter.
        .overlay(alignment: .top) {
            if settings.captureLook != .off {
                CellText(settings.captureLook.displayName, cell: GlobalLattice.gif(1))
                    .padding(.top, GlobalLattice.gif(4))
                    .allowsHitTesting(false)
                    .accessibilityLabel("Look: \(settings.captureLook.displayName)")
            }
        }
    }

    /// A horizontal swipe cycles the LOOK (right = next, left = previous) with a haptic
    /// tick. `.onEnded` so one swipe = one step; horizontal-dominant + a 6-cell minimum
    /// keeps it from firing on taps or vertical drags. It only writes `settings.captureLook`
    /// (a render param) — never a position, so the cell grid is never disturbed.
    private var lookSwipe: some Gesture {
        DragGesture(minimumDistance: GlobalLattice.gif(6))
            .onEnded { value in
                let dx = value.translation.width
                let dy = value.translation.height
                guard abs(dx) > abs(dy), abs(dx) >= GlobalLattice.gif(6) else { return }
                settings.captureLook = dx < 0 ? settings.captureLook.next : settings.captureLook.prev
                Haptics.selection()   // discrete look-CHANGE confirmation — NOT a cell detent
                                      // (cellTick `play(1)` is reserved for the frame-locked .cellDetent)
            }
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
        .movable(.palette16, settings: settings, surface: surface, clock: clock,
                 enabled: surface.phase == .live,
                 onTap: { surface.step(.shutterTap) })
        .accessibilityLabel("Capture 64-frame burst")
        .accessibilityHint("Tap to capture sixty-four frames; long-press to move the palette")
    }
}

#if DEBUG
/// TESTABLE ACT I in the Xcode canvas — the live influence field fed by the synthetic
/// `DemoScene` (no camera needed). Tune `InfluenceField`'s `static` constants and watch it here;
/// run the full interactive app (draggable widgets) with the `-demoScene` launch argument.
/// (docs/SIXFOUR-TESTABLE-ACT1-WORKFLOW.md)
#Preview("Act I — influence field (demo scene)") {
    let surface = Surface()
    surface.step(.sessionReady)                 // bootstrap → .live (enables the shutter gate)
    surface.previewTile = DemoScene.tile(tick: 0)
    surface.previewPalette = DemoScene.palette
    surface.palette = DemoScene.palette
    return LivePhaseField(surface: surface, clock: SurfaceClock(), settings: AppSettings())
        .ignoresSafeArea()
}
#endif
