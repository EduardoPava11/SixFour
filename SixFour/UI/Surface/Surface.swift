import Foundation
import Observation
import simd

/// σ — the ONE surface state. Every UI lifecycle "screen" is a phase of this single
/// field (`SixFour.Spec.Display.lawPhaseIsCellGrid`): capture → render → review are
/// cell updates on the one surface, never view swaps. The phase FSM is ported
/// bit-for-bit from `Generated/DisplayContract.swift` (`SixFourDisplay.phases` /
/// `.events`) and MUST reproduce `SixFourDisplay.goldenHappyPathTrace`. Review is
/// reachable ONLY via `.committed` (`lawReviewExplicit`).
///
/// Tier-2 pure: Foundation + Observation + simd only.

// MARK: - Phases (Σ)

/// The UI-lifecycle phases — the exact `SixFourDisplay.phases` tokens, one case each.
/// The rendering pipeline is its five sub-stages so the surface can show *which*
/// verified Zig kernel is running as a cell transform.
enum SurfacePhase: Equatable {
    case bootstrap
    case unauthorized
    case live
    case settings
    case locking
    case capturing
    case review
    case error
    case rendering(RenderStage)

    /// The five deterministic-core stages, in order — the `rendering:*` token suffixes.
    enum RenderStage: String, CaseIterable, Equatable {
        case quantize, dither, significance, palette, encode
    }

    /// The contract token for this phase — MUST be one of `SixFourDisplay.phases`.
    var token: String {
        switch self {
        case .bootstrap:        return "bootstrap"
        case .unauthorized:     return "unauthorized"
        case .live:             return "live"
        case .settings:         return "settings"
        case .locking:          return "locking"
        case .capturing:        return "capturing"
        case .review:           return "review"
        case .error:            return "error"
        case .rendering(let s): return "rendering:\(s.rawValue)"
        }
    }
}

// MARK: - Events (the FSM transition triggers)

/// The FSM events — the exact `SixFourDisplay.events` tokens. Out-of-band data
/// (palette bytes, the rendered GIF, progress) lives in Σ's fields, never here.
enum SurfaceEvent: Equatable {
    case sessionReady
    case authDenied
    case shutterTap
    case openSettings
    case closeSettings
    case lockComplete
    case burstComplete
    case committed
    case retake
    case fault
    case stageDone(SurfacePhase.RenderStage)

    /// The contract token — MUST be one of `SixFourDisplay.events`.
    var token: String {
        switch self {
        case .sessionReady:    return "sessionReady"
        case .authDenied:      return "authDenied"
        case .shutterTap:      return "shutterTap"
        case .openSettings:    return "openSettings"
        case .closeSettings:   return "closeSettings"
        case .lockComplete:    return "lockComplete"
        case .burstComplete:   return "burstComplete"
        case .committed:       return "committed"
        case .retake:          return "retake"
        case .fault:           return "fault"
        case .stageDone(let s): return "stageDone:\(s.rawValue)"
        }
    }
}

// MARK: - δ — the transition function

/// The pure FSM step `δ: (phase, event) → phase`, ported from the Display spec.
/// Total: any unmodelled (phase, event) pair is a no-op (stays in `phase`), so an
/// out-of-band event never derails the surface. `.fault` from any phase → `.error`.
/// Review is entered ONLY by `.committed` (`lawReviewExplicit`).
func surfaceStep(_ phase: SurfacePhase, _ event: SurfaceEvent) -> SurfacePhase {
    // A fault from anywhere drops to the error field.
    if case .fault = event { return .error }

    switch (phase, event) {
    case (.bootstrap, .sessionReady):   return .live
    case (.bootstrap, .authDenied):     return .unauthorized

    case (.live, .shutterTap):          return .locking
    case (.live, .openSettings):        return .settings
    case (.settings, .closeSettings):   return .live

    case (.locking, .lockComplete):     return .capturing
    case (.capturing, .burstComplete):  return .rendering(.quantize)

    // The verified Zig pipeline advances stage by stage.
    case (.rendering(.quantize), .stageDone(.quantize)):           return .rendering(.dither)
    case (.rendering(.dither), .stageDone(.dither)):               return .rendering(.significance)
    case (.rendering(.significance), .stageDone(.significance)):   return .rendering(.palette)
    case (.rendering(.palette), .stageDone(.palette)):             return .rendering(.encode)
    // The last stage completing does NOT enter review — only an explicit commit does
    // (`lawReviewExplicit`). encode stays on the encode field until `.committed`.
    case (.rendering(.encode), .stageDone(.encode)):               return .rendering(.encode)

    case (.rendering(.encode), .committed): return .review
    case (.review, .retake):                return .live

    default:
        return phase   // unmodelled pair → no-op
    }
}

