> **⚠ ARCHIVED (2026-06-05) — superseded, kept for lineage.** Folded into the palette-explorer umbrella as the 3D-volume sub-mode. Canon: palette-explorer-2d-3d-4d-design.md.
>
---

# LAB Color-Volume Renderer — Swift Integration Plan

> Companion to [`ios26-render-survey.md`](../ios26-render-survey.md). Grounded in a 2026-05-30
> read of the actual codebase. **Correction vs. memory:** `PaletteSphereView` does **not** exist
> today — the existing analog is `PaletteStripView` (1D). This plan builds the renderer fresh.

---

## 0. The key insight: the three sizes are SixFour's real data cardinalities

The 16³ / 64³ / 256³ tiers are not arbitrary — they line up with quantities the app already
computes, which is what makes each tier a *meaningful decision* rather than a zoom level:

| LOD | Count | What it *is* in SixFour | The decision it surfaces |
|-----|-------|--------------------------|--------------------------|
| **16³** | 4,096 | = pixels per frame (64×64); **also** the OKLab bin grid the `perFrameCoverage` metric already counts | *Is this palette diverse?* — coverage / occupancy |
| **64³** | 262,144 | = the whole 64-frame burst as one point cloud (64 × 4096) | *Does color move coherently across time?* — temporal coherence |
| **256³** | 16,777,216 | = the dense 8-bit OKLab quantization lattice (the continuous color space itself) | *Gamut & quantization quality* — render-to-still only |

This means the **2D→3D→4D ladder** from the design discussion maps cleanly:
- **2D** — one frame's 256-color palette as the 16×16 grid (≈ today's `PaletteStripView`).
- **3D** — the 256 palette centroids positioned in OKLab space (L, a, b): the "globe."
- **4D** — those centroids **× 64 frames**, animated: the color-time volume (the tesseract).

And the survey's hardware verdict applies directly: **16³/64³ are live-scrubbable; 256³ is
render-to-still** (compute software-rasterizer, deferred to a later phase).

---

## 1. Data availability (a real gap to close first)

From the scan, `CaptureOutput` (the value handed to the Review screen) carries:
- `palettesForDisplay: [[SIMD3<UInt8>]]` — T×256 sRGB8 ✅ (the palette centroids per frame)
- `perFrameCells: [[SixFourSignificantCell]]` — per-slot OKLab **mean + σ + count** ✅
- `perFrameCoverage: [Int]` — occupied 16³ OKLab bins ✅
- `perFrameMSE: [Float]` ✅

It does **not** carry the raw 4,096 OKLab pixels per frame — those live in `OKLabTile.pixels`
at capture time and are dropped before Review. **Consequence:**
- Rendering **palette centroids** (256/frame, OKLab from `perFrameCells` means) needs **no
  plumbing** — the data is already at Review.
- Rendering the **full 64³ pixel cloud** requires threading `OKLabTile.pixels` through to Review
  (memory: 262,144 × 3 × 4 B ≈ 3 MB — cheap) **or** rendering at capture time before the tiles
  are released.

**Plan default:** start with the **palette-centroid volume** (zero plumbing, and it's exactly
what the diversity spec is about — see §6), add the pixel cloud as an opt-in second pass.

---

## 2. Architecture: one renderer, three backends

```
LabVolumeView (SwiftUI)
 └─ LabVolumeRenderer  ── UIViewRepresentable wrapping a CAMetalLayer   ← NOT SwiftUI Canvas
     ├─ backend: instancedPoints   → 16³ / 64³   (drawPrimitives instanceCount, SoA buffer)
     └─ backend: computeRaster      → 256³        (Schütz software-rasterizer, Phase 4)
```

- **Why CAMetalLayer, not SwiftUI `Canvas` or RealityKit:** EDR + wide-gamut (`rgba16Float` +
  `extendedLinearDisplayP3` + `wantsExtendedDynamicRangeContent`) is only reachable on a
  CAMetalLayer. Mirror the existing `CameraPreview` `UIViewRepresentable` pattern.
- **Reuse the Metal scaffold:** `GPUContext` (device/queue/`pso(_:)`), and the OKLab math already
  in `Shaders.metal` (`linearSRGBToOKLab` / `okLabToLinearSRGB`). Add **one** new shader pair:
  an instanced impostor-quad vertex/fragment, and the OKLab→**linear-P3** matrix (the existing
  conversion targets sRGB — compose with sRGB→P3 per survey §3).
- **Color precision (survey §3):** positions + colors in an fp32 SoA `MTLBuffer`; OKLab→linear-P3
  in fp32 in-shader (`copysign(pow(abs(x),1.0/3.0),x)`, no `cbrt`); narrow to `rgba16Float` only
  at write-out; EDR gated on `potentialEDRHeadroom > 1`.

