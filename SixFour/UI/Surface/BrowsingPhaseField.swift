import SwiftUI
import simd

/// Π·browsing — the cell-field renderer for the `.browsing` phase (Act III) of the ONE
/// surface. The burst has finished; the user scrubs the 64-frame burst and picks 4 anchor
/// frames before the render fires. It is a pure projection of σ: it reads `palettesPerFrame`
/// / `indexCube` / `cursor` / `picks` and emits cells, mutating only out-of-band σ
/// (`togglePick` / `scrubCursor`) plus the ONE FSM edge `.picked4` (Continue).
///
/// Built entirely from the `ReviewPhaseField` vocabulary (CellSprite / CellSlider /
/// CellActionButton — no Text/glass/SF-Symbol):
///   1. Field64 scrubber — the same `gifaHero` CellSprite, painting the frame at `cursor`;
///      a TAP toggles that frame in/out of the 4-pick set.
///   2. Scrub rail — a 64-column `CellSlider` over the cursor (one cell = one frame = one
///      haptic via `.cellDetent`), finger-driven (κ does NOT auto-advance in `.browsing`).
///   3. 4-pick filmstrip — four 16×16 thumbnails over `surface.picks` (empty = ghost ink);
///      tapping a thumbnail jumps the cursor to it / removes it.
///   4. Inert Palette16 — the per-frame palette of the cursor frame (hit-testing off).
///   5. Pooled swatch — the 4 picks' pooled palettes (the diversity dock), inert.
///   6. Continue gate — fires `.picked4` ONLY when exactly 4 are chosen; the 4 ordered
///      picks become the render INPUT (the 4⁴ quad anchors; USER DECISION 2026-06-08).
///
/// Cells only. Tier-2 pure: SwiftUI + simd.
struct BrowsingPhaseField: View {
    /// σ — read for data; written via `togglePick` / `scrubCursor` (out-of-band) and the
    /// `.picked4` event (Continue).
    @Bindable var surface: Surface
    /// κ — drives the frame-locked detent flush on the scrub rail (the cursor itself is
    /// finger-driven here, not auto-advanced).
    let clock: SurfaceClock
    /// The ONE shared widget layout + persistence (the same three global positions).
    @Bindable var settings: AppSettings

    /// The current shared placement — the SAME three positions live/review read.
    private var placement: [ColorIdentity: (col: Int, row: Int)] { settings.widgetPlacement }

    /// The hero content edge — 64 cells × 4 pt = 256 pt (same as preview/review).
    private let gifEdge = GlobalLattice.gif(GlobalLattice.previewCells)
    /// The palette edge — 16 cells × 4 pt = 64 pt.
    private let paletteEdge = GlobalLattice.gif(GlobalLattice.shutterCells)