// MARK: - σ — the observable surface

@MainActor
@Observable
final class Surface {

    // MARK: phase (Σ)

    /// The current lifecycle phase — ι = `.bootstrap`. A phase change is a cell
    /// update, never a view swap.
    private(set) var phase: SurfacePhase = .bootstrap

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

    /// The LIVE camera tile as 64×64 indexed cells (row-major `y·64 + x`) + its paired
    /// sRGB palette — the live hero paints the REAL camera through these (the cube law:
    /// 1 GIF pixel per cell). Distinct from `palette` (the throttled shutter/ground palette)
    /// because the preview uses its own full quantize→dither palette. Empty until the first
    /// quantized frame; the hero then falls back to the ghost ink.
    var previewTile: [UInt8] = []
    var previewPalette: [SIMD3<UInt8>] = []

    /// The Z₆₄ playback cursor — the current frame `0..<64`. Advanced by κ each tick.
    var cursor: Int = 0

    /// The cube pose for the 3D review hero, packed integers (yaw, pitch) in degrees.
    var pose: SIMD2<Int32> = .zero

    /// 0 = flat (2D GIF hero), 1 = cube (3D voxel hero). The review render mode.
    var playerMode: Int = 0

    /// The surface settings (dither / deterministic-core toggles), integer-encoded.
    var settings: SurfaceSettings = .init()

    // MARK: δ

    /// Apply one event — the single mutation point for the phase. Mirrors
    /// `surfaceStep` and is the only writer of `phase`.
    func step(_ event: SurfaceEvent) {
        phase = surfaceStep(phase, event)
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
}

// MARK: - The cube AS cells (per-cell rasterizer — replaces the Metal raymarch)

/// A baked `N×N` cell raster of the 64³ GIFA cube at one (cursor, rung) pose — produced by
/// `Surface.bakeCube` via FORWARD SCATTER (the cheap byte-identical equivalent of the proven
/// inverse z-buffer, `SixFour.Spec.VoxelFit.cubeRasterMap`). It is a plain value: the review
/// hero bakes one per body eval and reads it through the SAME `CellSprite` the preview uses.
/// `nil` cells = silhouette gaps where the live ground shows through (cell-field law).
struct CubeRaster {
    let n: Int
    let colors: [SIMD3<UInt8>]   // n·n, row-major; valid where `mask`
    let mask: [Bool]             // n·n; emptiness = false (NOT colour==0; 0 is a real index)

    /// The colour of output cell `(c, r)`, or `nil` if empty (ground shows through).
    func color(_ c: Int, _ r: Int) -> SIMD3<UInt8>? {
        guard n > 0, c >= 0, c < n, r >= 0, r < n else { return nil }
        let cell = r * n + c
        return mask[cell] ? colors[cell] : nil
    }

