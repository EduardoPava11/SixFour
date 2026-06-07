import SwiftUI
import simd

/// Π·review — the cell-field renderer for the `.review` phase of the ONE surface.
///
/// This is the per-phase renderer the `PhaseField.field(for:_:)` seam routes `.review`
/// to (Stage 2 stub `PhaseStubField` → this). It is a pure projection of σ: it reads
/// the surface's `indexCube` / `palette` / `cursor` / `pose` / `playerMode` and emits
/// cells. It owns NO clock and NO state of its own beyond the bindings it threads back
/// into σ — the ONE `SurfaceClock` (κ) drives `σ.cursor` (the Z₆₄ frame), and the pose
/// sliders write `σ.pose` directly.
///
/// The hero is the GIFA cube RASTERIZED TO CELLS — the integer per-cell rasterizer
/// (`Surface.bakeCube`, geometry proven by `SixFour.Spec.VoxelFit`) baked once per body eval
/// and drawn through the SAME `CellSprite`/`CellBitmap` as the live preview. There is NO Metal,
/// NO raymarch (the old `CubeSurface`/`voxel_raymarch` is deleted): the cube IS the cell grid.
///   1. The hero reads its frame from `σ.cursor` (κ's Z₆₄ cursor), not a `PlaybackClock`.
///   2. At rung (0,0) the rasterized front face is byte-identical to the 2D GIF cell
///      (`lawRasterizeFrontIsGif`); the X/Y rung sliders shear depth to reveal the (x,t)/(y,t)
///      side faces, the cube shrinking to fit (`N` grows) — always crisp (INTEGER SCALE law).
///   3. The data is read from σ (`indexCube` + the true per-frame `palettesPerFrame`), so the
///      renderer never touches `CaptureViewModel`/`CaptureOutput` — σ is the only input.
///
/// Cells only: `CellText` / `CellSlider` / `CellActionButton` / `CellSprite`. No
/// `Text` / glass / SF-Symbol / UIKit `Slider`·`Picker` on the chrome.
///
/// Tier-2 pure: SwiftUI + simd, reusing existing Tier-2 cell primitives.
struct ReviewPhaseField: View {
    /// σ — read for data, written only via the pose bindings + the `.retake` event.
    @Bindable var surface: Surface
    /// κ — its `tick` keeps the cube's Metal view live; the frame itself comes from
    /// `σ.cursor` (advanced by the same clock), so there is exactly one cursor.
    let clock: SurfaceClock

    private let heroEdge = SFTheme.gifCanvasPt   // 256 at the 4 pt atom

