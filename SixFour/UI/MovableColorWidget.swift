import SwiftUI
import simd

/// MOVABLE COLOR WIDGETS — the Swift mirror of `Spec.MovableLayout` (source of truth)
/// + its generated `MoveContract` (the geometry algebra). A **ColorWidget** is a widget
/// whose cells are a projection of the ONE color cube; MOVABILITY is a property of being
/// one. Chrome (build stamp, gear, action row, the heartbeat ground, the determinism
/// badge) is NOT a ColorWidget — it has no placement state, so it is immovable by
/// construction (the closed `ColorIdentity` alphabet, emitted in `MoveContract.swift`,
/// is the only movable set).
///
/// This file adds NO geometry authority: `region(for:at:)` builds the SAME `GridRegion`
/// the existing `place(_ region:)` consumes, and `.movable` calls the generated
/// `MoveContract.move` (which reuses `GridLayoutContract.isDisjoint`). The only new
/// positioning is the transient drag-follow `.offset`, tagged `// LINT-ALLOW-POSITION`
/// (a live touch point, not a layout) — at rest, every widget is `.place()`-d.
///
/// Tier-2 pure: SwiftUI + simd, zero third-party deps.

// MARK: - The ColorWidget protocol (mirror of the Haskell `ColorWidget` class)

/// A ColorWidget is a projection of the one cube with a fixed cell footprint. The closed
/// `ColorIdentity` enum (generated in `MoveContract.swift`) is the conforming alphabet;
/// every member's footprint / dock / interactivity is sourced from `MoveContract`, never
/// free literals. Mirrors `Spec.MovableLayout.ColorWidget`.
protocol ColorWidget {
    /// Which closed color identity this widget is — its key into the shared `Placement`.
    /// `nonisolated` so a `View` (MainActor) conformer satisfies it without crossing actors.
    nonisolated var identity: ColorIdentity { get }
}

extension ColorIdentity {
    /// (side, side) cell footprint — from the generated contract (no free literals).
    var footprint: (w: Int, h: Int) { MoveContract.footprint(self) }
    /// Whether this identity is an interactive touch target (only `Palette16` = shutter).
    var interactive: Bool { MoveContract.interactive(self) }
}

// MARK: - region(for:at:) — placement from footprint + the live position

/// Build the `GridRegion` for one identity at a live placement — the SOLE bridge from a
/// movable position to the existing `place(_ region:)` primitive. Reuses the generated
/// `MoveContract.placedRegion` (footprint + ids from the spec), so there is no new
/// placement math and no new sanctioned `.position` site.
func region(for identity: ColorIdentity, at placement: [ColorIdentity: (col: Int, row: Int)]) -> GridRegion {
    let pos = placement[identity] ?? (MoveContract.defaultCol(identity), MoveContract.defaultRow(identity))
    return MoveContract.placedRegion(identity, col: pos.col, row: pos.row)
}

// MARK: - The .movable modifier (long-press LIFT → drag → SNAP)

/// The ONE movability modifier, shared by all three identities (chrome never applies it).
/// Long-press(0.3) LIFTS the widget; a sequenced drag moves it; release SNAPS the drop to
/// the 4 pt atom and commits via `MoveContract.move` — accepted iff the induced scene is
/// in-bounds AND disjoint, else an exact snap-back (the transient `@GestureState` offset
/// auto-resets to `.zero`). A clean TAP never enters long-press completion, so the
/// shutter's `.shutterTap` still fires (the gesture is attached to the INNER grid, not
/// the Button); a lift never fires a burst.
private struct MovableModifier: ViewModifier {
    let identity: ColorIdentity
    @Bindable var settings: AppSettings
    let surface: Surface
    /// Whether this widget is movable in the CURRENT phase. The shutter is movable only
    /// while `.live`; the heroes are always movable. A non-movable phase = no gesture +
    /// no overlay (byte-identical to the pre-feature view).
    let enabled: Bool
    /// A clean-tap action — the palette IS the shutter. When set, a quick tap fires this and
    /// the long-press still lifts/moves; composed via `.exclusively` so they never fight.
    /// (The old approach wrapped the grid in a `Button`, which swallowed the tap.) nil for
    /// the heroes, which have no tap action.
    let onTap: (() -> Void)?

