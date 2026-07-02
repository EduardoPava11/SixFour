import SwiftUI
import Combine

/// THE V3.0 DECISION SURFACE (workflow C1, `docs/V3-BUILD-WORKFLOW.md`): the
/// post-capture screen where the user iterates the 16³ proposal until they like
/// it. Every widget is one user-CHANGEABLE model-boundary knob, placed on the
/// proven lattice (`GridLayoutContract.decisionScene`, all eight GridLayout laws
/// green) via the ONE sanctioned `place(_:in:)` composer — this file hand-places
/// nothing.
///
/// The knobs, grounded in `SixFourModelInput` + the V3 somatic gene:
///   * preview  — the rendered result; horizontal drag scrubs the frame (and
///     derives the paint layer: 64 burst frames → 16 control layers, t/4).
///   * paint    — the 16³×9 `CellBudget` (`miNudge`), 16 pt per control cell.
///   * channels — which of the 9 ChannelProduct colour×space pairs the brush paints.
///   * gauge    — the φ6 toggle (`miGauge`).
///   * gene     — the SOMATIC θ_up toggle: learned invention vs the deterministic
///     floor. Disabled (floor) when the burst carried no gene — zero-gene == floor
///     makes OFF always safe.
///   * again / accept — the verdict (the decision stream the Identity preference
///     head will later train on).
///
/// The preview shows the REAL reconstruction: the 16³ proposal
/// (`Surface.coarseSubstrate`) up-rung'd to 64³ by `OctantCube.expandProposal` —
/// the deterministic floor, or the gene's invention when the toggle rides θ_up.
/// Never a faked image (the `NudgePaintView` honesty rule); without a substrate
/// it falls back to the capture frame. Paint conditions the LEARNED model (the
/// accepted input records it); it does not yet alter this preview.
enum DecideVerdict {
    case accept
    case again
}

/// Observable decision state: the paint model (nudge + gauge), the gene toggle,
/// and the preview scrub. `modelInput()` is the wireable boundary. MainActor:
/// this is UI state, and the off-main reconstruction build delivers back here.
@MainActor
final class DecideModel: ObservableObject {
    let tiles: [OKLabTile]
    let gene: CaptureGene.ThetaUp?
    /// The REAL 16³ proposal — the lossless coarse tier of the committed cube
    /// (`Surface.coarseSubstrate`, 16 frames × 16² OKLab Q16). Empty until a
    /// capture commits (then the surface falls back to capture-frame preview).
    let substrate: [[VoxelReduce.Px]]
    let paint = NudgePaintModel()

    /// Cached 64³ reconstructions (interleaved Q16): the deterministic floor and
    /// the gene's invention — both built by the REAL up-rung (`OctantCube.expandProposal`),
    /// so the preview is never a faked image. Built OFF-MAIN once at init (device
    /// audit: the synchronous build blocked first render ~0.5 s); the preview shows
    /// the capture-frame fallback until `reconstructionsReady`.
    private var floorRecon: [Int32]?
    private var geneRecon: [Int32]?
    @Published private(set) var reconstructionsReady = false

    /// `paint` is a NESTED ObservableObject — its mutations (gauge toggle, strokes)
    /// do not propagate through DecideModel automatically (device audit: the gauge
    /// button never repainted). Forward them.
    private var paintForward: AnyCancellable?

    /// Ride the learned somatic detail (true) or the deterministic floor (false).
    /// Defaults to the gene when the burst trained one; absence pins the floor.
    @Published var useGene: Bool
    /// The previewed burst frame (0-based); horizontal drag on the preview scrubs it.
    @Published var frame: Int = 0
    /// The brush's paint channel (default L·t, the φ6 diagonal value-over-time pair).
    @Published var channel: Int = 8
    /// The budget magnitude a stroke paints.
    let brush: Int = 32

    init(tiles: [OKLabTile], gene: CaptureGene.ThetaUp?,
         substrate: [[VoxelReduce.Px]] = []) {
        self.tiles = tiles
        self.gene = gene
        self.substrate = substrate
        self.useGene = gene != nil
        paintForward = paint.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
        buildReconstructions()
    }

    /// Build both reconstruction arms off the main thread (each ~0.1–0.8 s debug);
    /// publish when ready. The gene arm honours the gene's TRAINED channel.
    private func buildReconstructions() {
        guard !substrate.isEmpty else { return }
        let sub = substrate
        let theta = gene.map { g in g.theta.map(Double.init) }
        let channel = gene?.channel ?? 0
        Task { [weak self] in
            let (floor, geneArm) = await Self.buildArms(sub: sub, theta: theta, channel: channel)
            guard let self else { return }
            self.floorRecon = floor
            self.geneRecon = geneArm
            self.reconstructionsReady = true
        }
    }

