import SwiftUI
import simd

/// Π·review — the cell-field renderer for the `.review` phase of the ONE surface.
///
/// This is the per-phase renderer the `PhaseField.field(for:_:)` seam routes `.review`
/// to. It is a pure projection of σ: it reads `palettesPerFrame` / `indexCube` / `cursor`
/// and emits cells. It owns NO clock and NO state of its own — the ONE `SurfaceClock` (κ)
/// drives `σ.cursor` (the Z₆₄ frame), and this field just paints the frame at that cursor.
///
/// The hero is the FLAT 2D GIFA ANIMATION — a 64×64 cell sprite playing the committed
/// GIFA frame-by-frame through the TRUE per-frame palette (`Surface.gifCell`). The 3D cube
/// reveal (the x/y rung-shear `bakeCube` + the tilt sliders) is RETIRED: review is the
/// honest 2D loop, the same thing the GIF actually is. Below it, the 16×16 per-frame
/// palette (the GIF's first abstraction — and the live shutter's twin, so the element is
/// continuous capture→review). Both are MIDDLE-CENTERED with commensurate spacing.
///   1. The hero reads its frame from `σ.cursor` (κ's Z₆₄ cursor), not a `PlaybackClock`.
///   2. One cell per GIF pixel (the cube law); integer 4 pt atom → always crisp, no AA.
///   3. The data is read from σ only, so the renderer never touches `CaptureViewModel`.
///
/// Cells only: `CellText` / `CellActionButton` / `CellSprite`. No `Text` / glass /
/// SF-Symbol / UIKit `Slider`·`Picker`. Tier-2 pure: SwiftUI + simd.
struct ReviewPhaseField: View {
    /// σ — read for data, written only via the `.retake` event.
    @Bindable var surface: Surface
    /// κ — advances `σ.cursor`; the frame this field paints comes from that one cursor.
    let clock: SurfaceClock
    /// The ONE shared widget layout (the three global ColorWidget positions) + persistence.
    @Bindable var settings: AppSettings

    /// The current shared placement — the SAME three positions live/render read. Review is
    /// now placed (no longer VStack-centered), so all phases honor the one global layout.
    private var placement: [ColorIdentity: (col: Int, row: Int)] { settings.widgetPlacement }

    /// COLOR ATLAS (gated, default OFF) — the out-of-band curation SUB-STATE inside
    /// `.review` (docs/COLOR-ATLAS.md §8 Phase C): not a new FSM phase, no new movable
    /// widget identity. Both are view-local: leaving review removes this field from the
    /// hierarchy, so the sub-state and the session reset naturally on retake.
    @State private var atlasOpen = false
    @State private var atlas = AtlasState()

    /// The shared content edge — 64 cells × the 4 pt atom = 256 pt (same as the preview).
    private let gifEdge = GlobalLattice.gif(GlobalLattice.previewCells)
    /// The palette edge — 16 cells × 4 pt = 64 pt (the GIF's first abstraction = the shutter).
    private let paletteEdge = GlobalLattice.gif(GlobalLattice.shutterCells)

