import SwiftUI
import simd

/// A calm fixed accent for Settings controls (the capture HUD derives its accent from
/// the live scene; Settings is a static surface, so a pinned accent keeps it readable).
private let selectorAccent = SIMD3<UInt8>(96, 165, 250)
private let dimInk = SIMD3<UInt8>(140, 140, 140)

/// GRID component **`CellSelector`** (design language §6.7) — a horizontal row of
/// segment `CellButton`s sharing one band; exactly one selected, marked by a 1-cell
/// accent border (NOT a fill/glow — Law #2). Each segment clears the touch floor
/// (`segmentCells = touchFloorCells = 22` ⇒ 44 pt, a proven `Spec.Lattice` law), and
/// the band grows by widening, never by subdividing a segment below the floor.
struct CellSelector<T: Hashable>: View {
    let options: [(value: T, label: String)]
    @Binding var selection: T
    /// Compact label register so 2–3 segments fit the fixed screen width.
    var labelRows: Int = 9

    var body: some View {
        HStack(spacing: GlobalLattice.pt(GlobalLattice.gutterCells)) {
            ForEach(Array(options.enumerated()), id: \.offset) { _, opt in
                segment(opt.value, opt.label)
            }
        }
    }

    @ViewBuilder
    private func segment(_ value: T, _ label: String) -> some View {
        let isSel = value == selection
        Button { selection = value } label: {
            CellText(label, rows: labelRows, ink: isSel ? .white : Color(srgb8: dimInk))
                .padding(.horizontal, GlobalLattice.pt(3))
                .padding(.vertical, GlobalLattice.pt(2))
                .frame(minWidth: GlobalLattice.pt(GlobalLattice.segmentCells),
                       minHeight: GlobalLattice.pt(GlobalLattice.touchFloorCells))
                .background(Color(srgb8: SFTheme.ledGhost))   // flat opaque cell ground
                // 1-cell accent border on the selected segment (opaque, axis-aligned, no AA).
                .border(Color(srgb8: isSel ? selectorAccent : SFTheme.ledGhost),
                        width: GlobalLattice.pt(1))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityAddTraits(isSel ? [.isButton, .isSelected] : .isButton)
    }
}

/// GRID **`CellToggle`** — an on/off control as cells: a label row + a `CellCheckbox`.
/// On = filled accent box, off = hollow `ledGhost` outline (a cell transform, never
/// opacity). The whole row is the hit target.
struct CellToggle: View {
    let label: String
    @Binding var isOn: Bool
    var labelRows: Int = 11

    var body: some View {
        Button { isOn.toggle() } label: {
            HStack(spacing: GlobalLattice.pt(3)) {
                CellText(label, rows: labelRows, ink: .white)
                Spacer(minLength: GlobalLattice.pt(4))
                CellCheckbox(on: isOn)
            }
            .frame(minHeight: GlobalLattice.pt(GlobalLattice.touchFloorCells))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityValue(isOn ? "On" : "Off")
        .accessibilityAddTraits(.isButton)
    }
}

/// A 12×12-cell checkbox: filled accent when on, hollow `ledGhost` outline when off.
struct CellCheckbox: View {
    let on: Bool
    private let n = 12
    var body: some View {
        let accent = selectorAccent
        let ghost = SFTheme.ledGhost
        CellSprite(cols: n, rows: n) { c, r in
            let onBorder = c == 0 || c == n - 1 || r == 0 || r == n - 1
            if on { return onBorder ? accent : SIMD3<UInt8>(accent.x / 2, accent.y / 2, accent.z / 2) }
            return onBorder ? ghost : nil   // hollow when off
        }
        .accessibilityHidden(true)
    }
}
