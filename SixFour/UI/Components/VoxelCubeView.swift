import SwiftUI
import MetalKit
import simd

// MARK: - VoxelCubeView
//
// A 64×64×64 VOXEL CUBE view of a SixFour GIF, for the Review screen's
// palette-explorer (alongside .structure / .grid). See docs/SIXFOUR-VOXEL-CUBE.md.
//
// A SixFour GIF is 64 frames × (64×64 px) × 256-colour-per-frame palette. We
// read the 64 frames as a DEPTH/TIME axis and render the whole thing as a 64³
// voxel object. The defining trick (the surprise): the cube is drawn
// ORTHOGRAPHICALLY with the CURRENT FRAME as the front face, so at the rest
// pose (yaw = pitch = 0) it is **byte-for-byte indistinguishable from the 2D
// GIF** — one voxel on screen == one GIF pixel == gifCellPt. The instant you
// orbit, the GIF's recent frames extrude backward into space as depth = time.
//
//   • voxel at depth-slice z shows frame  f(z) = (cursor − 63 + z) mod 64
//     → front slice (z = 63, nearest the camera) is the current frame `cursor`.
//   • orthographic, so there is no foreshortening to break the 2D match.
//   • the on-screen window is fit EXACTLY to the cube's projected silhouette
//     (halfSpan, computed per-orientation), so face-on it fills at 32 = pixel
//     parity, and corner-on it grows to fit without ever clipping.
//
// 8-BIT ISOMETRIC RULESET (docs/SIXFOUR-VOXEL-CUBE.md §8, RULE-CUBE-ISO):
//   • the 3D "hero" pose is the canonical 2:1 DIMETRIC angle of 8-bit games —
//     azimuth 45° / elevation 30° (sin30°=0.5 ⇒ floor edges step 2px:1px). The
//     "cube.fill" button snaps to it and cycles the 4 iso corners; "lock" freezes
//     the orientation for study (see `VoxelIso`).
//   • the kernel quantises to a fixed 128² art-pixel grid (2 art-px/voxel) so the
//     dimetric edges read as CHUNKY 8-bit stairsteps, nearest-upscaled to any size.
//   • FRAME-ISOLATION (study): focus one frame opaque and ghost the rest (front-to-
//     back alpha compositing; α=1 collapses to the opaque first-hit march, so the
//     2D rest pose is untouched) to read a single frame's palette in 3D.
//
// RENDERER: a hand-written Metal compute DDA raymarcher (Amanatides–Woo) over a
// 64³ R8Uint index volume + a 64×256 RGBA8 palette texture. One discrete
// per-face brightness multiply is the ONLY depth cue (GRID Law #2: no AA /
// opacity / shading on a data cell). The cube is CONTENT (no glass on voxels);
// the controls around it are Liquid Glass chrome (GLASS Boundary Law).
//
// Tier-2 pure: Apple frameworks + simd only.

// MARK: - Input data shape

/// The voxel-cube input, exactly the Review data shape. Build it from a
/// `CaptureOutput` once `frameIndicesForVoxels` is present (it is threaded
/// through both render paths), or directly from synthetic data for previews.
struct VoxelCubeData: Sendable {
    /// 64 frames × 4096 (= 64×64) palette indices, row-major y*64+x, top-left origin.
    let frameIndices: [[UInt8]]
    /// 64 frames × 256 sRGB palettes.
    let srgbPalettes: [[SIMD3<UInt8>]]
    /// 64 frames × 256 provenance codes (0 = degenerate/air, 1 = extracted,
    /// 2 = split) — the §3 air-mask. nil ⇒ treat every slot as extracted.
    let provenance: [[UInt8]]?

    // The GIF's canonical shape (spec → SixFourShape, shared with the Zig core).
    static let frameCount = SixFourShape.T          // 64 frames (depth/time axis)
    static let side = SixFourShape.W                // 64 — x and y extent
    static let pixelsPerFrame = SixFourShape.pixelsPerFrame   // 4096
    static let paletteCount = SixFourShape.K        // 256

    var isWellFormed: Bool {
        frameIndices.count == Self.frameCount
            && srgbPalettes.count == Self.frameCount
            && frameIndices.allSatisfy { $0.count == Self.pixelsPerFrame }
            && srgbPalettes.allSatisfy { $0.count == Self.paletteCount }
    }