    /// The pure off-main build (only Sendable value types cross the boundary).
    private nonisolated static func buildArms(sub: [[VoxelReduce.Px]], theta: [Double]?,
                                              channel: Int) async -> ([Int32]?, [Int32]?) {
        await Task.detached(priority: .userInitiated) {
            let floor = OctantCube.expandProposal(substrate: sub, theta: nil)
            let geneArm = theta.flatMap {
                OctantCube.expandProposal(substrate: sub, theta: $0, geneChannel: channel)
            }
            return (floor, geneArm)
        }.value
    }

    /// The 64³ reconstruction the preview shows (floor or gene) — nil until a
    /// substrate exists. Cached per arm; the gene arm falls back to the floor
    /// when no gene was trained (zero-gene == floor).
    func reconstruction(useGene: Bool) -> [Int32]? {
        guard reconstructionsReady else { return nil }   // fallback shows meanwhile
        return (useGene && geneRecon != nil) ? geneRecon : floorRecon
    }

    /// The proposal's own colour at control cell (x, y, layer) — the 16³ voxel,
    /// display-converted. nil without a substrate.
    func proposalSRGB8(x: Int, y: Int, layer: Int) -> SIMD3<UInt8>? {
        guard layer >= 0, layer < substrate.count,
              x >= 0, x < 16, y >= 0, y < 16 else { return nil }
        let px = substrate[layer][y * 16 + x]
        return ModelRender.displaySRGB8(SIMD3<Int>(px.0, px.1, px.2))
    }

    /// One 64×64 frame slice of the reconstruction as RGBA (display-only
    /// conversion; the Q16 volume itself is the byte-exact object).
    func reconstructionSlice(frame: Int, useGene: Bool) -> [UInt8]? {
        guard let vol = reconstruction(useGene: useGene),
              frame >= 0, frame < 64 else { return nil }
        var rgba = [UInt8](); rgba.reserveCapacity(64 * 64 * 4)
        let base = frame * 64 * 64
        for p in 0 ..< 64 * 64 {
            let i = (base + p) * 3
            let c = ModelRender.displaySRGB8(
                SIMD3<Int>(Int(vol[i]), Int(vol[i + 1]), Int(vol[i + 2])))
            rgba.append(contentsOf: [c.x, c.y, c.z, 255])
        }
        return rgba
    }

    /// The 16³ paint layer the scrubbed frame governs (64 burst frames → 16
    /// control layers: t/4 — one time scrubber drives both widgets).
    var paintLayer: Int {
        guard !tiles.isEmpty else { return 0 }
        return min(NudgePaintModel.side - 1,
                   frame * NudgePaintModel.side / max(1, tiles.count))
    }

    /// The wireable model boundary (zero paint ⇒ the byte-exact floor).
    func modelInput() -> SixFourModelInput {
        paint.modelInput(captureHandle: 0)
    }
}

struct DecideSurface: View {
    @StateObject private var model: DecideModel
    private let onDecide: (DecideVerdict, SixFourModelInput, Bool) -> Void
    private let scene = GridLayoutContract.decisionScene

    @MainActor
    init(tiles: [OKLabTile], thetaUp: CaptureGene.ThetaUp?,
         substrate: [[VoxelReduce.Px]] = [],
         onDecide: @escaping (DecideVerdict, SixFourModelInput, Bool) -> Void) {
        _model = StateObject(wrappedValue: DecideModel(
            tiles: tiles, gene: thetaUp, substrate: substrate))
        self.onDecide = onDecide
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.black.ignoresSafeArea()
            DecidePreviewWidget(model: model).place("preview", in: scene)
            DecidePaintWidget(model: model, paint: model.paint).place("paint", in: scene)
            channelStrip.place("channels", in: scene)
            gaugeCell.place("gauge", in: scene)
            geneCell.place("gene", in: scene)
            againCell.place("again", in: scene)
            acceptCell.place("accept", in: scene)
        }
        .ignoresSafeArea()
    }

    // ── channels: which colour×space pair the brush paints ──────────────────

    private var channelStrip: some View {
        Picker("Channel", selection: $model.channel) {
            ForEach(0 ..< NudgeChannel.labels.count, id: \.self) { i in
                Text(NudgeChannel.labels[i]).tag(i)
            }
        }
        .pickerStyle(.segmented)
    }

    // ── the four decision cells ──────────────────────────────────────────────

    private var gaugeCell: some View {
        DecideCell(label: model.paint.gauge ? "φ6 dual" : "c × s",
                   active: model.paint.gauge) {
            model.paint.gauge.toggle()
        }
    }

    private var geneCell: some View {
        DecideCell(label: model.useGene ? "gene" : "floor",
                   active: model.useGene,
                   enabled: model.gene != nil) {
            model.useGene.toggle()
        }
    }

    private var againCell: some View {
        DecideCell(label: "again", active: false) {
            onDecide(.again, model.modelInput(), model.useGene)
        }
    }

    private var acceptCell: some View {
        DecideCell(label: "accept", active: true) {
            onDecide(.accept, model.modelInput(), model.useGene)
        }
    }
}

// ── the widgets ──────────────────────────────────────────────────────────────

