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
    /// The current deterministic-core sub-stage (drives the sweep front + the banner).
    let stage: SurfacePhase.RenderStage
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
            // The ONE universal ground: the INFLUENCE FIELD — colour radiates from the widgets
            // (order) into the chaos, fed by the resolving GIFA frame at the cursor + the partial
            // palette. Same field as every act; the monotonic κ tick keeps it alive (never pauses)
            // while the deterministic core resolves the GIFA on top.
            StageGround(surface: surface, placement: placement, tick: clock.tick)

            // Field64 — the resolve hero, placed at the SHARED global position + movable
            // (capture→render→review share the one surface geometry AND one position).
            // `.movable` BEFORE `.place` (footprint-scoped gesture — a greedy `.position`
            // otherwise makes the gesture full-screen and the hero ungrabbable).
            resolveHero
                .movable(.field64, settings: settings, surface: surface)
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
        let resolved = Int((progress * Double(GlobalLattice.previewCells * GlobalLattice.previewCells)).rounded())
        let ghost = SIMD3<UInt8>(12, 12, 14)
        return CellSprite(cols: GlobalLattice.previewCells,
                          rows: GlobalLattice.previewCells,
                          cellPt: cellPt) { c, r in
            let slot = r * GlobalLattice.previewCells + c
            // Unresolved cells are covered by the opaque ghost; resolved cells show the
            // frame underneath (or, if the cube isn't populated yet, the live checker).
            guard Self.sweepRank[slot] < resolved else { return ghost }
            return frameColor(col: c, row: r)
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
        surface.cellGlobal(c, r, surface.cursor)
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

    /// F4 — smooth GIFA build: the five ordered stages each own a 1/5 band of the resolve, and
    /// WITHIN a stage the serpentine front now EASES across its band (over `stageRevealTicks` 20 fps
    /// ticks since the stage was entered) instead of snapping the whole band at once. So the image
    /// builds cell-by-cell in serpentine order — you watch the GIFA assemble. The front eases to the
    /// band top and holds there until the (real, Zig-timed) stage advances, then continues.
    private static let stageRevealTicks = 8
    private var progress: Double {
        let order = SurfacePhase.RenderStage.allCases
        guard let i = order.firstIndex(of: stage) else { return 0 }
        let within = CellEase.progress(clock.tick, since: surface.phaseEnteredTick, ticks: Self.stageRevealTicks)
        return (Double(i) + within) / Double(order.count)
    }

    /// Human-readable label for the deterministic stage (the verified Zig kernel running).
    private static func label(_ stage: SurfacePhase.RenderStage) -> String {
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
