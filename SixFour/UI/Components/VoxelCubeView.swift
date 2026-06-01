import SwiftUI
import MetalKit
import simd

// MARK: - VoxelCubeView
//
// A 64×64×64 VOXEL CUBE view of a SixFour GIF, for the Review screen's
// palette-explorer (alongside treemap2D / grid2D).
//
// A SixFour GIF is 64 frames × (64×64 px) × 256-colour-per-frame palette. We
// treat it as a 64³ voxel cube: axes x∈0…63 (column), y∈0…63 (row, top-left
// origin), t∈0…63 (the 64 frames as the DEPTH/Z axis). The voxel colour at
// (x,y,t) is:
//
//     srgbPalettes[t][ frameIndices[t][y*64 + x] ]   (SIMD3<UInt8> sRGB)
//
// This is a PURE FUNCTION of data Review already has — no new capture/render.
//
// RENDERER: a hand-written Metal compute DDA raymarcher (Amanatides–Woo) that
// marches a 64³ R8Uint index volume per drawable pixel, looks up the per-frame
// 64×256 palette, applies a discrete per-face brightness multiply (the single
// permitted depth cue — NOT continuous shading), and writes one opaque indexed
// sRGB8 per surface voxel. This is the only design that (a) adds zero
// dependency surface (Metal is an Apple framework; CLAUDE.md Tier-2 allows it),
// (b) handles the per-frame palette (same index → different colour per frame,
// which breaks greedy meshing), and (c) makes slicing/threshold free per-ray
// adjustments with no geometry rebuild.
//
// CONTRACT: the cube is CONTENT (GRID): no glass on the voxels, the cell is the
// world unit (1 voxel = 1 cell = 1 GIF pixel). A couple of glass controls float
// around it as chrome. This file is Tier-2 pure: Apple frameworks + simd only.

// MARK: - Input data shape

/// The minimal voxel-cube input, exactly the Review data shape. In the app this
/// is built from `CaptureOutput` once `frameIndicesForVoxels` is threaded
/// through (see integration notes); here it is its own value so the view is
/// testable from synthetic data with no capture pipeline.
struct VoxelCubeData: Sendable {
    /// 64 frames × 4096 (= 64×64) palette indices, row-major y*64+x, top-left origin.
    let frameIndices: [[UInt8]]
    /// 64 frames × 256 sRGB palettes.
    let srgbPalettes: [[SIMD3<UInt8>]]

    static let frameCount = 64
    static let side = 64           // x and y extent
    static let pixelsPerFrame = 64 * 64
    static let paletteCount = 256

    /// Cheap shape check — the view degrades to a placeholder if this is false.
    var isWellFormed: Bool {
        frameIndices.count == Self.frameCount
            && srgbPalettes.count == Self.frameCount
            && frameIndices.allSatisfy { $0.count == Self.pixelsPerFrame }
            && srgbPalettes.allSatisfy { $0.count == Self.paletteCount }
    }
}

// MARK: - View state (single owner of all knobs)

/// The single value that owns every cube knob (GRID Law #5 spirit: one owner,
/// no view multiplies a size itself). Orbit, slice band, and the luminance
/// air-threshold all live here.
struct VoxelCubeState: Equatable {
    var yaw: Float = 0.6          // radians
    var pitch: Float = 0.4        // radians
    /// t-slice band [lo, hi] in 0…63 — the primary interior-reveal.
    var tLo: Int = 0
    var tHi: Int = 63
    /// Luminance air floor 0…255: voxels whose palette luminance < floor become
    /// air, carving the cube by brightness. 0 = fully solid.
    var lumaFloor: Int = 0
    /// Which frame's colour drives the cube (the depth/playback cursor).
    var frame: Int = 0
}

// MARK: - SwiftUI host

@MainActor
struct VoxelCubeView: View {
    let data: VoxelCubeData
    /// Edge of the square render surface, in points (the Review hero size).
    var edge: CGFloat = 320