    /// Bridge from a Review `CaptureOutput`. Returns nil when the per-pixel index
    /// map is absent (legacy outputs) so the caller can hide the voxel mode.
    init?(output: CaptureOutput) {
        guard let idx = output.frameIndicesForVoxels else { return nil }
        self.frameIndices = idx
        self.srgbPalettes = output.palettesForDisplay
        let cells = output.perFrameCells
        if cells.count == Self.frameCount && cells.allSatisfy({ $0.count == Self.paletteCount }) {
            self.provenance = cells.map { row in
                row.map { c -> UInt8 in
                    switch c.provenance {
                    case .extracted:  return 1
                    case .split:      return 2
                    case .degenerate: return 0
                    }
                }
            }
        } else {
            self.provenance = nil
        }
        guard isWellFormed else { return nil }
    }

    init(frameIndices: [[UInt8]], srgbPalettes: [[SIMD3<UInt8>]], provenance: [[UInt8]]? = nil) {
        self.frameIndices = frameIndices
        self.srgbPalettes = srgbPalettes
        self.provenance = provenance
    }
}

// MARK: - The 8-bit isometric ruleset (2:1 dimetric)
//
// Classic 8-bit/16-bit "isometric" games are not truly isometric — they are
// DIMETRIC at a 2:1 pixel ratio: every floor diagonal steps 2 px across : 1 down
// (slope 0.5), which a 6502/Z80 could draw by halving. That ratio is produced
// EXACTLY by an orthonormal camera at azimuth 45°, elevation 30° — because
// sin30° = 0.5. (True isometric is 35.26°/0.577, whose non-integer stairsteps look
// wrong in pixel art.) We therefore expose ONE canonical "hero" pose and an
// auto-fitting orthographic window; the kernel quantises to a 128² art grid so the
// 2:1 edges read as chunky 8-bit stairsteps. See docs/SIXFOUR-VOXEL-CUBE.md §8.
enum VoxelIso {
    static let yaw: Float = .pi / 4      // 45° azimuth
    static let pitch: Float = .pi / 6    // 30° elevation → exact 2:1 dimetric

    /// The 4 canonical isometric corners — each views the cube from a different
    /// top-corner while preserving the 30° elevation (so the 2:1 look is identical;
    /// only WHICH three faces you see changes). `n` cycles 0…3 → yaw = π/4 + n·π/2.
    static func corner(_ n: Int) -> (yaw: Float, pitch: Float) {
        (yaw: .pi / 4 + Float(n & 3) * (.pi / 2), pitch: pitch)
    }

    /// Mirror of the Metal `voxelOrbit` basis (orthonormal: yaw about world-Y, then
    /// pitch about the camera-right axis). Returns the camera basis vector for the
    /// canonical axis `v`. Kept in lockstep with Shaders.metal voxel_raymarch.
    static func orbit(_ v: SIMD3<Float>, yaw: Float, pitch: Float) -> SIMD3<Float> {
        let cy = cos(yaw), sy = sin(yaw)
        let a = SIMD3<Float>(cy * v.x + sy * v.z, v.y, -sy * v.x + cy * v.z)
        let r = SIMD3<Float>(cy, 0, -sy)
        let cp = cos(pitch), sp = sin(pitch)
        return a * cp + simd_cross(r, a) * sp + r * simd_dot(r, a) * (1 - cp)
    }

    /// Orthographic half-window that exactly FITS the 64³ cube's silhouette at this
    /// orientation — so the WHOLE 8-bit cube is framed when orbited (the chosen
    /// behaviour), while the flat pose stays pixel-exact. At yaw=pitch=0 the 8 corners
    /// project to ±32, so this returns exactly 32 ⇒ one voxel = one GIF cell = the 2D
    /// identity. Orbited, it grows to the largest |corner·basis|; a 1-unit pad (only
    /// when orbited) keeps the outermost corner voxels just inside the frame edge.
    static func fitHalfSpan(yaw: Float, pitch: Float) -> Float {
        let xb = orbit(SIMD3(1, 0, 0), yaw: yaw, pitch: pitch)
        let yb = orbit(SIMD3(0, 1, 0), yaw: yaw, pitch: pitch)
        var m: Float = 0
        for sx in [Float(-32), 32] {
            for sy in [Float(-32), 32] {
                for sz in [Float(-32), 32] {
                    let c = SIMD3<Float>(sx, sy, sz)   // corner relative to centre (32,32,32)
                    m = max(m, max(abs(simd_dot(c, xb)), abs(simd_dot(c, yb))))
                }
            }
        }
        let orbited = (yaw * yaw + pitch * pitch) > 1e-6
        return m + (orbited ? 1 : 0)
    }
}