/// A lattice-styled decision cell: fills its proven region, no free frames.
private struct DecideCell: View {
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

/// The preview hero: the scrubbed capture frame as nearest-neighbour pixels
/// (display-only OKLab → sRGB; never re-enters the byte-exact pipeline).
/// Horizontal drag scrubs the frame — which also selects the paint layer.
private struct DecidePreviewWidget: View {
    @ObservedObject var model: DecideModel

    var body: some View {
        GeometryReader { geo in
            Group {
                if let cg = reconstructionImage() {
                    // The REAL build: the 16³ proposal up-rung'd to 64³ (floor or
                    // the gene's invention) — what accepting would ship.
                    Image(decorative: cg, scale: 1)
                        .interpolation(.none)
                        .resizable()
                } else if let cg = Self.image(of: model.tiles.indices.contains(model.frame)
                                              ? model.tiles[model.frame] : nil) {
                    // No substrate yet: the honest fallback is the capture frame.
                    Image(decorative: cg, scale: 1)
                        .interpolation(.none)
                        .resizable()
                } else {
                    Color.white.opacity(0.06)
                }
            }
            .overlay(alignment: .bottomLeading) {
                Text("t \(model.frame)/\(max(1, model.tiles.count) - 1) · layer \(model.paintLayer) · \(model.substrate.isEmpty ? "capture" : (model.useGene ? "gene" : "floor"))")
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.7))
                    .padding(GlobalLattice.gif(1))
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0).onChanged { g in
                    guard !model.tiles.isEmpty else { return }
                    let t = Int(g.location.x / geo.size.width
                                * CGFloat(model.tiles.count))
                    model.frame = min(model.tiles.count - 1, max(0, t))
                }
            )
        }
    }

    /// The reconstruction slice at the scrubbed frame → CGImage (nil without a substrate).
    private func reconstructionImage() -> CGImage? {
        guard let rgba = model.reconstructionSlice(frame: model.frame, useGene: model.useGene)
        else { return nil }
        return Self.rgbaImage(rgba, side: 64)
    }

    /// One tile → CGImage (RGBA8, nearest-neighbour source).
    static func image(of tile: OKLabTile?) -> CGImage? {
        guard let tile else { return nil }
        var rgba = [UInt8]()
        rgba.reserveCapacity(tile.pixels.count * 4)
        for px in tile.pixels {
            let c = ColorScience.okLabToSRGB8(OKLab(px.x, px.y, px.z))
            rgba.append(contentsOf: [c.x, c.y, c.z, 255])
        }
        return rgbaImage(rgba, side: tile.side)
    }

    /// Packed RGBA8 → CGImage.
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

/// The 16×16 paint grid of the scrub-selected control layer (16 pt per control
/// cell on the proven 64-cell region). Tap/drag paints the brush into the
/// selected channel of `CellBudget` — the `miNudge` surface.
private struct DecidePaintWidget: View {
    @ObservedObject var model: DecideModel
    @ObservedObject var paint: NudgePaintModel
    private let side = NudgePaintModel.side

    var body: some View {
        GeometryReader { geo in
            let cell = geo.size.width / CGFloat(side)
            VStack(spacing: 0) {
                ForEach(0 ..< side, id: \.self) { y in
                    HStack(spacing: 0) {
                        ForEach(0 ..< side, id: \.self) { x in
                            paintCell(x: x, y: y)
                        }
                    }
                }
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0).onChanged { g in
                    let x = Int(g.location.x / cell)
                    let y = Int(g.location.y / cell)
                    guard x >= 0, x < side, y >= 0, y < side else { return }
                    paint.paint(x: x, y: y, z: model.paintLayer,
                                channel: model.channel, value: model.brush)
                }
            )
        }
    }

    private func paintCell(x: Int, y: Int) -> some View {
        let v = paint.value(x: x, y: y, z: model.paintLayer, channel: model.channel)
        let diag = paint.gauge && NudgeChannel.phi6Diagonal.contains(model.channel)
        // UNDERLAY: the proposal's own 16³ voxel at this (cell, layer) — the user
        // paints ON the thing they are deciding, not on a blank grid.
        let base: Color = model.proposalSRGB8(x: x, y: y, layer: model.paintLayer).map {
            Color(red: Double($0.x) / 255, green: Double($0.y) / 255, blue: Double($0.z) / 255)
        } ?? Color.white.opacity(0.05)
        return Rectangle()
            .fill(base)
            .overlay(Rectangle().fill(NudgeChannel.tint(model.channel)
                .opacity(v > 0 ? min(0.85, 0.25 + Double(v) / 128.0) : 0)))
            .overlay(Rectangle().stroke(Color.white.opacity(diag ? 0.4 : 0.12),
                                        lineWidth: diag ? 1 : 0.5))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#if DEBUG
struct DecideSurface_Previews: PreviewProvider {
    static var previews: some View {
        DecideSurface(tiles: [], thetaUp: nil) { _, _, _ in }
    }
}
#endif
