import SwiftUI
import simd

/// Π for the post-capture REVIEW phases (`.captured` / `.picked`): the SINGLE honest artifact,
/// the captured 64³ GIF, plus RETAKE and EXPORT. EXPORT drives the normal `.captured → .exporting
/// → .done` flow; the Done screen ships BOTH the GIF and the probability-field `.npy` bin as one
/// bundle (the training data), so there is one export path, not two.
///
/// DEPRECATED (2026-06-30) and removed from this screen: the tri-scale 16 / 64 / 256 review PYRAMID
/// (the 256³ tier only nearest-neighbour-upscaled the same 64³ data and labelled it "256" as if a
/// model had invented detail; the learned head is NOT ported), and the V2.1 FIELD widgets (not ready
/// to show). Both live in git history / `SixFour.Spec.Upscale256` for when the head deploys. Until
/// then this screen shows exactly what was captured and nothing it cannot back up.
///
/// The GIF plays on the shared Z₆₄ cursor (`SurfaceView` advances it every κ tick). The cell grid is a
/// PLACEMENT lattice, not a per-pixel canvas: the tile is a bitmap placed in a cell region, so it lives
/// in a large footprint at sub-atom pixels without ever breaking the 4 pt atom.
struct CapturedReviewPhaseField: View {
    let surface: Surface
    let clock: SurfaceClock

    private let ghost = SIMD3<UInt8>(20, 20, 24)
    private let labelInk = Color(srgb8: SIMD3<UInt8>(190, 190, 190))

    // Single centred capture tile (lattice is 100 cols wide; centre col = 50) with the controls
    // stacked below it, on-screen. The tile's GridRegion `w == h == captureFoot`.
    private enum Layout {
        static let captureCol = 8, captureRow = 26, captureFoot = 84  // 64³ capture (336 pt), centred
        static let labelH = 5
        static let controlsCol = 22, controlsRow = 122, controlsW = 56, controlsH = 10
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.clear

            label("CAPTURE", col: Layout.captureCol, row: Layout.captureRow - 6, w: Layout.captureFoot)
            captureTile.place(region("capture64", Layout.captureCol, Layout.captureRow, Layout.captureFoot))

            controls.place(GridRegion(name: "reviewControls",
                                      col: Layout.controlsCol, row: Layout.controlsRow,
                                      w: Layout.controlsW, h: Layout.controlsH,
                                      widget: 9, priority: 9, interactive: true))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .ignoresSafeArea()
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Review the captured GIF")
    }

    // MARK: - Tile (a bitmap in a footprint; pixel density is independent of the atom)

    /// The 64³ capture: 64 source voxels in a 64-cell footprint (4 pt/cell), the committed index
    /// cube read through its per-frame palette at the live cursor. The one honest artifact: exactly
    /// what the camera captured and collapsed, with no invented super-resolution rung above it.
    private var captureTile: some View {
        let t = surface.cursor
        return scaleTile(source: 64, footprint: Layout.captureFoot) { c, r in surface.gifCell(c, r, t) }
    }

    /// Render `source × source` voxels into a `footprint`-cell box. `cellPt = footprintPt / source`,
    /// so the placement footprint stays an integer number of 4 pt atoms.
    private func scaleTile(source: Int, footprint: Int,
                           _ cell: @escaping (Int, Int) -> SIMD3<UInt8>?) -> some View {
        let cellPt = GlobalLattice.gif(footprint) / CGFloat(source)
        return CellSprite(cols: source, rows: source, cellPt: cellPt) { c, r in cell(c, r) ?? ghost }
            .allowsHitTesting(false)
    }

    // MARK: - Chrome

    private func label(_ text: String, col: Int, row: Int, w: Int) -> some View {
        CellText(text, rows: Layout.labelH, ink: labelInk)
            .place(GridRegion(name: "label_\(text)", col: col, row: row, w: w, h: Layout.labelH,
                              widget: 8, priority: 8, interactive: false))
    }

    private func region(_ name: String, _ col: Int, _ row: Int, _ foot: Int) -> GridRegion {
        GridRegion(name: name, col: col, row: row, w: foot, h: foot,
                   widget: 1, priority: 1, interactive: false)
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
            .accessibilityLabel("Export the GIF and the probability-field training data")
        }
    }

    /// Forward to export. With A/B retired, accepting the capture is the single modeled edge out
    /// of `.captured` (`pickA`); from `.picked`, `exportFamily` enters `.exporting`, which advances
    /// to `.done`, where the GIF and the probability-field `.npy` bin ship together as one bundle.
    private func export() {
        if surface.phase == .captured { surface.step(.pickA) }
        surface.step(.exportFamily)
    }

    private func retake() { surface.step(.retake) }
}
