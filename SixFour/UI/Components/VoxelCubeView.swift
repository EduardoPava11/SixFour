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

    static let frameCount = 64
    static let side = 64           // x and y extent
    static let pixelsPerFrame = 64 * 64
    static let paletteCount = 256

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
        guard isWellFormed else { return nil }
    }

    init(frameIndices: [[UInt8]], srgbPalettes: [[SIMD3<UInt8>]]) {
        self.frameIndices = frameIndices
        self.srgbPalettes = srgbPalettes
    }
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
    /// Playback cursor — the frame shown on the front face. 0…63.
    var frame: Int = 0
    var playing: Bool = true
    var autoRotate: Bool = false

    /// θ = how far we are from the flat 2D pose (radians). 0 == pure 2D.
    var orbitMagnitude: Float { (yaw * yaw + pitch * pitch).squareRoot() }
    var isFlat: Bool { orbitMagnitude < 0.001 }
}

// MARK: - SwiftUI host

@MainActor
struct VoxelCubeView: View {
    let data: VoxelCubeData
    /// Edge of the square render surface, in points. Default = gifCanvasPt so a
    /// voxel is gifCellPt (6 pt) face-on — identical to the 2D GIF hero.
    var edge: CGFloat = 384

    @State private var cube = VoxelCubeState()
    @State private var tick = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // The single 60 Hz driver for playback (20 fps cursor) + auto-rotate.
    private let clock = Timer.publish(every: 1.0 / 60.0, on: .main, in: .common).autoconnect()

    var body: some View {
        Group {
            if data.isWellFormed { cubeBody } else { placeholder }
        }
        .onReceive(clock) { _ in advance() }
    }

    private var cubeBody: some View {
        VStack(spacing: 12) {
            ZStack(alignment: .topTrailing) {
                VoxelMetalView(data: data, state: cube)
                    .frame(width: edge, height: edge)
                    .background(Color.black)
                    .highPriorityGesture(orbitGesture)
                    .accessibilityElement()
                    .accessibilityLabel("64 by 64 by 64 voxel palette cube")
                    .accessibilityValue(cube.isFlat
                        ? "Flat view, frame \(cube.frame + 1) of 64. Drag to orbit into 3D."
                        : "Orbited \(Int(cube.orbitMagnitude * 57)) degrees, frame \(cube.frame + 1) of 64.")

                // Reset-to-2D — the "fold back flat" affordance (glass chrome).
                GlassIconButton(systemImage: "cube.transparent",
                                accessibilityLabel: "Reset to flat 2D view") {
                    withAnimation(.easeInOut(duration: 0.45)) {
                        cube.yaw = 0; cube.pitch = 0
                    }
                }
                .padding(8)
            }

            controls
        }
    }

    // MARK: Glass control chrome

    private var controls: some View {
        VStack(spacing: 10) {
            // Transport cluster — one GlassEffectContainer (GLASS G3).
            GlassToolbarCluster {
                GlassIconButton(systemImage: cube.playing ? "pause.fill" : "play.fill",
                                accessibilityLabel: cube.playing ? "Pause" : "Play") {
                    cube.playing.toggle()
                }
                GlassIconButton(systemImage: "rotate.3d",
                                accessibilityLabel: cube.autoRotate ? "Stop auto-rotate" : "Auto-rotate",
                                tint: cube.autoRotate ? .white : .white.opacity(0.6)) {
                    cube.autoRotate.toggle()
                }
            }

            // Knobs — a read-only-style glass panel (the cube stays content).
            VStack(spacing: 8) {
                slider("Frame \(cube.frame + 1)/64",
                       get: { Double(cube.frame) },
                       set: { cube.frame = Int($0.rounded()); cube.playing = false },
                       range: 0...63)
                slider("Trail depth \(cube.tHi - cube.tLo + 1)",
                       get: { Double(cube.tLo) },
                       set: { cube.tLo = min(Int($0.rounded()), cube.tHi) },
                       range: 0...63)
                slider("Air below luma \(cube.lumaFloor)",
                       get: { Double(cube.lumaFloor) },
                       set: { cube.lumaFloor = Int($0.rounded()) },
                       range: 0...255)
            }
            .padding(12)
            .glassEffect(.regular, in: RoundedRectangle(cornerRadius: SFTheme.cardCorner))
            .frame(maxWidth: edge)
        }
    }

