import SwiftUI
import simd

/// Which render mode the unified `GIFPlayer` shows. The 2D/3D toggle picks one;
/// both read the SAME `PlaybackClock`, so switching never changes the frame.
enum PlayerMode: String, CaseIterable, Codable, Sendable {
    case flat   // the 2D GIF (GIFCanvas)
    case cube   // the 64³ voxel cube (VoxelCubeView), front face == the 2D frame
}

/// The GRID transport strip for the unified player — play/pause, a 64-cell scrub
/// rail (one cell per frame), a fixed-width frame counter, and the 2D/3D mode
/// toggle. EVERYTHING is built from `CellSprite` at the 6 pt Review pitch
/// (`SFTheme.gifCellPt`), never a SwiftUI `Slider`/`Picker`/`Toggle`, so the whole
/// Review surface stays ONE pitch (GRID Law #5; docs/SIXFOUR-UNIFIED-PLAYER.md).
///
/// The strip is STATIC on the lattice: it re-bakes only on discrete input
/// (tap/drag/clock-frame change), never on the 20 fps clock — only the render
/// surface animates. Reduce-motion is owned by the clock (auto-advance frozen);
/// the scrub rail still works (discrete input).
struct PlayerTransport: View {
    @Bindable var clock: PlaybackClock
    @Binding var mode: PlayerMode
    /// Whether the 3D cube is available (false ⇒ the CUBE segment is hidden, exactly
    /// as the old palette voxel mode was gated on `frameIndicesForVoxels != nil`).
    var cubeAvailable: Bool

    /// A pinned, WCAG-legible Review accent (Review is a static surface, so it does
    /// not derive from the live scene like the capture HUD).
    private let accent = SIMD3<UInt8>(96, 165, 250)
    private var cell: CGFloat { SFTheme.gifCellPt }   // 6 pt