    @State private var cube = VoxelCubeState()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            if data.isWellFormed {
                cubeBody
            } else {
                placeholder
            }
        }
    }

    private var cubeBody: some View {
        VStack(spacing: 12) {
            ZStack(alignment: .topTrailing) {
                VoxelMetalView(data: data, state: cube)
                    .frame(width: edge, height: edge)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    // Orbit: one-finger drag rotates yaw/pitch. High-priority so
                    // it consumes the touch before any parent ScrollView.
                    .highPriorityGesture(orbitGesture)
                    .accessibilityLabel("Voxel cube, drag to orbit")

                // Reset view — a single floating glass chrome button over content.
                Button {
                    cube.yaw = 0.6
                    cube.pitch = 0.4
                } label: {
                    Image(systemName: "arrow.counterclockwise")
                        .font(.title3)
                        .foregroundStyle(.white)
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)
                .glassEffect(.regular.interactive(), in: Circle())
                .padding(8)
                .accessibilityLabel("Reset view")
            }

            controls
        }
    }

    // Glass chrome cluster: frame scrub, t-slice band, luminance air floor.
    private var controls: some View {
        VStack(spacing: 10) {
            labeledSlider("Frame \(cube.frame)",
                          value: Binding(
                            get: { Double(cube.frame) },
                            set: { cube.frame = Int($0.rounded()) }),
                          range: 0...63)

            labeledSlider("Slice from \(cube.tLo)",
                          value: Binding(
                            get: { Double(cube.tLo) },
                            set: { cube.tLo = min(Int($0.rounded()), cube.tHi) }),
                          range: 0...63)

            labeledSlider("Slice to \(cube.tHi)",
                          value: Binding(
                            get: { Double(cube.tHi) },
                            set: { cube.tHi = max(Int($0.rounded()), cube.tLo) }),
                          range: 0...63)

            labeledSlider("Air below luma \(cube.lumaFloor)",
                          value: Binding(
                            get: { Double(cube.lumaFloor) },
                            set: { cube.lumaFloor = Int($0.rounded()) }),
                          range: 0...255)
        }
        .padding(12)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .frame(maxWidth: edge)
    }

    private func labeledSlider(_ title: String,
                               value: Binding<Double>,
                               range: ClosedRange<Double>) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)
            Slider(value: value, in: range, step: 1)
        }
    }

    private var orbitGesture: some Gesture {
        DragGesture(minimumDistance: 1)
            .onChanged { v in
                // Map drag translation to yaw/pitch. Small gain; clamp pitch so
                // the cube never flips. No inertia → safe under Reduce Motion.
                let gain: Float = 0.01
                cube.yaw += Float(v.translation.width) * gain * 0.15
                cube.pitch += Float(-v.translation.height) * gain * 0.15
                cube.pitch = max(-1.5, min(1.5, cube.pitch))
            }
    }

    private var placeholder: some View {
        RoundedRectangle(cornerRadius: 14, style: .continuous)
            .fill(.secondary.opacity(0.15))
            .frame(width: edge, height: edge)
            .overlay(
                Text("Voxel data unavailable")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            )
    }
}

// MARK: - Metal host (MTKView via UIViewRepresentable, the CameraPreview pattern)

@MainActor
private struct VoxelMetalView: UIViewRepresentable {
    let data: VoxelCubeData
    let state: VoxelCubeState

    func makeCoordinator() -> Renderer {
        // If the renderer can't initialise (no device / kernel fails to
        // compile), we get a nil-safe Renderer that draws nothing.
        Renderer(data: data)
    }

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
    var invViewYaw: Float = 0
    var invViewPitch: Float = 0
    var resolution: SIMD2<Float> = .zero      // drawable px
    var frame: Int32 = 0
    var tLo: Int32 = 0
    var tHi: Int32 = 63
    var lumaFloor: Int32 = 0
    var _pad: Int32 = 0
}

// MARK: - Renderer

@MainActor
private final class Renderer: NSObject, MTKViewDelegate {
    let device: (any MTLDevice)?
    private let queue: (any MTLCommandQueue)?
    private let pso: (any MTLComputePipelineState)?

    // 64³ R8Uint index volume.
    private let indexTex: (any MTLTexture)?
    // 64(rows=t) × 256(cols=k) RGBA8 palette.
    private let paletteTex: (any MTLTexture)?

    private var uniforms = VoxelUniforms()