// MARK: - Chrome level

/// How much chrome the cube renders around its surface.
enum VoxelChrome {
    /// The palette-explorer `.voxel3D` mode: render + pose overlay + the study panel
    /// (provenance air-mask, trail depth, luma floor, frame-isolation).
    case full
    /// The `GIFPlayer` 3D mode: render + pose overlay only. The shared
    /// `PlayerTransport` owns play/pause/scrub, so the cube hides its own.
    case heroMinimal
}

// MARK: - View state (single owner of all knobs — GRID Law #5 spirit)

struct VoxelCubeState: Equatable {
    var yaw: Float = 0           // rest pose = 0 → indistinguishable from 2D
    var pitch: Float = 0
    /// Trail depth band [lo, hi] over depth-slices 0…63 (63 = current frame).
    var tLo: Int = 0
    var tHi: Int = 63
    /// Luminance air floor 0…255: voxels darker than this become air.
    var lumaFloor: Int = 0
    /// Provenance filter: 0 = all, 1 = extracted only, 2 = split only.
    var provMode: Int = 0
    // NOTE: `frame` and `playing` were REMOVED from the cube's local state — the
    // playback cursor now lives in the shared `PlaybackClock` (the single clock), so
    // the cube can never disagree with the 2D GIF or the palette analyzers.
    var autoRotate: Bool = false

    /// LOCK: freeze the orientation so the orbit gesture can't disturb a chosen iso
    /// pose (study mode). The iso-corner button still snaps among canonical corners.
    var locked: Bool = false
    /// Which of the 4 canonical isometric corners is selected (yaw = π/4 + n·π/2).
    var isoCorner: Int = 0
    /// FRAME-ISOLATION: focus the current frame opaque, ghost the rest, to study one
    /// frame's palette in 3D (design §0.3). `ghostAlpha` 0 = pure isolation.
    var isolate: Bool = false
    var ghostAlpha: Double = 0

    /// θ = how far we are from the flat 2D pose (radians). 0 == pure 2D.
    var orbitMagnitude: Float { (yaw * yaw + pitch * pitch).squareRoot() }
    var isFlat: Bool { orbitMagnitude < 0.001 }
}

// MARK: - SwiftUI host

@MainActor
struct VoxelCubeView: View {
    let data: VoxelCubeData
    /// The shared playback clock — the cube's front-face frame and play/pause come
    /// from here, NOT a private timer, so the 3D cube can never disagree with the 2D
    /// GIF or the palette analyzers about "the current frame".
    var clock: PlaybackClock
    /// Nominal chrome/placeholder width cap, in points (the controls panel + the
    /// not-well-formed placeholder). The RENDER SURFACE no longer uses this — it
    /// self-sizes via `SFTheme.canvasEdge` in `cubeBody`, exactly like the 2D
    /// `GIFCanvas`, so the two are 1:1 under the same Review column.
    var edge: CGFloat = SFTheme.gifCanvasPt
    /// Optional store: when present, the provenance filter / luma floor /
    /// auto-rotate are seeded from it and persisted back across captures.
    var settings: AppSettings?
    /// Shared cross-view brush (the same `brushedIndex` the grid / cloud / picker
    /// use): the cube highlights matching voxels when orbited, and tapping a voxel
    /// at the flat rest pose sets it. Defaults to a no-op binding.
    @Binding var brushedIndex: Int?
    /// Brush set per radix (`BrushSet.mode`): 0 single / 1 quad (4⁴) / 2 σ-pair (2⁸).
    var brushMode: Int32 = 0
    /// How much chrome to draw. `.full` = palette-explorer study cube; `.heroMinimal`
    /// = the `GIFPlayer` 3D mode (the shared transport owns play/pause/scrub).
    var chrome: VoxelChrome = .full

    @State private var cube: VoxelCubeState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // 60 Hz driver for AUTO-ROTATE ONLY — the playback cursor now lives in `clock`.
    private static let displayHz = 60
    private let rotateClock = Timer.publish(every: 1.0 / Double(displayHz), on: .main, in: .common).autoconnect()

