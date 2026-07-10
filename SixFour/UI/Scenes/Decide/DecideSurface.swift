import SwiftUI
import UIKit
import Combine
import simd

/// THE DECISION SURFACE — rebuilt around the TWO VERBS (THE DESIGN D3,
/// `docs/UI-FORM-FOLLOWS-FUNCTION.md`, 2026-07-08). The scene shows a DECISION,
/// not machinery:
///
///   * HERO — the 64³ reconstruction (floor or gene: what accepting would ship),
///     wearing the D1 control BRACKETS in its own gutter. Horizontal drag scrubs
///     the frame (one time axis: the scrub also derives the 16³ paint layer).
///   * COARSE — the RAW 16³ coarse tier at the scrubbed layer, beside the hero:
///     the 64-vs-16 judgment read at a glance. Above it, the STATIC intake-tally
///     idiom (4 slots × 3 cells — the liveScene intake16 geometry) names the
///     4-cells-per-frame ledger structure, so the pour-equivalence language
///     crosses scenes.
///   * ACCEPT / AGAIN — the two clearest controls in the app: 44×16-cell verb
///     faces (176×64 pt, 4× the touch floor). ACCEPT = filled control-ink face +
///     seal glyph (`Haptics.play(3)`, dropAccept); AGAIN = hollow FRAME + retake
///     glyph (`Haptics.selection()` — the discrete-event generator; `play(1)` is
///     reserved for the frame-locked `.cellDetent`).
///   * THE ADVANCED FOLD — everything W1 (channel strip, 16³ paint bench, φ6
///     gauge, somatic-gene toggle) is DEMOTED behind one 12-cell chevron
///     (FRAME face). Opening reveals the bench top-down as a cell-row reveal on
///     the ONE 20 Hz clock. Semantics untouched: painting still gates WHERE the
///     gene invents (`Spec.ModelForward.lawPaintGatesBlockLocal`); zero paint
///     keeps the whole-volume gene arm; zero-gene == floor keeps OFF always safe.
///
/// Every widget sits on the proven lattice (`GridLayoutContract.decisionScene`,
/// all eight GridLayout laws + the D3 witness pins green) via the ONE sanctioned
/// `place(_:in:)` composer — this file hand-places nothing. All timing derives
/// from the ONE 20 Hz `SurfaceClock.tick`; only the leaf views that need the beat
/// read it (the surface body itself never re-evaluates per tick). All control
/// states are opaque cell/ink transforms — never alpha.
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
    /// The somatic gene. `var` since QoL 2026-07-03: training left the burst seam, so
    /// the gene may ARRIVE LATE (`attachGene`) — the surface starts on the floor arm
    /// and the gene cell enables the moment θ_up lands.
    @Published private(set) var gene: CaptureGene.ThetaUp?
    /// The REAL 16³ proposal — the lossless coarse tier of the committed cube
    /// (`Surface.coarseSubstrate`, 16 frames × 16² OKLab Q16). Empty until a
    /// capture commits (then the surface falls back to capture-frame preview).
    /// `var` since QoL 2026-07-03: the substrate builds OFF-MAIN at the σ fold,
    /// so a fast user can mount this surface before it lands (`attachSubstrate`).
    @Published private(set) var substrate: [[VoxelReduce.Px]]
    let paint = NudgePaintModel()

    /// Cached 64³ reconstructions (interleaved Q16): the deterministic floor and
    /// the gene's invention — both built by the REAL up-rung (`OctantCube.expandProposal`),
    /// so the preview is never a faked image. Built OFF-MAIN once at init (device
    /// audit: the synchronous build blocked first render ~0.5 s); the preview shows
    /// the capture-frame fallback until `reconstructionsReady`.
    private var floorRecon: [Int32]?
    private var geneRecon: [Int32]?
    @Published private(set) var reconstructionsReady = false
    /// Steps whenever a reconstruction arm lands or rebuilds — the hero's bake key
    /// (the PERF discipline: the 64² image rebakes only when this or the scrub steps,
    /// never per body evaluation).
    @Published private(set) var reconRevision = 0

    /// `paint` is a NESTED ObservableObject — its mutations (gauge toggle, strokes)
    /// do not propagate through DecideModel automatically (device audit: the gauge
    /// button never repainted). Forward them.
    private var paintForward: AnyCancellable?
    /// The debounced gene-arm rebuild after a paint stroke (W1): cancelled and
    /// re-armed per stroke so a drag repaints once, ~0.35 s after the last cell.
    private var repaintTask: Task<Void, Never>?

    /// Ride the learned somatic detail (true) or the deterministic floor (false).
    /// Defaults to the gene when the burst trained one; absence pins the floor.
    @Published var useGene: Bool
    /// The previewed burst frame (0-based); horizontal drag on the hero scrubs it.
    @Published var frame: Int = 0
    /// The brush's paint channel (default L·t, the φ6 diagonal value-over-time pair).
    @Published var channel: Int = 8
    /// The budget magnitude a stroke paints.
    let brush: Int = 32

    /// THE MERGE (`Spec.MergeBoard` / `S4MergeBoard`): the post-capture
    /// decision game played ON the hero — every capture opens as the
    /// all-coarse 16-board and the player decomposes toward 64³ by spending
    /// poured signal. Fresh per decide entry (AGAIN → recapture → new board).
    @Published private(set) var merge = S4MergeBoard()
    /// Steps when a merge op is ACCEPTED — the hero's bake key reads this
    /// (the PERF discipline: refusals never rebake the image).
    @Published private(set) var mergeRevision = 0

    /// The one write path into the game. Refusals are total no-ops by the
    /// spec's law; callers read the verdict for haptics only.
    @discardableResult
    func mergeStep(_ op: S4MergeOp) -> S4MergeVerdict {
        let verdict = merge.step(op)
        if verdict == .accept { mergeRevision += 1 }
        return verdict
    }

    init(tiles: [OKLabTile], gene: CaptureGene.ThetaUp?,
         substrate: [[VoxelReduce.Px]] = []) {
        self.tiles = tiles
        self.gene = gene
        self.substrate = substrate
        self.useGene = gene != nil
        paintForward = paint.objectWillChange
            .sink { [weak self] _ in
                self?.objectWillChange.send()
                self?.scheduleGeneRebuild()
            }
        buildReconstructions()
    }

    /// Build both reconstruction arms off the main thread (each ~0.1–0.8 s debug);
    /// publish when ready. The gene arm honours the gene's TRAINED channel and the
    /// live paint mask (W1: painted cells invent, unpainted ride the floor).
    private func buildReconstructions() {
        guard !substrate.isEmpty else { return }
        let sub = substrate
        let theta = gene.map { g in g.theta.map(Double.init) }
        let channel = gene?.channel ?? 0
        let mask = paint.deviceMask()
        Task { [weak self] in
            let (floor, geneArm) = await Self.buildArms(sub: sub, theta: theta,
                                                        channel: channel, mask: mask)
            guard let self else { return }
            self.floorRecon = floor
            self.geneRecon = geneArm
            self.reconstructionsReady = true
            self.reconRevision += 1
        }
    }

    /// The ASYNC coarse substrate landed (QoL 2026-07-03 — the σ fold builds it
    /// off-main): attach it and build both reconstruction arms. Until then the
    /// surface honestly showed the capture-frame fallback. Repeat/empty = no-op.
    func attachSubstrate(_ sub: [[VoxelReduce.Px]]) {
        guard substrate.isEmpty, !sub.isEmpty else { return }
        substrate = sub
        buildReconstructions()
    }

    /// The ASYNC somatic gene landed (QoL 2026-07-03 — training left the burst seam):
    /// attach it, default the toggle ON (mirroring the old at-init behaviour), and
    /// build the gene arm. A nil or repeat delivery is a no-op; the floor arm the
    /// user has been looking at is untouched.
    func attachGene(_ g: CaptureGene.ThetaUp?) {
        guard gene == nil, let g else { return }
        gene = g
        useGene = true
        scheduleGeneRebuild()
    }

    /// W1: a paint stroke re-gates the gene arm. Debounced (a drag is many strokes);
    /// the floor arm never depends on paint, so only the gene arm rebuilds.
    private func scheduleGeneRebuild() {
        guard gene != nil, !substrate.isEmpty else { return }
        repaintTask?.cancel()
        repaintTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 350_000_000)
            guard !Task.isCancelled, let self else { return }
            let sub = self.substrate
            let theta = self.gene.map { g in g.theta.map(Double.init) }
            let channel = self.gene?.channel ?? 0
            let mask = self.paint.deviceMask()
            let (_, geneArm) = await Self.buildArms(sub: sub, theta: theta,
                                                    channel: channel, mask: mask)
            guard !Task.isCancelled else { return }
            self.geneRecon = geneArm
            self.reconRevision += 1
            self.objectWillChange.send()
        }
    }

    /// The pure off-main build (only Sendable value types cross the boundary).
    private nonisolated static func buildArms(sub: [[VoxelReduce.Px]], theta: [Double]?,
                                              channel: Int, mask: [Bool]?)
        async -> ([Int32]?, [Int32]?) {
        await Task.detached(priority: .userInitiated) {
            let floor = OctantCube.expandProposal(substrate: sub, theta: nil)
            let geneArm = theta.flatMap {
                OctantCube.expandProposal(substrate: sub, theta: $0, geneChannel: channel,
                                          paintMask: mask)
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
    /// THE one 20 Hz clock — passed to the leaf views that carry a beat (the hero
    /// brackets, the fold chevron, the reveal). The surface body never reads `tick`.
    let clock: SurfaceClock
    private let onDecide: (DecideVerdict, SixFourModelInput, Bool) -> Void
    /// THE MERGE's exit: ACCEPT hands the played decision word (as `.s4cr`
    /// v3 op-codes) to whoever owns the capture record — wired by
    /// `SurfaceView` to `CaptureViewModel.sealDecisionWord`. An unplayed
    /// board hands the empty word (the seal no-ops; shutter bytes stand).
    private let onSealWord: ([UInt64]) -> Void
    private let scene = GridLayoutContract.decisionScene
    /// Kept as plain properties so the ASYNC deliveries (QoL 2026-07-03: the gene
    /// trains off the burst seam; the substrate builds off the σ fold) reach the
    /// persistent `DecideModel` via `.onChange` — a re-init alone cannot update a
    /// `@StateObject`.
    private let thetaUp: CaptureGene.ThetaUp?
    private let substrate: [[VoxelReduce.Px]]

    /// The advanced fold (render state — the `advanced` region is static in the
    /// proven scene, so the reveal can never contend).
    @State private var advancedOpen = false
    @State private var foldOpenedAt = 0

    /// The STATIC intake-tally idiom above the coarse (all slots pending = the
    /// resting ghost rail): the exact liveScene intake16 geometry, baked once.
    private static let tallyBake: UIImage? = InvertedPyramidField.tallyImage(
        slots: [nil, nil, nil, nil], width: 16, slotCells: 3, gapCells: 1, flash: false)

    /// `clock` is REQUIRED (no default): a default `SurfaceClock()` is never started
    /// (tick stays 0), which silently kills the hero/fold BEAT and — worse — froze
    /// `AdvancedReveal` at a 4-row hit-test-dead sliver, making the whole demoted W1
    /// bench unreachable. Pass the surface's one running clock (`DecidingPhaseField`).
    @MainActor
    init(tiles: [OKLabTile], thetaUp: CaptureGene.ThetaUp?,
         substrate: [[VoxelReduce.Px]] = [],
         clock: SurfaceClock,
         onSealWord: @escaping ([UInt64]) -> Void = { _ in },
         onDecide: @escaping (DecideVerdict, SixFourModelInput, Bool) -> Void) {
        _model = StateObject(wrappedValue: DecideModel(
            tiles: tiles, gene: thetaUp, substrate: substrate))
        self.clock = clock
        self.thetaUp = thetaUp
        self.substrate = substrate
        self.onSealWord = onSealWord
        self.onDecide = onDecide
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.black.ignoresSafeArea()
            DecideHeroWidget(model: model, clock: clock).place("hero", in: scene)
            DecideCoarseWidget(model: model).place("coarse", in: scene)
            tallyRail.place("tally", in: scene)
            MergeSignalBar(model: model).place("signal", in: scene)
            MergePourWidget(model: model, clock: clock).place("pour", in: scene)
            FoldChevron(open: advancedOpen, clock: clock) {
                advancedOpen.toggle()
                foldOpenedAt = clock.tick
                Haptics.selection()
            }
            .place("fold", in: scene)
            if advancedOpen {
                advancedPanel.place("advanced", in: scene)
            }
            againVerb.place("again", in: scene)
            acceptVerb.place("accept", in: scene)
        }
        .ignoresSafeArea()
        // The async somatic gene landed after this surface mounted: attach it.
        .onChange(of: thetaUp) { _, g in model.attachGene(g) }
        // The async coarse substrate landed (built off-main at the σ fold): attach it.
        // Keyed on the layer count — the build only ever transitions empty → full.
        .onChange(of: substrate.count) { _, _ in model.attachSubstrate(substrate) }
    }

    // ── the static tally rail (the pour-equivalence language, crossing scenes) ──

    private var tallyRail: some View {
        Group {
            if let img = Self.tallyBake {
                Image(uiImage: img)
                    .interpolation(.none)
                    .resizable()
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    // ── the two verbs (D3: the clearest controls in the app) ────────────────

    private var againVerb: some View {
        Button {
            // The retake verb's discrete confirmation. THE DESIGN names the cellTick
            // feel (`play(1)`); `Haptics.selection()` IS that generator — the `play(1)`
            // ordinal itself is reserved for the frame-locked `.cellDetent` (LINT-DETENT).
            Haptics.selection()
            onDecide(.again, model.modelInput(), model.useGene)
        } label: { Color.clear }
        .buttonStyle(DecideVerbStyle(title: "AGAIN", filled: false, retake: true))
        .accessibilityLabel("Again: recapture")
        .accessibilityHint("Rejects this capture and returns to the camera")
    }

    private var acceptVerb: some View {
        Button {
            Haptics.play(3)   // dropAccept — the seal
            // THE MERGE's exit: the played decision word seals into the
            // capture's own .s4cr (v3 `dw`) BEFORE the verdict advances σ —
            // the word alone replays the whole game for training
            // (`Spec.CaptureRecord.lawRecordedWordReplays`).
            onSealWord(model.merge.decisionWordCodes)
            onDecide(.accept, model.modelInput(), model.useGene)
        } label: { Color.clear }
        .buttonStyle(DecideVerbStyle(title: "ACCEPT", filled: true, retake: false))
        .accessibilityLabel("Accept: commit this capture")
    }

    // ── the advanced fold content (the demoted W1 bench) ────────────────────

    /// The demoted W1 world inside the ONE proven `advanced` region: the FRAME face
    /// ring around the sheet, the 9-channel strip, the 16³ paint bench (3 atoms per
    /// control cell), and the φ6/gene toggles — all semantics untouched (placement
    /// demotion only). Revealed top-down by `AdvancedReveal` on the one clock.
    private var advancedPanel: some View {
        AdvancedReveal(clock: clock, openedAt: foldOpenedAt) {
            ZStack(alignment: .top) {
                advancedFrame
                VStack(spacing: 0) {
                    channelStrip
                        .frame(width: GlobalLattice.gif(60), height: GlobalLattice.gif(12))
                    DecidePaintWidget(model: model, paint: model.paint)
                        .frame(width: GlobalLattice.gif(48), height: GlobalLattice.gif(48))
                    HStack(spacing: 0) {
                        gaugeCell
                            .frame(width: GlobalLattice.gif(20), height: GlobalLattice.gif(12))
                        Spacer(minLength: 0)
                        geneCell
                            .frame(width: GlobalLattice.gif(20), height: GlobalLattice.gif(12))
                    }
                    .frame(width: GlobalLattice.gif(60), height: GlobalLattice.gif(12))
                }
                .padding(.top, GlobalLattice.gif(2))
            }
        }
    }

    /// The panel's FRAME face (the D1 control language): a 1-cell ring in control
    /// ink around the 64×76 sheet — an opaque ink border, never a stroke, never alpha.
    private var advancedFrame: some View {
        let ink = SIMD3<UInt8>(UInt8(SixFourCellMechanics.faceControlInk.r),
                               UInt8(SixFourCellMechanics.faceControlInk.g),
                               UInt8(SixFourCellMechanics.faceControlInk.b))
        return CellSprite(cols: 64, rows: 76, cellPt: GlobalLattice.gif(1)) { c, r in
            (c == 0 || c == 63 || r == 0 || r == 75) ? ink : nil
        }
        .allowsHitTesting(false)
    }

    // ── channels: which colour×space pair the brush paints ──────────────────

    /// The 9 ChannelProduct pairs as LATTICE CELLS (QoL 2026-07-03): each cell is
    /// tinted by its colour axis (`NudgeChannel.tint`, the same hues the paint grid
    /// shows), so selecting a channel and seeing its paint are one visual system.
    private var channelStrip: some View {
        HStack(spacing: 0) {
            ForEach(0 ..< NudgeChannel.labels.count, id: \.self) { i in
                channelCell(i)
            }
        }
    }

    private func channelCell(_ i: Int) -> some View {
        let selected = model.channel == i
        return Button { model.channel = i } label: {
            Text(NudgeChannel.labels[i])
                .font(.system(.caption2, design: .monospaced).weight(.semibold))
                .foregroundStyle(selected ? Color.black : NudgeChannel.tint(i).opacity(0.9))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(selected ? NudgeChannel.tint(i) : Color.white.opacity(0.10))
                .overlay(Rectangle().stroke(Color.white.opacity(selected ? 0.6 : 0.25),
                                            lineWidth: selected ? 1 : 0.5))
        }
        .buttonStyle(.plain)
    }

    // ── the demoted toggles ──────────────────────────────────────────────────

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
}

// ── the hero (the judgment view, wearing BRACKETS) ───────────────────────────

/// The 64³ judgment view AND THE MERGE's board: the scrubbed reconstruction
/// slice (floor or gene — what accepting would ship; the honest capture-frame
/// fallback until the substrate lands), rendered at each region's PLAYED
/// granularity (`S4MergeBoard`: depth 0/1/2 = 4/2/1-px blocks — the pooling
/// chunkiness IS the depth display, no decoration), wearing the D1 BRACKETS
/// in its gutter. One gesture, classified the CellMechanics way (movement =
/// scrub intent, the hold gate is the only door into K):
///   * horizontal DRAG scrubs the frame (brackets go full ink; a transient
///     CellText frame readout rides the bottom edge during the scrub only);
///   * TAP on a region = S (split one rung finer, spends poured signal);
///   * HOLD (≥ 0.45 s, no movement) = K (pool back coarser — mass kept).
/// Accepted verbs tick (`Haptics.selection()`); refusals pulse dropReject
/// (`Haptics.play(4)`) — the board never lies about the economy. The bake is
/// @State-cached keyed by (frame, arm, revision, merge) — a clock tick alone
/// never rebakes the image.
private struct DecideHeroWidget: View {
    @ObservedObject var model: DecideModel
    let clock: SurfaceClock
    @State private var scrubbing = false
    @State private var pressStart: (time: Date, loc: CGPoint)? = nil
    @State private var baked: (key: Int, image: UIImage?) = (.min, nil)

    var body: some View {
        let atom = GlobalLattice.gif(1)
        let key = imageKey
        ZStack {
            // idle = ghost brackets + the cadence BEAT (pinned off under reduce-motion);
            // scrubbing = the PRESSED ink.
            ControlBrackets(side: 64, state: scrubbing ? 1 : 0, tick: clock.tick,
                            reduceMotion: clock.reduceMotion)
            Group {
                if let img = baked.image {
                    Image(uiImage: img)
                        .interpolation(.none)
                        .resizable()
                } else {
                    Color.black   // no capture data yet — an honest void, no fake image
                }
            }
            .frame(width: GlobalLattice.gif(64), height: GlobalLattice.gif(64))
        }
        .overlay(alignment: .bottom) {
            if scrubbing {
                CellText("T \(model.frame)/\(max(model.tiles.count, 1) - 1)",
                         cell: GlobalLattice.pt(1))
                    .padding(.bottom, GlobalLattice.gif(3))
                    .allowsHitTesting(false)
            }
        }
        .contentShape(Rectangle())   // the bracket rect IS the hit rect (D1)
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { g in
                    if pressStart == nil { pressStart = (Date(), g.startLocation) }
                    // Movement is scrub intent; a still finger stays a verb
                    // press (the CellMechanics tap-cannot-drag gate, mirrored).
                    let moved = hypot(g.location.x - g.startLocation.x,
                                      g.location.y - g.startLocation.y)
                    guard scrubbing || moved > 2 * atom else { return }
                    scrubbing = true
                    guard !model.tiles.isEmpty else { return }
                    // Map over the TILE's 64 cells (the brackets add a 2-cell margin).
                    let t = Int((g.location.x - 2 * atom) / (64 * atom)
                                * CGFloat(model.tiles.count))
                    model.frame = min(model.tiles.count - 1, max(0, t))
                }
                .onEnded { _ in
                    let press = pressStart
                    pressStart = nil
                    if scrubbing { scrubbing = false; return }
                    guard let press else { return }
                    // The still press is a MERGE verb: tap = S, hold = K.
                    let held = Date().timeIntervalSince(press.time)
                    playMergeVerb(at: press.loc, hold: held >= 0.45, atom: atom)
                }
        )
        .onChange(of: key, initial: true) { _, k in
            guard k != baked.key else { return }
            baked = (k, bakeImage())
        }
        .accessibilityLabel("Judgment view")
        .accessibilityHint("Drag horizontally to scrub the sixty-four frames")
    }

    /// THE MERGE verb at a press location: map the press into the 64² plane
    /// (the scrub's own 2-cell bracket margin), find the region, play the
    /// verb. The board answers with the spec's verdict — accepted ticks,
    /// refused pulses dropReject. Off-tile presses are ignored.
    private func playMergeVerb(at loc: CGPoint, hold: Bool, atom: CGFloat) {
        let x = Int((loc.x - 2 * atom) / atom)
        let y = Int((loc.y - 2 * atom) / atom)
        guard x >= 0, x < 64, y >= 0, y < 64 else { return }
        let region = S4MergeBoard.regionOfPixel(x: x, y: y)
        switch model.mergeStep(.move(region, hold ? .k : .s)) {
        case .accept: Haptics.selection()
        case .rejected: Haptics.play(4)   // dropReject — the economy said no
        }
    }

    /// Everything that changes the hero's PIXELS (never the clock).
    private var imageKey: Int {
        var h = Hasher()
        h.combine(model.frame)
        h.combine(model.useGene)
        h.combine(model.reconstructionsReady)
        h.combine(model.reconRevision)
        h.combine(model.tiles.count)
        h.combine(model.substrate.count)
        h.combine(model.mergeRevision)
        return h.finalize()
    }

    /// The REAL build: the 16³ proposal up-rung'd to 64³ (floor or the gene's
    /// invention) — what accepting would ship. No substrate yet ⇒ the honest
    /// fallback is the capture frame itself. Never a faked image. Either
    /// source then renders at THE MERGE's played granularity (`pooled`).
    private func bakeImage() -> UIImage? {
        if let rgba = model.reconstructionSlice(frame: model.frame, useGene: model.useGene),
           let cg = Self.rgbaImage(pooled(rgba), side: 64) {
            return UIImage(cgImage: cg)
        }
        guard model.tiles.indices.contains(model.frame) else { return nil }
        let tile = model.tiles[model.frame]
        var rgba = [UInt8]()
        rgba.reserveCapacity(tile.pixels.count * 4)
        for px in tile.pixels {
            let c = ColorScience.okLabToSRGB8(OKLab(px.x, px.y, px.z))
            rgba.append(contentsOf: [c.x, c.y, c.z, 255])
        }
        let shaped = tile.side == 64 ? pooled(rgba) : rgba
        if let cg = Self.rgbaImage(shaped, side: tile.side) { return UIImage(cgImage: cg) }
        return nil
    }

    /// Render the 64² slice at each region's played granularity: a depth-d
    /// region shows `4 >> d`-px blocks (their round-half-up mean — the same
    /// display-only pooling everywhere else in the app), so the board state
    /// is VISIBLE as resolution, not decoration. Full-depth boards pass
    /// through untouched (the pre-MERGE hero, byte-identical).
    private func pooled(_ rgba: [UInt8]) -> [UInt8] {
        let depths = model.merge.depths
        guard depths.contains(where: { $0 < S4MergeBoard.maxDepth }) else { return rgba }
        var out = rgba
        for region in 0 ..< S4MergeBoard.regionCount {
            let d = depths[region]
            guard d < S4MergeBoard.maxDepth else { continue }
            let block = 4 >> d
            let rx = (region % S4MergeBoard.boardSide) * S4MergeBoard.regionSide
            let ry = (region / S4MergeBoard.boardSide) * S4MergeBoard.regionSide
            let n = block * block
            for by in stride(from: ry, to: ry + S4MergeBoard.regionSide, by: block) {
                for bx in stride(from: rx, to: rx + S4MergeBoard.regionSide, by: block) {
                    var sum = SIMD3<Int>(0, 0, 0)
                    for y in by ..< by + block {
                        for x in bx ..< bx + block {
                            let i = (y * 64 + x) * 4
                            sum &+= SIMD3(Int(rgba[i]), Int(rgba[i + 1]), Int(rgba[i + 2]))
                        }
                    }
                    let c = SIMD3<UInt8>(UInt8((sum.x + n / 2) / n),
                                         UInt8((sum.y + n / 2) / n),
                                         UInt8((sum.z + n / 2) / n))
                    for y in by ..< by + block {
                        for x in bx ..< bx + block {
                            let i = (y * 64 + x) * 4
                            out[i] = c.x; out[i + 1] = c.y; out[i + 2] = c.z
                        }
                    }
                }
            }
        }
        return out
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

// ── the coarse (the 16³ tier, beside the hero) ───────────────────────────────

/// The RAW 16³ coarse tier at the scrubbed layer — one screen cell per voxel
/// (16×16 cells): the other half of the 64-vs-16 judgment. Display-only
/// (`allowsHitTesting(false)`); ghost quarter-ink until the substrate lands.
/// Bake keyed by (layer, substrate arrival) — the scrub swaps whole tiles.
private struct DecideCoarseWidget: View {
    @ObservedObject var model: DecideModel
    @State private var baked: (key: Int, image: UIImage?) = (.min, nil)

    var body: some View {
        let key = model.substrate.isEmpty ? -1 : model.paintLayer
        Group {
            if let img = baked.image {
                Image(uiImage: img)
                    .interpolation(.none)
                    .resizable()
            } else {
                Color.clear
            }
        }
        .allowsHitTesting(false)
        .onChange(of: key, initial: true) { _, k in
            guard k != baked.key else { return }
            baked = (k, bake(layer: k))
        }
        .accessibilityLabel("Coarse sixteen-cubed view at the scrubbed layer")
    }

    private func bake(layer: Int) -> UIImage? {
        let ghost = SFTheme.ledGhost
        let pending = SIMD3<UInt8>(ghost.x / 4, ghost.y / 4, ghost.z / 4)
        return CellBitmap.image(cols: 16, rows: 16) { c, r in
            guard layer >= 0 else { return pending }
            return model.proposalSRGB8(x: c, y: r, layer: layer) ?? pending
        }
    }
}

// ── the fold chevron (FRAME face) ────────────────────────────────────────────

/// The ONE advanced-fold control: a 12×12 FRAME face (1-cell ring in control ink,
/// beating lit for 1 tick on every 16-rung realize — the D1 idle invite) around a
/// chevron pointing down (closed) or up (open). Baked once per (open, treatment).
private struct FoldChevron: View {
    let open: Bool
    let clock: SurfaceClock
    let action: () -> Void
    @State private var baked: (key: Int, image: UIImage?) = (.min, nil)

    var body: some View {
        // Reduce-motion pins the ring's BEAT off (tick 1 is provably beat-free —
        // `SixFourCellMechanics.goldenBeat[1]`); the chevron itself is static.
        let treatment = SixFourCellMechanics.faceTreatment(
            state: 0, tick: clock.reduceMotion ? 1 : clock.tick)
        let key = (open ? 8 : 0) + treatment
        Button(action: action) {
            Group {
                if let img = baked.image {
                    Image(uiImage: img)
                        .interpolation(.none)
                        .resizable()
                } else {
                    Color.clear
                }
            }
            .frame(width: GlobalLattice.gif(12), height: GlobalLattice.gif(12))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onChange(of: key, initial: true) { _, k in
            guard k != baked.key else { return }
            baked = (k, Self.bake(open: open, treatment: treatment))
        }
        .accessibilityLabel(open ? "Hide advanced tools" : "Show advanced tools")
        .accessibilityHint("Paint, channels, gauge, and gene live behind this fold")
    }

    private static func bake(open: Bool, treatment: Int) -> UIImage? {
        let lit = SIMD3<UInt8>(UInt8(SixFourCellMechanics.faceControlInk.r),
                               UInt8(SixFourCellMechanics.faceControlInk.g),
                               UInt8(SixFourCellMechanics.faceControlInk.b))
        let ghost = SFTheme.ledGhost
        let ring = treatment == 1 ? lit : ghost   // the BEAT lights the ring for 1 tick
        return CellBitmap.image(cols: 12, rows: 12) { c, r in
            if c == 0 || c == 11 || r == 0 || r == 11 { return ring }   // the FRAME
            // A 2-cell-thick chevron: down (closed — "more below") or up (open).
            let o = open ? (7 - r) : (r - 4)
            guard o >= 0, o <= 2 else { return nil }
            let onArm = (c == 2 + o || c == 3 + o || c == 8 - o || c == 9 - o)
            return onArm ? lit : nil
        }
    }
}

// ── the reveal (the fold opens as a cell-row paint, on the one clock) ────────

/// Reveals its content top-down in cell rows once the fold opens: rows paint in
/// groups of 4 per tick (one pour-group per tick — the full 76-row sheet lands in
/// ~1 s; the design's letter of 1 row/tick reads as a 3.8 s stall on device, so the
/// reveal keeps the top-down cell-row FORM at a usable rate). Hit-testing stays off
/// until fully revealed, then the clock is no longer read at all. A clock that is
/// not RUNNING (a preview / misconfigured mount) opens instantly — a stopped tick
/// must never leave the bench sealed behind a hit-test-dead 4-row sliver.
private struct AdvancedReveal<Content: View>: View {
    let clock: SurfaceClock
    let openedAt: Int
    @ViewBuilder let content: Content
    @State private var fullyOpen = false

    private static var totalRows: Int { 76 }
    private static var rowsPerTick: Int { 4 }

    var body: some View {
        if fullyOpen || !clock.running {
            content
        } else {
            let revealed = min(Self.totalRows,
                               max(0, (clock.tick - openedAt + 1) * Self.rowsPerTick))
            content
                .frame(width: GlobalLattice.gif(64),
                       height: GlobalLattice.gif(Self.totalRows), alignment: .top)
                .frame(height: GlobalLattice.gif(revealed), alignment: .top)
                .clipped()
                .frame(height: GlobalLattice.gif(Self.totalRows), alignment: .top)
                .allowsHitTesting(false)
                .onChange(of: revealed, initial: true) { _, r in
                    if r >= Self.totalRows { fullyOpen = true }
                }
        }
    }
}

// ── the verb faces (the control language on the two first-class verbs) ───────

/// The verb face renderer: ACCEPT = filled control-ink face (dark glyph/label);
/// AGAIN = hollow FRAME (1-cell control-ink ring, lit glyph/label). PRESSED is the
/// full ink inversion of the face (the filled face goes dark, the hollow face goes
/// filled) — cell transforms only. Face bitmaps are baked once per (filled) state.
private struct DecideVerbFace: View {
    let title: String
    let filled: Bool
    let retake: Bool
    let pressed: Bool
    @State private var baked: (key: Int, image: UIImage?) = (.min, nil)

    private static let inkLit = SIMD3<UInt8>(UInt8(SixFourCellMechanics.faceControlInk.r),
                                             UInt8(SixFourCellMechanics.faceControlInk.g),
                                             UInt8(SixFourCellMechanics.faceControlInk.b))
    private static let inkDark = SIMD3<UInt8>(255 - UInt8(SixFourCellMechanics.faceControlInk.r),
                                              255 - UInt8(SixFourCellMechanics.faceControlInk.g),
                                              255 - UInt8(SixFourCellMechanics.faceControlInk.b))

    var body: some View {
        // PRESSED inverts the face: filled ↔ hollow-dark, hollow ↔ filled.
        let showFilled = filled != pressed
        let fg = showFilled ? Self.inkDark : Self.inkLit
        let key = showFilled ? 1 : 0
        ZStack {
            Group {
                if let img = baked.image {
                    Image(uiImage: img)
                        .interpolation(.none)
                        .resizable()
                }
            }
            HStack(spacing: GlobalLattice.pt(4)) {
                if retake {
                    CellIcon.retake(box: 12, ink: fg)
                } else {
                    CellIcon.seal(box: 12, ink: fg)
                }
                CellText(title, rows: 11, cell: GlobalLattice.pt(1), ink: Color(srgb8: fg))
            }
        }
        .frame(width: GlobalLattice.gif(44), height: GlobalLattice.gif(16))
        .contentShape(Rectangle())
        .onChange(of: key, initial: true) { _, k in
            guard k != baked.key else { return }
            baked = (k, Self.bake(filled: showFilled))
        }
        .accessibilityHidden(true)   // the wrapping Button carries the real label
    }

    private static func bake(filled: Bool) -> UIImage? {
        CellBitmap.image(cols: 44, rows: 16) { c, r in
            if filled { return inkLit }
            let onRing = c == 0 || c == 43 || r == 0 || r == 15
            return onRing ? inkLit : nil
        }
    }
}

/// ButtonStyle wiring the verb face to the press: the whole 44×16-cell face is the
/// hit rect; `isPressed` drives the ink inversion (no opacity, no scale).
private struct DecideVerbStyle: ButtonStyle {
    let title: String
    let filled: Bool
    let retake: Bool

    func makeBody(configuration: Configuration) -> some View {
        DecideVerbFace(title: title, filled: filled, retake: retake,
                       pressed: configuration.isPressed)
    }
}

// ── the demoted-toggle cell (advanced fold only) ─────────────────────────────

/// A lattice-styled toggle cell for the demoted W1 knobs (gauge/gene): fills its
/// slot inside the advanced sheet. (The first-class verbs wear `DecideVerbFace`.)
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

// ── the paint bench (the demoted 16³ control grid) ───────────────────────────

/// The 16×16 paint grid of the scrub-selected control layer (3 atoms per control
/// cell inside the advanced sheet). Tap/drag paints the brush into the selected
/// channel of `CellBudget` — the `miNudge` surface. W1 semantics untouched.
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
        // Construct-and-START the one clock — a never-started clock would pin the
        // BEAT and (before the `clock.running` guard) seal the advanced fold.
        let clock = SurfaceClock()
        clock.start()
        return DecideSurface(tiles: [], thetaUp: nil, clock: clock) { _, _, _ in }
    }
}
#endif
