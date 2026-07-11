import Foundation
import Observation
import simd

/// σ — the ONE surface state. Every UI lifecycle "screen" is a phase of this single
/// field: capture → A/B → export are cell updates on the one surface, never view swaps.
/// The phase FSM is now the simplified `ABPhase` machine (`ABSurfaceMachine.swift`),
/// ported bit-for-bit from `Generated/ABSurfaceContract.swift` (`SixFourABSurface`) and
/// asserted by `ABPhase.assertSpecParity()`. `step(_:)` is the only writer of `phase`.
///
/// The old multi-phase Display FSM (`SurfacePhase` / `SurfaceEvent` / `surfaceStep`) is
/// RETIRED — the whole browse / refine / 5-stage-render lifecycle collapses to
/// capture → A/B → export. The CLOCK half (the 20 fps κ, the Z₆₄ cursor, the projections)
/// is unchanged.
///
/// Tier-2 pure: Foundation + Observation + simd only.

// MARK: - σ — the observable surface

@MainActor
@Observable
final class Surface {

    // MARK: phase (Σ)

    /// The current lifecycle phase — ι = `.bootstrap`. A phase change is a cell
    /// update, never a view swap. The A/B machine (`ABSurfaceMachine.swift`).
    private(set) var phase: ABPhase = .bootstrap

    // MARK: the field's data (out-of-band Σ)

    /// V3.0 (the `.deciding` surface): the committed burst's raw OKLab tiles, its somatic
    /// θ_up gene (nil == the deterministic floor), and — once the user accepts — the
    /// chosen model input + gene ride. Folded at `commit`; consumed by `DecidingPhaseField`
    /// and (later) the 256³ build.
    var burstTiles: [OKLabTile] = []
    var thetaUp: CaptureGene.ThetaUp?
    var acceptedInput: SixFourModelInput?
    var acceptedUseGene: Bool = false
    /// The curate excursion's verdict (LAUNCH L1.3): which detail source the user
    /// accepted at the 256³ curation surface (nil = never curated). Recorded by
    /// `Curating256PhaseField` on `.curateDone`; the export step's future input.
    /// Cleared on `.live` like every per-capture stash.
    var curatedUseGene: Bool?
    /// Mirrors the engine's flow version so late/invalidated flow arrivals are
    /// observable by VALUE change, not nil-ness (the Done bundle rebuild trigger).
    var v21FlowVersion: Int = 0

    /// THE ONTOLOGY: the committed render as a typed value — the canonical
    /// 64-side `Loop` (docs/REBUILD-2026-07-10-PLAN.md §2b). When present,
    /// `palettesPerFrame` / `indexCube` below are derived VIEWS of it,
    /// populated once at commit (the arrays stay stored as caches for the
    /// per-cell render cost of `gifCell`). nil before the first deterministic
    /// commit and on the float fallback path. UNIT 3 OWNERSHIP: all three are
    /// `private(set)` — the ONLY way in is `adopt(_:)` / `adoptLegacy(…)`, so
    /// no caller can ever desync the views from the value.
    private(set) var loop: Loop? = nil

    /// Adopt a committed render as the typed value: σ.loop plus every derived
    /// view (`palettesPerFrame`, `indexCube`, frame-0 `palette`) populated
    /// from it atomically — one owner, byte-identical to the legacy arrays by
    /// the same golden kernels (LoopPipelineParityTests). Returns false (and
    /// mutates NOTHING) if the palette view fails, so the caller can fall
    /// back to `adoptLegacy`.
    func adopt(_ newLoop: Loop) -> Bool {
        guard let pals = newLoop.srgb8Palettes() else { return false }
        loop = newLoop
        palettesPerFrame = pals
        if let pal = pals.first { palette = pal }
        indexCube = newLoop.cels.flatMap { $0.plane.indices }
        return true
    }