    init(data: VoxelCubeData, clock: PlaybackClock, edge: CGFloat = SFTheme.gifCanvasPt,
         settings: AppSettings? = nil, brushedIndex: Binding<Int?> = .constant(nil),
         brushMode: Int32 = 0, chrome: VoxelChrome = .full) {
        self.data = data
        self.clock = clock
        self.edge = edge
        self.settings = settings
        self._brushedIndex = brushedIndex
        self.brushMode = brushMode
        self.chrome = chrome
        var initial = VoxelCubeState()
        if let s = settings {
            initial.provMode = s.voxelProvenanceMode
            initial.lumaFloor = s.voxelLumaFloor
            initial.autoRotate = s.voxelAutoRotate
        }
        _cube = State(initialValue: initial)
    }

    var body: some View {
        Group {
            if data.isWellFormed { cubeBody } else { placeholder }
        }
        .onReceive(rotateClock) { _ in advance() }
        // Persist the durable knobs (orbit + frame stay session-transient).
        .onChange(of: cube.provMode) { _, v in settings?.voxelProvenanceMode = v }
        .onChange(of: cube.lumaFloor) { _, v in settings?.voxelLumaFloor = v }
        .onChange(of: cube.autoRotate) { _, v in settings?.voxelAutoRotate = v }
    }

