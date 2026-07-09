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

    // Single capture tile on the LOCKED SCENE ANCHOR — the identical (col 18, row 16, 64×64)
    // that capture + decide dock the scene at, so the scene never resizes or jumps as you move
    // capture → captured → decide. Centred (cols 18–82 ⇒ centre col 50) with the label below it
    // (row 16 is under the Dynamic Island, so the title cannot ride above the scene) and the
    // controls stacked lower. The tile's GridRegion `w == h == captureFoot`.
    private enum Layout {
        static let captureCol = 18, captureRow = 16, captureFoot = 64  // 64³ capture (256 pt), the anchor
        static let labelH = 5
        // The 16³/32³/64³ view toggle, centred (cols 26–74 ⇒ centre 50) below the scene + label.
        static let rungCol = 26, rungRow = 90, rungW = 48, rungH = 8
        static let controlsCol = 22, controlsRow = 122, controlsW = 56, controlsH = 10
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.clear

            captureTile.place(region("capture64", Layout.captureCol, Layout.captureRow, Layout.captureFoot))
            // Below the scene (row 16 clears the island for the tile, not for text above it).
            label("CAPTURE", col: Layout.captureCol,
                  row: Layout.captureRow + Layout.captureFoot + 1, w: Layout.captureFoot)
            rungToggle.place(GridRegion(name: "rungToggle", col: Layout.rungCol, row: Layout.rungRow,
                                        w: Layout.rungW, h: Layout.rungH,
                                        widget: 7, priority: 7, interactive: true))

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

    /// The capture at the SELECTED rung (`surface.sceneRung`): `rung.side` source voxels rendered
    /// into the SAME 64-cell footprint, so a coarser rung reads as chunkier (block-replicated),
    /// never smaller — the scene never moves or resizes. All three rungs are byte-exact pools of
    /// exactly what the camera captured; no invented super-resolution rung is ever offered.
    private var captureTile: some View {
        let t = surface.cursor
        let rung = surface.sceneRung
        return scaleTile(source: rung.side, footprint: Layout.captureFoot) { c, r in
            surface.sceneCell(c, r, cursor: t, rung: rung)
        }
    }

    /// The 16³ / 32³ / 64³ view toggle — three tap segments that walk the honest cube rungs. The
    /// active rung is inked bright; the coarser you go, the chunkier the SAME scene reads. This is
    /// the UI made an honest reflection of what the photons gave us: three exact resolutions, no
    /// invention. (256³ is deliberately not a segment.)
    private var rungToggle: some View {
        HStack(spacing: GlobalLattice.pt(2)) {
            ForEach(SceneRung.allCases, id: \.rawValue) { rung in
                let active = surface.sceneRung == rung
                Button { surface.sceneRung = rung } label: {
                    CellText(rung.label, rows: Layout.rungH,
                             ink: active ? Color(srgb8: SIMD3<UInt8>(235, 235, 235))
                                         : Color(srgb8: SIMD3<UInt8>(110, 110, 116)))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Show the \(rung.label) view")
                .accessibilityAddTraits(active ? [.isSelected] : [])
            }
        }
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
        // DECIDE rides its OWN row: three cell buttons overflow the control row's
        // width (device-observed overlap, 2026-07-01), and the decide loop is a
        // separate concern from the retake/export pair anyway.
        VStack(spacing: GlobalLattice.pt(4)) {
            if Feature.v3SomaticTrain, surface.phase == .captured {
                Button { surface.step(.beginDecide) } label: {
                    CellActionButton(icon: .none, title: "DECIDE", prominent: false, fillWidth: false)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Iterate the 16³ proposal before export")
            }

            // LAUNCH L1.3: the curate excursion is offered once a decide-accept
            // stashed its input (entry gated Picked-only, lawCurateEntryGated).
            if Feature.v3SomaticTrain, surface.phase == .picked, surface.acceptedInput != nil {
                Button { surface.step(.beginCurate) } label: {
                    CellActionButton(icon: .none, title: "CURATE", prominent: false, fillWidth: false)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Inspect and iterate the build before export")
            }

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