---

## 3. UX: depth navigation + glass chrome

The dimension axis collapses to **one LOD/zoom control**, rendered as glass depth — not three
screens (resolves the "everything needs controls" worry):

- **Content layer** = the volume (CAMetalLayer). **Chrome** = glass floating above. Keep the
  color-critical region clear of glass (it tints/desaturates — survey §2).
- Reuse **`GlassToolbarCluster`** + **`GlassIconButton`** (44 pt, `SFTheme.glassClusterSpacing`)
  for: LOD-tier selector (16³/64³/256³), frame scrubber, projection toggle (grid ↔ globe),
  export. Morph between tiers with `.glassEffectID` + `.glassEffectTransition(.matchedGeometry)`.
- **Placement:** in `GIFReviewView.reviewLayout`, after `PaletteStripView` (~line 42) — either a
  segmented **strip ↔ volume** toggle, or stacked. Gated by a new `AppSettings.showLabVolume`
  with a "Visualization" section in `SettingsView` (the store is one-property-extensible).

---

## 4. Palette ↔ GIF consistency

The renderer reads the **same** per-frame 256-entry palette the GIF uses. For the 256³
render-to-still export, route through the **8-bit sRGB LUT** (the `GIFEncoder.swift` path), **not**
a readback of the EDR drawable — the EDR P3 float pixels will never be byte-identical to the
8-bit indexed output. `GIFEncoder.swift` stays untouched.

---

## 5. Build phases

| Phase | Deliverable | Touches | Risk |
|-------|-------------|---------|------|
| **0** | Decide geometry (centroids / pixels / occupancy — see §6) + plumb data if pixels chosen | `CaptureOutput`, `CaptureViewModel` | low |
| **1** | `LabVolumeRenderer` (CAMetalLayer + instanced quads), **static** frame, OKLab→P3 fp32, 16³/64³ | new `Metal/LabVolume*.{swift,metal}`, `GPUContext` | med (new shader) |
| **2** | Animate over 64 frames (frameIndex uniform via `TimelineView`/`CADisplayLink`) | renderer | low |
| **3** | Glass chrome + LOD selector + `AppSettings.showLabVolume` + `SettingsView` section + `GIFReviewView` placement | `GlassControls` (reuse), `AppSettings`, `SettingsView`, `GIFReviewView` | low |
| **4** *(opt)* | 256³ compute software-rasterizer + EDR, **export-still mode** | new compute kernel | high |

Phases 1–3 are the shippable core; Phase 4 is the dense-tier stretch.

---

## 6. Geometry = the palette's split-tree partition of the OKLab volume

All three sizes are **one 256-leaf tree**, branching factor `b`, depth `d`, with `bᵈ = 256`.
"Structure" = recursive subdivision; the factorization just picks the branching factor.

| form | b × d | tree shape | spatial layout |
|---|---|---|---|
| **16²** | 16 × 2 | wide & shallow | flat 16×16 grid |
| **4⁴** | 4 × 4 | quadtree (2 axes/level) | nested 4×4 of 4×4 |
| **2⁸** | 2 × 8 | binary / median-cut (1 axis/level) | nested 2×2 ×4, Z-order/Hilbert |

- **These ARE the classic palette-quantizer trees.** 2⁸ = median cut; 4⁴ = quadtree. Crucially,
  **octree (8-way) cannot hit 256 at a clean depth** (8² = 64, 8³ = 512) — the `3 ∤ 8` gap that
  runs through this whole problem — which is *why* the "Octree" algorithm in the selector must
  prune/merge to land on 256. **Binary median-cut is the only branching that reaches 256 cleanly
  and dimension-agnostically**, making it the natural structure for a 3-D color volume.
- **One structure, three branchings.** Build a single partition of the OKLab volume; `b` (16/4/2)
  is the *structure selector*; tree depth `d` is the *drill-in* — the glass "go deeper" gesture.
  The dimension ladder (plane→volume→color-time) and the navigation gesture are the same motion.
- **Render the split planes, not just dots.** At b=2, eight nested median-cut slabs through the
  OKLab cloud; at b=4, nested quad-partitions; at b=16, the flat grid. Centroids sit at the
  **leaves**; the source-pixel cloud is the faint **field** being partitioned. Each split plane is
  a decision the quantizer made — so the structure is *also* the explanation of how the palette
  was built.

This **supersedes** the earlier flat centroids/pixels/occupancy choice — it subsumes all three:
leaves = centroids, field = pixels, partition = occupancy. The design work below targets this
split-tree model: `b` as selector, depth as drill-in.
