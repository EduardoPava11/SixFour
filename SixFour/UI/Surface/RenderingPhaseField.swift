import SwiftUI
import simd

/// Π for the `rendering(stage)` phase — the deterministic-core resolve field.
///
/// The verified fixed-point Zig pipeline runs in five ordered stages (quantize →
/// dither → significance → palette → encode; `SurfacePhase.RenderStage`). This field
/// makes that run VISIBLE as a cell transform, not a spinner: an on-grid serpentine
/// "resolve sweep" advances across the 64×64 surface as the stages complete, revealing
/// the GIFA-in-progress underneath, with the deterministic stage token shown as a cell
/// banner (σ is `rendering:<stage>`).
///
/// Ported from `CaptureView.latticeScene` (live checker ground) + `GIFAResolveOverlay`
/// (the serpentine sweep, `Spec.Order.serpentine` golden) + `phaseBanner` (the stage
/// banner). Cells only — no `Text`/glass/SF-Symbol/UIKit. Reads σ from the Surface and
/// the per-tick heartbeat from κ; emits cells.
struct RenderingPhaseField: View {
    /// The five deterministic-core stages, in order. DEPRECATED (5-stage render cut under
    /// ABSurface — render is now internal to `.live`); kept local so this unrouted field
    /// still compiles. (Was `SurfacePhase.RenderStage`.)
    enum RenderStage: String, CaseIterable, Equatable {
        case quantize, dither, significance, palette, encode
    }
    /// The current deterministic-core sub-stage (drives the sweep front + the banner).
    let stage: RenderStage
    /// σ — the surface state (palette + index cube of the GIFA being resolved).
    let surface: Surface
    /// κ — the ONE 20 fps clock (heartbeat for the live checker ground).
    let clock: SurfaceClock
    /// The ONE shared widget layout (the three global ColorWidget positions) + persistence.
    @Bindable var settings: AppSettings

    /// The current shared placement — Field64 + DiversityRing slide here at the SAME global
    /// positions set in any other phase.
    private var placement: [ColorIdentity: (col: Int, row: Int)] { settings.widgetPlacement }

    /// The 64-side serpentine resolve order (slot → sweep rank), computed once. Same
    /// `Spec.Order.serpentine` permutation the legacy `GIFAResolveOverlay` used.
    private static let sweepRank = Order.serpentine(GlobalLattice.previewCells).ranks

    /// The preview surface edge: 64 cells × the 4 pt atom = 256 pt — the same uniform
    /// hero geometry as the live field.
    private var heroEdge: CGFloat { GlobalLattice.gif(GlobalLattice.previewCells) }

