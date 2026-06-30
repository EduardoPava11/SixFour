import SwiftUI
import simd

/// Π for the post-capture REVIEW phases (`.captured` / `.picked`) — the tri-scale review
/// PYRAMID that replaced the retired A/B game. The three octree tiers grow downward and are
/// evenly spaced, centred on the one 4 pt lattice:
///
///        16   ·  the byte-exact octree coarse  (VoxelReduce substrate)
///       64    ·  the captured cube              (indexCube × per-frame palette)
///     256     ·  the super-res rung             (floor today; the model's invented 256³ later)
///
/// All three play on the shared Z₆₄ cursor (`SurfaceView` advances it every κ tick), with
/// EXPORT / RETAKE controls. The cell grid is a PLACEMENT lattice, not a per-pixel canvas: a
/// tile is a bitmap placed in a cell region, so a finer rung lives in a larger footprint at
/// sub-atom pixels without ever breaking the 4 pt atom.
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

    // Centred footprints (lattice is 100 cols wide; centre col = 50), growing downward into a
    // pyramid, with even 6-cell gaps between blocks. Each tile's GridRegion `w == h == footprint`.
    private enum Layout {
        static let coarseCol = 42, coarseRow = 14, coarseFoot = 16   // 16³ apex  (64 pt)
        static let captureCol = 18, captureRow = 42, captureFoot = 64 // 64³ middle (256 pt)
        static let superCol = 8, superRow = 118, superFoot = 84       // 256³ base  (336 pt)
        static let labelH = 5
        static let controlsCol = 22, controlsRow = 208, controlsW = 56, controlsH = 10
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.clear

            label("16", col: Layout.coarseCol, row: Layout.coarseRow - 6, w: Layout.coarseFoot)
            coarseTile.place(region("coarse16", Layout.coarseCol, Layout.coarseRow, Layout.coarseFoot))

            label("64", col: Layout.captureCol, row: Layout.captureRow - 6, w: Layout.captureFoot)
            captureTile.place(region("capture64", Layout.captureCol, Layout.captureRow, Layout.captureFoot))

            label("256", col: Layout.superCol, row: Layout.superRow - 6, w: Layout.superFoot)
            superTile.place(region("super256", Layout.superCol, Layout.superRow, Layout.superFoot))

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
        .accessibilityLabel("Review the captured GIF across scales")
        // V2.1: inspect the two widgets full-screen, or AirDrop the GIF + field tensor.
        .fullScreenCover(isPresented: $showField) {
            if let f = fieldData { V21WidgetSurface(field: f) } else { Color.black }
        }
        .sheet(isPresented: $showShare) { ActivityView(items: shareItems) }
    }

    // MARK: - Tiles (each a bitmap in a footprint; pixel density is independent of the atom)

    /// The 16³ octree coarse: 16 source voxels in a 16-cell footprint (4 pt/cell), the byte-exact
    /// `VoxelReduce` substrate at the coarse cursor (`cursor / 4`, the ×4 temporal reduction).
    private var coarseTile: some View {
        let t16 = surface.cursor / 4
        return scaleTile(source: 16, footprint: Layout.coarseFoot) { c, r in surface.gifCell16(c, r, t16) }
    }

    /// The 64³ capture: 64 source voxels in a 64-cell footprint (4 pt/cell), the committed index
    /// cube read through its per-frame palette at the live cursor.
    private var captureTile: some View {
        let t = surface.cursor
        return scaleTile(source: 64, footprint: Layout.captureFoot) { c, r in surface.gifCell(c, r, t) }
    }

    /// The 256³ rung. TODAY it is the deterministic FLOOR: the 64³ source rendered into the larger
    /// footprint with no interpolation, which is pixel-identical to a true 256³ nearest-neighbour
    /// floor (4×4 block replication = zero invented detail). MODEL SLOT: when the learned head
    /// deploys, swap `source: 64` + `gifCell` for `source: 256` + a `gifCell256` reading the
    /// invented 256³, and this tile shows the model's added detail in the same footprint.
    private var superTile: some View {
        let t = surface.cursor
        return scaleTile(source: 64, footprint: Layout.superFoot) { c, r in surface.gifCell(c, r, t) }
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
                CellActionButton(icon: .none, title: "AIRDROP", prominent: false, fillWidth: false)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("AirDrop the GIF and the probability field tensor")
        }
    }

    /// Build the per-bin temporal probability field from the committed burst (real capture data).
    private func builtField() -> V21FieldData? {
        V21FieldData.fromCapture(indexCube: surface.indexCube,
                                 palettesPerFrame: surface.palettesPerFrame,
                                 side: surface.cubeSide)
    }

    private func openField() {
        fieldData = builtField()
        if fieldData != nil { showField = true }
    }

    private func airdrop() {
        guard let f = builtField() else { return }
        shareItems = V21Export.shareItems(field: f, gifURL: surface.gifURL)
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