    /// The float-fallback commit (no deterministic Loop exists): populate the
    /// arrays exactly as the pre-ontology path did, and mark the typed value
    /// absent. `frameIndices` nil leaves the previous cube untouched
    /// (matching the legacy behaviour for outputs without voxel indices).
    func adoptLegacy(palettesPerFrame pals: [[SIMD3<UInt8>]], frameIndices: [[UInt8]]?) {
        loop = nil
        palettesPerFrame = pals
        if let pal = pals.first { palette = pal }
        if let frames = frameIndices {
            var cube = [UInt8]()
            cube.reserveCapacity(frames.count * SixFourShape.pixelsPerFrame)
            for f in frames { cube.append(contentsOf: f) }
            indexCube = cube
        }
    }

    /// The current 256-colour palette (sRGB8) the surface paints — the live per-frame
    /// palette during capture, frame-0's palette after a commit (the `palette` accessor).
    var palette: [SIMD3<UInt8>] = []

    /// The full PER-FRAME palette series (64 × 256 sRGB8) of the GIFA, populated at commit.
    /// Review renders the cube through THIS (not a single global palette replicated 64×), so
    /// the hero is the true per-frame GIFA the app produces — each frame its own 256 colours.
    /// Empty until a GIFA commits.
    private(set) var palettesPerFrame: [[SIMD3<UInt8>]] = []

    /// The 64×64×64 index cube (row-major `t,y,x`), populated once a GIFA exists.
    /// Empty until review. A flat buffer keeps the value type cheap to carry.
    private(set) var indexCube: [UInt8] = []

    /// The 16³ octree-coarse substrate — the byte-exact `VoxelReduce` reduction of the
    /// committed 64³ `indexCube`, in Q16 OKLab (`[frame'][position']`, 16 frames × 256
    /// positions). Built at `commit` by `buildCoarseSubstrate()`, read by `gifCell16` for the
    /// review bench's coarse tile. Empty until a capture commits; cleared on retake.
    var coarseSubstrate: [[VoxelReduce.Px]] = []

    /// The 32³ MID substrate — the `VoxelReduce` reduction ONE isotropic level down from the
    /// 64³ (32 frames × 32×32, Q16 OKLab), the middle rung between `coarseSubstrate` (16³) and
    /// the raw `indexCube` (64³). Built alongside the coarse in `buildCoarseSubstrate()`, read
    /// by `gifCell32`. These three cubes are the ONLY honest views of the capture: each is a
    /// byte-exact pool of the photons, never invention (256³ would be invented — deliberately
    /// not offered). The view toggle walks them via `sceneRung`.
    var midSubstrate: [[VoxelReduce.Px]] = []

    /// Which of the three honest cube rungs the scene is showing (default: the full 64³). The
    /// review scene reads `sceneCell(_:_:cursor:rung:)` at this rung; a byte-exact pool of the
    /// same capture, block-replicated into the same footprint so coarser = chunkier, never
    /// smaller. Reset to `.fine64` on retake.
    var sceneRung: SceneRung = .fine64

    /// The committed GIF file on disk — the Review Share source. Set by `commit(_:)` from
    /// the engine's `CaptureOutput.gifURL`; `nil` until a GIFA is rendered.
    var gifURL: URL?

    /// V2.1 (Feature.v21Capture only): the time-pooled camera-box probability field `[y,x,3,256]`
    /// Int32 counts from the last burst (the GPU `v21AccumulateHistKernel` pooled). Set by
    /// `SurfaceView.commit` from the engine; the review bench's FIELD / AIRDROP prefer it over the
    /// index-cube proxy. `nil` when the flag is off or the GPU field was unavailable.
    var v21Counts: [Int32]?

    /// The last burst's transport FLOW (barycenter anchor + per-frame RLE maps): the recovered time
    /// axis. Set by `SurfaceView.commit` from the engine; the export ships this instead of the pooled
    /// field, so a moving capture stays trainable. `nil` when off or the GPU field was unavailable.
    var v21Flow: V21Flow?

