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

    private var atom: CGFloat { GlobalLattice.gifPx }

    func body(content: Content) -> some View {
        guard enabled else { return AnyView(content) }
        let base = content
            // The transient drag-follow: the lifted widget tracks the finger. This is
            // a LIVE TOUCH POINT, not a layout — the single sanctioned `.offset`.
            .offset(drag)   // LINT-ALLOW-POSITION: transient lift-follow (auto-resets)
            .overlay { if lifted { dropOverlay } }
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
    /// drag begins, so a clean tap (<0.3 s) never lifts and the shutter tap is preserved.
    private var liftDrag: some Gesture {
        LongPressGesture(minimumDuration: 0.3)
            .sequenced(before: DragGesture(minimumDistance: atom))
            .updating($drag) { value, state, _ in
                if case .second(true, let d?) = value { state = d.translation }
            }
            .onChanged { value in
                if case .second(true, _) = value { lifted = true }
            }
            .onEnded { value in
                lifted = false
                guard case .second(true, let d?) = value else { return }
                commit(d.translation)
            }
    }

    /// Snap the pt-translation to a whole-atom CELL delta and run `MoveContract.move`.
    /// Persists the result only if accepted; a reject leaves the store unchanged (the
    /// transient offset auto-resets ⇒ exact snap-back). The Swift `move` reuses
    /// `GridLayoutContract.isDisjoint` and adds no geometry authority.
    private func commit(_ translation: CGSize) {
        let atomInt = SixFourLattice.gifPx
        let dCol = MoveContract.snapToAtom(Int(translation.width), atom: atomInt) / atomInt
        let dRow = MoveContract.snapToAtom(Int(translation.height), atom: atomInt) / atomInt
        guard dCol != 0 || dRow != 0 else { return }
        let current = settings.widgetPlacement
        let next = MoveContract.move(current, identity, dCol: dCol, dRow: dRow)
        // `move` returns the input unchanged on reject; only persist a real change.
        if !placementsEqual(next, current) { settings.widgetPlacement = next }
    }

    private func placementsEqual(_ a: [ColorIdentity: (col: Int, row: Int)],
                                 _ b: [ColorIdentity: (col: Int, row: Int)]) -> Bool {
        for i in ColorIdentity.allCases {
            if a[i]?.col != b[i]?.col || a[i]?.row != b[i]?.row { return false }
        }
        return true
    }

    /// Live valid/invalid feedback while lifted — a one-cell footprint outline drawn as a
    /// `CellSprite` (no glass, no opacity-on-a-cell). Green when the snapped drop would be
    /// accepted, red when it would snap back. Mirrors the move acceptance exactly.
    private var dropOverlay: some View {
        let atomInt = SixFourLattice.gifPx
        let dCol = MoveContract.snapToAtom(Int(drag.width), atom: atomInt) / atomInt
        let dRow = MoveContract.snapToAtom(Int(drag.height), atom: atomInt) / atomInt
        let current = settings.widgetPlacement
        let next = MoveContract.move(current, identity, dCol: dCol, dRow: dRow)
        let accepted = !placementsEqual(next, current) || (dCol == 0 && dRow == 0)
        let ink: SIMD3<UInt8> = accepted ? SIMD3(70, 200, 90) : SIMD3(220, 60, 60)
        let (w, h) = identity.footprint
        return CellSprite(cols: w, rows: h, cellPt: GlobalLattice.gifPx) { c, r in
            // A 1-cell border outline — interior transparent so the widget shows through.
            (c == 0 || r == 0 || c == w - 1 || r == h - 1) ? ink : nil
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