    init(data: VoxelCubeData) {
        let dev = MTLCreateSystemDefaultDevice()
        self.device = dev
        self.queue = dev?.makeCommandQueue()

        // Compile the raymarch kernel from source — keeps this file
        // self-contained (no dependency on Shaders.metal carrying the kernel).
        var builtPSO: (any MTLComputePipelineState)? = nil
        if let dev {
            if let lib = try? dev.makeLibrary(source: Renderer.kernelSource, options: nil),
               let fn = lib.makeFunction(name: "voxel_raymarch") {
                builtPSO = try? dev.makeComputePipelineState(function: fn)
            }
        }
        self.pso = builtPSO

        // Upload the index volume.
        if let dev, data.isWellFormed {
            let desc = MTLTextureDescriptor()
            desc.textureType = .type3D
            desc.pixelFormat = .r8Uint
            desc.width = VoxelCubeData.side
            desc.height = VoxelCubeData.side
            desc.depth = VoxelCubeData.frameCount
            desc.usage = .shaderRead
            let tex = dev.makeTexture(descriptor: desc)
            if let tex {
                // Pack [t][y*64+x] → linear z-slices.
                var buf = [UInt8](repeating: 0, count:
                    VoxelCubeData.side * VoxelCubeData.side * VoxelCubeData.frameCount)
                for t in 0..<VoxelCubeData.frameCount {
                    let base = t * VoxelCubeData.pixelsPerFrame
                    let frame = data.frameIndices[t]
                    for i in 0..<VoxelCubeData.pixelsPerFrame { buf[base + i] = frame[i] }
                }
                buf.withUnsafeBytes { raw in
                    tex.replace(
                        region: MTLRegionMake3D(0, 0, 0,
                                                VoxelCubeData.side,
                                                VoxelCubeData.side,
                                                VoxelCubeData.frameCount),
                        mipmapLevel: 0,
                        slice: 0,
                        withBytes: raw.baseAddress!,
                        bytesPerRow: VoxelCubeData.side,
                        bytesPerImage: VoxelCubeData.pixelsPerFrame)
                }
            }
            self.indexTex = tex
        } else {
            self.indexTex = nil
        }

        // Upload the per-frame palette as a 256-wide × 64-tall RGBA8 texture.
        if let dev, data.isWellFormed {
            let desc = MTLTextureDescriptor.texture2DDescriptor(
                pixelFormat: .rgba8Unorm,
                width: VoxelCubeData.paletteCount,
                height: VoxelCubeData.frameCount,
                mipmapped: false)
            desc.usage = .shaderRead
            let tex = dev.makeTexture(descriptor: desc)
            if let tex {
                var buf = [UInt8](repeating: 255, count:
                    VoxelCubeData.paletteCount * VoxelCubeData.frameCount * 4)
                for t in 0..<VoxelCubeData.frameCount {
                    let pal = data.srgbPalettes[t]
                    for k in 0..<VoxelCubeData.paletteCount {
                        let o = (t * VoxelCubeData.paletteCount + k) * 4
                        let c = pal[k]
                        buf[o + 0] = c.x
                        buf[o + 1] = c.y
                        buf[o + 2] = c.z
                        buf[o + 3] = 255
                    }
                }
                buf.withUnsafeBytes { raw in
                    tex.replace(
                        region: MTLRegionMake2D(0, 0,
                                                VoxelCubeData.paletteCount,
                                                VoxelCubeData.frameCount),
                        mipmapLevel: 0,
                        withBytes: raw.baseAddress!,
                        bytesPerRow: VoxelCubeData.paletteCount * 4)
                }
            }
            self.paletteTex = tex
        } else {
            self.paletteTex = nil
        }

        super.init()
    }

