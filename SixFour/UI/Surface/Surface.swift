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

    /// The current 256-colour palette (sRGB8) the surface paints — the live per-frame
    /// palette during capture, frame-0's palette after a commit (the `palette` accessor).
    var palette: [SIMD3<UInt8>] = []

    /// The full PER-FRAME palette series (64 × 256 sRGB8) of the GIFA, populated at commit.
    /// Review renders the cube through THIS (not a single global palette replicated 64×), so
    /// the hero is the true per-frame GIFA the app produces — each frame its own 256 colours.
    /// Empty until a GIFA commits.
    var palettesPerFrame: [[SIMD3<UInt8>]] = []

    /// The 64×64×64 index cube (row-major `t,y,x`), populated once a GIFA exists.
    /// Empty until review. A flat buffer keeps the value type cheap to carry.
    var indexCube: [UInt8] = []

    /// The 16³ octree-coarse substrate — the byte-exact `VoxelReduce` reduction of the
    /// committed 64³ `indexCube`, in Q16 OKLab (`[frame'][position']`, 16 frames × 256
    /// positions). Built at `commit` by `buildCoarseSubstrate()`, read by `gifCell16` for the
    /// review bench's coarse tile. Empty until a capture commits; cleared on retake.
    var coarseSubstrate: [[VoxelReduce.Px]] = []

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

    /// The Z₆₄ playback cursor — the current frame `0..<64`. Advanced by κ each tick.
    var cursor: Int = 0

    /// OUT-OF-BAND diagnostic (NOT in the FSM alphabet): the human-readable reason the surface
    /// last entered `.error` — i.e. WHICH engine/bootstrap step failed. Set by `SurfaceView`
    /// alongside the `.fault` event so `ErrorPhaseField` shows the failing step instead of a blind
    /// "something went wrong" (turning a future white/black death into a readable on-screen fault).
    /// Transient; never persisted; never a δ event (mirrors the out-of-band UI-state discipline).
    var faultMessage: String? = nil

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
        if phase == .live { coarseSubstrate = []; curatedUseGene = nil }   // retake drops the per-capture stashes
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
        let side = cubeSide / 4                  // 64 → 16 (2 spatial levels)
        guard t16 >= 0, t16 < coarseSubstrate.count else { return nil }
        guard x >= 0, x < side, y >= 0, y < side else { return nil }
        let frame = coarseSubstrate[t16]
        let p = y * side + x
        guard p >= 0, p < frame.count else { return nil }
        let lab = frame[p]
        return SurfaceColor.oklabQ16ToSrgb8(SIMD3<Int32>(Int32(lab.0), Int32(lab.1), Int32(lab.2)))
    }

    /// Build (and cache) the 16³ coarse substrate from the committed 64³ cube. Each frame's
    /// indexed sRGB8 is mapped to OKLab Q16 through the owned Zig kernel (`srgb8ToOklab`, the
    /// one canonical forward), then `VoxelReduce.reduce` collapses 64³ → 16³ byte-exact. Called
    /// once at `commit`; the result feeds `gifCell16`. Clears to empty if no cube is committed.
    func buildCoarseSubstrate() {
        coarseSubstrate = []
        let side = cubeSide                       // 64
        let ppf = SixFourShape.pixelsPerFrame     // 4096
        guard !indexCube.isEmpty, !palettesPerFrame.isEmpty else { return }
        let frames = indexCube.count / ppf
        guard frames > 0, palettesPerFrame.count >= frames else { return }

        var cube = [[VoxelReduce.Px]]()
        cube.reserveCapacity(frames)
        for t in 0..<frames {
            let pal = palettesPerFrame[t]
            var rgb = [UInt8](); rgb.reserveCapacity(ppf * 3)
            for p in 0..<ppf {
                let idx = Int(indexCube[t * ppf + p])
                let c = idx < pal.count ? pal[idx] : SIMD3<UInt8>(0, 0, 0)
                rgb.append(c.x); rgb.append(c.y); rgb.append(c.z)
            }
            guard let q16 = SixFourNative.srgb8ToOklab(rgb: rgb, k: ppf) else { return }
            var frame = [VoxelReduce.Px](); frame.reserveCapacity(ppf)
            for p in 0..<ppf {
                frame.append((Int(q16[p * 3]), Int(q16[p * 3 + 1]), Int(q16[p * 3 + 2])))
            }
            cube.append(frame)
        }
        coarseSubstrate = VoxelReduce.reduce(2, side, cube).substrate
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