    /// The transient lift offset (points). Auto-resets to `.zero` on gesture end, so a
    /// rejected move visibly snaps back with no extra stored state.
    @GestureState private var drag: CGSize = .zero
    /// True once the long-press has completed and the lift is active (drives the overlay).
    @State private var lifted = false
    /// The detent counter: cells crossed at the last `CellTick`, so we fire one tick per
    /// `tickEvery` boundary the finger crosses (the spec's `cellsCrossed` made felt).
    @State private var lastTickCells = 0

    private var atomInt: Int { SixFourLattice.gifPx }

    func body(content: Content) -> some View {
        guard enabled else { return AnyView(content) }
        // GREEN-FRAME FIX + DSL: `.overlay` is applied BEFORE `.offset`, so the drop
        // outline rides the SAME offset as the content and stays frame-locked to the
        // finger (`.offset` moves visuals but not the layout frame an after-overlay would
        // anchor to). The outline's colour comes from `SixFourCellMechanics.dropAccepts`,
        // the SAME verdict `commit` uses (`Spec.CellMechanics.lawDropColorMatchesMove`), so
        // it can never disagree with what the drop will do.
        let base = content
            .overlay { if lifted { dropOverlay } }
            .offset(drag)   // LINT-ALLOW-POSITION: transient lift-follow (auto-resets)
            // Give the gesture a solid hittable area even if the content opts out of hit
            // testing (the preview hero sets `.allowsHitTesting(false)` for a focus layer).
            .contentShape(Rectangle())
        // A clean TAP fires `onTap` ONLY if the lift-drag fails (quick release); `.exclusively`
        // gives the lift-drag precedence, so a long-press never fires the tap (no stray burst).
        if let onTap {
            return AnyView(base
                .gesture(liftDrag.exclusively(before: TapGesture().onEnded { onTap() }))
                .accessibilityAddTraits(.isButton)
                .accessibilityAction { onTap() })
        } else {
            return AnyView(base.gesture(liftDrag))
        }
    }

    /// LongPress(0.3) → Drag(minDistance: 1 cell). The long-press must complete before the
    /// drag begins, so a clean tap (<0.3 s) never lifts and the shutter tap is preserved —
    /// the SwiftUI realisation of `Spec.CellMechanics.lawDragRequiresHold` (the hold gate).
    private var liftDrag: some Gesture {
        LongPressGesture(minimumDuration: 0.3)
            .sequenced(before: DragGesture(minimumDistance: CGFloat(atomInt)))
            .updating($drag) { value, state, _ in
                if case .second(true, let d?) = value { state = d.translation }
            }
            .onChanged { value in
                guard case .second(true, let dOpt) = value else { return }
                if !lifted {                          // Pressed → Lifted (the hold armed)
                    lifted = true
                    lastTickCells = 0
                    Haptics.play(0)                    // liftPop
                }
                guard let d = dOpt else { return }
                // CellTick: one detent per `tickEvery` cell-boundary the finger crosses.
                let cell = snapCells(d.translation)
                let crossed = SixFourCellMechanics.cellsCrossed((col: 0, row: 0), cell)
                let every = max(1, SixFourCellMechanics.tickEvery(identity))
                if crossed / every != lastTickCells / every { Haptics.play(1) }   // cellTick
                lastTickCells = crossed
            }
            .onEnded { value in
                lifted = false
                guard case .second(true, let d?) = value else { return }
                commit(d.translation)
            }
    }