    var body: some View {
        ZStack(alignment: .topLeading) {
            // The influence-field ground is the ONE persistent surface in `SurfaceView` (behind
            // every phase). This phase renders only the GIFA hero + chrome on a clear background.

            if surface.palettesPerFrame.isEmpty {
                // No committed GIFA in σ yet: just the field ground, no label.
                Color.clear
            } else if atlasOpen && settings.colorAtlasEnabled {
                // The Color Atlas curation sub-state (flag-gated; never reachable
                // while `colorAtlasEnabled` is false — the default path is untouched).
                atlasCurationField
            } else {
                // All three ColorWidgets are PLACED at the ONE shared global position (no
                // more VStack-centering) and movable — Field64's gif-render and Palette16's
                // per-frame palette slide here at the SAME positions the live screen set.
                // `.movable` BEFORE `.place` so each gesture is footprint-scoped (else the
                // greedy `.position` in `.place` makes it full-screen and the top widget
                // eats every touch — the reason the hero would not move after capture).
                gifaHero
                    .movable(.field64, settings: settings, surface: surface)
                    .place(region(for: .field64, at: placement))

                paletteStrip
                    .movable(.palette16, settings: settings, surface: surface)
                    .place(region(for: .palette16, at: placement))

                // Immovable bottom chrome (NOT a ColorWidget): the action row, pinned to
                // the bottom edge. (Determinism text removed — illegible at cell size.)
                actionRow
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                .padding(.horizontal, GlobalLattice.gif(GlobalLattice.gutterCells))
                .padding(.bottom, GlobalLattice.gif(GlobalLattice.gutterCells))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .ignoresSafeArea()
    }

    // MARK: - The GIFA hero (64 × 64 cells, the 2D loop)

    /// The hero — the committed GIFA playing as a flat 64×64 cell loop at the cursor frame,
    /// read through the TRUE per-frame palette (`Surface.gifCell`). Same `CellSprite` the
    /// live preview uses, so capture→review is the SAME instrument (the element slides; it
    /// is never swapped). `nil` cells fall through to the live ground (no black backing).
    private var gifaHero: some View {
        CellSprite(cols: GlobalLattice.previewCells,
                   rows: GlobalLattice.previewCells,
                   cellPt: GlobalLattice.gifPx) { c, r in
            surface.gifCell(c, r, surface.cursor)
        }
        .frame(width: gifEdge, height: gifEdge)
    }

    // MARK: - The per-frame palette (16 × 16 cells, the shutter's twin)

    /// The 256 colours of the CURRENT frame as a 16×16 grid — the GIF's first abstraction
    /// and the capture shutter's continuation (same `GridScript.capture` order, so the
    /// element is continuous across the flow). Cycles with the cursor: you watch the palette
    /// breathe as the GIFA plays. Inert (review has no shutter); pure cells.
    private var paletteStrip: some View {
        let ghost = SIMD3<UInt8>(20, 20, 24)
        let frame = surface.cursor < surface.palettesPerFrame.count
            ? surface.palettesPerFrame[surface.cursor] : []
        let padded: [SIMD3<UInt8>] = (0 ..< 256).map { $0 < frame.count ? frame[$0] : ghost }
        let ordered = GridScript.capture(side: 16).surfaceColors(palette: padded)
        return CellSprite(cols: 16, rows: 16, cellPt: GlobalLattice.gifPx) { c, r in
            let rank = r * 16 + c
            return rank < ordered.count ? ordered[rank] : ghost
        }
        .frame(width: paletteEdge, height: paletteEdge)
        .accessibilityLabel("Per-frame palette, 256 colours")
    }

    // MARK: - Actions

    /// Share + Retake. Retake fires `.retake` (→ `.live`, the only modelled review exit).
    /// Share's source is the engine's `gifURL` (not on σ); until that seam is threaded it
    /// renders as a cell button placeholder, keeping the row visually intact.
    private var actionRow: some View {
        HStack(spacing: GlobalLattice.gif(GlobalLattice.gutterCells)) {
            if let url = surface.gifURL {
                ShareLink(item: url) {
                    CellActionButton(icon: .share, title: "Share", prominent: true)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Share GIF")
            } else {
                // No committed GIF on disk yet — inert placeholder, same footprint.
                CellActionButton(icon: .share, title: "Share", prominent: true)
                    .accessibilityHidden(true)
            }

            Button { surface.step(.retake) } label: {
                CellActionButton(icon: .retake, title: "Retake")
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Retake")

            // Color Atlas entry (flag-gated): off ⇒ this branch is EmptyView and
            // the action row is byte-identical to the pre-Atlas screen.
            if settings.colorAtlasEnabled {
                Button {
                    atlas.loadIfNeeded(palettesPerFrame: surface.palettesPerFrame,
                                       indexCube: surface.indexCube)
                    atlasOpen = true
                } label: {
                    CellActionButton(icon: .grid3x3, title: "Atlas")
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Open color atlas")
            }
        }
    }

    // MARK: - Color Atlas curation sub-state (gated)

    /// The 16³ curation field: the scrubbable board (ToggleBin / WeightRegion /
    /// PinAnchor by tap mode) over the Compare candidate strip — all four Move
    /// types are playable, every play is logged + replay-folded. VStack-pinned
    /// chrome (no new movable widget identity ⇒ no MoveContract regen).
    private var atlasCurationField: some View {
        VStack(spacing: GlobalLattice.gif(GlobalLattice.gutterCells)) {
            CellText("COLOR ATLAS · 16³", rows: 11,
                     ink: Color(srgb8: SIMD3<UInt8>(235, 235, 235)))

            AtlasBoardView(atlas: atlas)
            AtlasGalleryView(atlas: atlas)

            CellText("moves \(atlas.log.entries.count) · compares \(atlas.log.compareCount)",
                     rows: 6, ink: Color(srgb8: SIMD3<UInt8>(140, 140, 140)))

            Button { atlasOpen = false } label: {
                CellActionButton(icon: .none, title: "Done", prominent: true)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close color atlas")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, GlobalLattice.gif(GlobalLattice.gutterCells))
    }
}