    var body: some View {
        ZStack(alignment: .topLeading) {
            // The influence-field ground is the ONE persistent surface in `SurfaceView` (behind
            // every phase). This phase renders only the resolve hero + chrome on a clear background.

            // Field64 — the resolve hero, placed at the SHARED global position + movable
            // (capture→render→review share the one surface geometry AND one position).
            // `.movable` BEFORE `.place` (footprint-scoped gesture — a greedy `.position`
            // otherwise makes the gesture full-screen and the hero ungrabbable).
            resolveHero
                .movable(.field64, settings: settings, surface: surface, clock: clock)
                .place(region(for: .field64, at: placement))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .ignoresSafeArea()
        // The deterministic stage banner rides the top edge (the legacy `phaseBanner`
        // position) — a cell strip, not a constrained lattice region, so its width is free.
        .overlay(alignment: .top) { stageBanner }
        .overlay(alignment: .topLeading) { buildStamp }
    }

    // MARK: - The resolving hero (frame under the serpentine sweep)

    /// The 64×64 hero: the GIFA-in-progress frame (from σ's index cube + palette) with
    /// the serpentine sweep covering not-yet-resolved cells. As `progress` 0→1 the
    /// front advances in serpentine order, revealing the resolving image underneath.
    private var resolveHero: some View {
        let edge = heroEdge
        let cellPt = edge / CGFloat(GlobalLattice.previewCells)
        let n = GlobalLattice.previewCells
        let resolved = Int((progress * Double(n * n)).rounded())
        // The UNDER-CONSTRUCTION base = the frozen last captured frame (still populated through
        // render), NOT near-black. The true GIFA (frame 0, through its partial palette) RESOLVES
        // over it along the serpentine front as the real render progresses — you watch it construct.
        let baseTile = surface.previewTile
        let basePal = surface.previewPalette
        let ghost = SIMD3<UInt8>(12, 12, 14)
        return CellSprite(cols: n, rows: n, cellPt: cellPt) { c, r in
            let slot = r * n + c
            if Self.sweepRank[slot] < resolved, let col = frameColor(col: c, row: r) {
                return col                       // resolved → the true GIFA cell
            }
            let i = r * n + c                    // under construction → the frozen last frame
            if i < baseTile.count, Int(baseTile[i]) < basePal.count { return basePal[Int(baseTile[i])] }
            return ghost
        }
        .frame(width: edge, height: edge)
        .clipped()
        .allowsHitTesting(false)
    }

    /// The colour of cell (col,row) in the current frame of the GIFA being resolved —
    /// the ONE addressing function `Surface.cellGlobal(x,y,t)` (no inline `t*4096+y*64+x`).
    /// Returns `nil` when the cube isn't populated yet, so the live checker ground shows
    /// through the resolved cells instead of a flat fill.
    private func frameColor(col c: Int, row r: Int) -> SIMD3<UInt8>? {
        // Frame 0 — the partial palette streamed during render is frame-0's, so frame 0 has the
        // correct colours (a backward cursor sweep would mis-paint other frames with it).
        surface.cellGlobal(c, r, 0)
    }

    // MARK: - The deterministic stage banner (cells)

    /// The current stage as a cell banner — the deterministic-core token `rendering:<stage>`
    /// (what the user watches advance stage by stage) plus a human label. Cells, not glass.
    private var stageBanner: some View {
        VStack(alignment: .leading, spacing: GlobalLattice.pt(1)) {
            CellText("rendering:\(stage.rawValue)", rows: 9, ink: .white)
            CellText(Self.label(stage), rows: 7,
                     ink: Color(srgb8: SIMD3<UInt8>(150, 150, 162)))
        }
        .padding(.horizontal, GlobalLattice.pt(3))
        .padding(.vertical, GlobalLattice.pt(2))
        .background(Color(srgb8: SIMD3<UInt8>(20, 20, 24)))
        .padding(.top, GlobalLattice.pt(36))   // below the Dynamic Island
        .allowsHitTesting(false)
    }

    // MARK: - Stage → resolve progress / label

    /// The serpentine reveal front, driven by the REAL render progress (`surface.renderProgress` =
    /// the deterministic core's `loadingProgress`, monotonic 0→1 across the 5 stages) — NOT a clock
    /// timer that reset to black each stage (the old bug). The GIFA frame resolves over the frozen
    /// last frame in serpentine order as the Zig stages actually complete.
    private var progress: Double { surface.renderProgress }

    /// Human-readable label for the deterministic stage (the verified Zig kernel running).
    private static func label(_ stage: RenderStage) -> String {
        switch stage {
        case .quantize:     return "Quantizing per-frame palettes"
        case .dither:       return "Shaping the residual sampler"
        case .significance: return "Backing every slot with pixels"
        case .palette:      return "Collapsing to the global palette"
        case .encode:       return "Encoding the GIF"
        }
    }

    // MARK: - Build stamp (parity with the live field)

    /// The running commit + build time, top-left below the Dynamic Island — same stamp
    /// as the live field so a stale build is visible across every phase of the surface.
    private var buildStamp: some View {
        CellText("\(BuildStamp.gitSHA) \(BuildStamp.buildTime)", rows: 7,
                 ink: Color(srgb8: SIMD3<UInt8>(120, 120, 132)))
            .padding(.leading, GlobalLattice.pt(3))
            .padding(.top, GlobalLattice.pt(36))
            .allowsHitTesting(false)
    }
}