    /// The LIVE camera tile as 64×64 indexed cells (row-major `y·64 + x`) + its paired
    /// sRGB palette — the live hero paints the REAL camera through these (the cube law:
    /// 1 GIF pixel per cell). Distinct from `palette` (the throttled shutter/ground palette)
    /// because the preview uses its own full quantize→dither palette. Empty until the first
    /// quantized frame; the hero then falls back to the ghost ink.
    var previewTile: [UInt8] = []
    var previewPalette: [SIMD3<UInt8>] = []

    /// LIVE-LADDER (Feature.liveLadder only): the realized 32² (1024) and 16² (256) RGB
    /// ladder tiles from the persistent preview `ColorHead`, LOOK-graded like
    /// `previewPalette`. `InvertedPyramidField` reads these for its 32²/16² rungs when the
    /// flag is on; empty (the flag off ⇒ the callback never fires) ⇒ the pyramid falls
    /// back to in-view `poolSpatial2`. Display-only; not a per-capture stash to clear.
    var previewTile32: [SIMD3<UInt8>] = []
    var previewTile16: [SIMD3<UInt8>] = []
    /// THE FLUX BAR (THE DESIGN E6): the freshest 768-byte GCT (256 slots × RGB) from
    /// whichever ColorHead is live, at the ≤ 5 Hz 16-rung cadence. `FluxBar` differences
    /// consecutive values through `s4_v21_wdist1d` (paletteW1 — the wave meter). nil until
    /// a head realizes one; the last value then persists (an instrument, not a stash).
    var latestGCT: [UInt8]? = nil

    /// OPTICAL-EV (Feature.opticalEV only): three REAL-exposure rung tiles, each a distinct
    /// optical exposure realized to sRGB8 (64²=base / 32²=+1 / 16²=+2 stops). Empty while off.
    var opticalTile64: [SIMD3<UInt8>] = []
    var opticalTile32: [SIMD3<UInt8>] = []
    var opticalTile16: [SIMD3<UInt8>] = []

    /// RUNG TELEMETRY (Feature.rungTelemetry only): the latest per-rung instrument
    /// snapshot — exposure state, arrival pulse, √N significance, independence
    /// health — folded from the engine by `RungTelemetryFolds` at the ≤ 5 Hz rung
    /// cadence + the burst seam. The `liveScene` rung64/rung32/rung16 flank regions
    /// (`RungTelemetryFlanks`) read it. nil until a burst runs; the last burst's
    /// final snapshot then persists (an instrument, not a per-capture stash).
    var rungTelemetry: RungTelemetry?

    /// SYSTEM TELEMETRY (Feature.rungTelemetry only): tick CPU vs the 50 ms budget,
    /// the v21 hist-buffer lifecycle, thermal/system pressure — published on change
    /// and at burst boundaries only. The `liveScene` system region reads it.
    var systemTelemetry: SystemTelemetry?

    /// THE READS (step B, `Spec.RungReadDisplay`): the committed burst's realized
    /// per-rung read volumes, folded from the engine at `commit` PLUS a late
    /// `.onChange` fold (the realize runs detached and lands after `BurstResult` —
    /// the attachGene/attachSubstrate arrival pattern). The Decide hero renders
    /// each MERGE region from ITS OWN read when `independent` (ladder bursts
    /// only); derived bursts carry the honest c16-only subset and the hero stays
    /// on the pooled reconstruction. PER-CAPTURE stash: cleared on `.live` like
    /// `acceptedInput` (stale-reads-under-fresh-board is the σ-lifecycle hazard).
    var rungReads: RungReads?

    /// The capture's IMMUTABLE pour schedule (`Spec.MergeEvidence`), folded from
    /// the engine at `commit` — installed into `DecideModel` AT CONSTRUCTION
    /// (before the first pour can happen; a mid-game swap breaks
    /// `lawWordReplaysBoardUnderSchedule`). ALWAYS priced from the sealed
    /// telemetry (the flag-free replay-keystone rule); derived bursts price
    /// to the constant. PER-CAPTURE stash: reset to the constant on `.live`.
    var mergePourSchedule: [Int] = S4MergeBoard.derivedSchedule

