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

    /// The 64 ORIGINAL per-frame OKLab pixels in Q16 (each `pixelsPerFrame·3` Int32), retained
    /// at capture so the A/B game can RE-QUANTIZE every frame against a candidate genome's
    /// displaced palette (P3 — genome shapes the BYTES: A and B become genuinely different
    /// index cubes via `s4_dither_frame`, not just two recolours of one shared cube). Empty
    /// until a capture commits, or when the raw tiles aren't retained (then A/B fall back to
    /// recolouring the shared `indexCube`).
    var framePixelsQ16: [[Int32]] = []

    /// The committed GIF file on disk — the Review Share source. Set by `commit(_:)` from
    /// the engine's `CaptureOutput.gifURL`; `nil` until a GIFA is rendered.
    var gifURL: URL?

    /// The LIVE camera tile as 64×64 indexed cells (row-major `y·64 + x`) + its paired
    /// sRGB palette — the live hero paints the REAL camera through these (the cube law:
    /// 1 GIF pixel per cell). Distinct from `palette` (the throttled shutter/ground palette)
    /// because the preview uses its own full quantize→dither palette. Empty until the first
    /// quantized frame; the hero then falls back to the ghost ink.
    var previewTile: [UInt8] = []
    var previewPalette: [SIMD3<UInt8>] = []

    /// The Z₆₄ playback cursor — the current frame `0..<64`. Advanced by κ each tick.
    var cursor: Int = 0

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
