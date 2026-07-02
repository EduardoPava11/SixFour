import SwiftUI
import CoreGraphics

/// THE LAUNCH CURATE SURFACE (L1.3): the `Curating` phase's screen — a Picked
/// self-excursion where the user inspects and iterates the build the octant
/// ladder produced from their accepted 16³. Widgets live on the proven lattice
/// (`GridLayoutContract.curateScene`, all eight GridLayout laws green) via the
/// ONE sanctioned `place(_:in:)` composer — this file hand-places nothing.
///
/// FORM FOLLOWS FUNCTION — every live widget fronts a GATED engine call:
///   * hero    — the REAL build: `CurateBuilder.build` (GPU ladder, byte-equal
///     to the Zig oracle and to `OctantCube.expandProposal` — `CurateBuilderTests`
///     gates 1–2); horizontal drag scrubs t. Shown at the 64³ inspection tier:
///     the SAME operator the 256³ export iterates (the full-frame 256² realize
///     awaits the quantizer-scaling row — documented, not faked).
///   * slabs   — the t-rail: 16 slab cells over the 64 frames; tap jumps the
///     scrub (frame-locality/block-locality make slabs the streaming unit).
///   * source  — floor / my gene (adopted arm arrives with the gene store,
///     L2.9; the cell shows it gated, like decide's gene cell without a gene).
///   * repaint — PRESENT-BUT-GATED: re-entering the 16³ paint bench needs a
///     Curating→Deciding FSM edge that does not exist yet; the cell reports the
///     recorded paint honestly instead of faking an entry.
///   * rebuild — re-runs the ladder with the current knobs (the iterate verb).
///   * accept  — commits the curated choice (σ records it) and fires
///     `CurateDone` → Picked (export-eligible; the FSM golden proven in spec).
enum CurateVerdict {
    case accept
}

/// Observable curate state: the built arms (floor + gene), the scrub, the
/// source toggle. GPU-first (`CurateBuilder`), CPU fallback
/// (`OctantCube.expandProposal`) — byte-identical BY GATE, so the fallback is
/// a proof-backed substitution, not a different picture.
@MainActor
final class CurateModel: ObservableObject {
    let substrate: [[VoxelReduce.Px]]
    let gene: CaptureGene.ThetaUp?
    let paintedCells: Int

    private var floorVol: [Int32]?
    private var geneVol: [Int32]?
    @Published private(set) var buildReady = false
    @Published private(set) var buildCount = 0   // telemetry: rebuilds this session

    @Published var useGene: Bool
    @Published var frame: Int = 0

    /// The inspection tier's cube side (16³ substrate × 2 rungs).
    static let side = 64
    /// Slab cells on the rail (frames per slab = side / slabCount).
    static let slabCount = 16

    init(substrate: [[VoxelReduce.Px]], gene: CaptureGene.ThetaUp?,
         useGene: Bool, paintedCells: Int = 0) {
        self.substrate = substrate
        self.gene = gene
        self.useGene = useGene && gene != nil
        self.paintedCells = paintedCells
        rebuild()
    }

    /// (Re-)run the ladder off-main: both arms, GPU-first. The iterate verb.
    func rebuild() {
        guard !substrate.isEmpty else { return }
        buildReady = false
        let sub = substrate
        let theta = gene.map { g in g.theta.map(Double.init) }
        let channel = gene?.channel ?? 0
        Task { [weak self] in
            let (f, g) = await Self.buildArms(sub: sub, theta: theta, channel: channel)
            guard let self else { return }
            self.floorVol = f
            self.geneVol = g
            self.buildReady = true
            self.buildCount += 1
        }
    }

    private nonisolated static func buildArms(sub: [[VoxelReduce.Px]], theta: [Double]?,
                                              channel: Int) async -> ([Int32]?, [Int32]?) {
        await Task.detached(priority: .userInitiated) {
            if let builder = CurateBuilder() {
                let f = builder.build(substrate: sub, theta: nil, rungs: 2)
                let g = theta.flatMap {
                    builder.build(substrate: sub, theta: $0, geneChannel: channel, rungs: 2)
                }
                return (f, g)
            }
            // No Metal: the CPU twin — byte-identical by CurateBuilderTests gate 1.
            let f = OctantCube.expandProposal(substrate: sub, theta: nil)
            let g = theta.flatMap {
                OctantCube.expandProposal(substrate: sub, theta: $0, geneChannel: channel)
            }
            return (f, g)
        }.value
    }

    var volume: [Int32]? {
        guard buildReady else { return nil }
        return (useGene && geneVol != nil) ? geneVol : floorVol
    }

    /// The scrubbed frame as display RGBA (display-only conversion; the
    /// byte-exact pipeline is never re-entered here).
    func slice(frame f: Int) -> [UInt8]? {
        guard let vol = volume, f >= 0, f < Self.side else { return nil }
        let s = Self.side
        var rgba = [UInt8]()
        rgba.reserveCapacity(s * s * 4)
        let base = f * s * s
        for p in 0 ..< s * s {
            let i = (base + p) * 3
            let c = ModelRender.displaySRGB8(
                SIMD3<Int>(Int(vol[i]), Int(vol[i + 1]), Int(vol[i + 2])))
            rgba.append(contentsOf: [c.x, c.y, c.z, 255])
        }
        return rgba
    }

