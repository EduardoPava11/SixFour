import SwiftUI
import simd

/// Π for the post-capture REVIEW phases (`.captured` / `.picked`): the SINGLE honest artifact,
/// the captured 64³ GIF, plus the controls to EXPORT it, RETAKE, or (V2.1) AirDrop the training
/// data.
///
/// The tri-scale 16 / 64 / 256 review PYRAMID was DEPRECATED (2026-06-30): the 256³ tier only
/// nearest-neighbour-upscaled the same 64³ data and labelled it "256" as if a model had invented
/// detail. The learned head is NOT ported yet, so that tier was a lie, and its footprint pushed the
/// AIRDROP control off the bottom of the screen. Until a real `gifCell256` exists, this screen shows
/// exactly what was captured and nothing it cannot back up. (The old `gifCell16` coarse and the model
/// super-res slot live in git history / `SixFour.Spec.Upscale256` for when the head deploys.)
///
/// The GIF plays on the shared Z₆₄ cursor (`SurfaceView` advances it every κ tick). The cell grid is a
/// PLACEMENT lattice, not a per-pixel canvas: the tile is a bitmap placed in a cell region, so it lives
/// in a large footprint at sub-atom pixels without ever breaking the 4 pt atom.
struct CapturedReviewPhaseField: View {
    let surface: Surface
    let clock: SurfaceClock

    private let ghost = SIMD3<UInt8>(20, 20, 24)
    private let labelInk = Color(srgb8: SIMD3<UInt8>(190, 190, 190))

    // V2.1 review extras (gated by Feature.v21Capture): inspect the probability field through the two
    // widgets, and AirDrop the GIF + the field tensor. Off in MVP1, so these never mount.
    @State private var showField = false
    @State private var fieldData: V21FieldData?
    @State private var shareItems: [Any] = []
    @State private var showShare = false

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

            if Feature.v21Capture {
                v21Controls.place(GridRegion(name: "v21Controls",
                                             col: Layout.controlsCol, row: Layout.controlsRow + 12,
                                             w: Layout.controlsW, h: Layout.controlsH,
                                             widget: 9, priority: 9, interactive: true))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .ignoresSafeArea()
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Review the captured GIF")
        // V2.1: inspect the two widgets full-screen, or AirDrop the GIF + field tensor.
        .fullScreenCover(isPresented: $showField) {
            if let f = fieldData { V21WidgetSurface(field: f) } else { Color.black }
        }
        .sheet(isPresented: $showShare) { ActivityView(items: shareItems) }
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
    /// so a coarser source in a larger footprint nearest-neighbour-upscales (no interpolation) and
    /// the placement footprint stays an integer number of 4 pt atoms.
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
            .accessibilityLabel("Export the reviewed GIF")
        }
    }

    /// V2.1 controls (gated): FIELD opens the two probability widgets full-screen; AIRDROP shares the
    /// GIF and the field tensor (`.npy`). Both build the field from the committed burst.
    private var v21Controls: some View {
        HStack(spacing: GlobalLattice.pt(6)) {
            Button { openField() } label: {
                CellActionButton(icon: .none, title: "FIELD", prominent: false, fillWidth: false)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Inspect the V2.1 probability widgets")

            Button { airdrop() } label: {
                CellActionButton(icon: .none, title: "AIRDROP", prominent: true, fillWidth: false)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("AirDrop the GIF and the probability field tensor as training data")
        }
    }

    /// Build the probability field for the widgets / AirDrop, tagged with its provenance. Prefer the GPU
    /// camera-box field (`surface.v21Counts`, the true fine-grid histogram pooled over the burst); fall
    /// back to the index-cube temporal proxy when the GPU field is unavailable (flag off or allocation
    /// failed). The source travels into the AirDrop manifest so the receiver knows which field it got.
    private func builtField() -> (field: V21FieldData, source: V21FieldSource)? {
        let side = surface.cubeSide
        if let counts = surface.v21Counts, counts.count == side * side * 3 * 256 {
            return (V21FieldData(side: side, nLevels: 256, counts: counts), .cameraBox)
        }
        if let f = V21FieldData.fromCapture(indexCube: surface.indexCube,
                                            palettesPerFrame: surface.palettesPerFrame,
                                            side: side) {
            return (f, .temporalProxy)
        }
        return nil
    }

    private func openField() {
        fieldData = builtField()?.field
        if fieldData != nil { showField = true }
    }

    private func airdrop() {
        guard let built = builtField() else { return }
        shareItems = V21Export.shareItems(field: built.field, source: built.source, gifURL: surface.gifURL)
        if !shareItems.isEmpty { showShare = true }
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
