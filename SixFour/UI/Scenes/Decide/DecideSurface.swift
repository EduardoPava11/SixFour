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

    /// The capture's IMMUTABLE evidence schedule (`Spec.MergeEvidence`):
    /// installed AT CONSTRUCTION, before the first pour can happen — a
    /// mid-game schedule swap would break the replay keystone
    /// (`lawWordReplaysBoardUnderSchedule`), a runtime invariant no law can
    /// enforce, hence `let`. ALWAYS priced from the capture's own sealed
    /// telemetry (`S4MergeEvidence.schedule(from:)` — the same rule every
    /// replay reader runs on the record's bytes; a flag gating only the live
    /// side was the replay-keystone gap). Derived bursts price to the
    /// constant, under which every step is byte-for-byte today's game
    /// (`lawDerivedScheduleIsStep`).
    let pourSchedule: [Int]

    /// Whether pours credit MEASURED evidence (a non-constant schedule) —
    /// the ONE provenance bit the economy instruments caption
    /// (`MergeSignalBar`: MEASURED/DERIVED, the hero chip's vocabulary).
    var evidenceScaled: Bool { pourSchedule != S4MergeBoard.derivedSchedule }

    /// The one write path into the game. Refusals are total no-ops by the
    /// spec's law; callers read the verdict for haptics only. Every op runs
    /// under the capture's own schedule (`step(_:schedule:)` — the derived
    /// constant reproduces the classic step exactly).
    @discardableResult
    func mergeStep(_ op: S4MergeOp) -> S4MergeVerdict {
        let depthsBefore = merge.depths
        let verdict = merge.step(op, schedule: pourSchedule)
        // Only DEPTH changes repaint the hero: an accepted pour moves the
        // ledger (the signal bar re-reads `merge` via its own publish) but
        // no pixel. The revision in the cache KEY is the one invalidation
        // mechanism — stale entries become unreachable; the capacity bound
        // reclaims them.
        if verdict == .accept, merge.depths != depthsBefore {
            mergeRevision += 1
        }
        return verdict
    }

    // ── THE READS (step B, `Spec.RungReadDisplay` / `RungReads`) ─────────────

    /// The burst's realized independent rung reads — arrives LATE like the
    /// gene/substrate (the realize runs detached after the record write).
    /// @Published directly: `objectWillChange` is a Void send (no value
    /// copy/diff rides a publish), and a derived `rungReads != nil` in the
    /// cache key cannot desync the way a hand-pulsed revision int could.
    @Published private(set) var rungReads: RungReads?

    /// The ASYNC rung reads landed: attach them (the attachGene pattern —
    /// repeat/nil deliveries are no-ops; the first delivery wins). The bake
    /// keys carry `hasReads`, so every pre-reads cache entry is unreachable
    /// the moment this flips — no wholesale flush needed.
    func attachRungReads(_ r: RungReads?) {
        guard rungReads == nil, let r else { return }
        rungReads = r
    }

    /// The hero's 64² RGBA frame from THE READS — each MERGE region rendered
    /// from ITS OWN rung read (`RungReads.composited`: select + causal hold +
    /// block-replicate, the same chunk geometry as `pooled()` with an
    /// independent SOURCE). nil unless the feature is on AND the ladder wrote
    /// all three cubes (`independent` — the BINARY WHOLE-HERO gate: camera
    /// sRGB8 and Q16-OKLab reconstruction never mix inside one frame, the
    /// color-jump refusal). Derived bursts always answer nil ⇒ the pooled
    /// reconstruction stays the honest fallback, byte-for-byte today's hero.
    func readsSlice(frame: Int) -> [UInt8]? {
        guard Feature.rungReadHero, let reads = rungReads, reads.independent
        else { return nil }
        return reads.composited(frame: frame, depths: merge.depths)
    }

    // ── THE TIME SLIDE's playhead (Spec.TimeSlide / TimeSlideMath) ───────────

    /// The hero's PIXEL SOURCE seam: `bakeImage`'s source is a parameter, not
    /// a hardwired call, so step B (the independent rung reads,
    /// `Spec.RungReadDisplay`) plugs in here without touching the slide
    /// mechanic. Today the ONE honest source is the derived reconstruction.
    enum HeroSource: Equatable {
        /// The ONE reconstruction (floor or gene arm), MERGE-pooled — the
        /// derived display mode. The provenance chip reads "DERIVED".
        case derived
        /// The independent c64/c32/c16 read volumes (step B,
        /// `Spec.RungReadDisplay`) — ladder bursts only. The chip reads
        /// "READS" and carries the honesty note: ACCEPT ships the
        /// reconstruction, not the reads.
        case rungReads

        /// The gutter provenance chip's honest vocabulary.
        var chipLabel: String {
            switch self {
            case .derived: return "DERIVED"
            case .rungReads: return "READS"
            }
        }
    }

    /// Which source the hero bakes from — DATA-GATED, never a preference:
    /// `.rungReads` iff the feature is on and a ladder burst's three
    /// independent cubes realized (`independent`); every derived burst (the
    /// shipped path) answers `.derived` — the honest fallback stays forever.
    var heroSource: HeroSource {
        (Feature.rungReadHero && rungReads?.independent == true) ? .rungReads : .derived
    }

    /// THE TIME SLIDE's playhead — state + intent ONLY (the `PlaybackClock`
    /// template: no timer, the ONE 20 Hz `SurfaceClock` drives motion
    /// externally via the hero's leaf tick read). Non-published on purpose:
    /// the hero body already re-evaluates per tick (it reads `clock.tick`),
    /// so playhead mutations surface within one tick without a second
    /// publish stream.
    struct DecidePlayhead {
        /// Playback intent. Pausing keeps the detent (and the anchor).
        var playing = false
        /// The current detent k ∈ {0,1,2} (0 = 64-rung … 2 = 16-rung).
        var rungK = 0
        /// The clock tick the playhead was (re-)anchored at.
        var anchorTick = 0
        /// The frame at the anchor — ALWAYS snapped to a group boundary of
        /// `rungK` (the latch convention `lawGroupChangesExactlyOnRealize`
        /// requires: the group then steps exactly on the realize ticks).
        var anchorFrame = 0
    }

    /// The hero's playhead. Read by the hero leaf each tick; written only by
    /// the three intents below (`lawSlideNeverWritesTheWord`: none of them
    /// touches `merge` or the decision word).
    private(set) var playhead = DecidePlayhead()

    /// Start (or restart) playback at detent `k`, anchored on the one clock.
    /// `fromFrame` snaps DOWN to a group boundary (the latch convention).
    func startPlayback(rungK k: Int, atTick tick: Int, fromFrame frame: Int = 0) {
        let kc = min(TimeSlideMath.maxDetent, max(TimeSlideMath.minDetent, k))
        playhead = DecidePlayhead(playing: true, rungK: kc, anchorTick: tick,
                                  anchorFrame: TimeSlideMath.snapToGroupStart(frame, k: kc))
    }

    /// Pause playback (the position gesture's intent). The detent and anchor
    /// survive — a later slide resumes from here.
    func pausePlayback() {
        playhead.playing = false
    }

    /// Move to detent `k`, re-anchoring on the ALIGNED frame (the current
    /// playhead position snapped to the new period's group boundary) so the
    /// group keeps stepping exactly on realize ticks. Same-detent calls are
    /// no-ops (a touch drag must never re-anchor per event).
    func setRung(_ k: Int, atTick tick: Int) {
        let kc = min(TimeSlideMath.maxDetent, max(TimeSlideMath.minDetent, k))
        guard kc != playhead.rungK else { return }
        let current = playhead.playing
            ? TimeSlideMath.pos(anchorTick: playhead.anchorTick,
                                anchorFrame: playhead.anchorFrame, tick: tick)
            : frame
        playhead.rungK = kc
        playhead.anchorTick = tick
        playhead.anchorFrame = TimeSlideMath.snapToGroupStart(current, k: kc)
        // Realize the new detent's group NOW: if the new display group's
        // integer happens to equal the old detent's playKey, the hero's
        // `.onChange(of: playKey)` never fires and `frame` would keep the
        // OLD detent's group-end value for up to one full group.
        realizePlayhead(group: TimeSlideMath.displayGroup(
            k: kc, anchorTick: tick, anchorFrame: playhead.anchorFrame, tick: tick))
    }

    /// Realize one display group: `frame` becomes the group's END frame
    /// (`Spec.TimeSlide.groupEndFrame` — the poured window ENDS at the
    /// realize tick). Called exactly once per group change by the hero's
    /// `.onChange(of: playKey)`; `frame` stays THE one time axis, so the 16³
    /// paint layer (t/4) and `DecideCoarseWidget` follow for free.
    func realizePlayhead(group j: Int) {
        // Before the async reconstruction lands the hero rides the TILES
        // fallback, which owns fewer frames on a short burst (kernel-dropped
        // frames) — never realize past what can bake, or the hero flashes
        // blank for the tail groups of every loop. Once the reconstruction
        // exists all 64 frames are real.
        let cap = reconstructionsReady
            ? TimeSlideMath.windowUnits
            : max(1, min(TimeSlideMath.windowUnits, tiles.count))
        let f = min(cap - 1,
                    max(0, TimeSlideMath.groupEndFrame(group: j, k: playhead.rungK)))
        guard f != frame else { return }
        frame = f
    }

    // ── the hero's integral-frame cache (loop 2+ is a cached-image swap) ─────

    /// One baked hero image per (detent, group, arm, revisions): at the
    /// 16-rung a full loop is only 16 groups, so after one 3.2 s loop every
    /// realize is a dictionary hit. THE ONE INVALIDATION MECHANISM is the
    /// key itself: every pixel-changing input is a key field, so a bump makes
    /// stale entries unreachable — there are NO scattered `removeAll` calls
    /// to keep in sync (the capacity bound in `heroCacheStore` reclaims dead
    /// entries; a new pixel input goes HERE and nowhere else).
    struct HeroCacheKey: Hashable {
        let rungK: Int
        let group: Int
        let useGene: Bool
        let reconRevision: Int
        let mergeRevision: Int
        let substrateEpoch: Int
        /// The pixel SOURCE (0 = derived reconstruction, 1 = the reads) —
        /// step B's display mode is part of the pixels' identity.
        let mode: Int
        /// Whether the reads have landed — first-delivery-wins makes the
        /// Bool a complete arrival marker (a derived value cannot desync).
        let hasReads: Bool
    }

    /// Max cached images: all groups of all coarse detents is 32+16 = 48;
    /// 128 (~1.8 MiB of 64² RGBA) bounds any future source generously.
    private static let heroCacheCapacity = 128
    private var heroCache: [HeroCacheKey: UIImage] = [:]

    /// The cache key for detent `k`, group `j` under the CURRENT revisions.
    /// `mode` 0 = derived reconstruction (step A's integral bakes), 1 = the
    /// reads (step B — `group` then carries the display FRAME, the reads'
    /// finest-changing time index).
    func heroCacheKey(rungK k: Int, group j: Int, useGene: Bool,
                      mode: Int = 0) -> HeroCacheKey {
        HeroCacheKey(rungK: k, group: j, useGene: useGene,
                     reconRevision: reconRevision, mergeRevision: mergeRevision,
                     substrateEpoch: substrate.count,
                     mode: mode, hasReads: rungReads != nil)
    }

    /// Cached baked hero image, if this exact (detent, group, revisions) was
    /// baked before.
    func heroCached(_ key: HeroCacheKey) -> UIImage? { heroCache[key] }

    /// Store a baked hero image; wholesale-clears first at capacity (the
    /// revisions in the key make stale entries unreachable anyway).
    func heroCacheStore(_ key: HeroCacheKey, _ image: UIImage) {
        if heroCache.count >= Self.heroCacheCapacity { heroCache.removeAll() }
        heroCache[key] = image
    }

    /// The hero's 64² RGBA slice for a COARSE detent: the group's temporal
    /// integral (`TimeSlideMath.integralFrame64` — Int64 sums over the
    /// aligned window, ONE round-half-up divide by the frame count 2^k in
    /// Q16 OKLab; `lawIntegralIsSumsDividedOnce`), display-converted. The
    /// temporal divisor is applied ONCE here in Q16; the MERGE's spatial
    /// block-means happen once later in sRGB (`pooled`) — different axes,
    /// never a double-divide. nil until a reconstruction exists (the caller
    /// falls through to the honest fallback). k=0 callers must use
    /// `reconstructionSlice` (byte-identical short-circuit, no integral).
    func integralSlice(rungK k: Int, group j: Int, useGene: Bool) -> [UInt8]? {
        guard k > 0, let vol = reconstruction(useGene: useGene) else { return nil }
        let q16 = TimeSlideMath.integralFrame64(volume: vol, group: j, k: k)
        var rgba = [UInt8](); rgba.reserveCapacity(64 * 64 * 4)
        for p in 0 ..< 64 * 64 {
            let i = p * 3
            let c = ModelRender.displaySRGB8(
                SIMD3<Int>(Int(q16[i]), Int(q16[i + 1]), Int(q16[i + 2])))
            rgba.append(contentsOf: [c.x, c.y, c.z, 255])
        }
        return rgba
    }

    init(tiles: [OKLabTile], gene: CaptureGene.ThetaUp?,
         substrate: [[VoxelReduce.Px]] = [],
         rungReads: RungReads? = nil,
         pourSchedule: [Int] = S4MergeBoard.derivedSchedule) {
        self.tiles = tiles
        self.gene = gene
        self.substrate = substrate
        self.rungReads = rungReads
        self.pourSchedule = pourSchedule
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
            self.reconRevision += 1   // the key field IS the invalidation
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
            self.reconRevision += 1   // the key field IS the invalidation
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
    /// THE READS (step B): kept as a plain property like the gene/substrate so
    /// the ASYNC delivery (the realize runs detached after the record write)
    /// reaches the persistent `DecideModel` via `.onChange`.
    private let rungReads: RungReads?

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
         rungReads: RungReads? = nil,
         pourSchedule: [Int] = S4MergeBoard.derivedSchedule,
         clock: SurfaceClock,
         onSealWord: @escaping ([UInt64]) -> Void = { _ in },
         onDecide: @escaping (DecideVerdict, SixFourModelInput, Bool) -> Void) {
        _model = StateObject(wrappedValue: DecideModel(
            tiles: tiles, gene: thetaUp, substrate: substrate,
            rungReads: rungReads, pourSchedule: pourSchedule))
        self.clock = clock
        self.thetaUp = thetaUp
        self.substrate = substrate
        self.rungReads = rungReads
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
                // The paint bench targets ONE layer (paintLayer = frame/4):
                // opening the fold pauses playback so the stroke's z-layer
                // cannot drift under the finger mid-drag. The slide is the
                // resume verb, as everywhere else.
                if advancedOpen { model.pausePlayback() }
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
        // PLAY BY DEFAULT (THE TIME SLIDE): the hero opens PLAYING at the
        // 16-rung detent (k=2 — 5 realizes/s, thermally the gentlest lawful
        // cadence); the first slide re-anchors. A non-running clock (a
        // preview) pins tick=0, so the playhead honestly holds group 0.
        .onAppear {
            if Feature.decideTimeSlide {
                model.startPlayback(rungK: 2, atTick: clock.tick, fromFrame: 0)
            }
        }
        // The async somatic gene landed after this surface mounted: attach it.
        .onChange(of: thetaUp) { _, g in model.attachGene(g) }
        // The async coarse substrate landed (built off-main at the σ fold): attach it.
        // Keyed on the layer count — the build only ever transitions empty → full.
        .onChange(of: substrate.count) { _, _ in model.attachSubstrate(substrate) }
        // The async rung reads landed (step B — the realize runs detached after the
        // record write): attach them so a ladder burst's hero can flip to READS.
        .onChange(of: rungReads) { _, r in model.attachRungReads(r) }
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
///     CellText frame readout rides the bottom edge during the scrub only)
///     and PAUSES playback;
///   * vertical DRAG is THE TIME SLIDE (`Feature.decideTimeSlide`,
///     `Spec.TimeSlide`/`TimeSlideMath`): finger travel quantizes to the
///     three lawful detents (16 cells per rung step, down = coarser), the
///     hero PLAYS on the one 20 Hz clock at the detent's exact cadence
///     (64@20 Hz / 32@10 Hz / 16@5 Hz), coarse detents show true temporal
///     integrals, and the frame-locked `.cellDetent` ticks each crossing;
///   * TAP on a region = S (split one rung finer, spends poured signal);
///   * HOLD (≥ 0.45 s, no movement) = K (pool back coarser — mass kept).
/// Accepted verbs tick (`Haptics.selection()`); refusals pulse dropReject
/// (`Haptics.play(4)`) — the board never lies about the economy. The bake is
/// @State-cached keyed by (frame, detent, arm, revision, merge) — a clock
/// tick alone never rebakes the image (the playhead enters only as the
/// realized frame, once per 2^k ticks while playing).
private struct DecideHeroWidget: View {
    @ObservedObject var model: DecideModel
    let clock: SurfaceClock
    @State private var scrubbing = false
    /// THE TIME SLIDE latched (a vertical winner at the movement threshold):
    /// finger travel now picks the detent; the horizontal scrub branch is
    /// untouched (`Feature.decideTimeSlide` off ⇒ this never latches).
    @State private var timeSliding = false
    /// The detent when the slide latched (`Spec.TimeSlide.detentOf`'s anchor).
    @State private var slideLatchK = 0
    /// The tick the last slide released — the time rail dematerializes
    /// `Self.railLingerTicks` later (materialize-on-touch, no resident chrome).
    @State private var slideReleasedAt: Int? = nil
    @State private var pressStart: (time: Date, loc: CGPoint)? = nil
    /// The baked hero + THE SOURCE ITS PIXELS ACTUALLY CAME FROM: the chip
    /// reads `baked.source`, never the model's attempted mode — a reads
    /// composite that REFUSES falls through to the derived path, and the
    /// chip must fall with it (provenance can never disagree with pixels).
    @State private var baked: (key: Int, image: UIImage?,
                               source: DecideModel.HeroSource) = (.min, nil, .derived)

    /// Ticks the time rail lingers after release (8 ticks = 0.4 s).
    private static let railLingerTicks = 8

    var body: some View {
        let atom = GlobalLattice.gif(1)
        let key = imageKey
        // THE ADVANCE (leaf-reads-tick — `clock.onTick` is single-slot and
        // owned by `SurfaceView`, never claimed): the derived play key is the
        // playhead's display group, a pure function of the one 20 Hz tick.
        // It changes exactly on `realizesAt(2^k)` ticks (goldenSchedule16-
        // gated), so the bake fires at 20/10/5 Hz — coarse bakes FEWER. A
        // non-running clock (a preview) pins tick=0 ⇒ an honest static hero.
        // Reduce-motion keeps playing: cadence = CONTENT (the pyramid rule);
        // only the decorative bracket BEAT pins.
        let playKey: Int? = (Feature.decideTimeSlide && model.playhead.playing)
            ? TimeSlideMath.displayGroup(k: model.playhead.rungK,
                                         anchorTick: model.playhead.anchorTick,
                                         anchorFrame: model.playhead.anchorFrame,
                                         tick: clock.tick)
            : nil
        let railVisible = timeSliding
            || slideReleasedAt.map { clock.tick - $0 < Self.railLingerTicks } ?? false
        ZStack {
            // idle = ghost brackets + the cadence BEAT (pinned off under reduce-motion);
            // scrubbing OR sliding = the PRESSED ink.
            ControlBrackets(side: 64, state: (scrubbing || timeSliding) ? 1 : 0,
                            tick: clock.tick,
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
            // ONE bottom-edge readout slot, shared: the scrub's frame count
            // and the slide's detent readout are gesture-exclusive.
            if scrubbing {
                CellText(scrubReadout, cell: GlobalLattice.pt(1))
                    .padding(.bottom, GlobalLattice.gif(3))
                    .allowsHitTesting(false)
            } else if timeSliding {
                // The two-sided detent readout: side + exact GCE delay
                // ("64 - 5cs" / "32 - 10cs" / "16 - 20cs") — both integers
                // are theorems of the ladder (`s4_ladder_delay_cs`).
                CellText(TimeSlideMath.readoutLabel(model.playhead.rungK),
                         cell: GlobalLattice.pt(1))
                    .padding(.bottom, GlobalLattice.gif(3))
                    .allowsHitTesting(false)
            }
        }
        .overlay(alignment: .trailing) {
            // THE TIME RAIL (materialize-on-touch): the three lawful detents
            // as FRAMEd 2×2-cell blocks in the tile's rightmost 2 cell-
            // columns, top (k=0) → bottom (k=2), the current rung inverted.
            // Restricted to the THREE detents — never a continuum (off-
            // ladder holds are dilation, not rungs). Display-only.
            if Feature.decideTimeSlide && railVisible {
                timeRail
                    .padding(.trailing, GlobalLattice.gif(2))
                    .allowsHitTesting(false)
            }
        }
        .overlay(alignment: .topLeading) {
            // The provenance chip: the hero's pixel source, honestly named in
            // the gutter ("DERIVED" for the pooled reconstruction; "READS"
            // when a ladder burst's independent cubes drive the render). In
            // READS mode the chip carries the honesty note: ACCEPT still
            // ships the reconstruction — the reads are the display evidence,
            // never the committed GIF.
            // Materialize-on-touch (the charter's no-resident-chrome rule):
            // the DERIVED chip appears only while the time gesture is live
            // (where it contextualizes what the pixels are), then
            // dematerializes with the rail. READS mode is the one justified
            // resident label — an unusual pixel source must stay named for
            // as long as it is the source (color-provenance honesty outranks
            // chrome minimalism, and "SHIPS RECON" is the accept contract).
            // The chip reads the BAKED source — what the pixels on screen
            // actually are — so a refused reads-composite that fell through
            // to the derived path can never wear a READS label.
            if baked.source == .rungReads || railVisible {
                VStack(alignment: .leading, spacing: 0) {
                    CellText(baked.source.chipLabel, rows: 5,
                             cell: GlobalLattice.pt(1),
                             ink: Color(srgb8: SFTheme.ledGhost))
                    if baked.source == .rungReads {
                        CellText("SHIPS RECON", rows: 5,
                                 cell: GlobalLattice.pt(1),
                                 ink: Color(srgb8: SFTheme.ledGhost))
                    }
                }
                .padding(.leading, GlobalLattice.gif(2))
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            }
        }
        .contentShape(Rectangle())   // the bracket rect IS the hit rect (D1)
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { g in
                    if pressStart == nil {
                        pressStart = (Date(), g.startLocation)
                        // Self-heal a CANCELLED gesture (an incoming call or
                        // system alert skips onEnded, and @State does not
                        // auto-reset the way @GestureState does): a fresh
                        // press always starts UNLATCHED, so a stuck mode can
                        // never survive past the next touch — without this,
                        // a stale `timeSliding` would skip the latch guard,
                        // jump detents against the old anchor, and make the
                        // tap/hold verbs unreachable.
                        scrubbing = false
                        timeSliding = false
                    }
                    // Movement is scrub/slide intent; a still finger stays a
                    // verb press (the CellMechanics tap-cannot-drag gate).
                    let dx = g.location.x - g.startLocation.x
                    let dy = g.location.y - g.startLocation.y
                    let moved = hypot(dx, dy)
                    if !scrubbing && !timeSliding {
                        guard moved > 2 * atom else { return }
                        // AXIS TEST at the one threshold crossing: |dx| ≥ |dy|
                        // latches the EXISTING horizontal scrub byte-identically
                        // (ties go horizontal — the landed feel survives);
                        // |dy| > |dx| latches THE TIME SLIDE. Flag off ⇒ any
                        // movement scrubs, exactly as landed.
                        if Feature.decideTimeSlide && abs(dy) > abs(dx) {
                            timeSliding = true
                            slideLatchK = model.playhead.rungK
                            // A slide RESTARTS playback (scrub-end never
                            // auto-resumes; the slide is the resume verb).
                            if !model.playhead.playing {
                                model.startPlayback(rungK: slideLatchK,
                                                    atTick: clock.tick,
                                                    fromFrame: model.frame)
                            }
                        } else {
                            scrubbing = true
                            // The position gesture pauses playback (no-op
                            // while the flag is off — never playing).
                            model.pausePlayback()
                        }
                    }
                    if timeSliding {
                        // Finger travel → detent (`Spec.TimeSlide.detentOf`,
                        // FLOOR division — down = coarser). Cell conversion
                        // floors too, matching the spec's negative-branch
                        // discipline. Same-detent moves are model no-ops.
                        let dyCells = Int((dy / atom).rounded(.down))
                        model.setRung(TimeSlideMath.detentOf(kAtLatch: slideLatchK,
                                                             dyCells: dyCells),
                                      atTick: clock.tick)
                        return
                    }
                    guard !model.tiles.isEmpty else { return }
                    // Map over the TILE's 64 cells (the brackets add a 2-cell margin).
                    let t = Int((g.location.x - 2 * atom) / (64 * atom)
                                * CGFloat(model.tiles.count))
                    model.frame = min(model.tiles.count - 1, max(0, t))
                }
                .onEnded { _ in
                    let press = pressStart
                    pressStart = nil
                    if timeSliding {
                        // Release keeps playing at the released detent; the
                        // rail lingers `railLingerTicks` then dematerializes.
                        timeSliding = false
                        slideReleasedAt = clock.tick
                        return
                    }
                    if scrubbing { scrubbing = false; return }
                    guard let press else { return }
                    // The still press is a MERGE verb: tap = S, hold = K —
                    // stillness-gated, untouched by the slide (a latched
                    // slide returns above and can never reach here).
                    let held = Date().timeIntervalSince(press.time)
                    playMergeVerb(at: press.loc, hold: held >= 0.45, atom: atom)
                }
        )
        // DETENT HAPTIC — the LINT-DETENT-sanctioned route (never a bare
        // `Haptics.play(1)`): the synthetic cell IS the rung index, so
        // `cellsCrossed` fires exactly one frame-locked play(1) per detent
        // crossing, coalesced to the 20 fps tick.
        .cellDetent(tick: clock.tick, every: 1, position: {
            timeSliding ? (col: 0, row: model.playhead.rungK) : nil
        })
        // The realize gate: the group key steps exactly on the rung's
        // realize ticks; each step realizes ONE playhead frame
        // (`groupEndFrame` — model.frame stays THE one time axis, so the 16³
        // paint layer and the coarse widget follow free). `initial: true`
        // aligns the opening frame to its group end.
        .onChange(of: playKey, initial: true) { _, g in
            if let g { model.realizePlayhead(group: g) }
        }
        .onChange(of: key, initial: true) { _, k in
            guard k != baked.key else { return }
            let (image, source) = bakeImage()
            baked = (k, image, source)
        }
        .accessibilityLabel("Judgment view")
        // The hint must describe only gestures that EXIST in this build —
        // with the slide off, the escape hatch restores the landed classifier
        // (any movement scrubs) and a vertical-drag promise would be a lie.
        .accessibilityHint(Feature.decideTimeSlide
            ? "Drag horizontally to scrub the sixty-four frames; drag vertically to slow or speed playback"
            : "Drag horizontally to scrub the sixty-four frames")
    }

    /// The time rail bitmap: 2 columns × 10 rows — three 2×2 detent blocks
    /// (rows 0-1 / 4-5 / 8-9 for k = 0/1/2) separated by 2-row gaps. The
    /// current detent is INVERTED (filled control ink); the others are ghost.
    /// Tiny (20 cells), so the per-body CellSprite bake is free — the
    /// `CapturedReviewPhaseField` precedent at 1/200th the area.
    private var timeRail: some View {
        let lit = SIMD3<UInt8>(UInt8(SixFourCellMechanics.faceControlInk.r),
                               UInt8(SixFourCellMechanics.faceControlInk.g),
                               UInt8(SixFourCellMechanics.faceControlInk.b))
        let ghost = SFTheme.ledGhost
        let current = model.playhead.rungK
        return CellSprite(cols: 2, rows: 10, cellPt: GlobalLattice.gif(1)) { _, r in
            guard r % 4 < 2 else { return nil }   // the 2-row gaps
            let k = r / 4                          // block index == detent
            return k == current ? lit : ghost
        }
    }

    /// THE MERGE verb at a press location: map the press into the 64² plane
    /// (the scrub's own 2-cell bracket margin), find the region, play the
    /// verb. The board answers with the spec's verdict — accepted ticks,
    /// refused pulses dropReject. Off-tile presses are ignored.
    /// The scrub's bottom-edge readout, HONEST about what the pixels are: at
    /// the finest detent it names the exact frame; at a coarse detent the
    /// hero shows the GROUP's temporal integral (pixels identical across the
    /// window), so the readout names the whole window — never an exact-frame
    /// claim over blurred pixels.
    private var scrubReadout: String {
        let last = max(model.tiles.count, 1) - 1
        let k = Feature.decideTimeSlide ? model.playhead.rungK : 0
        guard k > 0 else { return "T \(model.frame)/\(last)" }
        let gs = TimeSlideMath.snapToGroupStart(model.frame, k: k)
        let ge = min(last, gs + TimeSlideMath.periodOf(k) - 1)
        return "T \(gs)-\(ge)/\(last)"
    }

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

    /// Everything that changes the hero's PIXELS (never the raw clock: the
    /// playhead enters ONLY as the realized `frame` + the detent `rungK`, so
    /// paused/idle ticks bake nothing and playing bakes once per 2^k ticks).
    /// ONE identity definition: the model's `HeroCacheKey` (every revision
    /// field lands there and nowhere else) plus the widget-only extras — the
    /// exact frame and the fallback inputs the cache never stores.
    private var imageKey: Int {
        var h = Hasher()
        h.combine(model.heroCacheKey(rungK: model.playhead.rungK,
                                     group: model.frame, useGene: model.useGene,
                                     mode: model.heroSource == .rungReads ? 1 : 0))
        h.combine(model.frame)
        h.combine(model.reconstructionsReady)
        h.combine(model.tiles.count)
        return h.finalize()
    }

    /// The REAL build: the 16³ proposal up-rung'd to 64³ (floor or the gene's
    /// invention) — what accepting would ship. No substrate yet ⇒ the honest
    /// fallback is the capture frame itself. Never a faked image. Either
    /// source then renders at THE MERGE's played granularity (`pooled`).
    ///
    /// THE TIME SLIDE's coarse detents (k > 0) bake the group's TEMPORAL
    /// INTEGRAL through the model's source seam (`integralSlice` — today the
    /// derived reconstruction; step B plugs the independent rung reads in
    /// there), cached per (detent, group, revisions) so loop 2+ of a coarse
    /// cycle is a dictionary hit. k=0 short-circuits below to today's
    /// `reconstructionSlice` path BYTE-IDENTICALLY. A coarse detent with no
    /// reconstruction yet falls through to the same honest fallback as k=0.
    /// Returns the image WITH the source its pixels actually came from —
    /// the chip renders that pair, so provenance can never outrun a refusal.
    private func bakeImage() -> (UIImage?, DecideModel.HeroSource) {
        // THE READS (step B, `Spec.RungReadDisplay`): when the ladder wrote
        // three independent cubes, every MERGE region renders from ITS OWN
        // read (`RungReads.composited` — select + causal hold, the SAME
        // sliceForTick hold during step-A playback, so playback and scrub
        // agree). BINARY WHOLE-HERO: any empty rung / realize failure drops
        // the ENTIRE frame to the derived path below (no intra-frame mixing
        // of camera sRGB8 with Q16-OKLab reconstruction). Derived bursts
        // never enter here — byte-for-byte today's hero.
        if model.heroSource == .rungReads {
            // The reads' pixels are independent of the DETENT (composited
            // holds on the display frame alone), so the key pins rungK to 0
            // — three detents share one entry per frame instead of tripling
            // the keyspace past the cache capacity.
            let key = model.heroCacheKey(rungK: 0,
                                         group: model.frame, useGene: false,
                                         mode: 1)
            if let hit = model.heroCached(key) { return (hit, .rungReads) }
            if let rgba = model.readsSlice(frame: model.frame),
               let cg = Self.rgbaImage(rgba, side: 64) {
                let img = UIImage(cgImage: cg)
                model.heroCacheStore(key, img)
                return (img, .rungReads)
            }
            // Composite refused — fall through to the honest derived path
            // (and the chip falls with it: the returned source is what BAKED).
        }
        if Feature.decideTimeSlide {
            // ONE cached path for every detent: coarse groups bake temporal
            // integrals; k=0 "groups" ARE the frames (periodOf(0) == 1) and
            // cache the plain slice — without this, the finest detent's
            // 3.2 s loop re-baked 64 pixel-identical images at 20 Hz forever
            // (the thermal budget is the standing priority).
            let k = model.playhead.rungK
            let j = model.frame / TimeSlideMath.periodOf(k)
            let key = model.heroCacheKey(rungK: k, group: j, useGene: model.useGene)
            if let hit = model.heroCached(key) { return (hit, .derived) }
            let rgba = k > 0
                ? model.integralSlice(rungK: k, group: j, useGene: model.useGene)
                : model.reconstructionSlice(frame: model.frame, useGene: model.useGene)
            if let rgba, let cg = Self.rgbaImage(pooled(rgba), side: 64) {
                let img = UIImage(cgImage: cg)
                model.heroCacheStore(key, img)
                return (img, .derived)
            }
            // No reconstruction yet — fall through to the honest fallback.
        }
        if let rgba = model.reconstructionSlice(frame: model.frame, useGene: model.useGene),
           let cg = Self.rgbaImage(pooled(rgba), side: 64) {
            return (UIImage(cgImage: cg), .derived)
        }
        guard model.tiles.indices.contains(model.frame) else { return (nil, .derived) }
        let tile = model.tiles[model.frame]
        var rgba = [UInt8]()
        rgba.reserveCapacity(tile.pixels.count * 4)
        for px in tile.pixels {
            let c = ColorScience.okLabToSRGB8(OKLab(px.x, px.y, px.z))
            rgba.append(contentsOf: [c.x, c.y, c.z, 255])
        }
        let shaped = tile.side == 64 ? pooled(rgba) : rgba
        if let cg = Self.rgbaImage(shaped, side: tile.side) { return (UIImage(cgImage: cg), .derived) }
        return (nil, .derived)
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
/// MEMOIZED PER LAYER: play-by-default cycles the same 16 layers forever
/// (5 Hz at the default detent), so each layer bakes ONCE per substrate
/// epoch and the permanent cadence is a pure image swap — never a perpetual
/// 256-conversion + UIImage alloc loop.
private struct DecideCoarseWidget: View {
    @ObservedObject var model: DecideModel
    @State private var layerCache: [Int: UIImage] = [:]
    @State private var cacheEpoch = -1

    var body: some View {
        let epoch = model.substrate.count
        let key = model.substrate.isEmpty ? -1 : model.paintLayer
        Group {
            if let img = layerCache[key] {
                Image(uiImage: img)
                    .interpolation(.none)
                    .resizable()
            } else {
                Color.clear
            }
        }
        .allowsHitTesting(false)
        .onChange(of: epoch, initial: true) { _, e in
            guard e != cacheEpoch else { return }
            cacheEpoch = e
            layerCache = [:]   // the substrate arrived/changed: all 16 stale
            if let img = bake(layer: key) { layerCache[key] = img }
        }
        .onChange(of: key) { _, k in
            guard layerCache[k] == nil, let img = bake(layer: k) else { return }
            layerCache[k] = img
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
