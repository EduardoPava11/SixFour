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

    /// The 64-side serpentine resolve order (slot → sweep rank), computed once. Same
    /// `Spec.Order.serpentine` permutation the legacy `GIFAResolveOverlay` used.
    private static let sweepRank = Order.serpentine(GlobalLattice.previewCells).ranks

    /// The preview surface edge: 64 cells × the 4 pt atom = 256 pt — the same uniform
    /// hero geometry as the live field.
    private var heroEdge: CGFloat { GlobalLattice.gif(GlobalLattice.previewCells) }

    var body: some View {
        ZStack(alignment: .topLeading) {
            // The live B/W checker ground (κ heartbeat) — proves the canvas is alive
            // while the deterministic core resolves the GIFA on top.
            GridRefreshFieldView(phase: clock.heartbeat)
                .ignoresSafeArea()

            // The resolve hero, placed by the same proven GridLayoutContract region as
            // the live preview (capture→render→review share the one surface geometry).
            resolveHero.place("preview")

            // The deterministic stage token, as cells.
            stageBanner.place("palette")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .ignoresSafeArea()
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

    /// The colour of cell (col,row) in the current frame of the GIFA being resolved,
    /// read from σ's `indexCube` (t,y,x row-major) through the `palette`. Returns `nil`
    /// (transparent) when the cube isn't populated yet, so the live checker ground shows
    /// through the resolved cells instead of a flat fill.
    private func frameColor(col c: Int, row r: Int) -> SIMD3<UInt8>? {
        let side = GlobalLattice.previewCells
        let frameStride = side * side
        let frame = surface.cursor
        let base = frame * frameStride
        let offset = base + r * side + c
        guard offset >= 0, offset < surface.indexCube.count else { return nil }
        let idx = Int(surface.indexCube[offset])
        guard idx < surface.palette.count else { return nil }
        return surface.palette[idx]
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
        .allowsHitTesting(false)
    }

    // MARK: - Stage → resolve progress / label

    /// The serpentine sweep front for the current stage: the five ordered stages each
    /// own a 1/5 band of the resolve, so the front advances monotonically across the
    /// pipeline (quantize 0→.2 … encode .8→1). Within a stage the band fills to its top
    /// (the surface advances per stage transition, the spec's only granularity here).
    private var progress: Double {
        let order = SurfacePhase.RenderStage.allCases
        guard let i = order.firstIndex(of: stage) else { return 0 }
        // The stage's band TOP — the sweep has resolved through the end of this stage.
        return Double(i + 1) / Double(order.count)
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
