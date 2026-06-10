import SwiftUI
import simd

/// COLOR ATLAS — the 16³ board as cells (docs/COLOR-ATLAS.md §8 Phase C).
///
/// The board is projected as 16 scrubbable L-slices; each slice is a 16×16 grid
/// of (a, b) bins drawn as one `CellSprite` (4×4 atoms per bin → a 64-cell-wide
/// block, the hero's footprint). Pure GRID vocabulary: `CellText` / `CellSprite`
/// / `CellSlider` / `CellActionButton` at `GlobalLattice` pitches — no glass, no
/// AA, no raw vectors. A tap plays the CURRENT MODE's curation move on the
/// tapped bin (ToggleBin / WeightRegion± / PinAnchor — all four Move types are
/// reachable here + the gallery's Compare).
///
/// Cell encoding (per 4×4-atom bin):
///   * occupied (ch0 > 0)  → the bin-centre OKLab colour ("the map" — colour as space);
///   * killed (ch4)        → a 2×2 dark-red checker (Law #2: no opacity dimming);
///   * anchored (ch5)      → a white 1-atom border ring;
///   * weighted (ch3 ≠ 0)  → a green (+) / red (−) 1-atom border ring;
///   * empty               → near-black ground (the grid stays legible).
struct AtlasBoardView: View {
    @Bindable var atlas: AtlasState

    /// Atoms per bin edge: 4 ⇒ 16 bins × 4 atoms = 64 cells = the 256 pt block.
    private let binAtoms = 4
    private var binCells: Int { AtlasBinIdx.perAxis * binAtoms }
    private var binPitch: CGFloat { GlobalLattice.gif(binAtoms) }

    var body: some View {
        VStack(spacing: GlobalLattice.pt(2)) {
            CellText(header, rows: 8, ink: Color(srgb8: SIMD3<UInt8>(200, 200, 200)))

            boardSprite
                .contentShape(Rectangle())
                .gesture(SpatialTapGesture().onEnded { tap($0.location) })
                .accessibilityLabel("Atlas board, L slice \(atlas.slice) of 15")

            CellSlider(value: sliceBinding, range: 0...15, step: 1)
                .accessibilityLabel("L slice")

            modeRow
        }
    }

    private var header: String {
        let mode: String
        switch atlas.mode {
        case .toggle:     mode = "KILL/KEEP"
        case .weightUp:   mode = "WEIGHT +"
        case .weightDown: mode = "WEIGHT -"
        case .pin:        mode = "PIN"
        }
        return String(format: "L %02d/15 · %@", atlas.slice, mode)
    }

    // MARK: the slice sprite (16×16 bins, 4×4 atoms each)

    private var boardSprite: some View {
        let board = atlas.board
        let slice = atlas.slice
        return CellSprite(cols: binCells, rows: binCells, cellPt: GlobalLattice.gifPx) { c, r in
            let bin = AtlasBinIdx(l: slice, a: c / binAtoms, b: r / binAtoms)
            let flat = bin.flat
            let sx = c % binAtoms, sy = r % binAtoms
            let onBorder = sx == 0 || sy == 0 || sx == binAtoms - 1 || sy == binAtoms - 1

            if board.anchorMask[flat] > 0.5, onBorder {
                return SIMD3<UInt8>(255, 255, 255)                       // anchored ring
            }
            if board.killMask[flat] > 0.5 {                              // killed checker
                let on = ((sx / 2) + (sy / 2)) % 2 == 0
                return on ? SIMD3<UInt8>(96, 24, 24) : SIMD3<UInt8>(28, 10, 10)
            }
            let w = board.weightField[flat]
            if w > 0, onBorder { return SIMD3<UInt8>(80, 210, 100) }     // boosted ring
            if w < 0, onBorder { return SIMD3<UInt8>(210, 80, 80) }      // suppressed ring

            if board.binMassPalettes[flat] > 0 {
                return AtlasState.srgb8(bin.centerQ16)                   // occupied: bin colour
            }
            return SIMD3<UInt8>(14, 14, 16)                              // empty ground
        }
    }

    /// Local tap point → bin (a = column, b = row) on the CURRENT L slice.
    private func tap(_ p: CGPoint) {
        let n = AtlasBinIdx.perAxis
        let a = min(n - 1, max(0, Int(p.x / binPitch)))
        let b = min(n - 1, max(0, Int(p.y / binPitch)))
        atlas.tap(bin: AtlasBinIdx(l: atlas.slice, a: a, b: b))
    }

    // MARK: slice + mode controls

    private var sliceBinding: Binding<Double> {
        Binding(
            get: { Double(atlas.slice) },
            set: { atlas.slice = min(15, max(0, Int($0.rounded()))) }
        )
    }

    private var modeRow: some View {
        HStack(spacing: GlobalLattice.pt(2)) {
            modeButton(.toggle, "KILL")
            modeButton(.weightUp, "W+")
            modeButton(.weightDown, "W-")
            modeButton(.pin, "PIN")
        }
    }

    private func modeButton(_ mode: AtlasState.EditMode, _ title: String) -> some View {
        Button { atlas.mode = mode } label: {
            CellActionButton(icon: .none, title: title, prominent: atlas.mode == mode)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Mode \(title)")
    }
}