    static let empty = CubeRaster(n: 0, colors: [], mask: [])
}

extension Surface {
    /// Rasterize the GIFA cube to an `N×N` cell raster at rung `(xRung, yRung)`, played at the
    /// current `cursor` (the near face shows the cursor frame; deeper slices show trailing
    /// frames — the proven `frontFaceFrame` depth→frame map). FORWARD SCATTER, near→far, with a
    /// depth z-test so the nearest opaque voxel wins each cell. Reads the TRUE per-frame GIFA
    /// (`palettesPerFrame[f]`). Geometry pinned by `SixFourVoxelFit` (`cubeBox` + `project`);
    /// the front face (d=0) is byte-identical to the 2D GIF cell (`lawRasterizeFrontIsGif`).
    func bakeCube(xRung: Int, yRung: Int) -> CubeRaster {
        let side = cubeSide                         // 64
        let frames = SixFourShape.T                 // 64
        let pixels = side * side                    // 4096
        guard indexCube.count == pixels * frames,
              palettesPerFrame.count == frames else { return .empty }

        let box = SixFourVoxelFit.cubeBox(xRung: xRung, yRung: yRung)
        let h = box.h, cu = box.cu, cv = box.cv
        let n = 2 * h + 1
        let rx = min(max(xRung, 0), SixFourVoxelFit.maxRung)
        let ry = min(max(yRung, 0), SixFourVoxelFit.maxRung)
        let pivot = SixFourVoxelFit.voxelPivot      // 32 — CELL scale (1 voxel = 1 cell)

        var colors = [SIMD3<UInt8>](repeating: .zero, count: n * n)
        var mask = [Bool](repeating: false, count: n * n)
        var depth = [Int](repeating: Int.max, count: n * n)

        // Near (t = frames-1, d = 0) first → smallest d wins each cell (opaque occlusion).
        for t in stride(from: frames - 1, through: 0, by: -1) {
            let d = (side - 1) - t
            let f = ((cursor - d) % frames + frames) % frames   // displayed frame; near = cursor
            let pal = palettesPerFrame[f]
            let fbase = f * pixels
            for y in 0..<side {
                let vbase = (y - pivot) + ry * d - cv + h
                if vbase < 0 || vbase >= n { continue }
                let rowBase = vbase * n
                for x in 0..<side {
                    let cuu = (x - pivot) + rx * d - cu + h
                    if cuu < 0 || cuu >= n { continue }
                    let cell = rowBase + cuu
                    if d < depth[cell] {
                        depth[cell] = d
                        let idx = Int(indexCube[fbase + y * side + x])
                        colors[cell] = idx < pal.count ? pal[idx] : .zero
                        mask[cell] = true
                    }
                }
            }
        }
        return CubeRaster(n: n, colors: colors, mask: mask)
    }
}

/// Integer-encoded surface settings (no floats on the state spine). Expanded as
/// the per-phase renderers wire real options through.
struct SurfaceSettings: Equatable {
    /// Whether the deterministic fixed-point Zig core (vs the GPU float path) renders.
    var useDeterministicCore: Bool = true
}

// MARK: - Spec parity gate (debug)

extension Surface {
    /// Re-derives the golden happy-path trace by folding `surfaceStep` over the
    /// generated `SixFourDisplay.goldenHappyPathEvents`, and asserts it matches
    /// `SixFourDisplay.goldenHappyPathTrace` token-for-token — the live Swift↔Haskell
    /// parity pin for the phase FSM. Also runs the contract's own `selfCheck()`.
    /// Debug-only; release builds compile this to nothing.
    static func assertSpecParity() {
        #if DEBUG
        assert(SixFourDisplay.selfCheck(), "SixFourDisplay.selfCheck() failed")

        // Fold our step over the golden event tokens, starting at bootstrap.
        var phase = SurfacePhase.bootstrap
        var trace = [phase.token]
        for token in SixFourDisplay.goldenHappyPathEvents {
            guard let event = SurfaceEvent.fromToken(token) else {
                assertionFailure("unknown golden event token: \(token)")
                return
            }
            phase = surfaceStep(phase, event)
            trace.append(phase.token)
        }
        assert(trace == SixFourDisplay.goldenHappyPathTrace,
               "Surface.step trace \(trace) != golden \(SixFourDisplay.goldenHappyPathTrace)")
        #endif
    }
}

extension SurfaceEvent {
    /// Parse a contract event token back to an event (for the parity gate). The
    /// `stageDone:*` family carries its stage suffix.
    static func fromToken(_ token: String) -> SurfaceEvent? {
        switch token {
        case "sessionReady":  return .sessionReady
        case "authDenied":    return .authDenied
        case "shutterTap":    return .shutterTap
        case "openSettings":  return .openSettings
        case "closeSettings": return .closeSettings
        case "lockComplete":  return .lockComplete
        case "burstComplete": return .burstComplete
        case "committed":     return .committed
        case "retake":        return .retake
        case "fault":         return .fault
        default:
            guard token.hasPrefix("stageDone:"),
                  let stage = SurfacePhase.RenderStage(rawValue: String(token.dropFirst("stageDone:".count)))
            else { return nil }
            return .stageDone(stage)
        }
    }
}