    private var cubeBody: some View {
        VStack(spacing: 12) {
            // The square render surface sizes EXACTLY like the 2D `GIFCanvas`
            // (a `GeometryReader` + `SFTheme.canvasEdge` inside `.pixelFrame()`),
            // so under the same Review column it gets the identical on-screen edge —
            // the rest-pose indistinguishability invariant (RULE-CUBE-2D-IDENTITY).
            GeometryReader { geo in
                let e = SFTheme.canvasEdge(forAvailable: min(geo.size.width, geo.size.height),
                                           cells: SFTheme.gifSideCells)
                ZStack(alignment: .topTrailing) {
                    VoxelMetalView(data: data, state: cube, frame: clock.frame,
                                   brushedIndex: brushedIndex, brushMode: brushMode)
                        .frame(width: e, height: e)
                        .background(Color.black)
                        .highPriorityGesture(orbitGesture)
                        // Tap-to-pick on the FLAT rest pose: the front-face pixel's
                        // palette index becomes the shared brush (tap again to clear).
                        // Gated to flat so it reads the exact 2D frame the user sees.
                        .simultaneousGesture(SpatialTapGesture().onEnded { v in
                            guard cube.isFlat, e > 0 else { return }
                            let side = VoxelCubeData.side
                            let x = min(side - 1, max(0, Int(v.location.x / e * CGFloat(side))))
                            let y = min(side - 1, max(0, Int(v.location.y / e * CGFloat(side))))
                            let idx = Int(data.frameIndices[clock.frame][y * side + x])
                            brushedIndex = (brushedIndex == idx) ? nil : idx
                        })
                        .accessibilityElement()
                        .accessibilityLabel("64 by 64 by 64 voxel palette cube")
                        .accessibilityValue(cube.isFlat
                            ? "Flat view, frame \(clock.frame + 1) of 64. Drag to orbit into 3D."
                            : "Orbited \(Int(cube.orbitMagnitude * 57)) degrees, frame \(clock.frame + 1) of 64.")

                    // Pose affordances (glass chrome): snap to / cycle the 8-bit iso
                    // corners (2:1 dimetric), lock the orientation for study, or fold
                    // back flat to 2D. Buttons change shape with state.
                    VStack(spacing: 8) {
                        GlassIconButton(systemImage: "cube.fill",
                                        accessibilityLabel: "Isometric view (tap to rotate corner)") {
                            withAnimation(.easeInOut(duration: 0.5)) {
                                // From flat: snap to the current corner. Already iso: advance
                                // to the next of the 4 canonical corners (same 2:1 angle).
                                if !cube.isFlat { cube.isoCorner &+= 1 }
                                let c = VoxelIso.corner(cube.isoCorner)
                                cube.yaw = c.yaw; cube.pitch = c.pitch
                            }
                        }
                        GlassIconButton(systemImage: cube.locked ? "lock.fill" : "lock.open",
                                        accessibilityLabel: cube.locked ? "Unlock orientation" : "Lock orientation",
                                        tint: cube.locked ? .white : .white.opacity(0.6)) {
                            cube.locked.toggle()
                        }
                        GlassIconButton(systemImage: "cube.transparent",
                                        accessibilityLabel: "Reset to flat 2D view") {
                            withAnimation(.easeInOut(duration: 0.45)) {
                                cube.yaw = 0; cube.pitch = 0; cube.locked = false
                            }
                        }
                    }
                    .padding(8)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .pixelFrame()

            // The study panel (provenance / trail / luma / isolate) only in the
            // palette-explorer `.full` chrome. In the `GIFPlayer` hero, the shared
            // `PlayerTransport` owns play/pause/scrub, so the cube shows render-only.
            if chrome == .full {
                controls
            }
        }
    }

    // MARK: Glass control chrome

    private var controls: some View {
        VStack(spacing: 10) {
            // Transport cluster — flat cell icon buttons (GlassToolbarCluster is now a
            // plain HStack; the buttons are pixelated CellSymbol grounds).
            GlassToolbarCluster {
                GlassIconButton(systemImage: clock.playing ? "pause.fill" : "play.fill",
                                accessibilityLabel: clock.playing ? "Pause" : "Play") {
                    clock.togglePlay()
                }
                GlassIconButton(systemImage: "rotate.3d",
                                accessibilityLabel: cube.autoRotate ? "Stop auto-rotate" : "Auto-rotate",
                                tint: cube.autoRotate ? .white : .white.opacity(0.6)) {
                    cube.autoRotate.toggle()
                }
                // Frame-isolation: focus the current frame, make the rest transparent,
                // to study one frame's palette in 3D (the button changes shape).
                GlassIconButton(systemImage: cube.isolate ? "square.stack.3d.up.fill" : "square.stack.3d.up",
                                accessibilityLabel: cube.isolate ? "Show all frames" : "Isolate this frame",
                                tint: cube.isolate ? .white : .white.opacity(0.6)) {
                    cube.isolate.toggle()
                }
            }

            // Provenance filter — which slots count as solid (design §3).
            provenanceFilter

            // Knobs — a read-only-style glass panel (the cube stays content).
            VStack(spacing: 8) {
                slider("Frame \(clock.frame + 1)/\(VoxelCubeData.frameCount)",
                       value: Binding(get: { Double(clock.frame) },
                                      set: { clock.scrub(to: Int($0.rounded())) }),
                       range: 0...Double(VoxelCubeData.frameCount - 1))
                slider("Trail depth \(cube.tHi - cube.tLo + 1)",
                       value: Binding(get: { Double(cube.tLo) },
                                      set: { cube.tLo = min(Int($0.rounded()), cube.tHi) }),
                       range: 0...Double(VoxelCubeData.frameCount - 1))
                slider("Air below luma \(cube.lumaFloor)",
                       value: Binding(get: { Double(cube.lumaFloor) },
                                      set: { cube.lumaFloor = Int($0.rounded()) }),
                       range: 0...255)
                // Ghost amount only matters while isolating: 0 = the other frames vanish
                // entirely; higher = they linger as a faint translucent context cloud.
                if cube.isolate {
                    VStack(alignment: .leading, spacing: GlobalLattice.pt(1)) {
                        CellText("Ghost other frames \(Int(cube.ghostAlpha * 100))%",
                                 rows: 7, ink: Color(srgb8: SIMD3(210, 210, 210)))
                        CellSlider(value: $cube.ghostAlpha, range: 0...0.4, step: 0.05)
                    }
                }
            }
            .padding(GlobalLattice.pt(6))
            .background(Color(srgb8: SFTheme.ledGhost))   // flat cell panel, no glass
            .frame(maxWidth: edge)
        }
    }

    // Pixelated air-mask filter — a CellSelector over provMode (0 all / 1 extracted /
    // 2 split), flat cell segments instead of glass.
    private var provenanceFilter: some View {
        CellSelector(options: [(value: 0, label: "All"), (value: 1, label: "Real"), (value: 2, label: "Split")],
                     selection: Binding(get: { cube.provMode }, set: { cube.provMode = $0 }))
    }

    // Pixelated knob row: CellText label + CellSlider (a discrete cell stepper).
    private func slider(_ title: String,
                        value: Binding<Double>,
                        range: ClosedRange<Double>) -> some View {
        VStack(alignment: .leading, spacing: GlobalLattice.pt(1)) {
            CellText(title, rows: 7, ink: Color(srgb8: SIMD3(210, 210, 210)))
            CellSlider(value: value, range: range)
        }
    }

    // MARK: Drivers

    /// Orbit: drag rotates yaw/pitch. No inertia → nothing to freeze for a11y.
    private var orbitGesture: some Gesture {
        DragGesture(minimumDistance: 1)
            .onChanged { v in
                guard !cube.locked else { return }   // study mode: orientation frozen
                let gain: Float = 0.006
                cube.yaw += Float(v.translation.width) * gain
                cube.pitch += Float(-v.translation.height) * gain
                cube.pitch = max(-1.5, min(1.5, cube.pitch))
            }
    }

    /// Auto-rotate driver ONLY. The playback cursor is advanced by the shared
    /// `PlaybackClock` (the single clock) — this 60 Hz timer now drives just the slow
    /// turntable. Reduce Motion freezes auto-rotate (the clock owns the playback
    /// freeze); the user can still orbit/scrub by hand.
    private func advance() {
        guard !reduceMotion, cube.autoRotate else { return }
        // Ease the elevation up to the 8-bit iso angle (30°) so auto-rotate is a
        // dimetric TURNTABLE showing the 2:1 look, not a flat spin. Blooms smoothly
        // out of the rest pose; the auto-fit window keeps the whole cube framed.
        cube.yaw += 0.010
        cube.pitch += (VoxelIso.pitch - cube.pitch) * 0.08
    }

    private var placeholder: some View {
        RoundedRectangle(cornerRadius: SFTheme.cardCorner)
            .fill(.white.opacity(0.06))
            .frame(width: edge, height: edge)
            .overlay(CellText("Voxel data unavailable", rows: 8, ink: Color(srgb8: SIMD3(150, 150, 150))))
    }
}

// MARK: - Metal host (MTKView via UIViewRepresentable, the CameraPreview pattern)

@MainActor
private struct VoxelMetalView: UIViewRepresentable {
    let data: VoxelCubeData
    let state: VoxelCubeState
    /// The front-face frame, supplied by the shared `PlaybackClock`.
    let frame: Int
    /// Shared cross-view brush: palette index to highlight, or nil.
    var brushedIndex: Int?
    /// Brush set per radix (BrushSet.mode): 0 single / 1 quad (4⁴) / 2 σ-pair (2⁸).
    var brushMode: Int32 = 0

    func makeCoordinator() -> Renderer { Renderer(data: data) }

    func makeUIView(context: Context) -> MTKView {
        let v = MTKView()
        v.device = context.coordinator.device
        v.delegate = context.coordinator
        v.framebufferOnly = false                 // compute writes to the drawable
        v.colorPixelFormat = .bgra8Unorm
        v.preferredFramesPerSecond = 60
        v.isPaused = false
        v.enableSetNeedsDisplay = false
        v.clearColor = MTLClearColorMake(0, 0, 0, 1)
        context.coordinator.apply(state, frame: frame, brushedIndex: brushedIndex, brushMode: brushMode)
        return v
    }

    func updateUIView(_ uiView: MTKView, context: Context) {
        context.coordinator.apply(state, frame: frame, brushedIndex: brushedIndex, brushMode: brushMode)
    }
}

// MARK: - Uniforms (must mirror the kernel struct exactly)

private struct VoxelUniforms {
    var yaw: Float = 0
    var pitch: Float = 0
    var resolution: SIMD2<Float> = .zero
    var frame: Int32 = 0
    var tLo: Int32 = 0
    var tHi: Int32 = 63
    var lumaFloor: Int32 = 0
    var halfSpan: Float = 32            // projected half-extent → exact-fit window
    var provMode: Int32 = 0             // 0 all / 1 extracted / 2 split
    var brushedIndex: Int32 = -1        // shared cross-view brush; -1 = none
    var brushMode: Int32 = 0            // brush set: 0 single (16²) / 1 quad (4⁴) / 2 σ-pair (2⁸)
    var isolate: Int32 = 0             // frame-isolation: 0 off / 1 on
    var ghostAlpha: Float = 0          // alpha of non-focus slices when isolating
}

// MARK: - Renderer

@MainActor
private final class Renderer: NSObject, MTKViewDelegate {
    let device: (any MTLDevice)?
    private let queue: (any MTLCommandQueue)?
    private let pso: (any MTLComputePipelineState)?
    private let indexTex: (any MTLTexture)?      // 64³ R8Uint
    private let paletteTex: (any MTLTexture)?    // 64(t) × 256(k) RGBA8
    private var uniforms = VoxelUniforms()

    init(data: VoxelCubeData) {
        let dev = MTLCreateSystemDefaultDevice()
        self.device = dev
        self.queue = dev?.makeCommandQueue()

        // The kernel lives in Shaders.metal (compile-time validated); load it from
        // the default library, the GPUContext pattern. No first-launch hitch.
        var builtPSO: (any MTLComputePipelineState)? = nil
        if let dev,
           let lib = dev.makeDefaultLibrary(),
           let fn = lib.makeFunction(name: "voxel_raymarch") {
            builtPSO = try? dev.makeComputePipelineState(function: fn)
        }
        self.pso = builtPSO

        // Index volume: pack [t][y*64+x] → linear z-slices.
        if let dev, data.isWellFormed {
            let d = MTLTextureDescriptor()
            d.textureType = .type3D
            d.pixelFormat = .r8Uint
            d.width = VoxelCubeData.side
            d.height = VoxelCubeData.side
            d.depth = VoxelCubeData.frameCount
            d.usage = .shaderRead
            let tex = dev.makeTexture(descriptor: d)
            if let tex {
                var buf = [UInt8](repeating: 0,
                                  count: VoxelCubeData.pixelsPerFrame * VoxelCubeData.frameCount)
                for t in 0..<VoxelCubeData.frameCount {
                    let base = t * VoxelCubeData.pixelsPerFrame
                    let frame = data.frameIndices[t]
                    for i in 0..<VoxelCubeData.pixelsPerFrame { buf[base + i] = frame[i] }
                }
                buf.withUnsafeBytes { raw in
                    tex.replace(region: MTLRegionMake3D(0, 0, 0,
                                                        VoxelCubeData.side,
                                                        VoxelCubeData.side,
                                                        VoxelCubeData.frameCount),
                                mipmapLevel: 0, slice: 0,
                                withBytes: raw.baseAddress!,
                                bytesPerRow: VoxelCubeData.side,
                                bytesPerImage: VoxelCubeData.pixelsPerFrame)
                }
            }
            self.indexTex = tex
        } else { self.indexTex = nil }

        // Palette: 256-wide × 64-tall RGBA8 (row t = frame t's palette).
        if let dev, data.isWellFormed {
            let d = MTLTextureDescriptor.texture2DDescriptor(
                pixelFormat: .rgba8Unorm,
                width: VoxelCubeData.paletteCount,
                height: VoxelCubeData.frameCount,
                mipmapped: false)
            d.usage = .shaderRead
            let tex = dev.makeTexture(descriptor: d)
            if let tex {
                var buf = [UInt8](repeating: 255,
                                  count: VoxelCubeData.paletteCount * VoxelCubeData.frameCount * 4)
                for t in 0..<VoxelCubeData.frameCount {
                    let pal = data.srgbPalettes[t]
                    for k in 0..<VoxelCubeData.paletteCount {
                        let o = (t * VoxelCubeData.paletteCount + k) * 4
                        let c = pal[k]
                        // Alpha carries provenance (0 degenerate / 1 extracted /
                        // 2 split); default 1 when no significance data.
                        buf[o] = c.x; buf[o + 1] = c.y; buf[o + 2] = c.z
                        buf[o + 3] = data.provenance?[t][k] ?? 1
                    }
                }
                buf.withUnsafeBytes { raw in
                    tex.replace(region: MTLRegionMake2D(0, 0,
                                                        VoxelCubeData.paletteCount,
                                                        VoxelCubeData.frameCount),
                                mipmapLevel: 0,
                                withBytes: raw.baseAddress!,
                                bytesPerRow: VoxelCubeData.paletteCount * 4)
                }
            }
            self.paletteTex = tex
        } else { self.paletteTex = nil }

        super.init()
    }

    func apply(_ s: VoxelCubeState, frame: Int, brushedIndex: Int? = nil, brushMode: Int32 = 0) {
        uniforms.yaw = s.yaw
        uniforms.pitch = s.pitch
        uniforms.frame = Int32(max(0, min(63, frame)))
        uniforms.tLo = Int32(max(0, min(63, s.tLo)))
        uniforms.tHi = Int32(max(0, min(63, s.tHi)))
        uniforms.lumaFloor = Int32(max(0, min(255, s.lumaFloor)))
        uniforms.provMode = Int32(max(0, min(2, s.provMode)))
        uniforms.brushedIndex = brushedIndex.map { Int32(max(0, min(255, $0))) } ?? -1
        uniforms.brushMode = brushMode
        uniforms.isolate = s.isolate ? 1 : 0
        uniforms.ghostAlpha = Float(max(0, min(1, s.ghostAlpha)))

        // AUTO-FIT orthographic scale (the 8-bit "whole cube visible" rule). The window
        // exactly frames the cube's projected silhouette at the current orientation:
        // face-on it returns 32 (one voxel = one GIF cell ⇒ PIXEL-IDENTICAL to the 2D
        // GIF, RULE-CUBE-2D-IDENTITY); orbited toward the isometric pose it grows so the
        // whole dimetric hexagon is framed (voxels shrink a little). One formula serves
        // both the flat-identity rule and the chosen whole-cube iso framing, with no
        // discontinuity — at small orbit the silhouette ≈ 64 wide so the scale barely
        // moves out of identity. Supersedes the old fixed halfSpan=32 (which clipped).
        uniforms.halfSpan = VoxelIso.fitHalfSpan(yaw: s.yaw, pitch: s.pitch)
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    func draw(in view: MTKView) {
        guard let queue, let pso, let indexTex, let paletteTex,
              let drawable = view.currentDrawable,
              let cmd = queue.makeCommandBuffer(),
              let enc = cmd.makeComputeCommandEncoder()
        else { return }

        uniforms.resolution = SIMD2<Float>(Float(view.drawableSize.width),
                                           Float(view.drawableSize.height))
        enc.setComputePipelineState(pso)
        enc.setTexture(indexTex, index: 0)
        enc.setTexture(paletteTex, index: 1)
        enc.setTexture(drawable.texture, index: 2)
        var u = uniforms
        enc.setBytes(&u, length: MemoryLayout<VoxelUniforms>.stride, index: 0)

        let tg = MTLSize(width: 8, height: 8, depth: 1)
        let grid = MTLSize(width: (Int(uniforms.resolution.x) + 7) / 8,
                           height: (Int(uniforms.resolution.y) + 7) / 8,
                           depth: 1)
        enc.dispatchThreadgroups(grid, threadsPerThreadgroup: tg)
        enc.endEncoding()
        cmd.present(drawable)
        cmd.commit()
    }
}

// MARK: - Preview (synthetic 64³ data, no capture needed)

#if DEBUG
private func makeSyntheticVoxelData() -> VoxelCubeData {
    let side = VoxelCubeData.side, frames = VoxelCubeData.frameCount, pal = VoxelCubeData.paletteCount
    var frameIndices: [[UInt8]] = [], palettes: [[SIMD3<UInt8>]] = []
    var provenance: [[UInt8]] = []
    for t in 0..<frames {
        // Synthetic provenance to exercise the filter: top quarter = split (2),
        // a couple of slots degenerate/air (0), the rest extracted (1).
        provenance.append((0..<pal).map { k in k >= pal * 3 / 4 ? 2 : (k % 97 == 0 ? 0 : 1) })
        var p = [SIMD3<UInt8>](repeating: .zero, count: pal)
        for k in 0..<pal {
            let hue = Float(k) / Float(pal) + Float(t) / Float(frames)
            let r = UInt8((0.5 + 0.5 * sin(hue * 6.28318)) * 255)
            let g = UInt8((0.5 + 0.5 * sin((hue + 0.33) * 6.28318)) * 255)
            let b = UInt8((0.5 + 0.5 * sin((hue + 0.66) * 6.28318)) * 255)
            let scale: Float = k < pal / 4 ? 0.2 : 1.0   // dark slots exercise the luma floor
            p[k] = SIMD3<UInt8>(UInt8(Float(r) * scale), UInt8(Float(g) * scale), UInt8(Float(b) * scale))
        }
        palettes.append(p)
        var idx = [UInt8](repeating: 0, count: side * side)
        let cx = Float(side) * (0.3 + 0.4 * Float(t) / Float(frames)), cy = Float(side) * 0.5
        for y in 0..<side {
            for x in 0..<side {
                let dx = Float(x) - cx, dy = Float(y) - cy
                let d = (dx * dx + dy * dy).squareRoot()
                idx[y * side + x] = d < 18 ? UInt8(64 + Int(d * 8) % 192) : UInt8(x % (pal / 4))
            }
        }
        frameIndices.append(idx)
    }
    return VoxelCubeData(frameIndices: frameIndices, srgbPalettes: palettes, provenance: provenance)
}

#Preview("Voxel Cube — synthetic") {
    VoxelCubeView(data: makeSyntheticVoxelData(), clock: PlaybackClock(count: 64))
        .padding()
        .preferredColorScheme(.dark)
}
#endif