    /// The Z₆₄ playback cursor — the current frame `0..<64`. Advanced by κ each tick.
    var cursor: Int = 0

    /// OUT-OF-BAND diagnostic (NOT in the FSM alphabet): the human-readable reason the surface
    /// last entered `.error` — i.e. WHICH engine/bootstrap step failed. Set by `SurfaceView`
    /// alongside the `.fault` event so `ErrorPhaseField` shows the failing step instead of a blind
    /// "something went wrong" (turning a future white/black death into a readable on-screen fault).
    /// Transient; never persisted; never a δ event (mirrors the out-of-band UI-state discipline).
    var faultMessage: String? = nil

    /// OUT-OF-BAND UI state (NOT in the FSM alphabet): THE SCROLL self-excursion flag —
    /// `.live` shows `ScrollPhaseField` (the infinite tube) instead of the pyramid while
    /// this is true (`Feature.scrollTube` gated). Pure render state, exactly like the
    /// Decide fold: never a δ event, never persisted; cleared by `SurfaceView` whenever
    /// the phase leaves `.live`, so a fault/capture can never strand the surface here.
    var scrollTube: Bool = false

    /// OUT-OF-BAND UI state (NOT in the FSM alphabet): which ColorWidget is currently LIFTED for
    /// a move, or `nil`. The influence-field ground reads this to CALM the radiation while a
    /// widget is being lifted out of the field (order is being rearranged → the chaos recedes).
    /// Transient; never persisted; never an `δ` event (mirrors the Display out-of-band discipline).
    var liftedWidget: ColorIdentity? = nil

    /// OUT-OF-BAND ANIMATION STATE (Ints, not events) — the κ tick at which an eased per-tick
    /// transition began, so the renderers can compute `CellEase.progress(tick, since:, ticks:)`
    /// at the fixed 20 fps cadence (docs/SIXFOUR-CELL-FLUIDITY-WORKFLOW.md). Set by `SurfaceView`.
    /// `phaseEnteredTick` drives the eased act-to-act transition; `liftChangedTick` the lift-dim ramp.
    var phaseEnteredTick: Int = 0
    var liftChangedTick: Int = 0

    // MARK: δ

    /// Apply one event — the single mutation point for the phase. Mirrors
    /// `abStep` (`ABSurfaceMachine.swift`) and is the only writer of `phase`.
    func step(_ event: ABEvent) {
        phase = abStep(phase, event)
        if phase == .live {                                    // retake drops the per-capture stashes
            coarseSubstrate = []; midSubstrate = []; sceneRung = .fine64; curatedUseGene = nil
            rungReads = nil; mergePourSchedule = S4MergeBoard.derivedSchedule
        }
    }

    // MARK: κ-fed cursor advance (Z₆₄)

    /// Advance the playback cursor one frame mod 64 — routed through the spec-pinned
    /// `SixFourPlaybackClock.frameAfter` (the ONE κ math). Called by `SurfaceClock`.
    func advanceCursor() {
        cursor = SixFourPlaybackClock.frameAfter(cursor, count: SixFourPlaybackClock.frameCount)
    }
}

// MARK: - The ONE addressing function (cells × frames)

extension Surface {
    /// The volume side — the spec-pinned 64 (`SixFourShape.W`). One definition for the
    /// row-major `t·side² + y·side + x` layout every reader of the cube shares.
    var cubeSide: Int { SixFourShape.W }

    /// THE 2D GIFA reader — the colour of pixel `(x, y)` in frame `t` of the committed
    /// GIFA, read through the TRUE per-frame palette (`palettesPerFrame[t]`), one cell per
    /// GIF pixel. This is the flat 2D animation the review hero plays (the cube reveal is
    /// retired): a pure projection of σ's `indexCube` at the cursor frame. Returns `nil`
    /// until a GIFA commits (the live ground shows through), so no flat fill is ever drawn.
    func gifCell(_ x: Int, _ y: Int, _ t: Int) -> SIMD3<UInt8>? {
        let side = cubeSide
        guard t >= 0, t < palettesPerFrame.count else { return nil }
        return gifCell(x, y, t, palette: palettesPerFrame[t])
    }

