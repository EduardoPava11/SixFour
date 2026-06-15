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
    /// Act II motion outline: when on, `paletteStrip` recedes the high-displacement ("motion")
    /// quartet slots so the low-displacement "core" colours stand out (a cell-brightness split,
    /// no strokes/text). Pure projection of `QuartetDelta`; default off ⇒ strip is byte-identical.
    @State private var motionOutlineOn = false
    /// The live motion-threshold override (nil = use the median default). The Review
    /// motion-threshold `CellSlider` writes here; `motionCoreSet` reads it to re-threshold
    /// the core/motion split live (the paletteStrip re-renders every tick).
    @State private var motionThreshold: Double? = nil

    /// CUT-LEVER tool: collapse the global palette to a SHALLOWER tree depth and PREVIEW it.
    /// `cutLeverOn` reveals the toggle's slider + 16×16 preview; `cutDepth` is the depth the
    /// slider cuts to (nil = full depth); `cutGlobal` is the live 256 sRGB8 painted from the
    /// cut groups. This is PREVIEW-ONLY — it does NOT touch the Save/export path. At full depth
    /// the cut yields the same 256-colour SET as the shipped global palette, but NOT index-for-
    /// index identical: it reads the no-mask `flatGlobalLeaves` (all 64 frames, vs the shipped
    /// `groupGlobal` which honours `selectedGroups`) and `SplitTree.build` median-sorts the
    /// leaves, permuting vs the shipped maximin order. Order/mask don't matter for a swatch.
    /// (No `Spec.CollapseLever`: a Swift clamp on `PaletteBranching.depth` over the proven
    /// `SplitTree.collapse`/`descendants`.)
    @State private var cutLeverOn = false
    @State private var cutDepth: Int? = nil
    @State private var cutGlobal: [SIMD3<UInt8>] = []
    /// Cached flat maximin leaves for the cut tool — the ~seconds maximin runs ONCE on
    /// open; each drag re-projects only `SplitTree.build` + `collapse` (cheap), so the
    /// frame-locked haptic never lags behind the maximin.
    @State private var cutFlatLeaves: [OKLabQ16] = []

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
                    .movable(.field64, settings: settings, surface: surface, clock: clock)
                    .place(region(for: .field64, at: placement))

                paletteStrip
                    .movable(.palette16, settings: settings, surface: surface, clock: clock)
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
        // Act II motion outline: recede high-displacement ("motion") slots in ORIGINAL slot order,
        // BEFORE the grid permutation, so the recede carries through `surfaceColors` cell-for-cell
        // (coreColors returns ORIGINAL-order indices; surfaceColors permutes to grid-rank order).
        // Off ⇒ `shown == padded`, so the strip is byte-identical to the plain per-frame palette.
        let core = motionOutlineOn ? motionCoreSet : []
        let shown: [SIMD3<UInt8>] = motionOutlineOn
            ? padded.enumerated().map { core.contains($0.offset) ? $0.element : Self.darkenCell($0.element) }
            : padded
        let ordered = GridScript.capture(side: 16).surfaceColors(palette: shown)
        return CellSprite(cols: 16, rows: 16, cellPt: GlobalLattice.gifPx) { c, r in
            let rank = r * 16 + c
            return rank < ordered.count ? ordered[rank] : ghost
        }
        .frame(width: paletteEdge, height: paletteEdge)
        .accessibilityLabel(motionOutlineOn ? "Per-frame palette, core colours outlined" : "Per-frame palette, 256 colours")
    }

    /// The Act II "core" slot indices for the FIXED quartet `[0,21,42,63]` — low-displacement
    /// (structural) colours, per `QuartetDelta` (the motion residual the global collapse discards).
    /// Cursor-INDEPENDENT: the quartet is built once from those 4 frames; `paletteStrip` then shows
    /// whichever colour each core slot holds at the current cursor. Empty (no recede) when fewer than
    /// 4 frames exist. Only evaluated while `motionOutlineOn`.
    private var motionCoreSet: Set<Int> {
        let slots = motionSlots
        guard !slots.isEmpty else { return [] }
        // The slider value (if any) OVERRIDES the median default, so the overlay
        // re-thresholds live as the user drags (paletteStrip reads this every render).
        let thr = motionThreshold ?? QuartetDelta.medianDisplacementThreshold(slots)
        return Set(QuartetDelta.coreColors(thr, slots))
    }

    /// The 256 OKLab quartet trajectories for the FIXED `[0,21,42,63]` frames — factored
    /// out of `motionCoreSet` so the threshold slider's range can read the slot
    /// displacements without recomputing the quartet. Computed (never stored) to stay
    /// in sync with `surface.palettesPerFrame`. Empty when fewer than 4 frames exist.
    private var motionSlots: [[SIMD3<Double>]] {
        let idx = [0, 21, 42, 63].filter { $0 < surface.palettesPerFrame.count }
        guard idx.count == 4 else { return [] }
        let fourFrames: [[SIMD3<Double>]] = idx.map { f in
            let pal = surface.palettesPerFrame[f]
            return (0 ..< 256).map { i -> SIMD3<Double> in
                let c = i < pal.count ? pal[i] : SIMD3<UInt8>(20, 20, 24)
                return SIMD3<Double>(ColorScience.srgb8ToOKLab(c.x, c.y, c.z).simd)
            }
        }
        return QuartetDelta.toSlots(fourFrames)
    }

    /// The threshold slider's value range: from the smallest to the largest slot
    /// displacement in the current quartet (so the slider spans exactly the meaningful
    /// cut points). Degenerate-safe (`0...1` fallback when no quartet / a flat spread).
    private var motionThresholdRange: ClosedRange<Double> {
        let ds = motionSlots.map(QuartetDelta.slotDisplacement)
        let lo = ds.min() ?? 0
        let hi = ds.max() ?? 1
        return lo < hi ? lo...hi : 0...1
    }

    /// The slider step — the range split into `cols` cells (the M of the M×11 slider), so
    /// one cell = one detent. Keeps `CellSlider.set`'s quantisation aligned with the cell
    /// columns the detent flush counts.
    private var motionThresholdStep: Double {
        let r = motionThresholdRange
        let span = r.upperBound - r.lowerBound
        let cells = max(1, GlobalLattice.shutterCells - 1)
        return span > 0 ? span / Double(cells) : 1
    }

    /// A non-optional bridge for the `CellSlider`: reads the live threshold (falling back
    /// to the median when unset), writes back into the `motionThreshold` override.
    private var motionThresholdBinding: Binding<Double> {
        Binding(
            get: { motionThreshold ?? QuartetDelta.medianDisplacementThreshold(motionSlots) },
            set: { motionThreshold = $0 }
        )
    }

    /// The knob's current CELL column — the same `frac * (cols-1)` rounding `CellSlider`
    /// uses, so the frame-locked flush counts exactly the cells the knob has crossed.
    private var thresholdKnobCell: Int {
        let r = motionThresholdRange
        let span = max(r.upperBound - r.lowerBound, 0.0001)
        let value = motionThreshold ?? QuartetDelta.medianDisplacementThreshold(motionSlots)
        let frac = (value - r.lowerBound) / span
        let cols = GlobalLattice.shutterCells
        return max(0, min(cols - 1, Int((frac * Double(cols - 1)).rounded())))
    }

    // MARK: - Cut-lever helpers

    /// The branching the cut tool reads (the shared settings choice — the same tree the
    /// Save ladder + structure view use). The cut never re-roots the tree; it only chooses
    /// how deep to merge along the radix the user already picked.
    private var cutBranching: PaletteBranching { settings.paletteBranching }

    /// The cut slider's range: `0 … depth`. `depth` (the upper bound) = no levels merged =
    /// the full palette (same colour set as shipped); lower values merge more levels (fewer,
    /// broader colours). One cell per integer depth ⇒ `cols = depth + 1`.
    private var cutRange: ClosedRange<Double> { 0 ... Double(cutBranching.depth) }

    /// A non-optional bridge for the cut `CellSlider`: reads `cutDepth` (full depth when
    /// unset ⇒ the full colour set), writes back the clamped integer depth + recomputes the
    /// cut preview off the main thread (the maximin is cached, so this is the cheap path).
    private var cutBinding: Binding<Double> {
        Binding(
            get: { Double(cutDepth ?? cutBranching.depth) },
            set: { raw in
                let d = max(0, min(cutBranching.depth, Int(raw.rounded())))
                cutDepth = d
                recomputeCutGlobal()
            }
        )
    }

    /// The cut knob's current CELL column — the SAME `frac * (cols-1)` rounding `CellSlider`
    /// uses (here `cols = depth + 1`), so the frame-locked flush counts exactly the depth
    /// cells the knob has crossed.
    private var cutKnobCell: Int {
        let cols = cutBranching.depth + 1
        let span = max(Double(cutBranching.depth), 0.0001)
        let value = Double(cutDepth ?? cutBranching.depth)
        let frac = value / span
        return max(0, min(cols - 1, Int((frac * Double(cols - 1)).rounded())))
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

            // Act II motion outline — recolours `paletteStrip` to separate the structural
            // "core" colours from the high-motion ones (a cell-brightness split). Immovable
            // chrome: it modulates an existing widget's paint, it is NOT a movable widget.
            Button {
                motionOutlineOn.toggle()
                if motionOutlineOn, motionThreshold == nil {
                    // Seed the slider at the current overlay state (the median cut). The
                    // `.cellDetent` anchors itself on its first tick, so no re-baseline is
                    // needed — re-opening never bursts ticks.
                    motionThreshold = QuartetDelta.medianDisplacementThreshold(motionSlots)
                }
            } label: {
                CellActionButton(icon: .grid3x3, title: "Motion")
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Outline motion vs core colours")

            // The motion-threshold slider — reuses the M×11 `CellSlider` (one lit knob
            // cell). Shown only while the overlay is on; dragging re-thresholds the
            // core/motion split live. ONE frame-locked `Haptics.play(1)` (cellTick) per
            // crossed cell, flushed on the 20 fps clock tick (≤1 Taptic/frame).
            if motionOutlineOn {
                CellSlider(value: motionThresholdBinding,
                           range: motionThresholdRange,
                           step: motionThresholdStep,
                           cols: GlobalLattice.shutterCells)
                    // The SAME frame-locked detent as the movable widgets (one mechanism):
                    // ≤1 cellTick per 20 fps frame as the knob crosses cells.
                    .cellDetent(tick: clock.tick, every: 1, position: { (col: thresholdKnobCell, row: 0) })
                    .accessibilityLabel("Motion threshold")
            }

            // CUT-LEVER — collapse the global palette to a shallower tree depth and PREVIEW
            // it (preview-only; does NOT change Save/export). Same shape as the Motion block
            // (a toggle + a frame-locked cell slider + an inline preview), dogfooding the SAME
            // `.cellDetent` mechanism. Off ⇒ this branch is inert and the row is byte-identical;
            // full depth ⇒ the preview shows the full colour set (same set as shipped, swatch only).
            Button {
                if cutLeverOn {
                    cutLeverOn = false
                } else {
                    openCutLever()
                }
            } label: {
                CellActionButton(icon: .grid3x3, title: "Cut")
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Collapse the global palette to a shallower depth")

            if cutLeverOn {
                // The radix the cut walks (16²/4⁴/2⁸) — the SAME shared settings choice the
                // Save ladder + structure view use. Changing it re-seeds the cut to full
                // depth and recomputes (the new radix has a new depth ceiling). Kept in the
                // ACTION row (chrome), never in the cell-field preview (cell-field law).
                BranchingSelector(selection: Binding(
                    get: { settings.paletteBranching },
                    set: { settings.paletteBranching = $0; cutDepth = $0.depth; recomputeCutGlobal() }
                ))
                .accessibilityLabel("Cut radix")

                CellSlider(value: cutBinding,
                           range: cutRange,
                           step: 1,
                           cols: cutBranching.depth + 1)
                    // The SAME frame-locked detent as the movable widgets + the motion
                    // slider: ≤1 cellTick per 20 fps frame as the knob crosses depth cells.
                    .cellDetent(tick: clock.tick, every: 1, position: { (col: cutKnobCell, row: 0) })
                    .accessibilityLabel("Cut depth")

                // The live cut preview — a flat 16×16 cell palette from `cutGlobal` (copy of
                // the group-pick preview 458-461), cells only.
                CellSprite(cols: 16, rows: 16, cellPt: GlobalLattice.gifPx) { c, r in
                    let i = r * 16 + c
                    return i < cutGlobal.count ? cutGlobal[i] : nil
                }
                .accessibilityLabel("Live cut palette preview")
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

    // MARK: - Cut-lever tool (collapse the global palette to a shallower tree depth)

    /// Open the cut tool: run the ~seconds maximin ONCE to cache the flat global leaves,
    /// seed the slider at full depth (the full colour set), then paint the first preview.
    /// Every later drag re-projects only `SplitTree.build` + `collapse`.
    private func openCutLever() {
        cutLeverOn = true
        cutDepth = cutBranching.depth
        let palettes = surface.palettesPerFrame
        Task {
            let leaves = await Task.detached(priority: .userInitiated) {
                LadderExport.flatGlobalLeaves(palettesPerFrame: palettes)
            }.value
            cutFlatLeaves = leaves
            recomputeCutGlobal()
        }
    }

    /// Re-derive the live 256-colour cut preview from the CACHED flat leaves. The cut merges
    /// `max(0, depth - k)` view levels (`k = cutDepth`), i.e. `levelsToMerge` BINARY levels
    /// (× `collapseK`), via the proven `SplitTree.collapse`; each cut group is painted with
    /// its FIRST leaf's colour and expanded back to 256 (one entry per original leaf), so the
    /// preview is a flat 256-cell palette. `k == depth` ⇒ zero levels merged ⇒ the full colour
    /// set (preview only; index order/mask may differ from the shipped table — see the state
    /// doc). Off the main thread (tree+collapse is cheap but not free).
    private func recomputeCutGlobal() {
        let leaves = cutFlatLeaves
        let k = cutDepth ?? cutBranching.depth
        let branching = cutBranching
        Task {
            let painted = await Task.detached(priority: .userInitiated) { () -> [SIMD3<UInt8>] in
                guard !leaves.isEmpty else { return [] }
                // Flat leaves → IndexedColor (OKLab for the split, sRGB8 for the fill).
                let ics: [IndexedColor] = leaves.enumerated().map { i, leaf in
                    let f = SIMD3<Float>(Float(leaf.x), Float(leaf.y), Float(leaf.z)) / 65536
                    return IndexedColor(index: i,
                                        oklab: f,
                                        srgb: ColorScience.okLabToSRGB8(OKLab(f)))
                }
                let tree = SplitTree.build(ics)
                // The cut keeps `k` VIEW levels of detail (× collapseK BINARY levels each),
                // merging everything below. `SplitTree.descendants(at:)` yields the cut
                // GROUPS directly: the subtrees rooted at that binary depth, canonical
                // in-order. `k == depth` ⇒ binary depth `depth·collapseK == 8` ⇒ 256
                // singleton groups ⇒ the full colour set; `k == 0` ⇒ one group ⇒ a single
                // colour. (`depth − k` is the count of merged levels.)
                let keepBinaryLevels = max(0, min(branching.depth, k)) * branching.collapseK
                let groups = tree.descendants(at: keepBinaryLevels)
                // Paint each cut group with its FIRST leaf; expand back to one entry per
                // leaf so the preview stays a flat 256-cell palette (in-order alignment).
                var out = [SIMD3<UInt8>](); out.reserveCapacity(ics.count)
                for g in groups {
                    let groupLeaves = g.leaves
                    let first = groupLeaves.first?.srgb ?? SFTheme.ledGhost
                    for _ in groupLeaves { out.append(first) }
                }
                return out
            }.value
            cutGlobal = painted
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