    var body: some View {
        // Bake the cube to an N×N CELL raster at the current rung + cursor (forward scatter,
        // the proven `SixFourVoxelFit` geometry). One bake per body eval; the SAME `CellSprite`
        // the preview uses then draws it. NO Metal, NO raymarch — the cube IS the cell grid.
        let raster = surface.bakeCube(xRung: stopX, yRung: stopY)
        return ZStack {
            // The live cell-field ground (κ heartbeat) — the whole screen is ONE cell
            // field in EVERY phase (cell-field-law); review is not an exception. `nil` cube
            // cells (silhouette gaps) let this ground show through.
            GridRefreshFieldView(phase: clock.heartbeat)
                .ignoresSafeArea()

            if raster.n > 0 {
                VStack(spacing: SFTheme.gifCellPt) {
                    Spacer(minLength: 0)
                    heroSurface(raster)
                    poseSliders
                    determinismBadge
                    Spacer(minLength: 0)
                    actionRow
                }
                .padding(.horizontal, SFTheme.gifCellPt)
                .padding(.bottom, SFTheme.gifCellPt)
            } else {
                // No well-formed GIFA in σ yet (empty/short cube): a static "no GIF"
                // cell line, never a spinner (the surface is always cells).
                CellText("no GIF in surface", rows: 11,
                         ink: Color(srgb8: SIMD3<UInt8>(140, 140, 140)))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ignoresSafeArea()
    }

    // MARK: - Hero (the cube AS cells)

    /// The hero — the GIFA cube RASTERIZED to cells, drawn through the same `CellSprite` as the
    /// live preview. An integer cell pitch (`floor(heroEdge / N)`) keeps it crisp (INTEGER SCALE
    /// law) while the cube shrinks-to-fit as it rotates (`N` grows with the rung). At rung (0,0)
    /// the front face is byte-identical to the 2D GIF (`lawRasterizeFrontIsGif`). The cube floats
    /// on the live cell ground — `nil` cells show it through (no black backing).
    private func heroSurface(_ raster: CubeRaster) -> some View {
        let pitch = max(1, floor(heroEdge / CGFloat(raster.n)))   // integer pt/cell → crisp
        return CellSprite(cols: raster.n, rows: raster.n, cellPt: pitch) { c, r in
            raster.color(c, r)
        }
        .frame(width: heroEdge, height: heroEdge)   // fixed box; the cube centres within it
    }

    // MARK: - Pose sliders (σ.pose, integer degrees)

    /// The two controls — DISCRETE rung sliders that snap the cube flat→isometric in
    /// integer stops (the 8-bit ladder, `SixFourVoxelFit`): X tilts the (y,t) side open,
    /// Y the (x,t) top. σ.pose holds the two rung indices `[0, maxRung]`; the binding rounds
    /// to an integer rung so every resting pose is a named stop. Cell sliders only.
    private var poseSliders: some View {
        let dim = SIMD3<UInt8>(170, 170, 170)
        return VStack(alignment: .leading, spacing: GlobalLattice.pt(2)) {
            CellText("tilt X · \(Self.stopName(stopX))", rows: 6, ink: Color(srgb8: dim))
            CellSlider(value: xRungBinding, range: 0 ... Double(SixFourVoxelFit.maxRung))
            CellText("tilt Y · \(Self.stopName(stopY))", rows: 6, ink: Color(srgb8: dim))
            CellSlider(value: yRungBinding, range: 0 ... Double(SixFourVoxelFit.maxRung))
        }
        .frame(maxWidth: heroEdge)
    }

    /// The named ladder stop for a rung (the a11y/label name, not raw degrees).
    private static func stopName(_ r: Int) -> String {
        switch r {
        case 0:  return "flat (the GIF)"
        case 1:  return "quarter"
        default: return "isometric"
        }
    }

    private var stopX: Int { clampRung(Int(surface.pose.x)) }
    private var stopY: Int { clampRung(Int(surface.pose.y)) }
    private func clampRung(_ r: Int) -> Int { min(max(r, 0), SixFourVoxelFit.maxRung) }

    // MARK: - Determinism badge

    /// The trust line: the deterministic-core badge (σ.settings.useDeterministicCore),
    /// or an explicit GPU-fallback note. The legacy SHA-256 string lives on the engine's
    /// `CaptureOutput`, not on σ, so it is not surfaced here (see file notes / seam gap);
    /// the badge still proves WHICH core produced the cube.
    private var determinismBadge: some View {
        let green = SIMD3<UInt8>(70, 200, 90)
        let amber = SIMD3<UInt8>(225, 200, 70)
        return Group {
            if surface.settings.useDeterministicCore {
                CellText("deterministic core · byte-reproducible", rows: 6,
                         ink: Color(srgb8: green))
            } else {
                CellText("GPU fallback · not byte-reproducible", rows: 6,
                         ink: Color(srgb8: amber))
            }
        }
    }

    // MARK: - Actions

    /// Share + Retake. Retake fires `.retake` (→ `.live`, the only modelled review exit).
    /// Share's source is the engine's `gifURL` (not on σ); until that seam is threaded it
    /// renders as a cell button placeholder (see notes), keeping the row visually intact.
    private var actionRow: some View {
        HStack(spacing: GlobalLattice.pt(GlobalLattice.gutterCells)) {
            CellActionButton(icon: .share, title: "Share", prominent: true)
                .accessibilityHidden(true)   // not yet wired through σ

            Button { surface.step(.retake) } label: {
                CellActionButton(icon: .retake, title: "Retake")
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Retake")
        }
    }

    // MARK: - σ → rung bindings

    /// `CellSlider` is `Double`-valued; the setter rounds to an integer RUNG so every
    /// resting pose is a named ladder stop. These are the only writers of σ.pose.
    private var xRungBinding: Binding<Double> {
        Binding(get: { Double(stopX) },
                set: { surface.pose.x = Int32(clampRung(Int($0.rounded()))) })
    }
    private var yRungBinding: Binding<Double> {
        Binding(get: { Double(stopY) },
                set: { surface.pose.y = Int32(clampRung(Int($0.rounded()))) })
    }
}