    /// THE 2D GIFA reader, generalized over an EXPLICIT per-frame palette + index buffer —
    /// so the A/B game's two competing candidate looks read the SAME cube projection the
    /// review hero does (the `t·side² + y·side + x` offset is the one cube-index law). `palette`
    /// is the candidate's frame-`t` 256 sRGB8; `indexFrame` (when non-empty) is that candidate's
    /// RE-QUANTIZED frame indices (`y·side + x`, P3 — A and B are genuinely different cubes),
    /// falling back to the shared `indexCube` when the candidate cube isn't available. Returns
    /// `nil` (the live ground shows through, no flat fill) for any out-of-range address.
    func gifCell(_ x: Int, _ y: Int, _ t: Int,
                 palette: [SIMD3<UInt8>], indexFrame: [UInt8] = []) -> SIMD3<UInt8>? {
        let side = cubeSide
        guard x >= 0, x < side, y >= 0, y < side, t >= 0 else { return nil }
        let i: Int
        if !indexFrame.isEmpty {
            let off = y * side + x
            guard off >= 0, off < indexFrame.count else { return nil }
            i = Int(indexFrame[off])
        } else {
            let offset = t * side * side + y * side + x
            guard offset >= 0, offset < indexCube.count else { return nil }
            i = Int(indexCube[offset])
        }
        guard i >= 0, i < palette.count else { return nil }
        return palette[i]
    }

    // MARK: - 16³ octree coarse (the review bench's coarse tile)

    /// One cell of the 16³ octree-coarse tile at coarse-frame `t16` (0..<16). The substrate is
    /// the byte-exact `VoxelReduce` reduction of the committed 64³ cube — the same coarse tier
    /// the model reads — mapped back to sRGB8 through the canonical Q16 OKLab gamma path.
    /// Returns `nil` until `buildCoarseSubstrate()` has run on a committed cube.
    func gifCell16(_ x: Int, _ y: Int, _ t16: Int) -> SIMD3<UInt8>? {
        substrateCell(coarseSubstrate, side: cubeSide / 4, x, y, t16)   // 64 → 16 (2 levels)
    }

    /// One cell of the 32³ MID tile at mid-frame `t32` (0..<32) — the same reader as `gifCell16`
    /// one isotropic level up (side 32). Reads `midSubstrate`; `nil` until it is built.
    func gifCell32(_ x: Int, _ y: Int, _ t32: Int) -> SIMD3<UInt8>? {
        substrateCell(midSubstrate, side: cubeSide / 2, x, y, t32)      // 64 → 32 (1 level)
    }

    /// Shared Q16-OKLab substrate reader (the `gifCell16`/`gifCell32` body): `substrate` is
    /// `[frame'][position']`, `side` its spatial side. Out-of-range → `nil` (ground shows through).
    private func substrateCell(_ substrate: [[VoxelReduce.Px]], side: Int,
                               _ x: Int, _ y: Int, _ t: Int) -> SIMD3<UInt8>? {
        guard t >= 0, t < substrate.count, x >= 0, x < side, y >= 0, y < side else { return nil }
        let frame = substrate[t]
        let p = y * side + x
        guard p >= 0, p < frame.count else { return nil }
        let lab = frame[p]
        return SurfaceColor.oklabQ16ToSrgb8(SIMD3<Int32>(Int32(lab.0), Int32(lab.1), Int32(lab.2)))
    }

