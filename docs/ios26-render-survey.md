# SixFour: Rendering a LAB/OKLab Color Volume as Geometry on iPhone 17 Pro (iOS 26, A19 Pro)

> Source: verified fan-out survey (2026-05-30). 41 candidates discovered, 33 confirmed,
> 8 refuted. Every nontrivial claim carries a source URL. This document is the reference
> for the color-volume render build.

**Scope.** Render a dense LAB/OKLab color volume as positioned, self-colored geometry at
three LOD tiers — 16³ = 4,096 / 64³ = 262,144 / 256³ = 16,777,216 points — animated over a
64-frame global-palette / GIF flow, under a Liquid Glass UI, with maximum color precision.

**One-line headline.** The three sizes are **three different rendering architectures**, not
one architecture with a quality knob. Liquid Glass is **chrome only** — it renders zero
geometry. The GIF format is the deliberate precision collapse the on-screen EDR view escapes.

---

## 1. Verdict per LOD

| LOD | Geometry path | Color path | Glass integration | Limiting factor / honesty |
|-----|--------------|------------|-------------------|--------------------------|
| **16³ (4,096)** | Anything works. Simplest: hardware point sprites [`MTLPrimitiveType.point`](https://developer.apple.com/documentation/metal/mtlprimitivetype/point) + `[[point_size]]`, or instanced impostor quads ([`drawPrimitives`](https://developer.apple.com/documentation/metal/mtlrendercommandencoder/1515561-drawprimitives)), or RealityKit [`LowLevelMesh`](https://developer.apple.com/documentation/realitykit/lowlevelmesh). | fp32 in-shader OKLab→linear-P3, output to `rgba16Float` drawable. | Glass chrome floats freely above; cost independent of point count. | Trivial. 60–120 Hz with full headroom. ~250–600K static points sustained interactively even on iPad Air 2 ([forum 69217](https://developer.apple.com/forums/thread/69217)). |
| **64³ (262,144)** | **Recommended ceiling for rich per-point geometry.** Instanced sphere-impostor quads via `drawPrimitives(instanceCount:)` + `[[instance_id]]` indexing an SoA buffer ([metalbyexample](https://metalbyexample.com/instanced-rendering/)); or `LowLevelMesh` with a compute kernel rewriting vertices per frame ([WWDC24 10104](https://developer.apple.com/videos/play/wwdc2024/10104/)). | Same fp32 OKLab path. Per-point color resolved from the 256-entry palette LUT (MTLBuffer) for frame *f*. | RealityView or CAMetalLayer-backed view as content; `GlassEffectContainer` cluster above. | Comfortably interactive at 60–120 Hz on A19 Pro. Maps onto the 270K-pts-@-6.8 ms data point on old hardware ([forum 69217](https://developer.apple.com/forums/thread/69217)); A19 Pro has large headroom. |
| **256³ (16.7M)** | **NOT interactive as naive geometry.** Do NOT use hardware points/instanced quads (overdraw- and tiler-bound). **Use the compute software-rasterizer** (Schütz 2021: project each point, pack depth+color into a 64-bit int, `atomic_min` into a screen-sized buffer, resolve pass blits to drawable) ([arXiv 2104.07526](https://arxiv.org/pdf/2104.07526), [repo](https://github.com/m-schuetz/compute_rasterizer)). 64-bit atomics confirmed on Apple9+ ⇒ A19 Pro (Apple10) qualifies ([Feature Set Tables](https://developer.apple.com/metal/Metal-Feature-Set-Tables.pdf)). | Base packed path stores 8-bit sRGB (banding, no wide gamut). For accurate LAB/OKLab you must store a **per-point index** and **gather float color in the resolve pass** (wider resolve) — not the single-atomic packed color. | Glass chrome still fine above; keep glass clear of any region you rasterize for GIF export. | Bandwidth-bound: A19 Pro ~76.8 GB/s LPDDR5X ([A19 specs](https://en.wikipedia.org/wiki/Apple_A19)). The compute-raster pass is single-digit-ms and is the ONLY path that sustains the full dense tier interactively. Fixed-function point/instanced paths and `LowLevelMesh`/RealityKit instancing do NOT (the 796M-pts desktop result was an RTX 3090 with ~12× the bandwidth — does not transfer). **Fallbacks: sparse/occupied-voxel rendering, downsample to 64³ for animation, or splatting.** |

**Bottom line on 256³.** Interactive full-density animation is achievable *only* via the
compute software-rasterizer (with threadgroup write-merge to cut atomic contention), and
*only* with the wider index+gather resolve if you want color fidelity. Every fixed-function
geometry path (hardware points, instanced quads, `LowLevelMesh`, RealityKit
`MeshInstancesComponent`, mesh/object shaders) tops out at **64³ interactive** on A19 Pro.
Memory alone is a warning: 16.7M × float4×4 transforms ≈ 1.07 GB for
[`MeshInstancesComponent`](https://developer.apple.com/documentation/realitykit/meshinstancescomponent).

**Design consequence.** Treat **64³ as the animated, scrubbable working tier** and **256³ as a
render-to-still / export mode**, not a live-scrubbable one.

---

## 2. Liquid Glass integration

Liquid Glass is **navigation chrome only** — it renders zero points of the volume. Apple's
design contract: glass floats above content, signals hierarchy through depth/lensing, and
**cannot sample other glass** ([WWDC25 323](https://developer.apple.com/videos/play/wwdc2025/323/)).
Keep the LAB volume as the content layer beneath; glass controls above.

Concrete wiring, reusing SixFour's existing `GlassControls.swift` / `SFTheme` / `PaletteSphereView`:

- **Host the 3D volume**: a [`RealityView(make:update:)`](https://developer.apple.com/documentation/realitykit/realityview)
  (iOS 18+) for the RealityKit `LowLevelMesh` path at 16³/64³, OR a `UIViewRepresentable`-wrapped
  CAMetalLayer view for the Metal/compute-raster path (mandatory for 256³ and for EDR — see §3).
  SixFour already wraps `AVCaptureVideoPreviewLayer` this way; mirror that pattern.
- **Float glass controls** with the existing `GlassToolbarCluster` (a single
  [`GlassEffectContainer(spacing:)`](https://developer.apple.com/documentation/swiftui/glasseffectcontainer)).
  Reuse `GlassIconButton` (44 pt, `.glassEffect(.regular.interactive(), in: Circle())`) for the
  LOD-tier selector (16³/64³/256³), frame scrubber, and export button.
- **Morph controls between LOD tiers / scrub states** with `.glassEffectID(_:in:)` +
  [`.glassEffectTransition(.matchedGeometry)`](https://developer.apple.com/documentation/swiftui/glasseffecttransition)
  inside the container. Pure animation plumbing — no color/geometry data, dozens of shapes max.
- **`PaletteSphereView`** (the existing on-device 256-color globe) is the natural 16³/64³
  surface to graduate into this renderer; it already lives in the Review screen.

**Critical constraint.** Glass **tints / refracts / desaturates** whatever is beneath it. Any
region of the volume under glass is perceptually color-shifted — keep color-critical regions
(and anything you rasterize for GIF export) clear of glass overlap. `.glassEffect` is
[`Glass`](https://developer.apple.com/documentation/swiftui/glass) (`.regular`/`.clear`,
`.tint(_:)`, `.interactive()`), iOS 26.0+ on all iOS 26 devices.

---

## 3. Color precision path

Maximum-precision recipe (this is where wide gamut + EDR live; the GIF deliberately collapses out of it):

1. **Store per-point LAB/OKLab in an fp32 MTLBuffer** (`rgba32Float`-equivalent layout).
   fp32 ≈ 24-bit mantissa, ~7 decimal digits — effectively lossless for OKLab (a/b ≈ ±0.4,
   ulp ~1e-8) and CIELAB (L 0–100, a/b ±128)
   ([rgba32Float](https://developer.apple.com/documentation/metal/mtlpixelformat/rgba32float)).
2. **Do the OKLab↔linear-P3 math in fp32 in-shader.** Two 3×3 matrices (M1 linear-RGB→LMS,
   M2 LMS'→Lab) + cube-root nonlinearity (Ottosson, [bottosson.github.io](https://bottosson.github.io/posts/oklab/)).
   **MSL has no `cbrt`** — use `pow(lms, 1.0/3.0)`, or sign-preserving
   `copysign(pow(abs(x), 1.0/3.0), x)` for out-of-gamut/negative LMS; `cbrt()` fails to compile.
   **Ottosson's M1 is for linear sRGB** — compose with a linear-sRGB↔linear-P3 3×3 (or rebuild
   M1 from P3 primaries) before tagging the buffer P3, or you mis-color.
3. **Render into an `rgba16Float` drawable** (half: 10-bit stored mantissa). Adequate as the
   *display surface*; do the math in fp32 and narrow to half only at write-out (half bands in
   OKLab shadows) ([rgba16Float](https://developer.apple.com/documentation/metal/mtlpixelformat/rgba16float)).
4. **Tag the layer for EDR + wide gamut.** On the CAMetalLayer: `pixelFormat = .rgba16Float`,
   `colorspace = CGColorSpace(name: .extendedLinearDisplayP3)`,
   `wantsExtendedDynamicRangeContent = true` — **all three together**, or content clips to SDR
   ([WWDC22 10113](https://developer.apple.com/videos/play/wwdc2022/10113/),
   [wantsEDR](https://developer.apple.com/documentation/quartzcore/cametallayer/wantsextendeddynamicrangecontent),
   [extendedLinearDisplayP3](https://developer.apple.com/documentation/coregraphics/cgcolorspace/extendedlineardisplayp3)).
   The extended-linear space removes the [0,1] clamp (preserves <0 wide-gamut channels and >1
   EDR brightness); it does **not** extend beyond P3 primaries, so true LAB colors outside P3
   must still be gamut-mapped (prefer mapping toward the L axis over naive RGB clamp).
5. **Gate EDR on headroom.** `UIScreen.currentEDRHeadroom` / `.potentialEDRHeadroom` (CGFloat,
   iOS 16+); enable EDR when `potentialEDRHeadroom > 1`
   ([docs](https://developer.apple.com/documentation/uikit/uiscreen/3951383-currentedrheadroom)).
   iPhone 17 Pro: 1000 nits SDR / 1600 HDR peak / 3000 outdoor ⇒ real ~1.6×+ headroom
   ([specs](https://www.apple.com/iphone-17-pro/specs/)). Headroom is a **luminance** scalar —
   never push a/b chroma through it. KVO does not fire on `currentEDRHeadroom`; proxy via
   `UIScreenBrightnessDidChangeNotification`. Note iOS 26 deprecates `UIScreen.main` (reach via
   `view.window.windowScene.screen`).

**Where precision is lost:** (a) storing LAB intermediates as half instead of fp32; (b) the
256³ compute-raster packed path quantizing color to 8-bit sRGB at the atomic store — use
index+gather resolve instead; (c) the GIF export (§4); (d) `SwiftUI.Color.mix` perceptual space
is **not documented as OKLab** — do all LAB/OKLab math yourself in Metal, not via SwiftUI Color.
If any color work runs through Core Image, use `CIFormat.RGBAh` + extended-linear-P3 working
space (fp16, borderline for LAB), not RGBA8.

**CIELAB option.** `CGColorSpace.genericLab` exists (D65, range [-128,127], **iOS 11+**) for CPU
round-trip checks only — there's no GPU path; hand-roll Lab→XYZ→linear-P3 in MSL.

---

## 4. Palette ↔ GIF coupling

The volume's per-point color and the exported GIF must read from the **same 256-entry table** to
stay consistent.

- **GPU LUT.** Metal has **no native indexed/paletted pixel format**. Implement the LUT
  yourself: a 256-entry MTLBuffer (256 × float4 = 4 KB, cache-resident). Each LAB point holds an
  8-bit index; the shader resolves `color[index]` for the current frame. Use **nearest only** —
  interpolating indices is meaningless. Keep two representations: an `rgba16Float`/`rgba32Float`
  copy for the EDR display pass, and an `rgba8Unorm_srgb` copy that is byte-identical to the
  GIF's 256 entries.
- **GIF hard ceiling.** GIF89a = ≤256 entries/frame, each a 24-bit RGB triple, 8 bits/index,
  **no ICC/color-space tag, no wide gamut, no EDR, no float, no alpha gradient**
  ([W3C GIF89a spec](https://www.w3.org/Graphics/GIF/spec-gif89a.txt)). Decoders assume sRGB. So
  OKLab/P3 colors must be gamut-mapped + clamped to 8-bit sRGB before encode — the deliberate
  collapse the on-screen EDR view escapes. Global palette = one Global Color Table; per-frame
  palettes = one Local Color Table per frame.
- **Encoder.** `CGImageDestinationCreateWithURL(url, UTType.gif.identifier as CFString, 64, nil)`
  + `AddImage` per frame + `Finalize`; loop via `kCGImagePropertyGIFLoopCount` (0 = forever),
  per-frame delay via `kCGImagePropertyGIFDelayTime`. **Two gotchas:** (1) ImageIO runs its **own
  quantizer/dither** and exposes no documented way to supply an explicit palette or force a
  shared Global Color Table — colors come out noticeably off. For SixFour's byte-exact
  deterministic-palette contract (the Zig core), **keep the existing hand-rolled GIF89a/LZW
  encoder `GIFEncoder.swift`** — it gives exact palette control ImageIO does not. (2)
  `kCGImagePropertyGIFDelayTime` is clamped by viewers to a **0.1 s / 10 fps floor** (NOT
  0.02 s/50 fps); use `kCGImagePropertyGIFUnclampedDelayTime` and accept viewer variance.
- **Timeline.** Drive the 64-frame loop with `CADisplayLink` (set
  `CADisableMinimumFrameDurationOnPhone=YES` for 120 Hz ProMotion) or `TimelineView(.animation)`;
  `frameIndex = Int(t*fps) % 64`. Pure clocks (zero color/geometry role). The export must re-run
  the identical index→sRGB→8-bit-clamp math used on screen to guarantee display==file bytes; the
  EDR P3 float pixels will never be byte-identical to the 8-bit indexed output, so route export
  through the 8-bit LUT copy, **not** a readback of the EDR drawable.

---

## 5. Refuted / do-not-use

The verify phase flagged these as hallucinated or misavailable — they all *look* plausible:

- **`glassBackgroundEffect(in:displayMode:)`** — **visionOS only** (visionOS 1.0/2.4), NOT iOS.
  Does not compile on iPhone. Use `.glassEffect(_:in:)`.
- **`UIGlassEffect(glass:isInteractive:)`** — wrong initializer. Real API is `UIGlassEffect(style:)`
  (`.regular`/`.clear`), then set `.isInteractive`/`.tintColor` as properties, applied via
  `UIVisualEffectView(effect:)`. `UIGlassContainerEffect` is correct.
- **`MTLRenderPipelineDescriptor.supportRDIndirectCommandBuffer`** — does not exist. Correct is
  `supportIndirectCommandBuffers`. ICBs are draw-submission glue only; they do NOT make dense 256³
  interactive — a dense translucent LAB cube has poor occlusion culling, so only frustum culling
  helps, and the workload stays rasterizer/bandwidth-bound.
- **`Glass`/`glassEffect` as a volume renderer** — category error. 2D UI chrome that
  blurs/tints/desaturates content behind it; renders zero geometry and actively destroys color
  fidelity. Not a LAB/OKLab point-cloud renderer.
- **`LowLevelMesh` / RealityKit `MeshInstancesComponent` for 256³** — NOT recommended at 16.7M
  points (≈335 MB–1.3 GB+ buffers, rasterizer-bound, no internal culling). Fine for 16³/64³ only.
  Also: **do not assume `MTLPrimitiveType.point` renders in RealityKit** — every Apple sample uses
  triangles/strips and `[[point_size]]` is not exposed through RealityKit materials; emit
  triangle/quad geometry per point or validate point rendering on-device first. Use
  `replace(bufferIndex:using:)`, not `replace(using:)`.
- **Raw Metal point/instanced rendering for 256³ "comfortably"** — overstated. The 796M-pts-@-64fps
  figure is RTX 3090 (~936 GB/s, ~12× A19 Pro's ~76.8 GB/s); does not transfer. Naive `[[point_size]]`
  of even 250K random points exceeds 16 ms on Apple TBDR GPUs without Morton/spatial ordering. 64³
  is the reliable geometry ceiling; 256³ needs the compute software-rasterizer or downsampling.
- **TimelineView/CADisplayLink as a renderer or precision source** — schedulers only; per-frame
  redraw cost and color precision belong to the Metal subsystem.
- **ImageIO GIF for color-exact export** — its built-in quantizer cannot guarantee a byte-exact
  palette; keep the hand-rolled `GIFEncoder.swift`. And the GIF delay floor is 0.1 s/10 fps.