    /// Snap a pt-translation to a whole-atom CELL delta (the one continuous→discrete edge).
    private func snapCells(_ t: CGSize) -> (col: Int, row: Int) {
        (MoveContract.snapToAtom(Int(t.width),  atom: atomInt) / atomInt,
         MoveContract.snapToAtom(Int(t.height), atom: atomInt) / atomInt)
    }

    /// Commit the drop through the SAME verdict the overlay shows. On accept, persist
    /// `MoveContract.move` and confirm; on reject, the transient offset auto-resets ⇒ exact
    /// snap-back, and the error haptic fires. No new geometry authority (verdict = move).
    private func commit(_ translation: CGSize) {
        let cell = snapCells(translation)
        guard cell.col != 0 || cell.row != 0 else { return }
        let current = settings.widgetPlacement
        if SixFourCellMechanics.dropAccepts(current, identity, dCol: cell.col, dRow: cell.row) {
            settings.widgetPlacement = MoveContract.move(current, identity, dCol: cell.col, dRow: cell.row)
            Haptics.play(3)                            // dropAccept
        } else {
            Haptics.play(4)                            // dropReject (snaps back)
        }
    }

    /// Live drop feedback while lifted — a one-cell footprint outline that BREATHES: its
    /// colour is the spec verdict (`dropAccepts` → green accept / red reject), and it
    /// pulses via `SixFourCellMechanics.reactivePulse` (faster & wider on reject, faster
    /// the farther the drag), sampled by the integer `pulseSampleQ16` triangle. So the
    /// outline visibly tracks the user's intent — calm green when valid, urgent red when not.
    private var dropOverlay: some View {
        let cell = snapCells(drag)
        let accepted = SixFourCellMechanics.dropAccepts(
            settings.widgetPlacement, identity, dCol: cell.col, dRow: cell.row)
        let dragMag = SixFourCellMechanics.cellsCrossed((col: 0, row: 0), cell)
        let pulse = SixFourCellMechanics.reactivePulse(identity: identity, accept: accepted, dragMag: dragMag)
        let accent = accepted ? SixFourCellMechanics.acceptInk : SixFourCellMechanics.rejectInk
        // The trough: an opaque dim of the accent (GRID Law: step the colour, never alpha).
        let dim = (r: accent.r * 30 / 100, g: accent.g * 30 / 100, b: accent.b * 30 / 100)
        let (w, h) = identity.footprint
        // TimelineView gives the per-frame tick that samples the (spec-pinned) pulse — the
        // single impure leaf. Spec owns the waveform; this only reads the clock.
        return TimelineView(.animation) { tl in
            let tick = Int(tl.date.timeIntervalSinceReferenceDate * 20)   // ~20 fps phase
            let amp = SixFourCellMechanics.pulseSampleQ16(
                period: pulse.period, lo: pulse.lo, hi: pulse.hi, tick: tick)
            let t = SixFourCellMechanics.tintLerpQ16(base: dim, accent: accent, ampQ16: amp)
            let ink = SIMD3<UInt8>(UInt8(clamping: t.r), UInt8(clamping: t.g), UInt8(clamping: t.b))
            CellSprite(cols: w, rows: h, cellPt: GlobalLattice.gifPx) { c, r in
                // A 1-cell border outline — interior transparent so the widget shows through.
                (c == 0 || r == 0 || c == w - 1 || r == h - 1) ? ink : nil
            }
        }
        .allowsHitTesting(false)
    }
}

extension View {
    /// Make this view a movable ColorWidget (long-press lift → drag → snap). `enabled`
    /// gates movability per-phase (the shutter is movable only while `.live`).
    func movable(_ identity: ColorIdentity, settings: AppSettings, surface: Surface,
                 enabled: Bool = true, onTap: (() -> Void)? = nil) -> some View {
        modifier(MovableModifier(identity: identity, settings: settings, surface: surface,
                                 enabled: enabled, onTap: onTap))
    }
}