    /// THE THREE-CUBE READER: one cell of the scene at `rung`, driven by the shared Z₆₄ playback
    /// `cursor` (0..<64). The coarser rungs have fewer frames (32³→32, 16³→16), so the cursor is
    /// mapped down proportionally (`cursor·rungFrames/64`) — the three rungs animate in lockstep.
    /// `fine64` reads the raw `indexCube` through its per-frame palette; the coarse rungs read the
    /// byte-exact OKLab substrates. All three are exact pools of the capture (no invention).
    func sceneCell(_ x: Int, _ y: Int, cursor t: Int, rung: SceneRung) -> SIMD3<UInt8>? {
        switch rung {
        case .fine64:   return gifCell(x, y, t)
        case .mid32:    return gifCell32(x, y, (t * 32) / cubeSide)
        case .coarse16: return gifCell16(x, y, (t * 16) / cubeSide)
        }
    }

    /// Build (and cache) the 16³ coarse substrate from the committed 64³ cube. Each frame's
    /// indexed sRGB8 is mapped to OKLab Q16 through the owned Zig kernel (`srgb8ToOklab`, the
    /// one canonical forward), then `VoxelReduce.reduce` collapses 64³ → 16³ byte-exact. Called
    /// once at `commit`; the result feeds `gifCell16`. Clears to empty if no cube is committed.
    ///
    /// OFF-MAIN since QoL 2026-07-03: the 262K-pixel reindex + 64 Zig OKLab calls +
    /// the VoxelReduce ran synchronously INSIDE the σ fold (a main-thread hitch right at
    /// the `.done` transition). The heavy pass is now a pure detached function over value
    /// snapshots; σ publishes the result when it lands, and consumers that mounted early
    /// attach it late (the async-gene pattern — `DecideModel.attachSubstrate`).
    func buildCoarseSubstrate() {
        coarseSubstrate = []
        midSubstrate = []
        let side = cubeSide                       // 64
        let ppf = SixFourShape.pixelsPerFrame     // 4096
        guard !indexCube.isEmpty, !palettesPerFrame.isEmpty else { return }
        let frames = indexCube.count / ppf
        guard frames > 0, palettesPerFrame.count >= frames else { return }
        let idx = indexCube
        let pals = palettesPerFrame
        Task { [weak self] in
            let (coarse, mid) = await Task.detached(priority: .userInitiated) {
                Self.reduceScenePyramid(indexCube: idx, palettes: pals,
                                        frames: frames, side: side, ppf: ppf)
            }.value
            self?.coarseSubstrate = coarse
            self?.midSubstrate = mid
        }
    }

    /// The pure heavy pass (value-in / value-out, runs detached): indexed sRGB8 → OKLab Q16
    /// (owned Zig kernel) once, then TWO byte-exact `VoxelReduce` reductions of the same cube —
    /// `(16³ = reduce level 2, 32³ = reduce level 1)`. Both share the OKLab conversion, so the
    /// mid rung is nearly free. Returns `([], [])` if the OKLab kernel refuses a frame.
    private nonisolated static func reduceScenePyramid(
        indexCube: [UInt8], palettes: [[SIMD3<UInt8>]],
        frames: Int, side: Int, ppf: Int
    ) -> (coarse16: [[VoxelReduce.Px]], mid32: [[VoxelReduce.Px]]) {
        var cube = [[VoxelReduce.Px]]()
        cube.reserveCapacity(frames)
        for t in 0..<frames {
            let pal = palettes[t]
            var rgb = [UInt8](); rgb.reserveCapacity(ppf * 3)
            for p in 0..<ppf {
                let idx = Int(indexCube[t * ppf + p])
                let c = idx < pal.count ? pal[idx] : SIMD3<UInt8>(0, 0, 0)
                rgb.append(c.x); rgb.append(c.y); rgb.append(c.z)
            }
            guard let q16 = SixFourNative.srgb8ToOklab(rgb: rgb, k: ppf) else { return ([], []) }
            var frame = [VoxelReduce.Px](); frame.reserveCapacity(ppf)
            for p in 0..<ppf {
                frame.append((Int(q16[p * 3]), Int(q16[p * 3 + 1]), Int(q16[p * 3 + 2])))
            }
            cube.append(frame)
        }
        return (VoxelReduce.reduce(2, side, cube).substrate,   // 64³ → 16³
                VoxelReduce.reduce(1, side, cube).substrate)   // 64³ → 32³
    }
}