    var body: some View {
        VStack(spacing: cell) {
            ScrubRail(clock: clock, accent: accent)
            HStack(spacing: cell) {
                PlayPauseCell(playing: clock.playing, accent: accent) { clock.togglePlay() }
                CellDigits(value: clock.frame + 1, width: 2, lit: accent, cellPt: cell)
                    .accessibilityLabel("Frame \(clock.frame + 1) of \(clock.count)")
                    .accessibilityHidden(false)
                Spacer(minLength: cell)
                if cubeAvailable {
                    ModeToggleCell(mode: $mode, accent: accent)
                }
            }
        }
        // Hit-rect == visible rect; the strip never animates with the clock.
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Play / pause (a cell glyph, two states)

/// An 8×8-cell play/pause glyph (48 pt — clears the 44 pt touch floor). Pressed
/// state is a cell transform (inverted), never opacity. The whole 48 pt box is the
/// hit target (`contentShape`).
private struct PlayPauseCell: View {
    let playing: Bool
    let accent: SIMD3<UInt8>
    let action: () -> Void
    private let n = 8
    private var cell: CGFloat { SFTheme.gifCellPt }

    var body: some View {
        Button(action: action) {
            CellSprite(cols: n, rows: n, cellPt: cell) { c, r in
                let on = playing ? Self.pauseMask(c, r, n) : Self.playMask(c, r, n)
                return on ? accent : nil
            }
            .frame(width: cell * CGFloat(n), height: cell * CGFloat(n))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(playing ? "Pause" : "Play")
        .accessibilityAddTraits(.isButton)
    }

    /// Two vertical bars with a gap — the pause glyph.
    static func pauseMask(_ c: Int, _ r: Int, _ n: Int) -> Bool {
        guard r >= 1 && r <= n - 2 else { return false }
        return (c == 1 || c == 2) || (c == n - 3 || c == n - 2)
    }

    /// A right-pointing triangle, apex at the right-middle — the play glyph.
    static func playMask(_ c: Int, _ r: Int, _ n: Int) -> Bool {
        let cy = Double(n - 1) / 2
        let dr = abs(Double(r) - cy) / cy             // 0 centre … 1 edge
        guard dr <= 1 else { return false }
        let left = 1.5
        let rightEdge = left + (1 - dr) * (Double(n - 2) - left)
        return Double(c) >= left && Double(c) <= rightEdge
    }
}

// MARK: - Scrub rail (one cell per frame)

/// A `count`-cell horizontal rail (one cell per frame, so 64 cells = 384 pt = the
/// GIF canvas width). A baseline ghost line, with the current frame's column lit in
/// accent (the playhead). Drag/tap maps x → frame and scrubs (which pauses the
/// clock). 8 cells tall ⇒ a 48 pt drag target.
private struct ScrubRail: View {
    @Bindable var clock: PlaybackClock
    let accent: SIMD3<UInt8>
    private let rows = 8
    private var cell: CGFloat { SFTheme.gifCellPt }
    private var cols: Int { clock.count }

    var body: some View {
        let ghost = SFTheme.ledGhost
        let f = clock.frame
        CellSprite(cols: cols, rows: rows, cellPt: cell) { c, r in
            if c == f { return accent }                       // the playhead column
            return (r == rows / 2 - 1 || r == rows / 2) ? ghost : nil   // baseline
        }
        .frame(width: cell * CGFloat(cols), height: cell * CGFloat(rows))
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { v in scrub(x: v.location.x) }
        )
        .accessibilityElement()
        .accessibilityLabel("Scrub")
        .accessibilityValue("Frame \(f + 1) of \(clock.count)")
        .accessibilityAdjustableAction { dir in
            switch dir {
            case .increment: clock.scrub(to: f + 1)
            case .decrement: clock.scrub(to: f - 1)
            default: break
            }
        }
    }

    private func scrub(x: CGFloat) {
        let width = cell * CGFloat(cols)
        guard width > 0 else { return }
        let i = Int((x / width) * CGFloat(cols))
        clock.scrub(to: i)
    }
}

// MARK: - 2D / 3D mode toggle (cell icons, accent border on the selected segment)

/// Two 10×10-cell segments — a FLAT square glyph and a CUBE wireframe glyph. The
/// selected segment carries a 1-cell accent border (a cell transform, NOT a
/// fill/glow — GRID Law #2). Each segment is 60 pt, clearing the touch floor.
private struct ModeToggleCell: View {
    @Binding var mode: PlayerMode
    let accent: SIMD3<UInt8>
    private let n = 10
    private var cell: CGFloat { SFTheme.gifCellPt }

    var body: some View {
        HStack(spacing: cell) {
            segment(.flat)
            segment(.cube)
        }
    }

    @ViewBuilder
    private func segment(_ m: PlayerMode) -> some View {
        let isSel = mode == m
        Button { mode = m } label: {
            CellSprite(cols: n, rows: n, cellPt: cell) { c, r in
                let border = c == 0 || c == n - 1 || r == 0 || r == n - 1
                if isSel && border { return accent }                 // selected ring
                if !isSel && border { return SFTheme.ledGhost }      // unselected ring
                let ink: SIMD3<UInt8> = isSel ? accent : SFTheme.ledGhost
                return (m == .flat ? Self.flatMask(c, r, n) : Self.cubeMask(c, r, n)) ? ink : nil
            }
            .frame(width: cell * CGFloat(n), height: cell * CGFloat(n))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(m == .flat ? "2D flat view" : "3D cube view")
        .accessibilityAddTraits(isSel ? [.isButton, .isSelected] : .isButton)
    }

    /// FLAT: a filled inner square (the 2D GIF).
    static func flatMask(_ c: Int, _ r: Int, _ n: Int) -> Bool {
        c >= 3 && c <= n - 4 && r >= 3 && r <= n - 4
    }

    /// CUBE: two offset square outlines joined at the corners — a wireframe cube.
    static func cubeMask(_ c: Int, _ r: Int, _ n: Int) -> Bool {
        // Front square (lower-left) and back square (upper-right), offset by 2 cells.
        func onSquareBorder(_ x0: Int, _ y0: Int, _ s: Int) -> Bool {
            let onX = (c == x0 || c == x0 + s) && r >= y0 && r <= y0 + s
            let onY = (r == y0 || r == y0 + s) && c >= x0 && c <= x0 + s
            return onX || onY
        }
        let s = 4
        if onSquareBorder(2, 4, s) { return true }   // front
        if onSquareBorder(4, 2, s) { return true }   // back
        // Connect the matching corners (the depth edges).
        if (c == 2 && r == 4) || (c == 4 && r == 2) { return true }
        if (c == 6 && r == 4) || (c == 8 && r == 2) { return true }
        if (c == 2 && r == 8) || (c == 4 && r == 6) { return true }
        if (c == 6 && r == 8) || (c == 8 && r == 6) { return true }
        return false
    }
}