    func apply(_ s: VoxelCubeState) {
        uniforms.invViewYaw = s.yaw
        uniforms.invViewPitch = s.pitch
        uniforms.frame = Int32(max(0, min(63, s.frame)))
        uniforms.tLo = Int32(max(0, min(63, s.tLo)))
        uniforms.tHi = Int32(max(0, min(63, s.tHi)))
        uniforms.lumaFloor = Int32(max(0, min(255, s.lumaFloor)))
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    func draw(in view: MTKView) {
        guard
            let queue, let pso, let indexTex, let paletteTex,
            let drawable = view.currentDrawable,
            let cmd = queue.makeCommandBuffer(),
            let enc = cmd.makeComputeCommandEncoder()
        else { return }

        let w = view.drawableSize.width
        let h = view.drawableSize.height
        uniforms.resolution = SIMD2<Float>(Float(w), Float(h))

        enc.setComputePipelineState(pso)
        enc.setTexture(indexTex, index: 0)
        enc.setTexture(paletteTex, index: 1)
        enc.setTexture(drawable.texture, index: 2)
        var u = uniforms
        enc.setBytes(&u, length: MemoryLayout<VoxelUniforms>.stride, index: 0)

        let tg = MTLSize(width: 8, height: 8, depth: 1)
        let grid = MTLSize(
            width: (Int(w) + 7) / 8,
            height: (Int(h) + 7) / 8,
            depth: 1)
        enc.dispatchThreadgroups(grid, threadsPerThreadgroup: tg)
        enc.endEncoding()
        cmd.present(drawable)
        cmd.commit()
    }

    // MARK: Kernel source (DDA raymarch)
    //
    // Amanatides–Woo voxel traversal of a 64³ index volume. The camera orbits
    // the cube centre; eye rays are built in cube-local space by applying the
    // inverse orbit rotation, so the DDA marches in integer voxel space.
    nonisolated static let kernelSource = """
    #include <metal_stdlib>
    using namespace metal;

    struct Uniforms {
        float invViewYaw;
        float invViewPitch;
        float2 resolution;
        int frame;
        int tLo;
        int tHi;
        int lumaFloor;
        int _pad;
    };

    // Rotate a vector by yaw (about Y) then pitch (about X).
    static inline float3 orbit(float3 v, float yaw, float pitch) {
        float cy = cos(yaw), sy = sin(yaw);
        float3 r = float3(cy * v.x + sy * v.z, v.y, -sy * v.x + cy * v.z);
        float cp = cos(pitch), sp = sin(pitch);
        return float3(r.x, cp * r.y - sp * r.z, sp * r.y + cp * r.z);
    }

    // Intersect ray (o,d) with the [0,64]^3 box. Returns t-enter (clamped >=0)
    // in .x and t-exit in .y; .y < .x means a miss.
    static inline float2 boxHit(float3 o, float3 d) {
        float3 inv = 1.0 / d;
        float3 t0 = (float3(0.0) - o) * inv;
        float3 t1 = (float3(64.0) - o) * inv;
        float3 tmin = min(t0, t1);
        float3 tmax = max(t0, t1);
        float tenter = max(max(tmin.x, tmin.y), tmin.z);
        float texit  = min(min(tmax.x, tmax.y), tmax.z);
        return float2(max(tenter, 0.0), texit);
    }

    kernel void voxel_raymarch(
        texture3d<uint, access::read>  indexTex   [[texture(0)]],
        texture2d<float, access::sample> paletteTex [[texture(1)]],
        texture2d<float, access::write> outTex     [[texture(2)]],
        constant Uniforms& U                       [[buffer(0)]],
        uint2 gid                                  [[thread_position_in_grid]])
    {
        if (gid.x >= (uint)U.resolution.x || gid.y >= (uint)U.resolution.y) return;

        // Background (dark, not glass — the cube is content on a neutral field).
        float4 bg = float4(0.06, 0.06, 0.07, 1.0);

        // Normalised screen coords in [-1,1], square aspect from min dim.
        float2 uv = (float2(gid) + 0.5) / U.resolution * 2.0 - 1.0;
        float aspect = U.resolution.x / U.resolution.y;
        uv.x *= aspect;
        uv.y = -uv.y;  // flip so +y is up on screen

        // Camera in cube-local space: orbit a fixed eye + ray direction.
        // Base eye looks down -Z toward the centred cube.
        float radius = 150.0;
        float3 eyeBase = float3(0.0, 0.0, radius);
        float3 dirBase = normalize(float3(uv * 0.55, -1.0)); // simple perspective

        float3 eye = orbit(eyeBase, U.invViewYaw, U.invViewPitch);
        float3 dir = orbit(dirBase, U.invViewYaw, U.invViewPitch);

        // Shift to cube-local [0,64] space (cube centre at (32,32,32)).
        float3 o = eye + float3(32.0, 32.0, 32.0);

        float2 hit = boxHit(o, dir);
        if (hit.y < hit.x) { outTex.write(bg, gid); return; }

        // Entry point, nudged inside.
        float3 p = o + dir * (hit.x + 1e-3);

        // DDA setup.
        int3 voxel = int3(floor(p));
        int3 step = int3(sign(dir));
        float3 inv = 1.0 / dir;
        float3 nextBoundary = float3(voxel) + max(float3(step), float3(0.0));
        float3 tMax = (nextBoundary - o) * inv;
        float3 tDelta = abs(inv);

        int tLo = clamp(U.tLo, 0, 63);
        int tHi = clamp(U.tHi, 0, 63);
        int frame = clamp(U.frame, 0, 63);

        float4 col = bg;
        int axisHit = -1;  // 0=x,1=y,2=z face — for directional brightening

        // March. 64*3 worst-case steps bounds the loop.
        for (int i = 0; i < 200; ++i) {
            bool inside = voxel.x >= 0 && voxel.x < 64 &&
                          voxel.y >= 0 && voxel.y < 64 &&
                          voxel.z >= 0 && voxel.z < 64;
            if (!inside) break;

            // Slice band on the t (z) axis.
            if (voxel.z >= tLo && voxel.z <= tHi) {
                uint k = indexTex.read(uint3(voxel.x, voxel.y, voxel.z)).r;

                // Palette colour for the CURRENT display frame (not voxel.z),
                // so the whole cube is coloured by the playback cursor while its
                // SHAPE is the index volume. (z still drives slicing.)
                float2 pcoord = (float2(float(k) + 0.5, float(frame) + 0.5)) /
                                float2(256.0, 64.0);
                constexpr sampler s(coord::normalized, filter::nearest,
                                    address::clamp_to_edge);
                float4 rgb = paletteTex.sample(s, pcoord);

                // Luminance air threshold (Rec.709 on the sRGB bytes, cheap).
                float luma255 = (0.2126 * rgb.r + 0.7152 * rgb.g + 0.0722 * rgb.b) * 255.0;
                bool air = luma255 < float(U.lumaFloor);

                if (!air) {
                    // Directional face brightening — the ONE depth cue, applied
                    // as a discrete per-face multiply (not continuous shading).
                    float mul = 1.0;
                    if (axisHit == 0) mul = 0.82;
                    else if (axisHit == 2) mul = 0.90;
                    else mul = 1.0; // top/y face brightest
                    col = float4(rgb.rgb * mul, 1.0);
                    break;
                }
            }

            // Advance to the next voxel along the smallest tMax.
            if (tMax.x < tMax.y) {
                if (tMax.x < tMax.z) { voxel.x += step.x; tMax.x += tDelta.x; axisHit = 0; }
                else                 { voxel.z += step.z; tMax.z += tDelta.z; axisHit = 2; }
            } else {
                if (tMax.y < tMax.z) { voxel.y += step.y; tMax.y += tDelta.y; axisHit = 1; }
                else                 { voxel.z += step.z; tMax.z += tDelta.z; axisHit = 2; }
            }
        }

        outTex.write(col, gid);
    }
    """
}

// MARK: - Preview (synthetic 64³ data, no capture needed)

#if DEBUG
private func makeSyntheticVoxelData() -> VoxelCubeData {
    let side = VoxelCubeData.side
    let frames = VoxelCubeData.frameCount
    let pal = VoxelCubeData.paletteCount

    var frameIndices: [[UInt8]] = []
    var palettes: [[SIMD3<UInt8>]] = []
    frameIndices.reserveCapacity(frames)
    palettes.reserveCapacity(frames)

    for t in 0..<frames {
        // Palette: a per-frame HSV-ish ramp so frames are visibly distinct and
        // some slots are dark (to exercise the luminance air threshold).
        var p = [SIMD3<UInt8>](repeating: .zero, count: pal)
        for k in 0..<pal {
            let hue = (Float(k) / Float(pal) + Float(t) / Float(frames))
            let r = UInt8((0.5 + 0.5 * sin(hue * 6.28318)) * 255)
            let g = UInt8((0.5 + 0.5 * sin((hue + 0.33) * 6.28318)) * 255)
            let b = UInt8((0.5 + 0.5 * sin((hue + 0.66) * 6.28318)) * 255)
            // Darken the first quarter of slots so a luma floor carves them out.
            let scale: Float = k < pal / 4 ? 0.25 : 1.0
            p[k] = SIMD3<UInt8>(UInt8(Float(r) * scale),
                                UInt8(Float(g) * scale),
                                UInt8(Float(b) * scale))
        }
        palettes.append(p)

        // Index map: a moving sphere of bright indices in a sea of dark ones, so
        // the cube has visible 8-bit voxel structure rather than a flat box.
        var idx = [UInt8](repeating: 0, count: side * side)
        let cx = Float(side) * (0.3 + 0.4 * Float(t) / Float(frames))
        let cy = Float(side) * 0.5
        for y in 0..<side {
            for x in 0..<side {
                let dx = Float(x) - cx
                let dy = Float(y) - cy
                let d = sqrt(dx * dx + dy * dy)
                let v = d < 18 ? UInt8(64 + Int(d * 8) % 192) : UInt8(x % (pal / 4)) // dark bg
                idx[y * side + x] = v
            }
        }
        frameIndices.append(idx)
    }

    return VoxelCubeData(frameIndices: frameIndices, srgbPalettes: palettes)
}

#Preview("Voxel Cube — synthetic") {
    VoxelCubeView(data: makeSyntheticVoxelData(), edge: 340)
        .padding()
        .preferredColorScheme(.dark)
}
#endif
