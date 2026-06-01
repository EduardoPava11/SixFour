# SixFour LAB Color-Volume Renderer — Implementation Design

> Reviewed code design (2026-05-30). Built from [`ios26-render-survey.md`](./ios26-render-survey.md)
> + [`lab-volume-render-plan.md`](./lab-volume-render-plan.md). 5 components designed + adversarially
> critiqued against the survey constraints AND the real codebase; blocker/major fixes folded in.

## 1. Overview

The LAB color-volume renderer is a new Review-screen visualization that shows one frame's
256-entry per-frame palette (and, optionally, its faint source-pixel cloud) as an interactive 3-D
point volume in OKLab space, animated across the 64 frames. The structure is a **split-tree
partition model**: a pure, canonical binary (median-cut) tree over the 256 OKLab centroids, depth
8, with `b ∈ {16,4,2}` *views* derived by collapsing binary levels (b=4 collapses 2 levels → depth
4; b=16 collapses 4 levels → depth 2; `bᵈ=256` for all three). Navigation is **prefix addressing**
— a base-`b` digit path of length ≤ `d` selects a focused subtree, the "drill-in" gesture; `b` is
the structure selector, `d` is the drill depth. The split-tree is data-only (no Metal). It feeds a
**one-renderer/two-backend architecture**: `LabVolumeRenderer` is a `UIViewRepresentable` hosting a
`CAMetalLayer` (mirroring `CameraPreview`'s `layerClass` override), wired for EDR + wide-gamut via
the three-property combo (`rgba16Float` + `extendedLinearDisplayP3` + `wantsExtendedDynamicRangeContent`,
gated on `potentialEDRHeadroom > 1`). Behind a `LabVolumeBackend` protocol, the **instanced
impostor-quad backend** ships first (the live 16³/64³ tier: `drawPrimitives(.triangleStrip,
instanceCount:)` + `[[instance_id]]` over an fp32 SoA buffer), and a deferred **compute-software-
rasterizer backend** slots into the same protocol for the optional 256³ dense tier (render-to-still).
All color math is fp32 OKLab→linear-Display-P3 in-shader (no `cbrt`), narrowing to half only at the
drawable write-out; the GIF export path is byte-exact and bypasses the EDR drawable entirely.

## 2. File layout

| Path | Kind | Responsibility |
|---|---|---|
| **Split-tree model** | | |
| `SixFour/Palette/SplitTree.swift` | swift-new | `SplitTree` value types (`SplitNode`, `SplitLeaf`, `SplitPlane`, `SplitAxis`, `OKLabBox`, `Branching`), canonical b=2 median-cut builder, level-collapse `view(branching:)`, prefix addressing. Pure (Foundation+simd only), `Sendable`, no Metal/UIKit. |
| `SixFour/Palette/SplitTree+Build.swift` | swift-new | Median-cut internals: widest-axis selection, **pinned tie-break** (sort key `(axisCoord, paletteIndex)`), recursion to depth 8. |
| `spec/src/SixFour/Spec/SplitTree.hs` | haskell-spec | Source-of-truth partition: data type, reference b=2 median-cut (same pinned tie-break), level-collapse, prefix addressing, exported law functions + golden vectors. |
| `spec/test/Properties/SplitTree.hs` | haskell-spec | QuickCheck properties exercising the SplitTree laws — mirrors `Properties.PairTree`/`Properties.Quad4`. |
| `spec/spec.cabal` | manifest | Add `SixFour.Spec.SplitTree` to `exposed-modules`; add `Properties.SplitTree` to the `spec-tests` `other-modules`. **(NOT `sixfour-spec.cabal`; NOT `Laws.hs`.)** |
| **Data plumbing** | | |
| `SixFour/Metal/LabVolumeData.swift` | swift-new | `LabVolumeData` input contract + `LabCloudField` + `from(output:tiles:)` factory + `centroidBuffer(_:)`/`cloudBuffer(_:)` fp32 SoA packers. Pure CPU, testable. |
| `SixFour/UI/Screens/Capture/CaptureViewModel.swift` | swift-modify | Add one computed accessor `var labVolumeTiles: [OKLabTile]? { currentBundle?.tiles }`. No new retained state. |
| **Renderer scaffold** | | |
| `SixFour/Metal/LabVolumeRenderer.swift` | swift-new | `UIViewRepresentable` over `LabVolumeMTKView` (CAMetalLayer host); EDR/wide-gamut layer config + headroom gating; depth-texture ownership; `CADisplayLink` per-frame redraw via `Coordinator`. |
| `SixFour/Metal/LabVolumeBackend.swift` | swift-new | `protocol LabVolumeBackend`; shared `LabVolumeUniforms` Swift struct (byte-matched to MSL). |
| `SixFour/Metal/InstancedLabVolumeBackend.swift` | swift-new | Phase 1–2 backend: SoA instance buffer + 256-entry LUT buffer + render PSO + depth-stencil + blend state; impostor pass + split-plane pass. `isLiveScrubbable = true`, `requiresDrawableWrite = false`. |
| `SixFour/Metal/ComputeRasterLabVolumeBackend.swift` | swift-new | Phase 4 stub: compute software-raster, render-to-still. `isLiveScrubbable = false`, `requiresDrawableWrite = true`. Present so the protocol is validated against two conformers. |
| `SixFour/Metal/GPUContext.swift` | swift-modify | Add `func renderPSO(_:) throws -> any MTLRenderPipelineState` beside the compute-only `pso(_:)`. |
| **Shaders** | | |
| `SixFour/Metal/LabVolume.metal` | metal-new | Impostor vertex/fragment pair + split-plane pair; `ImpostorVertexOut` (with `[[position]]`) declared **locally** (GIFtok lesson). |
| `SixFour/Metal/Shaders.metal` | metal-modify | ADD (near `p3ToSRGB`): `okLabToLinearSRGB`, `linearSRGBToLinearP3`, fused `okLabToLinearP3`. No existing function changes. |
| `SixFour/Metal/LabVolumeTypes.h` | metal-new | Shared bridging header: C-ABI `LabVolumeUniforms`, `LabLeaf`, `SplitPlaneGPU` so Swift and MSL agree byte-for-byte (resolves the `float3` 16-byte-padding ABI hazard). |
| **Navigation / glass / settings** | | |
| `SixFour/UI/Screens/Review/LabVolumeView.swift` | swift-new | SwiftUI host: `LabVolumeRenderer` content + `VolumeNavChrome` overlaid `.overlay(alignment: .bottom)`; color-critical square kept clear of glass. |
| `SixFour/UI/Components/VolumeNavChrome.swift` | swift-new | Floating glass cluster: branching selector, depth breadcrumb + ascend/reset, projection toggle. Reuses `GlassToolbarCluster`/`GlassIconButton`/`SFTheme`. |
| `SixFour/UI/Components/VolumeNavState.swift` | swift-new | `@MainActor @Observable` nav state: branching, prefix path, projection, frame; `drill/ascend/reset/setBranching`; emits `VolumeNavSnapshot`. |
| `SixFour/Settings/VisualizationEnums.swift` | swift-new | `VolumeBranching` (b16/b4/b2) + `VolumeProjection` (splitPlanes/dots). Matches `DitherMethod`'s shape. |
| `SixFour/Settings/AppSettings.swift` | swift-modify | Add `showLabVolume`/`volumeBranching`/`volumeProjection` with `Key`s + `didSet` persistence (mirror `useDeterministicCore`); seed in `init()`. |
| `SixFour/UI/Screens/Settings/SettingsView.swift` | swift-modify | Add `visualizationSection` after `engineSection`; binds via existing `@Bindable var settings`. |
| `SixFour/UI/Screens/Review/GIFReviewView.swift` | swift-modify | Insert strip↔volume toggle + `LabVolumeView` host **between `GIFCanvas` and `perFrameStatus`** — gated on `vm.settings.showLabVolume`. **(There is NO `PaletteStripView` in this file.)** |
| `SixFour/Encoder/GIFEncoder.swift` | UNTOUCHED | Zero edits. Its per-frame Local Color Tables (256 sRGB triples) are exactly what `palettesForDisplay` mirrors. |

> **xcodegen:** new files under existing groups are auto-picked by the recursive glob; run `xcodegen generate`.

## 3. Core types & signatures

### 3.1 SplitTree model

```swift
enum Branching: Int, Sendable, CaseIterable {
    case flat = 16, quad = 4, binary = 2
    var depth: Int { switch self { case .binary: 8; case .quad: 4; case .flat: 2 } }  // fixed lookup, NO float pow
    var factor: Int { rawValue }
}
enum SplitAxis: Int, Sendable { case L = 0, a = 1, b = 2 }   // SIMD3 lane order
struct OKLabBox: Sendable, Hashable {
    let lo: SIMD3<Float>; let hi: SIMD3<Float>
    func widestAxis() -> SplitAxis
    func split(axis: SplitAxis, at: Float) -> (OKLabBox, OKLabBox)
}
struct SplitPlane: Sendable, Hashable { let axis: SplitAxis; let position: Float; let level: Int }
struct SplitLeaf: Sendable, Hashable {
    let paletteIndex: UInt8        // = slot position in palettesForDisplay[frame]/perFrameCells[frame]
    let oklab: SIMD3<Float>        // = cell.mean (empirical post-dither centroid)
    let srgb8: SIMD3<UInt8>        // = palettesForDisplay[frame][index]  (GIF LCT bytes)
    let population: Int            // = cell.count
}
indirect enum SplitNode: Sendable {
    case leaf(SplitLeaf)
    case branch(box: OKLabBox, planes: [SplitPlane], children: [SplitNode])  // children.count == b
}
struct SplitTree: Sendable {
    let frameIndex: Int
    let root: SplitNode            // ALWAYS canonical binary, depth 8
    let leaves: [SplitLeaf]        // 256, in paletteIndex order (the SoA storage order)
    static func build(cells: [SixFourSignificantCell], srgb8: [SIMD3<UInt8>], frameIndex: Int) -> SplitTree
    func view(branching: Branching) -> SplitNode           // collapse: b=4→2 levels, b=16→4 levels
    func subtree(at address: [Int]) -> SplitNode?          // each element ∈ 0..<b
    func leaf(atLinearIndex i: UInt8) -> SplitLeaf
    func planes(downTo depth: Int, branching: Branching) -> [SplitPlane]
}
```

**Corrected semantics (folded critique blockers/majors):**
- **b=16 view is a 2-D arrangement of the 256 leaves, NOT the 16³ Coverage voxel grid.** `okLabBin`
  (Coverage.hs) yields 16³ = 4096 cells; 256 leaves ≠ 4096. The Coverage-agreement claim is
  **removed** from the law set and the survey-honored list. (b=16 = collapse 4 binary levels.)
- **Collapse arithmetic standardized:** b=4 collapses **2** binary levels; b=16 collapses **4**.
- **Determinism pinned:** median selection uses total order keyed `(axisCoord, paletteIndex)`, stated
  in `Spec.SplitTree` so the Swift port and Haskell golden vectors agree bit-for-bit.
- **paletteIndex is array position** in `perFrameCells[frame]`. Leaf uses `cell.count` + `cell.mean`;
  impostor σ comes from `cell.stdDev` only (no covariance/eigenvalue exposed at this seam).

**Spec laws:** leaf count = 256 ∀b; collapse preserves leaf set; true partition (disjoint, union =
all 256); prefix-address↔linear-index round-trip; determinism under the pinned tie-break. **No
Coverage-agreement law.**

### 3.2 Data plumbing

```swift
struct LabCloudField: Sendable {
    let pointsOKLab: [SIMD3<Float>]   // flattened OKLabTile.pixels
    let frameOffsets: [Int]           // prefix offsets, length T+1
}
struct LabVolumeData: Sendable {
    let frameCount: Int               // T = 64
    let k: Int                        // K = 256
    let centroidOKLab: [[SIMD3<Float>]]   // [T][K] from perFrameCells[f][j].mean (empirical post-dither)
    let centroidSRGB8:  [[SIMD3<UInt8>]]  // [T][K] from palettesForDisplay (GIF quantize-centroid bytes)
    let exportLUT:      [[SIMD3<UInt8>]]  // === palettesForDisplay, by reference (byte-exact to file)
    let cloud: LabCloudField?             // nil when no tiles retained
    static func from(output: CaptureOutput, tiles: [OKLabTile]?) -> LabVolumeData
    func centroidBuffer(_ device: any MTLDevice) -> any MTLBuffer   // fp32 SoA
    func cloudBuffer(_ device: any MTLDevice) -> (any MTLBuffer)?   // fp32 SoA, nil if no cloud
}
```

> **Corrected framing:** `centroidOKLab[f][j]` (`cell.mean`, post-dither empirical mean) and
> `centroidSRGB8/exportLUT[f][j]` (the GIF's quantize-centroid bytes) are **co-indexed by slot but
> deliberately distinct colors** — `okLabToSRGB8(centroidOKLab) ≠ exportLUT` in general. The
> byte-exact contract applies to `exportLUT` (and `SplitLeaf.srgb8`) = `palettesForDisplay` by
> reference. The geometry point lands at the empirical mean; documented, not asserted as "same color."

### 3.3 Renderer + backend protocol

```swift
struct LabVolumeRenderer: UIViewRepresentable {
    let gpu: GPUContext
    let data: LabVolumeData
    let snapshot: VolumeNavSnapshot
    var onFrameAdvance: ((Int) -> Void)?
    func makeUIView(context: Context) -> LabVolumeMTKView
    func updateUIView(_ v: LabVolumeMTKView, context: Context)
    func makeCoordinator() -> Coordinator
}
final class LabVolumeMTKView: UIView {
    override class var layerClass: AnyClass { CAMetalLayer.self }
    var metalLayer: CAMetalLayer { layer as! CAMetalLayer }
    private var depthTexture: (any MTLTexture)?     // .depth32Float, [.renderTarget], sized to drawable
    var backend: (any LabVolumeBackend)?
    var uniforms: LabVolumeUniforms
    func configureLayer(device: any MTLDevice)      // rgba16Float + extendedLinearDisplayP3;
                                                    // framebufferOnly = !(backend?.requiresDrawableWrite ?? false)
    func updateEDR(window: UIWindow?)               // wantsExtendedDynamicRangeContent iff potentialEDRHeadroom > 1
    func resizeDepthIfNeeded()
    func draw()
}
protocol LabVolumeBackend: AnyObject {
    init(gpu: GPUContext, data: LabVolumeData) throws
    func encode(into drawable: any CAMetalDrawable, depth: any MTLTexture, uniforms: LabVolumeUniforms) throws
    var isLiveScrubbable: Bool { get }
    var requiresDrawableWrite: Bool { get }         // false for instanced, true for compute-raster
}
final class Coordinator {                           // the ONLY place that names concrete backends
    var displayLink: CADisplayLink?
    var backend: (any LabVolumeBackend)?
    @objc func step(_ link: CADisplayLink)          // advance frame % 64, call view.draw()
    func rebuildBackendIfNeeded(branching: Int, gpu: GPUContext, data: LabVolumeData)
}
```

**Corrected (renderer critique):**
- **Depth attachment added** — owned `.depth32Float` texture, rebuilt on resize; impostor writes
  quad-center depth so spheres occlude correctly (avoids depth-PSO-vs-no-attachment validation error).
- `framebufferOnly` defaults **true** for instanced; flipped to `false` only for compute-raster.
- **`queue` parameter dropped** from `encode(...)`; backends commit on the single labeled `gpu.queue`.
- Host view references only the protocol; the **Coordinator** is the single site naming concrete backends.

### 3.4 MSL signatures

```cpp
// --- added to Shaders.metal (near p3ToSRGB) ---
inline float3 okLabToLinearSRGB(float3 lab);       // port ColorScience.swift VERBATIM; cube via l*l*l (sign-preserved; no cbrt)
inline float3 linearSRGBToLinearP3(float3 c);      // canonical sRGB→P3 3x3 (high-precision inv of p3ToSRGB)
inline float3 okLabToLinearP3(float3 lab) { return linearSRGBToLinearP3(okLabToLinearSRGB(lab)); }

// --- LabVolume.metal ---
struct ImpostorVertexOut { float4 position [[position]]; float2 uv; float3 oklab; float size; };  // [[position]] struct MUST be local

vertex ImpostorVertexOut labVolumeImpostorVertex(
    uint vid [[vertex_id]], uint iid [[instance_id]],
    constant LabVolumeUniforms& u [[buffer(0)]],
    device const LabLeaf* leaves [[buffer(1)]]);
    // leaf = leaves[u.frameIndex*256 + iid]; corner = leaf.oklab + (uv.x*u.cameraRight + uv.y*u.cameraUp)*leaf.size*u.pointSizeScale

fragment float4 labVolumeImpostorFragment(ImpostorVertexOut in [[stage_in]], constant LabVolumeUniforms& u [[buffer(0)]]);
    // round mask (discard r2>1); linP3 = okLabToLinearP3(in.oklab);
    // multiply FULL RGB triple by u.edrLuminanceScale (NOT achromatic-only); v1 gamut: clamp >=0

vertex   ImpostorVertexOut labVolumeSplitPlaneVertex(uint vid, uint iid, constant LabVolumeUniforms& u [[buffer(0)]], device const SplitPlaneGPU* planes [[buffer(2)]]);  // oriented quad, NOT billboarded
fragment float4 labVolumeSplitPlaneFragment(ImpostorVertexOut in [[stage_in]]);  // translucent, alpha-blended
```

```cpp
// shared bridging header LabVolumeTypes.h (resolves float3 16-byte ABI hazard)
struct LabVolumeUniforms {
    float4x4 viewProjection; float4x4 model;
    float3 cameraRight; float3 cameraUp;
    uint frameIndex; uint frameCount; uint branchingB; uint depthD; uint instanceCount;
    float pointSizeScale; float edrLuminanceScale;
};
struct LabLeaf  { float3 oklab; float size; uint8_t paletteIndex; uint8_t parentSlab; uint16_t _pad; };
struct SplitPlaneGPU { float3 center, normal, halfExtentU, halfExtentV, tintOklab; float opacity; uint level; };
```

**Corrected (shader critique):** EDR scaling = convert→linearP3 first, then multiply the **full RGB
triple** by `edrLuminanceScale` (achromatic-only wording removed). `LabLeaf.size` driven by
`SixFourSignificantCell.stdDev` (`length(stdDev)`) — **not** a covariance eigenvalue (only diagonal
`stdDev` exists at the seam). `paletteIndex` is highlight/drill-in metadata only. Pin
`MemoryLayout<LabLeaf>.stride` with a Swift assertion against the bridging header.

### 3.5 SwiftUI + AppSettings + CaptureOutput

```swift
enum VolumeBranching: String, CaseIterable, Sendable {
    case b16, b4, b2
    var branchingFactor: Int { switch self { case .b16: 16; case .b4: 4; case .b2: 2 } }
    var maxDepth: Int        { switch self { case .b16: 2;  case .b4: 4; case .b2: 8 } }
    var label: String        // "16²" / "4⁴" / "2⁸"
    var blurb: String        // "flat grid" / "quadtree (2 axes/level)" / "median-cut (1 axis/level)"
}                            // octree excluded: 3 ∤ 8
enum VolumeProjection: String, CaseIterable, Sendable { case splitPlanes, dots; var label: String; var systemImage: String }

@MainActor @Observable final class VolumeNavState {
    var branching: VolumeBranching
    private(set) var path: [UInt8]      // base-b prefix address
    var projection: VolumeProjection
    var frame: Int
    var depthCapacity: Int { branching.maxDepth }
    var currentDepth: Int  { path.count }
    var snapshot: VolumeNavSnapshot { ... }
    func drill(into child: UInt8)       // appends iff currentDepth < depthCapacity
    func ascend(); func reset(); func setBranching(_ b: VolumeBranching)   // setBranching resets path
}
struct VolumeNavSnapshot: Equatable, Sendable { let branchingFactor: Int; let path: [UInt8]; let projection: VolumeProjection; let frame: Int }
struct VolumeNavChrome: View {
    let state: VolumeNavState
    @Bindable var settings: AppSettings      // @Bindable so picker write-back two-way binds
    var body: some View                      // GlassToolbarCluster + GlassIconButtons, .bottom, off the square
}
```

```swift
// AppSettings.swift — mirror useDeterministicCore
var showLabVolume: Bool       { didSet { defaults.set(showLabVolume, forKey: Key.showLabVolume) } }
var volumeBranching: VolumeBranching   { didSet { defaults.set(volumeBranching.rawValue, forKey: Key.volumeBranching) } }
var volumeProjection: VolumeProjection { didSet { defaults.set(volumeProjection.rawValue, forKey: Key.volumeProjection) } }
```

**CaptureOutput changes:** none required. Centroids from existing `perFrameCells` + `palettesForDisplay`;
cloud from `currentBundle?.tiles` via the new `labVolumeTiles` accessor. An optional
`cloudDownsample` field is documented as an escape hatch, **default NOT added**.

**Corrected (nav critique blockers):** placement re-anchored to the real `GIFReviewView` structure
(`GIFCanvas` → `perFrameStatus` → `determinismBadge`) — `PaletteStripView` does **not** exist in this
file and is dropped. `VolumeNavChrome` takes `@Bindable var settings` for two-way binding. b/d navigate
the **256-centroid split-tree (the palette)**, orthogonal to the renderer's point-cloud LOD tier.

## 4. Data flow

```
Capture (unchanged)
  └─ CaptureOutput { palettesForDisplay [T][256] sRGB8,   ← GIF LCT bytes (byte-exact)
  │                  perFrameCells     [T][256] cells }   ← cell.mean (OKLab), .stdDev, .count
  └─ currentBundle.tiles : [OKLabTile]   ← .pixels (3 MB OKLab cloud), already retained

Review (settings.showLabVolume, volume mode)
  ├─ LabVolumeData.from(output: vm.primaryOutput, tiles: vm.labVolumeTiles)
  │     centroidOKLab ← perFrameCells[f][j].mean ;  exportLUT ← palettesForDisplay (by ref)
  │     cloud ← flatten tiles[f].pixels  (uploaded ONCE, immutable across the 64-frame loop)
  ├─ SplitTree.build(cells:, srgb8:, frameIndex:)   (per displayed frame; 256 centroids, pure)
  │     view(branching:) → SplitNode ;  planes(downTo: path.count, branching:)
  └─ LabVolumeRenderer(gpu, data, snapshot)
       InstancedLabVolumeBackend → SoA LabLeaf buffer ([T*256] flat) + 256 LUT + PSO + depth + blend
       Coordinator.step (CADisplayLink, frame % 64) → draw():
         pass: impostor quads (.triangleStrip, 4 verts, instanceCount = visible leaves) → okLabToLinearP3 (fp32) → rgba16Float, depth-write
         pass: split planes (instanceCount = active-depth planes, alpha-blended, depth-test, no depth-write)
```

**Export path (always 8-bit, EDR-free):** GIF export continues through the existing ShareLink →
`GIFEncoder.encode(volume:perFramePalettes:)` using `palettesForDisplay` (== `exportLUT` == the Local
Color Tables). The `rgba16Float` drawable is **never read back**; `display(8-bit) == file bytes` by
construction. `GIFEncoder.swift` untouched.

## 5. Survey-constraint checklist

| Constraint | Where satisfied |
|---|---|
| Color stored fp32 | `SplitLeaf.oklab`, `centroidOKLab`, `pointsOKLab` are `SIMD3<Float>`; buffers pack fp32 SoA. Half only at write-out. |
| OKLab→linear-P3 in-shader, no `cbrt` | `okLabToLinearP3`; inverse cubes via `l*l*l` (sign-preserved); `cbrt` never used. |
| Ottosson M1 sRGB → compose sRGB→P3 | `okLabToLinearP3 = linearSRGBToLinearP3(okLabToLinearSRGB(...))`. |
| EDR three-property combo + gating | `configureLayer`: rgba16Float + extendedLinearDisplayP3; `updateEDR`: wantsEDR iff headroom>1; `edrLuminanceScale` multiplies full RGB after conversion. |
| Geometry = instanced impostor quads | `drawPrimitives(.triangleStrip, instanceCount:)` + `[[instance_id]]`. No `[[point_size]]`/`LowLevelMesh`/`MeshInstancesComponent`. |
| Depth correctness | Owned `.depth32Float`, rebuilt on resize, attached; impostor writes quad-center depth. |
| 256³ deferred | `ComputeRasterLabVolumeBackend` behind the same protocol; Phase 4 only. |
| Glass is chrome only | `VolumeNavChrome` floats `.bottom`; `.glassEffect(_:in:)`. No `glassBackgroundEffect`/`UIGlassEffect(...)`. Square has no glass overlay. |
| GIF export byte-exact, no EDR readback | `exportLUT` === `palettesForDisplay` === GIF LCT bytes; drawable never read back. |
| Nearest-only palette indexing | Integer slot index resolved as `color[index]`; no interpolation. |
| CAMetalLayer hosting | `LabVolumeMTKView` via `UIViewRepresentable` (`layerClass`), mirroring `CameraPreview`. |
| `[[position]]` struct local to .metal | `ImpostorVertexOut` in `LabVolume.metal`. |
| `bᵈ = 256` invariant | `Branching.depth` fixed lookup; `drill()` cannot exceed `depthCapacity`. |
| Haskell spec per convention | `Spec.SplitTree` + `Properties.SplitTree` in `spec/spec.cabal`; golden vectors; pinned tie-break. |

## 6. Build order

**Phase 0 — Plumbing & spec (no pixels on screen).**
Files: `SplitTree.swift`, `SplitTree+Build.swift`, `Spec/SplitTree.hs`, `Properties/SplitTree.hs`,
`spec/spec.cabal`, `LabVolumeData.swift`, `CaptureViewModel.swift` (accessor).
DoD: `cabal test` green incl. partition/round-trip/determinism laws; Swift `SplitTree.build` matches
Haskell golden vectors bit-for-bit; `LabVolumeData.from` assembles correct `[T][256]` + `exportLUT`;
`MemoryLayout<LabLeaf>.stride` assertion passes. No UI.

**Phase 1 — Static render (one frame, leaves only).**
Files: `Shaders.metal` (3 color helpers + MSL golden test), `LabVolume.metal` (impostor pair),
`LabVolumeTypes.h`, `GPUContext.swift` (`renderPSO`), `LabVolumeBackend.swift`,
`InstancedLabVolumeBackend.swift`, `LabVolumeRenderer.swift`.
DoD: temporary harness shows frame 0's 256 impostors in OKLab, EDR-tagged on a headroom>1 display,
depth-correct occlusion, round masks; MSL `okLabToLinearSRGB` matches `ColorScience.swift` goldens;
no Metal validation errors.

**Phase 2 — Animate + split planes.**
Files: `LabVolume.metal` (split-plane pair), `InstancedLabVolumeBackend.swift` (second pass + blend),
`LabVolumeRenderer.swift` (`Coordinator` + `CADisplayLink`; `CADisableMinimumFrameDurationOnPhone=YES`).
DoD: 64-frame loop animates via `frameIndex*256+iid` (cloud uploaded once); translucent split planes
for the active drill depth with correct depth-test/no-write ordering; live + scrubbable at 16³/64³.

**Phase 3 — Glass / UX wiring.**
Files: `VisualizationEnums.swift`, `VolumeNavState.swift`, `VolumeNavChrome.swift`, `LabVolumeView.swift`,
`AppSettings.swift`, `SettingsView.swift`, `GIFReviewView.swift`.
DoD: Settings "Visualization" section toggles `showLabVolume` + default branching/projection (persisted);
`GIFReviewView` shows a strip↔volume toggle hosting `LabVolumeView`; `VolumeNavChrome` drives
`b ∈ {16,4,2}` with `.glassEffectID` morphs + drill/ascend/reset; glass clear of the square; b/d map to
`SplitTree` prefix addressing.

**Phase 4 — Optional 256³ dense tier.**
Files: `ComputeRasterLabVolumeBackend.swift`.
DoD: protocol-conformant compute software-rasterizer (64-bit atomics, index+gather, render-to-still);
`Coordinator` swaps it in when LOD crosses 64³→256³, transparent to SwiftUI; no live-scrub claim.

## 7. Open questions / risks

- **Drill-in target selection (decide before Phase 3 ships interactively):** chrome buttons have no
  spatial target. Proposed: buttons drive depth + a default child (most-occupied); content drag drives
  orbit; tapping a rendered split-cell needs a renderer→nav focused-child callback not yet specified.
- **Gamut mapping (Phase 1 ships `clamp(>=0)`):** survey prefers reducing chroma toward L (binary-search
  C until in-gamut). Follow-up quality upgrade; not a v1 blocker.
- **Impostor shape:** flat round billboard ships; ray-traced sphere normal is a later upgrade.
- **Cloud upload cost:** full 262k-point fp32 buffer uploaded once (static); strided downsample is the
  fallback if measured latency matters. Confirm on-device.
- **Frame-clock unification:** `VolumeNavState.frame` duplicates the `GIFCanvas` playback clock; a shared
  app-wide clock crosses into the animation component's scope — defer.
- **Centroid geometry source (product call):** geometry points use `cell.mean` (empirical post-dither
  mean), which differs from the GIF's quantize centroid. If leaves should land exactly on the GIF color,
  derive `centroidOKLab` from the quantize centroids instead — currently a deliberate distinction.
- **Haskell spec scope:** `Spec.SplitTree` warranted (partition laws + pinned tie-break + golden vectors).
  MSL `okLabToLinearP3` needs a golden-vector test against the `ColorScience.swift` reference. An optional
  bridge law (SplitTree ↔ `Spec.PairTree`/`Spec.Quad4`) is deferred unless the look-NN requires it.
