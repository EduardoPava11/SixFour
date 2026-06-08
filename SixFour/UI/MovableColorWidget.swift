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
        // The lifted widget tracks the finger via `.offset` (auto-resets on release ⇒ the
        // drop snaps to the committed cell). No drop-outline: with nearest-free snapping a
        // drop always lands, so a valid/invalid frame served no purpose and the finger-
        // tracked outline only confused. Feedback is the widget moving + the haptics.
        let base = content
            .offset(drag)   // LINT-ALLOW-POSITION: transient lift-follow (auto-resets)
            // Give the gesture a solid hittable area even if the content opts out of hit
            // testing (the preview hero sets `.allowsHitTesting(false)` for a focus layer).
            .contentShape(Rectangle())
        // The shutter tap MUST be bulletproof (this IS the camera button). A plain
        // `.onTapGesture` fires capture on a quick tap; the SEPARATE `.gesture(liftDrag)`
        // needs a 0.3 s hold first, so the two are mutually exclusive by timing and never
        // fight. (The old `liftDrag.exclusively(before: TapGesture)` let the LongPress
        // starve the tap in the gesture arena — capture would silently not fire.)
        if let onTap {
            return AnyView(base
                .onTapGesture { onTap() }
                .gesture(liftDrag)
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

    /// Commit the drop by SNAPPING TO THE NEAREST FREE CELL: the widget lands at the
    /// dropped position if it is in-bounds and clear, else slides to the closest cell that
    /// is — "approximate a location and snap into place as long as I am not over another
    /// widget." Only when the whole field is full (never, in practice) does it stay put.
    private func commit(_ translation: CGSize) {
        let cell = snapCells(translation)
        guard cell.col != 0 || cell.row != 0 else { return }
        if let next = snapToNearestFree(settings.widgetPlacement, dCol: cell.col, dRow: cell.row) {
            settings.widgetPlacement = next
            Haptics.play(3)                            // dropAccept — landed
        } else {
            Haptics.play(4)                            // dropReject — nowhere free (rare)
        }
    }

    /// Identities that actually OCCUPY the screen (so a move collides with them). The
    /// `DiversityRing` is in the closed alphabet but is not rendered, so it is NOT a
    /// collider — excluding it removes an invisible dead-zone. (Field64 + Palette16 only.)
    private static let colliders: [ColorIdentity] = [.field64, .palette16]

    /// Is `identity` clear (in-bounds AND disjoint from the other COLLIDERS) at `(c,r)`?
    /// Reuses the proven `GridLayoutContract.isDisjoint` over `MoveContract.placedRegion`,
    /// so this adds no geometry authority — only the search for WHICH free cell is new.
    private func isFree(_ placement: [ColorIdentity: (col: Int, row: Int)],
                        at c: Int, _ r: Int) -> Bool {
        let clamped = MoveContract.clampInBounds(identity, c, r)
        guard clamped.col == c, clamped.row == r else { return false }   // in-bounds only
        // Stay inside the ROUNDED boundary — never past the edge or into a rounded corner.
        let (fw, fh) = identity.footprint
        guard Boundary.footprintFits(col: c, row: r, w: fw, h: fh) else { return false }
        var scene: [GridRegion] = [MoveContract.placedRegion(identity, col: c, row: r)]
        for other in Self.colliders where other != identity {
            if let p = placement[other] {
                scene.append(MoveContract.placedRegion(other, col: p.col, row: p.row))
            }
        }
        return GridLayoutContract.isDisjoint(scene)
    }

    /// The placement after moving `identity` to the NEAREST free cell to its dropped
    /// position (expanding square rings, nearest-by-distance within each ring). Returns
    /// `nil` only if no free cell exists within the search bound.
    private func snapToNearestFree(_ current: [ColorIdentity: (col: Int, row: Int)],
                                   dCol: Int, dRow: Int) -> [ColorIdentity: (col: Int, row: Int)]? {
        guard let cur = current[identity] else { return nil }
        let target = MoveContract.clampInBounds(identity, cur.col + dCol, cur.row + dRow)
        func placed(_ c: Int, _ r: Int) -> [ColorIdentity: (col: Int, row: Int)] {
            var p = current; p[identity] = (c, r); return p
        }
        if isFree(current, at: target.col, target.row) { return placed(target.col, target.row) }
        let maxRadius = 64
        for radius in 1 ... maxRadius {
            var best: (c: Int, r: Int)? = nil
            var bestDist = Int.max
            for dc in -radius ... radius {
                for dr in -radius ... radius where max(abs(dc), abs(dr)) == radius {
                    let c = target.col + dc, r = target.row + dr
                    if isFree(current, at: c, r) {
                        let d = dc * dc + dr * dr
                        if d < bestDist { bestDist = d; best = (c, r) }
                    }
                }
            }
            if let b = best { return placed(b.c, b.r) }
        }
        return nil
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