    var slab: Int { frame * Self.slabCount / Self.side }

    func jump(toSlab s: Int) {
        frame = min(Self.side - 1, max(0, s * (Self.side / Self.slabCount)))
    }
}

struct CurateSurface: View {
    @StateObject private var model: CurateModel
    private let onCurate: (CurateVerdict, Bool) -> Void
    private let scene = GridLayoutContract.curateScene

    @MainActor
    init(substrate: [[VoxelReduce.Px]], thetaUp: CaptureGene.ThetaUp?,
         useGene: Bool, paintedCells: Int,
         onCurate: @escaping (CurateVerdict, Bool) -> Void) {
        _model = StateObject(wrappedValue: CurateModel(
            substrate: substrate, gene: thetaUp, useGene: useGene,
            paintedCells: paintedCells))
        self.onCurate = onCurate
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.black.ignoresSafeArea()
            CurateHeroWidget(model: model).place("hero", in: scene)
            slabRail.place("slabs", in: scene)
            sourceCell.place("source", in: scene)
            repaintCell.place("repaint", in: scene)
            rebuildCell.place("rebuild", in: scene)
            acceptCell.place("accept", in: scene)
        }
        .ignoresSafeArea()
    }

    private var slabRail: some View {
        HStack(spacing: 0) {
            ForEach(0 ..< CurateModel.slabCount, id: \.self) { s in
                Rectangle()
                    .fill(s == model.slab ? Color.white : Color.white.opacity(0.14))
                    .overlay(Rectangle().stroke(Color.black, lineWidth: 1))
                    .onTapGesture { model.jump(toSlab: s) }
            }
        }
        .accessibilityLabel("Frame slab rail — tap to jump the scrub")
    }

    private var sourceCell: some View {
        CurateCell(label: model.useGene ? "gene" : "floor",
                   active: model.useGene,
                   enabled: model.gene != nil) {
            model.useGene.toggle()
        }
    }

    private var repaintCell: some View {
        // GATED: no Curating→Deciding FSM edge exists yet; report the recorded
        // paint honestly rather than fake an entry (see the header).
        CurateCell(label: "paint \(model.paintedCells)", active: false, enabled: false) {}
    }

    private var rebuildCell: some View {
        CurateCell(label: model.buildReady ? "rebuild" : "building…",
                   active: false, enabled: model.buildReady) {
            model.rebuild()
        }
    }

    private var acceptCell: some View {
        CurateCell(label: "accept", active: true, enabled: model.buildReady) {
            onCurate(.accept, model.useGene)
        }
    }
}

/// A lattice-styled curate cell (the decide-cell idiom: fills its proven
/// region, no free frames).
private struct CurateCell: View {
    let label: String
    let active: Bool
    var enabled: Bool = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.system(.caption, design: .monospaced).weight(.semibold))
                .foregroundStyle(enabled ? (active ? Color.black : Color.white) : Color.gray)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(active && enabled ? Color.white : Color.white.opacity(0.12))
                .overlay(Rectangle().stroke(Color.white.opacity(0.25), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }
}

/// The hero: the scrubbed frame of the REAL build (nearest-neighbour, no
/// interpolation), with the tier and arm named on-face — never a faked image.
private struct CurateHeroWidget: View {
    @ObservedObject var model: CurateModel

    var body: some View {
        GeometryReader { geo in
            Group {
                if let rgba = model.slice(frame: model.frame),
                   let cg = Self.rgbaImage(rgba, side: CurateModel.side) {
                    Image(decorative: cg, scale: 1)
                        .interpolation(.none)
                        .resizable()
                } else {
                    Color.white.opacity(0.06)
                        .overlay(Text("building…")
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.6)))
                }
            }
            .overlay(alignment: .bottomLeading) {
                Text("t \(model.frame)/\(CurateModel.side - 1) · 64³ tier · \(model.useGene ? "gene" : "floor") · build \(model.buildCount)")
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.7))
                    .padding(GlobalLattice.gif(1))
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0).onChanged { g in
                    let t = Int(g.location.x / geo.size.width * CGFloat(CurateModel.side))
                    model.frame = min(CurateModel.side - 1, max(0, t))
                }
            )
        }
    }

    static func rgbaImage(_ rgba: [UInt8], side: Int) -> CGImage? {
        guard rgba.count == side * side * 4,
              let provider = CGDataProvider(data: Data(rgba) as CFData) else { return nil }
        return CGImage(width: side, height: side, bitsPerComponent: 8, bitsPerPixel: 32,
                       bytesPerRow: side * 4, space: CGColorSpaceCreateDeviceRGB(),
                       bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                       provider: provider, decode: nil, shouldInterpolate: false,
                       intent: .defaultIntent)
    }
}
