# SixFour Voxel Cube Explorer — design note ("CUBE")

**Status:** Design note, v1.0 (2026-06-01). A Review-surface tool; subordinate to GRID and GLASS.
**Scope:** the third palette-representation mode on the **Review** screen — a 64×64×64 voxel cube rendered from the data the deterministic core already produced. Where this note and GRID/GLASS overlap, **GRID wins on content, GLASS wins on chrome**; this note only fills the surface those two leave to "a 3D palette explorer alongside the treemap and the grid."
**Hard boundary (read first):** the cube is **CONTENT**, not chrome. Its voxels are flat indexed cells (one voxel = one GIF pixel = one world unit) and **never** carry glass, opacity, AA, or rounding (GRID Law #2). Every control *around* the cube is Liquid Glass chrome (GLASS Boundary Law). The cube never sits on glass; glass never fills a voxel.

---

## 0. Why a cube — and why it is not just a coloured box

A SixFour GIF is a 64×64×256 object: 64 frames, each a 64×64 grid of indices into that frame's 256-colour palette. Read the 64 frames as a **depth/time axis t**, and the GIF *is* a 64³ voxel cube: `voxel(x,y,t) = srgbPalettes[t][frameIndices[t][y*64 + x]]`. This is the same cube GRID calls "the law" (§0), now shown in three dimensions.

The danger is honest: a fully-dense 64³ cube is 262,144 voxels but only its ~6·64² shell is ever visible — from outside it is a coloured box. The value, and the 8-bit voxel *character*, come from two places, and this note is organised around them:

1. **What is AIR vs SOLID** — which voxels matter (§3).
2. **Interaction** — orbit, t-slice, time-explode, threshold, playback (§4).

The cube is a **read-only explorer / verifier**, the 3D sibling of the treemap (`.structure`) and the coordinate grid (`.grid`). It does not edit the palette — that is `GlobalPaletteEditorView`'s job — and it never merges the 64 per-frame palettes into one (that would destroy the t-axis that is the whole point).

### 0.1 The 2D↔3D identity (the surprise) — CORE INVARIANT

At the rest pose (`yaw = pitch = 0`) the cube must be **byte-for-byte indistinguishable from the 2D GIF hero**, and orbiting must continuously bloom it into 3D. This is not decoration; it is the load-bearing idea and it dictates three renderer facts:

1. **Orthographic projection, never perspective.** Perspective foreshortens, which would break the 2D match the instant the cube is on screen. Orthographic also *is* the MagicaVoxel / 8-bit-voxel look — constraint and aesthetic agree.
2. **Depth = time, current frame frontmost.** Depth-slice `z` shows frame `f(z) = (cursor − 63 + z) mod 64`, so the near face (`z = 63`) is the current frame `cursor` and earlier frames recede behind it. Head-on you see only the near face = the playing 2D GIF; orbit reveals the GIF's recent history extruded into space. As the playback cursor advances, the whole stack flows front-to-back.
3. **Exact-fit orthographic window.** The on-screen window half-extent (`halfSpan`) is the cube's projected silhouette for the current orientation — computed CPU-side by projecting the 8 cube corners onto the rotating view-plane axes. Face-on this is exactly **32**, so the 64-wide cube fills the square and one voxel = `edge/64` = **`gifCellPt` (6 pt)** = one GIF pixel. Corner-on it grows to fit, so the cube never clips. The handoff is seamless because at `θ→0` the side faces have zero projected width.

**Verification (RULE-CUBE-2D-IDENTITY):** orbit head-on at any frame, screenshot, and compare to the 2D GIF hero at that frame — surface voxels must match the GIF pixels (modulo the sRGB-drawable parity note in the prototype assumptions).

---

## 1. Principles (ordered C1 > C2 > C3)

### C1 — The voxel is a cell; the cell is the world unit.
One voxel = one GIF pixel = side **1.0** in cube-local space. There is exactly **one** size scalar, `cellWorld` (the on-screen size of a voxel), owned by one `VoxelCubeState` value — never per-axis, never per-widget (GRID Law #1/#5 carried onto Review). A voxel is rendered as one opaque indexed sRGB8 via the `Color(srgb8:)` semantics (explicit `.sRGB`), so a voxel matches the GIF **byte-for-byte** (GRID §2.6).

### C2 — Flatness holds in 3D.
No AA, no opacity, no rounding on a voxel (GRID Law #2). The **one** permitted depth cue is a discrete MagicaVoxel-style directional face multiply (top 1.0 / front 0.85 / side 0.7) applied to the indexed colour — a fixed per-face step, not a continuous shade. "Dimming" (e.g. split slots) is expressed as an adjacent **opaque** darker index step, never alpha (GRID index-dither rule).

### C3 — Chrome is glass, content is grid.
The cube is content. Orbit/playback/slice/threshold controls are Liquid Glass, composed from GLASS §4 components inside one `GlassEffectContainer` (G3). Selection tint is the sanctioned `hairline` white@0.18 (GLASS G4). The cube never composites onto glass and glass never tints a voxel (GLASS Boundary Law; the `.clear` carve-out, GLASS §3.3, is available only if a control must float directly over the cube).

---

## 2. Data path — a pure function of existing output

The cube needs **no new capture and no new render**. Every field already exists:

- `DeterministicRenderer.Result` (`Encoder/DeterministicRenderer.swift:41-57`) and the GPU `GIFRenderer.Output` (`Encoder/GIFRenderer.swift:37-53`) both carry `frameIndices: [[UInt8]]` (64×4096), `srgbPalettes`/`palettesForDisplay` (64×256), and `cells`/`perFrameCells: [[SixFourSignificantCell]]` (64×256, with `.count` and `.provenance`).

**The one gap.** `CaptureOutput` (`UI/Screens/Capture/CaptureViewModel.swift:9-59`) is the Review boundary, and it carries `palettesForDisplay` + `perFrameCells` but **drops `frameIndices`**. Without the per-pixel index map, `voxel(x,y,t)` is unrecoverable. The fix is one field:

```swift
// CaptureOutput
let frameIndicesForVoxels: [[UInt8]]?   // 64 × 4096; nil on legacy outputs
```

populated at **both** construction sites — `CaptureViewModel.swift:428` (`result.frameIndices`) and `GIFRenderer.swift:224` (`output.frameIndices`) — and excluded from `Hashable`/`==` (identity stays the gifURL, per the existing contract).

**Consumption (once, on appear):** build `indexBuf[t*4096 + y*64 + x]` → an `MTLTexture` (R8Uint, 64×64×64); upload the 64×256 palette as an RGBA8 2D texture; upload a 64×256 `airMask` byte derived from `perFrameCells` (§3). The raymarch kernel reads only these three textures.

---

## 3. Air vs Solid

**Default (the honest baseline, not user-toggleable):** provenance + significance from `perFrameCells` (`Generated/SignificanceContract.swift:50`). A voxel is **air** iff its slot is `.degenerate`; by the SixFour significance contract degenerate is *unreachable* (every one of the 256·64 slots is backed by `count ≥ minPopulation`), so the default cube is **fully solid** — which is the truth, and makes the cube a verifier you can *see*. To keep it sculptural rather than a box, `.split` slots (synthetic, created to reach K) render one discrete dark step below `.extracted` slots, so the user reads real-cluster vs filled structure.

**User-toggleable (glass controls, persisted in `AppSettings`):**
- **Luminance threshold** — voxels below a brightness floor become air. Luminance is `Y = 0.2126R + 0.7152G + 0.0722B` on linearized sRGB (GRID §2.6), **precomputed into a 256-entry LUT per frame** and folded into `airMask` on the CPU — never computed per-voxel in the kernel.
- **Provenance filter** — show extracted-only / split-only / all (chroma-key by provenance).
- **t-slice band [tLo,tHi]** — the primary interior reveal; clamps each ray's z-extent.

All toggles recompute the 16 KB `airMask` on the CPU on change and re-upload; the kernel only *samples* the mask, never branches on float math.

---

## 4. Interaction → GLASS components

| Control | Gesture | Glass component | Behaviour |
|---|---|---|---|
| **Orbit** | drag | `GlassIconButton` "reset" floats top-trailing | yaw/pitch into `VoxelCubeState`; gesture consumes the touch before the parent `ScrollView` |
| **Playback** | play/pause | `GlassIconButton` (`.symbolEffect(.replace)`) | t driven by the **single** clock `frameIndex(at:rate:20,count:64)` (`PixelGrid.swift:34`) — frame-locked to the GIF hero; holds frame 0 under Reduce Motion |
| **Auto-rotate** | tap | segment in a `GlassToolbarCluster` | slow yaw on the 20 fps clock; **frozen** under Reduce Motion (GLASS §6 RULE-GLASS-MOTION) |
| **t-slice** | range drag | glass `Capsule` pill (`pillCorner`) | sets [tLo,tHi]; debounced ≥100 ms |
| **Time-explode** | toggle | `GlassSelector` segment | spring-morph plane spacing; snap (no animation) under Reduce Motion |
| **Air/threshold** | slider + segmented | `GlassSelector` (`controlCorner=0`) + glass pill | recomputes `airMask`, re-uploads |
| **Mode entry** | tap | `RepresentationSelector` (third segment) | swaps content for `VoxelCubeView`; segment **hidden when `frameIndicesForVoxels == nil`** |

All multi-control clusters sit in one `GlassEffectContainer(spacing: glassClusterSpacing)` (GLASS G3 / §4.2). Selection uses the `hairline` tint (GLASS §3.1).

---

## 5. Renderer

Hand-written **Metal compute DDA raymarcher** (Amanatides-Woo voxel traversal) over the R8Uint index texture, hosted in an `MTKView` via `UIViewRepresentable`. Chosen over SceneKit/RealityKit/instanced meshes because: the app already owns the Metal stack (`Metal/GPUContext.swift`, `Metal/Shaders.metal`, `Metal/Pipeline.swift`); the per-frame local palette breaks greedy-meshing/occlusion assumptions (a mesh would rebuild every frame anyway); and DDA is O(pixels × steps) ≈ 150M ops at the Review hero size — comfortably <10 ms on A19, with slicing/threshold free per-ray. **Zero third-party dependencies:** Metal is an Apple framework permitted by CLAUDE.md Tier-2; SceneKit/RealityKit are likewise Apple frameworks (not the contingency on contract grounds, only on performance grounds).

New files: `UI/Components/VoxelCubeView.swift` (representable + Coordinator, the `CameraPreview.swift` pattern), `Metal/VoxelCubePipeline.swift` (device/queue/PSO + texture upload, the `GPUContext.swift`/`KMeansPalettePipeline.swift` pattern), and a `voxelRaymarchKernel` added to `Metal/Shaders.metal`.

> **As-built (2026-06-01).** `UI/Components/VoxelCubeView.swift` + the
> `voxel_raymarch` kernel in `Metal/Shaders.metal` implement: the orthographic
> temporal renderer with the 2D↔3D identity (§0.1, depth = time, current frame
> frontmost, exact-fit window); orbit / play-pause / auto-rotate / reset-to-2D /
> frame-scrub / trail-depth / luminance-air controls (Liquid Glass chrome); and
> the **§3 provenance air-mask** — provenance is packed in the palette texture's
> alpha (0 degenerate→air, 1 extracted, 2 split→one dark step) with an
> all / extracted / split filter. The kernel lives in `Shaders.metal` (loaded via
> the default library, GPUContext pattern) so it is **compile-time validated** and
> has no first-launch compile hitch. **Still deferred:** time-explode (§4), the
> separate `Metal/VoxelCubePipeline.swift` split, and persisting the controls in
> `AppSettings`. The luma threshold is computed CPU-friendly per-ray (Rec.709 on
> the sRGB bytes) rather than the §3 precomputed-LUT-into-airMask form — a later
> optimisation, same result.

---

## 6. Accessibility & governance

- **A11y:** the cube container is **one** combined label ("64 by 64 by 64 voxel palette cube, frame i of 64"); each glass control owns its label; no per-voxel AX nodes (mirrors GRID §6.5 CellRing's single-owner rule).
- **Reduce Motion:** auto-rotate/explode freeze; playback holds frame 0 (mirrors `GIFCanvas`).
- **Reduce Transparency / Increase Contrast:** glass chrome degrades to a solid contrast-passing fill (GLASS §6 RULE-GLASS-REDUCE-TRANSPARENCY).
- **Decisions gate:** adding a third `RepresentationSelector` mode is a `RULE-GLASS-DECISIONS` / GRID `GATE-DECISIONS` item — signed off, not drifted in.

---

## 7. References
- **GRID** — `docs/SIXFOUR-DESIGN-LANGUAGE.md` (Cardinal Law §0, Law #2 render surface §1/§4, §2.6 luminance, §7.2 EXEMPT-REVIEW-PITCH).
- **GLASS** — `docs/SIXFOUR-GLASS-LANGUAGE.md` (Boundary Law §0, §4 components, §6 accessibility, EXEMPT-GLASS-REVIEW).
- **Data** — `Encoder/DeterministicRenderer.swift:41-57`, `Encoder/GIFRenderer.swift:37-53`, `Generated/SignificanceContract.swift:50-66`, `UI/Screens/Capture/CaptureViewModel.swift:9-59`.
- **Reusable code** — `UI/Components/CameraPreview.swift` (UIViewRepresentable + gestures), `Metal/GPUContext.swift` (device/queue/library), `Metal/Shaders.metal` (compute kernels), `UI/Components/PixelGrid.swift` (`Color(srgb8:)`, `frameIndex(at:rate:count:)`), `UI/Components/PaletteGridView.swift:64-95` (`PaletteRepresentation` + `RepresentationSelector`), `Settings/AppSettings.swift:32/101/119` (persisted toggles).
- **App map** — `docs/APP-MAP.md`.