    var body: some View {
        ZStack(alignment: .topLeading) {
            if surface.palettesPerFrame.isEmpty && surface.indexCube.isEmpty {
                // Nothing to browse yet (the burst hasn't folded into σ) — the field
                // ground shows through; the chrome row still renders below.
                Color.clear
            } else {
                // The scrubber hero — placed at the SAME global Field64 position the live /
                // review screens use (continuous instrument). The widget is NOT movable in
                // browsing (`enabled: false` suppresses the lift gesture); a clean TAP
                // toggles the current frame's pick (a separate `.onTapGesture`, since the
                // disabled movable modifier drops its `onTap`). Tap and the rail-drag scrub
                // are timing-disjoint — the same seam the live shutter uses.
                field64Scrubber
                    .contentShape(Rectangle())
                    .onTapGesture { surface.togglePick(surface.cursor) }
                    .movable(.field64, settings: settings, surface: surface, clock: clock,
                             enabled: false)
                    .place(region(for: .field64, at: placement))

                // The inert per-frame palette of the cursor frame.
                paletteStrip
                    .allowsHitTesting(false)
                    .place(region(for: .palette16, at: placement))
            }

            // Immovable bottom chrome (NOT a ColorWidget): the scrub rail, the 4-pick
            // filmstrip, the pooled swatch, and the Continue gate — pinned to the bottom.
            chromeColumn
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                .padding(.horizontal, GlobalLattice.gif(GlobalLattice.gutterCells))
                .padding(.bottom, GlobalLattice.gif(GlobalLattice.gutterCells))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .ignoresSafeArea()
    }

    // MARK: - (1) Field64 scrubber

    /// The 64×64 cell hero painting the burst frame at `surface.cursor`, through the TRUE
    /// per-frame palette (`Surface.gifCell`) — the SAME instrument the live/review heroes
    /// use. `nil` cells fall through to the live ground (no black backing).
    private var field64Scrubber: some View {
        CellSprite(cols: GlobalLattice.previewCells,
                   rows: GlobalLattice.previewCells,
                   cellPt: GlobalLattice.gifPx) { c, r in
            surface.gifCell(c, r, surface.cursor)
        }
        .frame(width: gifEdge, height: gifEdge)
    }

    // MARK: - (4) Inert per-frame palette

    /// The 256 colours of the CURRENT frame as a 16×16 grid (the GIF's first abstraction).
    /// Inert in browsing — pure projection of σ at `cursor`.
    private var paletteStrip: some View {
        let ghost = SFTheme.ledGhost
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

    // MARK: - Bottom chrome column

    /// The bottom controls: scrub rail · 4-pick filmstrip · pooled swatch · Continue.
    private var chromeColumn: some View {
        VStack(spacing: GlobalLattice.gif(GlobalLattice.gutterCells)) {
            scrubRail
            filmstrip
            pooledSwatch
            continueGate
        }
    }

    // MARK: - (2) Scrub rail

    /// A 64-column `CellSlider` driving `surface.cursor` directly (the finger-driven
    /// scrub) — one cell = one frame. The frame-locked `.cellDetent` fires ≤1 cellTick per
    /// 20 fps frame as the knob crosses frames (the same detent the Review sliders use).
    private var scrubRail: some View {
        CellSlider(value: cursorBinding,
                   range: 0 ... Double(GlobalLattice.previewCells - 1),
                   step: 1,
                   cols: GlobalLattice.previewCells)
            .cellDetent(tick: clock.tick, every: 1, position: { (col: surface.cursor, row: 0) })
            .accessibilityLabel("Scrub frame")
    }

    /// A non-optional bridge for the scrub `CellSlider`: reads the cursor, writes it back
    /// through `scrubCursor` (clamped, NO FSM event).
    private var cursorBinding: Binding<Double> {
        Binding(
            get: { Double(surface.cursor) },
            set: { surface.scrubCursor(to: Int($0.rounded())) }
        )
    }

    // MARK: - (3) 4-pick filmstrip

    /// Four 16×16 thumbnails over `surface.picks` (in pick order) — empty docks show the
    /// ghost ink. Tapping a filled thumbnail JUMPS the cursor to that frame; tapping again
    /// at the same cursor frame removes it via `togglePick` (the toggle-group idiom).
    private var filmstrip: some View {
        HStack(spacing: GlobalLattice.gif(GlobalLattice.gutterCells)) {
            ForEach(0 ..< 4, id: \.self) { i in
                let f: Int? = i < surface.picks.count ? surface.picks[i] : nil
                Button {
                    if let f { surface.scrubCursor(to: f) }
                } label: {
                    CellSprite(cols: 16, rows: 16, cellPt: GlobalLattice.gifPx) { c, r in
                        guard let f else { return SFTheme.ledGhost }
                        return surface.gifCell(c, r, f) ?? SFTheme.ledGhost
                    }
                    .frame(width: paletteEdge, height: paletteEdge)
                }
                .buttonStyle(.plain)
                .disabled(f == nil)
                .accessibilityLabel(f == nil ? "Empty anchor slot \(i + 1)"
                                             : "Anchor frame \(f! + 1)")
            }
        }
    }

    // MARK: - (5) Pooled swatch (the diversity dock)

    /// The 4 picks' pooled per-frame palettes painted as a flat 16×16 swatch — an inert
    /// read of the anchors' colour spread (the diversity-ring dock, rendered as cells).
    /// Empty (ghost) until anchors are chosen.
    private var pooledSwatch: some View {
        let pooled: [SIMD3<UInt8>] = surface.picks
            .filter { $0 < surface.palettesPerFrame.count }
            .flatMap { surface.palettesPerFrame[$0] }
        return CellSprite(cols: 16, rows: 16, cellPt: GlobalLattice.gifPx) { c, r in
            let i = r * 16 + c
            return i < pooled.count ? pooled[i] : SFTheme.ledGhost
        }
        .frame(width: paletteEdge, height: paletteEdge)
        .allowsHitTesting(false)
        .accessibilityLabel("Anchor colour spread")
    }

    // MARK: - (6) Continue gate

    /// Fires `.picked4` ONLY when exactly 4 anchors are chosen — the count is load-bearing
    /// downstream (the 4⁴ quad). `surfaceStep`'s `.picked4` edge is unconditional (a pure
    /// mirror of the spec δ); the exactly-4 gate lives HERE in the button.
    private var continueGate: some View {
        Button {
            if surface.picks.count == 4 { surface.step(.picked4) }
        } label: {
            CellActionButton(title: "Continue · \(surface.picks.count)/4",
                             prominent: surface.picks.count == 4)
        }
        .buttonStyle(.plain)
        .disabled(surface.picks.count != 4)
        .accessibilityLabel("Continue with 4 anchor frames")
    }
}
