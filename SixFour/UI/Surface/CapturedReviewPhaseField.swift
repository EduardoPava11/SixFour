import SwiftUI
import simd

/// Π for the post-capture REVIEW phases (`.captured` / `.picked`) — the tri-scale review
/// bench that replaced the retired A/B game. It shows the committed 64³ capture beside its
/// byte-exact 16³ octree coarse (the same coarse tier the model reads), both playing on the
/// shared Z₆₄ cursor, plus EXPORT / RETAKE controls. Cells only, placed on the one 4 pt lattice.
///
/// The 64 tile reads `surface.gifCell` (index cube × per-frame palette); the 16 tile reads
/// `surface.gifCell16` (the `VoxelReduce` substrate built at commit). Both animate because
/// `SurfaceView` advances `surface.cursor` every κ tick regardless of phase.
struct CapturedReviewPhaseField: View {
    let surface: Surface
    let clock: SurfaceClock

    private let ghost = SIMD3<UInt8>(20, 20, 24)
    private let labelInk = Color(srgb8: SIMD3<UInt8>(190, 190, 190))

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.clear

            CellText("64", rows: 6, ink: labelInk)
                .place(GridRegion(name: "review64Label", col: 18, row: 16,
                                  w: 10, h: 6, widget: 0, priority: 0, interactive: false))
            tile64
                .place(GridRegion(name: "review64", col: 18, row: 24,
                                  w: 64, h: 64, widget: 1, priority: 1, interactive: false))

            CellText("16", rows: 6, ink: labelInk)
                .place(GridRegion(name: "review16Label", col: 42, row: 94,
                                  w: 10, h: 6, widget: 2, priority: 2, interactive: false))
            tile16
                .place(GridRegion(name: "review16", col: 42, row: 102,
                                  w: 16, h: 16, widget: 3, priority: 3, interactive: false))

            controls
                .place(GridRegion(name: "reviewControls", col: 22, row: 128,
                                  w: 56, h: 12, widget: 4, priority: 4, interactive: true))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .ignoresSafeArea()
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Review the captured GIF")
    }

    /// The 64³ capture: 64×64 cells at the 4 pt atom (256 pt), the committed index cube read
    /// through its per-frame palette at the live playback cursor.
    private var tile64: some View {
        let t = surface.cursor
        return CellSprite(cols: 64, rows: 64, cellPt: GlobalLattice.gif(1)) { c, r in
            surface.gifCell(c, r, t) ?? ghost
        }
        .allowsHitTesting(false)
    }

    /// The 16³ octree coarse: 16×16 cells at the atom (64 pt), the byte-exact `VoxelReduce`
    /// substrate at the coarse cursor (`cursor / 4`, the ×4 temporal reduction).
    private var tile16: some View {
        let t16 = surface.cursor / 4
        return CellSprite(cols: 16, rows: 16, cellPt: GlobalLattice.gif(1)) { c, r in
            surface.gifCell16(c, r, t16) ?? ghost
        }
        .allowsHitTesting(false)
    }

    private var controls: some View {
        HStack(spacing: GlobalLattice.pt(6)) {
            Button { retake() } label: {
                CellActionButton(icon: .none, title: "RETAKE", prominent: false, fillWidth: false)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Discard and shoot again")

            Button { export() } label: {
                CellActionButton(icon: .none, title: "EXPORT", prominent: true, fillWidth: false)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Export the reviewed GIF")
        }
    }

    /// Forward to export. With A/B retired, accepting the capture is the single modeled edge out
    /// of `.captured` (`pickA`); from `.picked`, `exportFamily` enters `.exporting`, which ships
    /// the already-committed GIF (`surface.gifURL`) and advances to `.done`.
    private func export() {
        if surface.phase == .captured { surface.step(.pickA) }
        surface.step(.exportFamily)
    }

    private func retake() { surface.step(.retake) }
}
