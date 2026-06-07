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
/// Ported from `ReviewScene` (the legacy in-lattice Review): GIF/cube hero, X/Y pose
/// sliders, the determinism badge, and the Share/Retake action row. Three substantive
/// changes for the one-surface spine:
///   1. The hero reads its frame from `σ.cursor` (κ's Z₆₄ cursor), not a `PlaybackClock`.
///   2. The hero ALWAYS renders through `CubeSurface` — at pose (0,0) its front face is
///      byte-identical to the 2D GIF (RULE-CUBE-2D-IDENTITY), so `playerMode == 0` (flat)
///      is just the rest pose. `playerMode == 1` lets the pose sliders orbit it.
///   3. The data is rebuilt from σ (the flat `indexCube` + the global `palette`), so the
///      renderer never touches `CaptureViewModel`/`CaptureOutput` — σ is the only input.
///
/// Cells only: `CellText` / `CellSlider` / `CellActionButton` / `CubeSurface`. No
/// `Text` / glass / SF-Symbol / UIKit `Slider`·`Picker` on the chrome.
///
/// Tier-2 pure: SwiftUI + simd, reusing existing Tier-2 cell + voxel primitives.
struct ReviewPhaseField: View {
    /// σ — read for data, written only via the pose bindings + the `.retake` event.
    @Bindable var surface: Surface
    /// κ — its `tick` keeps the cube's Metal view live; the frame itself comes from
    /// `σ.cursor` (advanced by the same clock), so there is exactly one cursor.
    let clock: SurfaceClock

    private let heroEdge = SFTheme.gifCanvasPt   // 256 at the 4 pt atom

    var body: some View {
        ZStack {
            // The live cell-field ground (κ heartbeat) — the whole screen is ONE cell
            // field in EVERY phase (cell-field-law); review is not an exception. Matches
            // RenderingPhaseField's ground so the grid is continuous capture → review
            // (was a flat Color.black, which made the grid vanish at review).
            GridRefreshFieldView(phase: clock.heartbeat)
                .ignoresSafeArea()

            if let cube = cubeData {
                VStack(spacing: SFTheme.gifCellPt) {
                    Spacer(minLength: 0)
                    heroSurface(cube)
                    if surface.playerMode == 1 { poseSliders }
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

    // MARK: - Hero

    /// The hero surface — the rotatable 64³ voxel cube, posed by σ.pose. At pose (0,0)
    /// (the default / `playerMode == 0`) its front face is byte-identical to the 2D GIF
    /// (RULE-CUBE-2D-IDENTITY), so the flat player IS the rest pose. The frame comes from
    /// σ.cursor (κ's Z₆₄ cursor) — one clock, one cursor.
    private func heroSurface(_ cube: VoxelCubeData) -> some View {
        CubeSurface(data: cube,
                    yaw: yawRadians,
                    pitch: pitchRadians,
                    frame: surface.cursor)
            .frame(width: heroEdge, height: heroEdge)
            .background(Color.black)
            .pixelFrame()
    }

    // MARK: - Pose sliders (σ.pose, integer degrees)

    /// The two controls — slider X → yaw, slider Y → pitch — written straight into
    /// σ.pose (degrees, integer). Pitch clamps to ±86° (≈ the cube's ±1.5 rad orbit
    /// limit). Cell sliders only; no UIKit `Slider`.
    private var poseSliders: some View {
        let dim = SIMD3<UInt8>(170, 170, 170)
        return VStack(alignment: .leading, spacing: GlobalLattice.pt(2)) {
            CellText("rotate X · yaw \(surface.pose.x)°", rows: 6, ink: Color(srgb8: dim))
            CellSlider(value: yawDegBinding, range: -180 ... 180)
            CellText("rotate Y · pitch \(surface.pose.y)°", rows: 6, ink: Color(srgb8: dim))
            CellSlider(value: pitchDegBinding, range: -86 ... 86)
        }
        .frame(maxWidth: heroEdge)
    }

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

    // MARK: - σ → renderer adapters

    /// Build the voxel data from σ: slice the flat `indexCube` (row-major t,y,x) into 64
    /// frames of 4096, and replicate the ONE global `palette` across all 64 frames (σ
    /// carries a single global palette for review; the per-frame palettes collapse to it).
    /// Returns nil when σ has no well-formed GIFA, so the field shows the "no GIF" line.
    private var cubeData: VoxelCubeData? {
        let pixels = SixFourShape.pixelsPerFrame    // 4096
        let frames = SixFourShape.T                 // 64
        let k = SixFourShape.K                      // 256
        guard surface.indexCube.count == pixels * frames,
              surface.palette.count == k else { return nil }

        var frameIndices = [[UInt8]]()
        frameIndices.reserveCapacity(frames)
        for t in 0..<frames {
            let base = t * pixels
            frameIndices.append(Array(surface.indexCube[base ..< base + pixels]))
        }
        let palettes = [[SIMD3<UInt8>]](repeating: surface.palette, count: frames)
        let data = VoxelCubeData(frameIndices: frameIndices, srgbPalettes: palettes)
        return data.isWellFormed ? data : nil
    }

    /// σ.pose is integer degrees; the cube renderer wants radians.
    private var yawRadians: Float { Float(surface.pose.x) * .pi / 180 }
    private var pitchRadians: Float { Float(surface.pose.y) * .pi / 180 }

    /// `CellSlider` is `Double`-valued; thread the value straight into σ.pose (rounded
    /// to an integer degree, the state spine's unit). These are the only writers of pose.
    private var yawDegBinding: Binding<Double> {
        Binding(get: { Double(surface.pose.x) },
                set: { surface.pose.x = Int32($0.rounded()) })
    }
    private var pitchDegBinding: Binding<Double> {
        Binding(get: { Double(surface.pose.y) },
                set: { surface.pose.y = Int32($0.rounded()) })
    }
}