    private func slider(_ title: String,
                        get: @escaping () -> Double,
                        set: @escaping (Double) -> Void,
                        range: ClosedRange<Double>) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.white.opacity(0.85))
            Slider(value: Binding(get: get, set: set), in: range, step: 1)
        }
    }

    // MARK: Drivers

    /// Orbit: drag rotates yaw/pitch. No inertia → nothing to freeze for a11y.
    private var orbitGesture: some Gesture {
        DragGesture(minimumDistance: 1)
            .onChanged { v in
                let gain: Float = 0.006
                cube.yaw += Float(v.translation.width) * gain
                cube.pitch += Float(-v.translation.height) * gain
                cube.pitch = max(-1.5, min(1.5, cube.pitch))
            }
    }

    /// One clock: advance the 20 fps playback cursor (every 3rd 60 Hz tick) and
    /// the slow auto-rotate. Reduce Motion freezes BOTH (the cube holds still;
    /// the user can still scrub manually) — GLASS §6 RULE-GLASS-MOTION.
    private func advance() {
        guard !reduceMotion else { return }
        tick &+= 1
        if cube.playing, tick % 3 == 0 {
            cube.frame = (cube.frame + 1) % 64
        }
        if cube.autoRotate {
            cube.yaw += 0.010
        }
    }

    private var placeholder: some View {
        RoundedRectangle(cornerRadius: SFTheme.cardCorner)
            .fill(.white.opacity(0.06))
            .frame(width: edge, height: edge)
            .overlay(Text("Voxel data unavailable")
                .font(.caption).foregroundStyle(.white.opacity(0.6)))
    }
}

// MARK: - Metal host (MTKView via UIViewRepresentable, the CameraPreview pattern)