/// THE THREE HONEST CUBE RUNGS — the isotropic octant ladder within capture. Each is a
/// byte-exact `VoxelReduce` pool of the same 64³ photons (space AND time halved per level),
/// so all three are TRUE readings of the scene, never invention. 256³ is deliberately absent
/// (it would be invented, not measured). `side³` voxels, block-replicated into the same
/// footprint — coarser reads as chunkier, never smaller.
enum SceneRung: Int, CaseIterable, Sendable {
    case coarse16 = 16
    case mid32 = 32
    case fine64 = 64

    /// The spatial (and temporal) side of this rung's cube.
    var side: Int { rawValue }
    /// The display label ("16³" / "32³" / "64³").
    var label: String { "\(rawValue)³" }
    /// Cycle coarse → mid → fine → coarse (the toggle's forward step).
    var next: SceneRung {
        switch self { case .coarse16: return .mid32; case .mid32: return .fine64; case .fine64: return .coarse16 }
    }
}

// The 3D cube reveal (`CubeRaster` + `Surface.bakeCube`, the x/y rung-shear rasterizer)
// is RETIRED — the review hero is now the flat 2D GIFA animation (`gifCell`). The cube
// geometry remains proven in `SixFour.Spec.VoxelFit` for the (deferred) authoring tool;
// the live render path no longer consumes it. (Simplify the 2D animation; harden the flow.)

// MARK: - Spec parity gate (debug)

extension Surface {
    /// Re-asserts the live Swift↔Haskell parity pins. The phase-FSM pin is now the A/B
    /// machine's own gate (`ABPhase.assertSpecParity()`, folding `abStep` over
    /// `SixFourABSurface.goldenHappyPathEvents`); the other contract self-checks (move /
    /// cell-mechanics / boundary / field-tuning / influence-field) + the MoveContract
    /// golden fold are kept. Debug-only; release builds compile this to nothing.
    static func assertSpecParity() {
        #if DEBUG
        // Phase-FSM parity: the simplified capture → A/B → export machine.
        ABPhase.assertSpecParity()

        // Movable ColorWidget parity: re-fold the generated `move` over `goldenScript`
        // from `defaultPlacement` and assert it reproduces `goldenAfter` — the live
        // Swift↔Haskell bit-pin of the move operator (mirrors the Display golden trace
        // fold above). `MoveContract.selfCheck()` re-asserts the seed laws + the fold.
        assert(MoveContract.selfCheck(), "MoveContract.selfCheck() failed")

        // Cell-mechanics parity: re-fold the golden gesture through the generated FSM,
        // re-derive the golden haptics + pulse — the live Swift↔Haskell pin of the
        // interaction algebra (lifetime / detent / haptics / reactive pulse).
        assert(SixFourCellMechanics.selfCheck(), "SixFourCellMechanics.selfCheck() failed")

        // Geometry + field parity: the Stage (byte-exact), the field params, and the field
        // FUNCTION golden (noise hash byte-exact + falloff within ε) — the live Swift↔Haskell pin
        // for the influence-field architecture (the same primitives the Metal shader will use).
        assert(SixFourBoundary.selfCheck(), "SixFourBoundary.selfCheck() failed")
        assert(SixFourFieldTuning.selfCheck(), "SixFourFieldTuning.selfCheck() failed")
        assert(SixFourInfluenceFieldGolden.selfCheck(), "SixFourInfluenceFieldGolden.selfCheck() failed")
        var placement = MoveContract.defaultPlacement
        for step in MoveContract.goldenScript {
            placement = MoveContract.move(placement, step.id, dCol: step.dCol, dRow: step.dRow)
        }
        let goldenParity = ColorIdentity.allCases.allSatisfy { i in
            placement[i]?.col == MoveContract.goldenAfter[i]?.col
                && placement[i]?.row == MoveContract.goldenAfter[i]?.row
        }
        assert(goldenParity, "MoveContract.move fold != goldenAfter")
        #endif
    }
}
