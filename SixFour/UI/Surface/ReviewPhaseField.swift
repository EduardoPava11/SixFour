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
    /// The on-device training session (the visible flywheel) — view-local like
    /// `atlas`; its MPSGraph trainer lives on a confined worker actor and is
    /// stopped when the curation sub-state leaves the hierarchy.
    @State private var atlasTraining = AtlasTrainingSession()

    /// The built `.cube` awaiting the share sheet (set by the Export LUT button).
    @State private var lutShare: LUTShareItem?
    /// The produced ladder GIF awaiting the share sheet (set by the Save menu) — any
    /// rung (16³ working copy / 64³-B global), one gesture. SIXFOUR-WIDGETS Family 1.
    @State private var ladderShare: LadderShareItem?
    /// The rung currently being produced off-thread (nil = idle). Drives the Save
    /// button's progress label + disables it so the maximin collapse can't double-fire.
    @State private var exporting: LadderExport.Rung?
    /// Whether the cell-native rung picker is revealed (the Save button toggles it).
    /// The picker is cell buttons, NOT a system `Menu` — the screen IS the cell grid.
    @State private var rungPickerOpen = false

    // The global-palette CREATION control was a VStack FORM — rejected: the cell grid IS the
    // widget, operated by gesture. Rebuilt as gesture-grid tools; the byte-exact backend
    // (projectQ16(override:), Spec.LeafOverride, LadderExport, the Save ladder) is KEPT.

    // GROUP-PICK tool (the first gesture-grid LAB tool): browse the 64-frame burst as 16 RGBT
    // groups (a 4×4 macro-grid of 2×2 quads); TAP a group to include/exclude it from the
    // global palette. The live 16×16 preview + the export rebuild from only the picked groups
    // (Spec.GroupRGBT seam, byte-exact). docs/SIXFOUR-LAB-CHOICES.md.
    @State private var groupPickOpen = false
    @State private var selectedGroups = [Bool](repeating: true, count: GroupRGBT.numGroups)
    @State private var frameMeans: [SIMD3<UInt8>] = []     // 64 per-frame mean colours (the rail)
    @State private var groupGlobal: [SIMD3<UInt8>] = []    // live 256 global from picked groups
    @State private var computingGroups = false

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
            } else if groupPickOpen {
                // The GROUP-PICK gesture tool (browse 16 RGBT groups, tap to include/exclude).
                groupPickField
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
        .sheet(item: $ladderShare) { item in
            ActivityView(items: [item.url])
        }
        .sheet(item: $lutShare) { item in
            ActivityView(items: [item.url])
        }
    }

    /// The colours the LUT grades toward: ALL frames' palettes pooled into one cloud
    /// (a clip-wide profile), falling back to the single review palette.
    private var lutPalette: [SIMD3<UInt8>] {
        let pooled = surface.palettesPerFrame.flatMap { $0 }
        return pooled.isEmpty ? surface.palette : pooled
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

            // Save a GIF at any size — one gesture, the size is just which rung
            // (16³ working copy / 64³-B global). The picker is CELL BUTTONS, not a system
            // `Menu`: the screen IS the cell grid (GRID / total-pixelation law). Tapping
            // Save reveals a cell button per rung; the producer is deterministic
            // (`LadderExport`, collapsed via the chosen radix), then the share sheet.
            // SIXFOUR-WIDGETS Family 1 — the GIF is the product, getting one out is cheap.
            Button { rungPickerOpen.toggle() } label: {
                CellActionButton(icon: .share, title: exporting != nil ? "…" : "Save",
                                 fillWidth: false)
            }
            .buttonStyle(.plain)
            .disabled(exporting != nil)
            .accessibilityLabel("Save GIF at any size")

            if rungPickerOpen && exporting == nil {
                ForEach(LadderExport.Rung.allCases) { rung in
                    Button { rungPickerOpen = false; exportRung(rung) } label: {
                        CellActionButton(title: rung.shortTitle, fillWidth: false)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Save \(rung.title)")
                }
            }

            // Export the active LOOK as a .cube LUT for R3D (only when a grade is on;
            // `.off` would be an identity LUT). Builds via the deterministic Zig core
            // from the clip-wide palette, then shares the file.
            if settings.captureLook != .off {
                Button {
                    lutShare = LUTFile.makeShareItem(palette: lutPalette, look: settings.captureLook)
                } label: {
                    CellActionButton(icon: .share, title: "LUT")
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Export 3D LUT for R3D")
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

            // GROUP-PICK entry: browse the burst as 16 RGBT groups, pick which shape the palette.
            Button { openGroupPick() } label: {
                CellActionButton(icon: .grid3x3, title: "Groups")
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Pick RGBT groups for the palette")
        }
    }

    /// Produce a ladder rung OFF the main thread (the maximin collapse is ~seconds for
    /// 64³), then present the share sheet — so the Save tap never blocks the UI. Surface
    /// data is captured into value-type locals before the hop; `LadderShareItem` is
    /// `Sendable`, so it returns cleanly to the main actor.
    private func exportRung(_ rung: LadderExport.Rung, selectedGroups groups: [Bool] = []) {
        let palettes = surface.palettesPerFrame
        let cube = surface.indexCube
        let branching = settings.paletteBranching
        exporting = rung
        Task {
            let item = await Task.detached(priority: .userInitiated) {
                (try? LadderExport.makeURL(rung: rung, palettesPerFrame: palettes,
                                           indexCube: cube, branching: branching,
                                           selectedGroups: groups))
                    .map { LadderShareItem(url: $0) }
            }.value
            exporting = nil
            ladderShare = item
        }
    }

    // MARK: - Group-pick gesture tool (16 RGBT groups → the global palette)

    /// Open the group-pick tool: compute the 64 per-frame mean colours (the rail) once, then
    /// the live global preview from the current selection (all groups by default).
    private func openGroupPick() {
        groupPickOpen = true
        frameMeans = surface.palettesPerFrame.map { meanColour($0) }
        recomputeGroupGlobal()
    }

    /// Re-derive the live 256-colour global from ONLY the selected groups, off the main
    /// thread (the maximin is the ~seconds step). The grid IS the feedback: the preview
    /// repopulates with colours from the picked groups.
    private func recomputeGroupGlobal() {
        let palettes = surface.palettesPerFrame
        let sel = selectedGroups
        computingGroups = true
        Task {
            let leaves = await Task.detached(priority: .userInitiated) {
                LadderExport.flatGlobalLeaves(palettesPerFrame: palettes, selectedGroups: sel)
            }.value
            groupGlobal = LadderGIF.paletteToSRGB8(leaves)
            computingGroups = false
        }
    }

    private func toggleGroup(_ g: Int) {
        guard g >= 0 && g < selectedGroups.count else { return }
        selectedGroups[g].toggle()
        recomputeGroupGlobal()
    }

    /// The 4×4 macro-grid of 16 groups, each a 2×2 quad of its R/G/B/T frame means. TAP a
    /// group to include/exclude it; deselected groups recede by an OPAQUE darken (Law #2).
    private var groupGrid: some View {
        let cell = GlobalLattice.gif(6)   // 24 pt/cell ⇒ each 2×2 group = 48 pt ≥ 44 pt floor
        let means = frameMeans
        let sel = selectedGroups
        return CellSprite(cols: 8, rows: 8, cellPt: cell) { c, r in
            let g = (r / 2) * 4 + (c / 2)            // group index 0..15
            let role = (r % 2) * 2 + (c % 2)         // 0=R 1=G 2=B 3=T within the group
            let f = g * 4 + role
            guard f < means.count else { return SFTheme.ledGhost }
            return (g < sel.count && sel[g]) ? means[f] : Self.darkenCell(means[f])
        }
        .contentShape(Rectangle())
        .gesture(DragGesture(minimumDistance: 0).onEnded { v in
            let col = max(0, min(7, Int(v.location.x / cell)))
            let row = max(0, min(7, Int(v.location.y / cell)))
            toggleGroup((row / 2) * 4 + (col / 2))
        })
        .accessibilityLabel("16 RGBT groups; tap to include or exclude")
    }

    /// The group-pick field: the 16-group macro-grid + the live global palette it builds.
    private var groupPickField: some View {
        let picked = selectedGroups.filter { $0 }.count
        return VStack(spacing: GlobalLattice.gif(GlobalLattice.gutterCells)) {
            CellText("PICK GROUPS · \(picked)/\(GroupRGBT.numGroups)\(computingGroups ? " ·…" : "")",
                     rows: 11, ink: Color(srgb8: SIMD3<UInt8>(235, 235, 235)))

            groupGrid

            CellText("global palette ↓ (built from the picked groups)", rows: 9,
                     ink: Color(srgb8: SIMD3<UInt8>(140, 140, 140)))
            CellSprite(cols: 16, rows: 16, cellPt: GlobalLattice.gifPx) { c, r in
                let i = r * 16 + c
                return i < groupGlobal.count ? groupGlobal[i] : nil
            }
            .accessibilityLabel("Live global palette from the picked groups")

            HStack(spacing: GlobalLattice.gif(GlobalLattice.gutterCells)) {
                Button { exportRung(.global64, selectedGroups: selectedGroups) } label: {
                    CellActionButton(icon: .share, title: "64³", fillWidth: false)
                }
                .buttonStyle(.plain).disabled(exporting != nil).accessibilityLabel("Export 64³ from picked groups")
                Button { exportRung(.working16, selectedGroups: selectedGroups) } label: {
                    CellActionButton(icon: .share, title: "16³", fillWidth: false)
                }
                .buttonStyle(.plain).disabled(exporting != nil).accessibilityLabel("Export 16³ from picked groups")
                Button { groupPickOpen = false } label: {
                    CellActionButton(title: "Done", prominent: true)
                }
                .buttonStyle(.plain).accessibilityLabel("Close group pick")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, GlobalLattice.gif(GlobalLattice.gutterCells))
    }

    /// Mean sRGB8 colour of a frame's palette (the group rail's per-frame swatch).
    private func meanColour(_ pal: [SIMD3<UInt8>]) -> SIMD3<UInt8> {
        guard !pal.isEmpty else { return SFTheme.ledGhost }
        var r = 0, g = 0, b = 0
        for c in pal { r += Int(c.x); g += Int(c.y); b += Int(c.z) }
        let n = pal.count
        return SIMD3<UInt8>(UInt8(r / n), UInt8(g / n), UInt8(b / n))
    }

    /// Recede an unpicked group cell by an OPAQUE 35% darken — never alpha (GRID Law #2).
    private static func darkenCell(_ c: SIMD3<UInt8>) -> SIMD3<UInt8> {
        SIMD3<UInt8>(UInt8(Int(c.x) * 35 / 100),
                     UInt8(Int(c.y) * 35 / 100),
                     UInt8(Int(c.z) * 35 / 100))
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

            // The on-device training instrument (the visible flywheel): loss
            // sparkline + V(A)/V(B) + train/pause. Inert-labeled on simulator.
            AtlasTrainingField(atlas: atlas, session: atlasTraining)

            CellText("moves \(atlas.log.entries.count) · compares \(atlas.log.compareCount)",
                     rows: 6, ink: Color(srgb8: SIMD3<UInt8>(140, 140, 140)))

            Button {
                atlasTraining.stop()
                atlasOpen = false
            } label: {
                CellActionButton(icon: .none, title: "Done", prominent: true)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close color atlas")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, GlobalLattice.gif(GlobalLattice.gutterCells))
        .onDisappear { atlasTraining.stop() }   // leaving review halts the loop
    }
}