@MainActor
private struct VoxelMetalView: UIViewRepresentable {
    let data: VoxelCubeData
    let state: VoxelCubeState

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
        context.coordinator.apply(state)
        return v
    }

    func updateUIView(_ uiView: MTKView, context: Context) {
        context.coordinator.apply(state)
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

        var builtPSO: (any MTLComputePipelineState)? = nil
        if let dev,
           let lib = try? dev.makeLibrary(source: Renderer.kernelSource, options: nil),
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
                        buf[o] = c.x; buf[o + 1] = c.y; buf[o + 2] = c.z; buf[o + 3] = 255
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

    /// Mirror the Metal `orbit()` so the CPU-side window fit matches the kernel.
    private static func orbit(_ v: SIMD3<Float>, _ yaw: Float, _ pitch: Float) -> SIMD3<Float> {
        let cy = cos(yaw), sy = sin(yaw)
        let r = SIMD3<Float>(cy * v.x + sy * v.z, v.y, -sy * v.x + cy * v.z)
        let cp = cos(pitch), sp = sin(pitch)
        return SIMD3<Float>(r.x, cp * r.y - sp * r.z, sp * r.y + cp * r.z)
    }

    func apply(_ s: VoxelCubeState) {
        uniforms.yaw = s.yaw
        uniforms.pitch = s.pitch
        uniforms.frame = Int32(max(0, min(63, s.frame)))
        uniforms.tLo = Int32(max(0, min(63, s.tLo)))
        uniforms.tHi = Int32(max(0, min(63, s.tHi)))
        uniforms.lumaFloor = Int32(max(0, min(255, s.lumaFloor)))

        // Exact-fit orthographic window: project the 8 cube corners (centred
        // ±32) onto the rotating view plane and take the max half-extent. Face-on
        // this is 32 → one voxel = edge/64 = gifCellPt → PIXEL-IDENTICAL to 2D.
        let xb = Self.orbit(SIMD3(1, 0, 0), s.yaw, s.pitch)
        let yb = Self.orbit(SIMD3(0, 1, 0), s.yaw, s.pitch)
        var m: Float = 0
        for sx in [Float(-32), 32] {
            for sy in [Float(-32), 32] {
                for sz in [Float(-32), 32] {
                    let c = SIMD3<Float>(sx, sy, sz)
                    m = max(m, abs(simd_dot(c, xb)))
                    m = max(m, abs(simd_dot(c, yb)))
                }
            }
        }
        uniforms.halfSpan = m
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

    // MARK: Kernel — orthographic DDA raymarch, depth = time, front = current frame
    nonisolated static let kernelSource = """
    #include <metal_stdlib>
    using namespace metal;

    struct Uniforms {
        float yaw;
        float pitch;
        float2 resolution;
        int frame;
        int tLo;
        int tHi;
        int lumaFloor;
        float halfSpan;
    };

    // Rotate a vector by yaw (about Y) then pitch (about X). Matches Renderer.orbit.
    static inline float3 orbit(float3 v, float yaw, float pitch) {
        float cy = cos(yaw), sy = sin(yaw);
        float3 r = float3(cy * v.x + sy * v.z, v.y, -sy * v.x + cy * v.z);
        float cp = cos(pitch), sp = sin(pitch);
        return float3(r.x, cp * r.y - sp * r.z, sp * r.y + cp * r.z);
    }

    // Slab intersection with [0,64]^3. .x = t-enter (>=0), .y = t-exit; miss if y<x.
    static inline float2 boxHit(float3 o, float3 d) {
        float3 inv = 1.0 / d;
        float3 t0 = (float3(0.0) - o) * inv;
        float3 t1 = (float3(64.0) - o) * inv;
        float3 tmin = min(t0, t1), tmax = max(t0, t1);
        return float2(max(max(max(tmin.x, tmin.y), tmin.z), 0.0),
                      min(min(tmax.x, tmax.y), tmax.z));
    }

    kernel void voxel_raymarch(
        texture3d<uint,  access::read>   indexTex   [[texture(0)]],
        texture2d<float, access::sample> paletteTex [[texture(1)]],
        texture2d<float, access::write>  outTex     [[texture(2)]],
        constant Uniforms& U                        [[buffer(0)]],
        uint2 gid                                   [[thread_position_in_grid]])
    {
        if (gid.x >= (uint)U.resolution.x || gid.y >= (uint)U.resolution.y) return;

        float4 bg = float4(0.0, 0.0, 0.0, 1.0);   // pure black: at rest the cube
                                                  // fills the frame, so bg never shows

        // Square-fit the drawable, top-left origin.
        float side = min(U.resolution.x, U.resolution.y);
        float2 off = (U.resolution - side) * 0.5;
        float2 px = float2(gid) + 0.5 - off;
        if (px.x < 0.0 || px.y < 0.0 || px.x >= side || px.y >= side) { outTex.write(bg, gid); return; }
        float2 uv = px / side;                    // 0..1, top-left

        // Orthographic camera. Plane axes rotate with the orbit; window is the
        // exact projected silhouette (halfSpan). At rest halfSpan = 32 so the
        // 64-wide cube fills the square 1:1 with the 2D GIF.
        float2 plane = (uv - 0.5) * 2.0 * U.halfSpan;   // +x right, +y down
        float3 Xb = orbit(float3(1, 0, 0), U.yaw, U.pitch);
        float3 Yb = orbit(float3(0, 1, 0), U.yaw, U.pitch);
        float3 Zb = orbit(float3(0, 0, 1), U.yaw, U.pitch);
        float3 center = float3(32.0);
        float3 o = center + plane.x * Xb + plane.y * Yb + 200.0 * Zb;  // camera plane
        float3 d = -Zb;                                               // parallel rays

        float2 hit = boxHit(o, d);
        if (hit.y < hit.x) { outTex.write(bg, gid); return; }

        float3 p = o + d * (hit.x + 1e-3);
        int3 voxel = int3(floor(p));
        int3 stp = int3(sign(d));
        float3 inv = 1.0 / d;
        float3 tMax = (float3(voxel) + max(float3(stp), float3(0.0)) - o) * inv;
        float3 tDelta = abs(inv);

        int tLo = clamp(U.tLo, 0, 63);
        int tHi = clamp(U.tHi, 0, 63);
        int cursor = clamp(U.frame, 0, 63);

        float4 col = bg;
        int axis = -1;

        for (int i = 0; i < 220; ++i) {
            bool inside = voxel.x >= 0 && voxel.x < 64 &&
                          voxel.y >= 0 && voxel.y < 64 &&
                          voxel.z >= 0 && voxel.z < 64;
            if (!inside) break;

            if (voxel.z >= tLo && voxel.z <= tHi) {
                // Depth = time: slice z shows frame f(z); front (z=63) = cursor,
                // earlier frames recede behind it. This is what makes the rest
                // pose identical to the 2D GIF and the orbit reveal its history.
                int fz = ((cursor - 63 + voxel.z) % 64 + 64) % 64;

                uint k = indexTex.read(uint3(uint(voxel.x), uint(voxel.y), uint(fz))).r;
                constexpr sampler s(coord::normalized, filter::nearest, address::clamp_to_edge);
                float2 pc = float2(float(k) + 0.5, float(fz) + 0.5) / float2(256.0, 64.0);
                float4 rgb = paletteTex.sample(s, pc);

                float luma255 = (0.2126 * rgb.r + 0.7152 * rgb.g + 0.0722 * rgb.b) * 255.0;
                if (luma255 >= float(U.lumaFloor)) {
                    // One discrete per-face multiply — the only depth cue.
                    float mul = (axis == 0) ? 0.82 : (axis == 2 ? 0.90 : 1.0);
                    col = float4(rgb.rgb * mul, 1.0);
                    break;
                }
            }

            if (tMax.x < tMax.y) {
                if (tMax.x < tMax.z) { voxel.x += stp.x; tMax.x += tDelta.x; axis = 0; }
                else                 { voxel.z += stp.z; tMax.z += tDelta.z; axis = 2; }
            } else {
                if (tMax.y < tMax.z) { voxel.y += stp.y; tMax.y += tDelta.y; axis = 1; }
                else                 { voxel.z += stp.z; tMax.z += tDelta.z; axis = 2; }
            }
        }

        outTex.write(col, gid);
    }
    """
}

// MARK: - Preview (synthetic 64³ data, no capture needed)

#if DEBUG
private func makeSyntheticVoxelData() -> VoxelCubeData {
    let side = VoxelCubeData.side, frames = VoxelCubeData.frameCount, pal = VoxelCubeData.paletteCount
    var frameIndices: [[UInt8]] = [], palettes: [[SIMD3<UInt8>]] = []
    for t in 0..<frames {
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
    return VoxelCubeData(frameIndices: frameIndices, srgbPalettes: palettes)
}

#Preview("Voxel Cube — synthetic") {
    VoxelCubeView(data: makeSyntheticVoxelData())
        .padding()
        .preferredColorScheme(.dark)
}
#endif
