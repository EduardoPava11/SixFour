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

    /// PALETTE creation control (gated, default OFF) — the `.review` sub-state where the
    /// user chooses the global-palette genome (16²/4⁴/2⁸ face) and reads it in honest LAB
    /// rank, with a live 16×16 preview that EQUALS the exported GIFB (same `projectQ16` on
    /// the same leaves). docs/SIXFOUR-GLOBAL-PALETTE-CONTROL.md (SIXFOUR-WIDGETS Family 2).
    @State private var paletteOpen = false
    /// The branching-INDEPENDENT flat global leaves (the ~seconds maximin), computed once
    /// off-thread on entry and re-projected cheaply per face — empty until cached.
    @State private var globalLeaves: [OKLabQ16] = []
    /// The brushed genome leaf (nil = none). Lights that leaf full + recedes the rest by an
    /// OPAQUE darken (GRID Law #2); on the 2⁸ face it also lights the σ-partner (slot ^ 1).
    @State private var paletteBrush: Int?

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
            } else if paletteOpen && settings.paletteControlEnabled {
                // The PALETTE creation control sub-state (flag-gated; mutually exclusive
                // with normal review, leaves the hierarchy + resets on `.retake`).
                paletteControlField
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

            // PALETTE creation control entry (flag-gated): choose the global-palette
            // genome face + read it in LAB rank, then export at that genome.
            if settings.paletteControlEnabled {
                Button { openPaletteControl() } label: {
                    CellActionButton(icon: .grid3x3, title: "Palette")
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Open global palette control")
            }
        }
    }

    /// Produce a ladder rung OFF the main thread (the maximin collapse is ~seconds for
    /// 64³), then present the share sheet — so the Save tap never blocks the UI. Surface
    /// data is captured into value-type locals before the hop; `LadderShareItem` is
    /// `Sendable`, so it returns cleanly to the main actor.
    private func exportRung(_ rung: LadderExport.Rung) {
        let palettes = surface.palettesPerFrame
        let cube = surface.indexCube
        let branching = settings.paletteBranching
        exporting = rung
        Task {
            let item = await Task.detached(priority: .userInitiated) {
                (try? LadderExport.makeURL(rung: rung, palettesPerFrame: palettes,
                                           indexCube: cube, branching: branching))
                    .map { LadderShareItem(url: $0) }
            }.value
            exporting = nil
            ladderShare = item
        }
    }

    /// Compute the flat global leaves once OFF the main thread (the maximin is the
    /// ~seconds step), then open the PALETTE control; cheap re-projection per face after.
    private func openPaletteControl() {
        paletteOpen = true
        guard globalLeaves.isEmpty else { return }
        let palettes = surface.palettesPerFrame
        Task {
            let leaves = await Task.detached(priority: .userInitiated) {
                LadderExport.flatGlobalLeaves(palettesPerFrame: palettes)
            }.value
            globalLeaves = leaves
        }
    }

    /// Cycle a `GridAxis` to its next case — six axis segments do not fit one row, so we
    /// single-tap cycle and name the active axis in the readout (honest, budget-fitting).
    private func nextAxis(_ a: GridAxis) -> GridAxis {
        let all = GridAxis.allCases
        return all[((all.firstIndex(of: a) ?? 0) + 1) % all.count]
    }

    // MARK: - PALETTE creation control sub-state (gated)

    /// The user's control of global-palette CREATION (SIXFOUR-WIDGETS Family 2): a FACE
    /// selector (16²/4⁴/2⁸) sets the genome that reaches the GIFB bytes; the 16×16 surface
    /// shows it live in honest LAB rank; export ships exactly that genome. Fully
    /// cell-rendered (CellSelector/CellSprite/CellActionButton/CellText) — lint-grid clean.
    private var paletteControlField: some View {
        VStack(spacing: GlobalLattice.gif(GlobalLattice.gutterCells)) {
            CellText("GLOBAL PALETTE · \(settings.paletteBranching.label)", rows: 11,
                     ink: Color(srgb8: SIMD3<UInt8>(235, 235, 235)))

            // FACE — the genome selector. Reaches the collapse OUTPUT (preview ≡ ship).
            CellSelector(options: PaletteBranching.allCases.map { (value: $0, label: $0.label) },
                         selection: $settings.paletteBranching)

            paletteSurface

            // X/Y LAB axes (16² SEE face only) — honest rank, single-tap cycle.
            if settings.paletteBranching == .b16 {
                HStack(spacing: GlobalLattice.gif(GlobalLattice.gutterCells)) {
                    Button { settings.gridAxisX = nextAxis(settings.gridAxisX) } label: {
                        CellActionButton(title: "X \(settings.gridAxisX.rawValue)", fillWidth: false)
                    }
                    .buttonStyle(.plain).accessibilityLabel("Cycle X axis")
                    Button { settings.gridAxisY = nextAxis(settings.gridAxisY) } label: {
                        CellActionButton(title: "Y \(settings.gridAxisY.rawValue)", fillWidth: false)
                    }
                    .buttonStyle(.plain).accessibilityLabel("Cycle Y axis")
                }
            }

            CellText(paletteReadout, rows: 9, ink: Color(srgb8: SIMD3<UInt8>(140, 140, 140)))

            // Export at THIS genome — the producer already reads settings.paletteBranching.
            HStack(spacing: GlobalLattice.gif(GlobalLattice.gutterCells)) {
                Button { exportRung(.working16) } label: {
                    CellActionButton(icon: .share, title: "16³", fillWidth: false)
                }
                .buttonStyle(.plain).disabled(exporting != nil).accessibilityLabel("Export 16³")
                Button { exportRung(.global64) } label: {
                    CellActionButton(icon: .share, title: "64³", fillWidth: false)
                }
                .buttonStyle(.plain).disabled(exporting != nil).accessibilityLabel("Export 64³")
                Button { paletteOpen = false } label: {
                    CellActionButton(title: "Done", prominent: true)
                }
                .buttonStyle(.plain).accessibilityLabel("Close palette control")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, GlobalLattice.gif(GlobalLattice.gutterCells))
    }

    /// The ONE 16×16 leaf surface — the projected genome, laid by FACE: 16² in honest LAB
    /// rank (GridLayout), 4⁴/2⁸ in genome (leaf) order. Painted from the cached flat leaves
    /// re-projected by `projectQ16`, so it EQUALS the exported GIFB. Ghost until cached.
    private var paletteSurface: some View {
        let proj = globalLeaves.isEmpty
            ? []
            : BranchedPalette.projectQ16(globalLeaves, branching: settings.paletteBranching)
        let srgb = proj.isEmpty ? [] : LadderGIF.paletteToSRGB8(proj)
        let grid = paletteGrid(proj, srgb: srgb)
        let brush = paletteBrush
        let isB2 = settings.paletteBranching == .b2
        return CellSprite(cols: 16, rows: 16, cellPt: GlobalLattice.gifPx) { c, r in
            guard !grid.isEmpty else { return nil }   // ghost-fill until the maximin lands
            let slot = grid[r][c]
            guard slot < srgb.count else { return nil }
            let color = srgb[slot]
            guard let b = brush else { return color }            // no brush → every cell full
            let lit = slot == b || (isB2 && slot == (b ^ 1))     // σ-partner = slot ^ 1
            return lit ? color : Self.darken(color)              // others recede (opaque, Law #2)
        }
        .contentShape(Rectangle())
        .gesture(DragGesture(minimumDistance: 0).onEnded { v in
            guard !grid.isEmpty else { return }
            let cell = GlobalLattice.gifPx
            let col = max(0, min(15, Int(v.location.x / cell)))
            let row = max(0, min(15, Int(v.location.y / cell)))
            let hit = grid[row][col]
            paletteBrush = (paletteBrush == hit) ? nil : hit     // tap again to release
        })
        .accessibilityLabel("Global palette, \(settings.paletteBranching.label)")
    }

    /// Recede an unbrushed cell by an OPAQUE 35% darken — never alpha (GRID Law #2,
    /// mirroring `PaletteGridView`'s darkenStep).
    private static func darken(_ c: SIMD3<UInt8>) -> SIMD3<UInt8> {
        SIMD3<UInt8>(UInt8(Int(c.x) * 35 / 100),
                     UInt8(Int(c.y) * 35 / 100),
                     UInt8(Int(c.z) * 35 / 100))
    }

    /// The 16×16 slot layout: 16² → GridLayout LAB rank (assignable X/Y); 4⁴/2⁸ → genome
    /// (leaf) order. (Per-face Quad4/σ-pair adjacency re-layout is the next refinement.)
    private func paletteGrid(_ proj: [OKLabQ16], srgb: [SIMD3<UInt8>]) -> [[Int]] {
        guard proj.count == 256, srgb.count == 256 else { return [] }
        switch settings.paletteBranching {
        case .b16:
            // SEE: honest L/a/b rank on the assignable X/Y axes.
            let colors = proj.enumerated().map { i, q in
                IndexedColor(index: i,
                             oklab: SIMD3<Float>(Float(q.x), Float(q.y), Float(q.z)) / 65536,
                             srgb: srgb[i])
            }
            let g = GridLayout.layout(x: settings.gridAxisX, y: settings.gridAxisY, colors: colors)
            return g.isEmpty ? rowMajorGrid : g
        case .b4:  return quadtreeGrid   // CONTROL: opponent-quadrant nesting
        case .b2:  return rowMajorGrid    // LEARN: row-major already adjacents σ-pairs (2i,2i+1)
        }
    }

    private var rowMajorGrid: [[Int]] {
        (0 ..< 16).map { r in (0 ..< 16).map { c in r * 16 + c } }
    }

    /// 4⁴ quadtree layout: each base-4 digit q → a 2×2 quadrant (row-bit `q>>1`, col-bit
    /// `q&1`), nested 4 levels = 16×16, so every opponent-quadrant node's four children
    /// occupy one 2×2 block (the Quad4 structure, made spatial).
    private var quadtreeGrid: [[Int]] {
        var grid = Array(repeating: Array(repeating: 0, count: 16), count: 16)
        for i in 0 ..< 256 {
            var row = 0, col = 0
            for k in 0 ..< 4 {
                let q = (i >> ((3 - k) * 2)) & 3   // k-th base-4 digit, most significant first
                row = (row << 1) | (q >> 1)
                col = (col << 1) | (q & 1)
            }
            grid[row][col] = i
        }
        return grid
    }

    private var paletteReadout: String {
        if globalLeaves.isEmpty { return "collapsing…" }
        let face: String
        switch settings.paletteBranching {
        case .b16: face = "X \(settings.gridAxisX.rawValue) · Y \(settings.gridAxisY.rawValue)"
        case .b4:  face = "4⁴ opponent quadrants"
        case .b2:  face = "2⁸ σ-pair genome"
        }
        if let b = paletteBrush {
            let grabbed = settings.paletteBranching == .b2 ? "σ-pair \(b / 2)" : "leaf \(b)"
            return "\(face) · grabbed \(grabbed)"
        }
        return "256 leaves · \(face)"
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
