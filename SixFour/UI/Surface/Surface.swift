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
    /// palette during capture, frame-0's palette in review (the `cellGlobal` accessor).
    var palette: [SIMD3<UInt8>] = []

    /// The full PER-FRAME palette series (64 × 256 sRGB8) of the GIFA, populated at commit.
    /// Review renders the cube through THIS (not a single global palette replicated 64×), so
    /// the hero is the true per-frame GIFA the app produces — each frame its own 256 colours.
    /// Empty until a GIFA commits.
    var palettesPerFrame: [[SIMD3<UInt8>]] = []

    /// The 64×64×64 index cube (row-major `t,y,x`), populated once a GIFA exists.
    /// Empty until review. A flat buffer keeps the value type cheap to carry.
    var indexCube: [UInt8] = []

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

    // DEPRECATED (browse flow cut; kept so unrouted fields compile) — the 4 ORDERED anchor
    // frames the old `.browsing` flow let the user pick. The browse phase is gone under
    // ABSurface; this field stays only so the unrouted Browsing/Review fields still build.
    // Reset to `[]` on `.live`.
    var picks: [Int] = []

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

    /// REAL render progress 0→1 (the deterministic core's `loadingProgress`), bridged from the engine
    /// while `.rendering`. Drives the GIFA construction reveal (`RenderingPhaseField`) — monotonic
    /// across the whole render, NOT a per-stage clock timer (which snapped back to black each stage).
    var renderProgress: Double = 0


    /// The surface settings (dither / deterministic-core toggles), integer-encoded.
    var settings: SurfaceSettings = .init()

    // MARK: δ

    /// Apply one event — the single mutation point for the phase. Mirrors
    /// `abStep` (`ABSurfaceMachine.swift`) and is the only writer of `phase`.
    func step(_ event: ABEvent) {
        phase = abStep(phase, event)
        // Out-of-band Σ housekeeping: returning to `.live` clears any vestigial picks.
        if phase == .live { picks = [] }
    }

    // MARK: - Browsing picks (out-of-band Σ — vestigial)

    // DEPRECATED (browse flow cut; kept so unrouted fields compile).
    /// Toggle frame `f` in the ordered pick list: a re-tap REMOVES it; otherwise it is
    /// APPENDED (preserving pick order) while fewer than 4 are chosen — the 5th tap is
    /// rejected (the cap is 4, the quad). Mutates only the out-of-band σ field, never `phase`.
    func togglePick(_ f: Int) {
        guard f >= 0, f < SixFourPlaybackClock.frameCount else { return }
        if let i = picks.firstIndex(of: f) {
            picks.remove(at: i)
        } else if picks.count < 4 {
            picks.append(f)
        }
    }

    // DEPRECATED (browse flow cut; kept so unrouted fields compile).
    /// Move the playback cursor to frame `f` directly (the old finger-driven browse scrub).
    /// Clamps to `0..<64`; writes `cursor` with NO FSM event.
    func scrubCursor(to f: Int) {
        cursor = max(0, min(SixFourPlaybackClock.frameCount - 1, f))
    }

    // MARK: κ-fed cursor advance (Z₆₄)

    /// Advance the playback cursor one frame mod 64 — routed through the spec-pinned
    /// `SixFourPlaybackClock.frameAfter` (the ONE κ math). Called by `SurfaceClock`.
    func advanceCursor() {
        cursor = SixFourPlaybackClock.frameAfter(cursor, count: SixFourPlaybackClock.frameCount)
    }

    /// Advance the cursor one frame BACKWARDS — the Act-II no-freeze reverse playback.
    /// While `.capturing` / `.rendering` the surface sweeps the assembling GIFA backwards
    /// (`SixFourPlaybackClock.frameBefore`, the spec-pinned inverse of `frameAfter`)
    /// instead of holding a frozen frame. Same single κ, opposite direction.
    func advanceCursorReverse() {
        cursor = SixFourPlaybackClock.frameBefore(cursor, count: SixFourPlaybackClock.frameCount)
    }
}

// MARK: - The ONE addressing function (cells × frames)

extension Surface {
    /// The volume side — the spec-pinned 64 (`SixFourShape.W`). One definition for the
    /// row-major `t·side² + y·side + x` layout every reader of the cube shares.
    var cubeSide: Int { SixFourShape.W }

    /// THE addressing function: the colour of voxel `(x, y, t)` in the review/loading
    /// cube — a WHERE `(x,y)` at a WHEN `t`. Reads `indexCube` (row-major `t,y,x`) through
    /// the global `palette`. Returns `nil` when the cube isn't populated at `(x,y,t)` yet,
    /// so the caller lets the live ground show through (no flat fill).
    ///
    /// Named `cellGlobal` because `palette` is the single REVIEW palette; the per-frame
    /// live tile and the per-frame palette series carry their own bytes. This is the one
    /// place the cube's index layout lives — `RenderingPhaseField` (loading) and the
    /// review-flat path read through it, not their own inline `t*4096+y*64+x`.
    func cellGlobal(_ x: Int, _ y: Int, _ t: Int) -> SIMD3<UInt8>? {
        let side = cubeSide
        guard x >= 0, x < side, y >= 0, y < side, t >= 0 else { return nil }
        let offset = t * side * side + y * side + x
        guard offset >= 0, offset < indexCube.count else { return nil }
        let i = Int(indexCube[offset])
        guard i >= 0, i < palette.count else { return nil }
        return palette[i]
    }

    /// THE 2D GIFA reader — the colour of pixel `(x, y)` in frame `t` of the committed
    /// GIFA, read through the TRUE per-frame palette (`palettesPerFrame[t]`), one cell per
    /// GIF pixel. This is the flat 2D animation the review hero plays (the cube reveal is
    /// retired): a pure projection of σ's `indexCube` at the cursor frame. Returns `nil`
    /// until a GIFA commits (the live ground shows through), so no flat fill is ever drawn.
    func gifCell(_ x: Int, _ y: Int, _ t: Int) -> SIMD3<UInt8>? {
        let side = cubeSide
        guard x >= 0, x < side, y >= 0, y < side, t >= 0, t < palettesPerFrame.count else { return nil }
        let offset = t * side * side + y * side + x
        guard offset >= 0, offset < indexCube.count else { return nil }
        let pal = palettesPerFrame[t]
        let i = Int(indexCube[offset])
        guard i >= 0, i < pal.count else { return nil }
        return pal[i]
    }
}

// The 3D cube reveal (`CubeRaster` + `Surface.bakeCube`, the x/y rung-shear rasterizer)
// is RETIRED — the review hero is now the flat 2D GIFA animation (`gifCell`). The cube
// geometry remains proven in `SixFour.Spec.VoxelFit` for the (deferred) authoring tool;
// the live render path no longer consumes it. (Simplify the 2D animation; harden the flow.)

/// Integer-encoded surface settings (no floats on the state spine). Expanded as
/// the per-phase renderers wire real options through.
struct SurfaceSettings: Equatable {
    /// Whether the deterministic fixed-point Zig core (vs the GPU float path) renders.
    var useDeterministicCore: Bool = true
}

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
