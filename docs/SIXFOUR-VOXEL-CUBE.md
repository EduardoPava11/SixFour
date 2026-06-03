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
3. **AUTO-FIT scale — face-on = pixel identity, orbited = whole cube framed (RULE-CUBE-ISO-FIT; see §8.3).** The orthographic window half-extent (`halfSpan`) **auto-fits the cube's projected silhouette** at the current orientation (`VoxelIso.fitHalfSpan`). At the flat pose the 8 corners project to ±32, so `halfSpan = 32` and one voxel = `gifCellPt` = one GIF pixel — **pixel-identical to the 2D GIF**. As you orbit toward the isometric hero pose it grows to ~50.3 so the **whole dimetric cube stays framed** (voxels shrink ~37%, never clipped). One formula serves both the flat-identity rule and the whole-cube iso framing, with no discontinuity. (This **supersedes** an earlier fixed `halfSpan = 32` rule that clipped the corners when orbited; the project owner chose "fit whole cube at iso" on 2026-06-03.)

**The look is consistent everywhere.** Flat indexed cells, nearest-neighbour, the same 8-bit pixelated surface as the 2D GIF hero, the capture preview, and the palette grid — extended to 3D by the 2:1 dimetric ruleset (§8). The cube is a *3D view of the same pixels*, not a re-rendering.

**Verification (RULE-CUBE-2D-IDENTITY):** orbit head-on at any frame, screenshot, and compare to the 2D GIF hero at that frame — surface voxels must match the GIF pixels (modulo the sRGB-drawable parity note in the prototype assumptions).

### 0.2 Part of the palette-explorer family — branchings ARE design-language law

The cube is the **3D member of the Review palette-explorer family** (alongside the `.structure` treemap and the `.grid`), and shares their colour model. The 256 colours of each frame's palette organise by the SAME canonical branchings the rest of the family uses — `PaletteBranching` `.b16 / .b4 / .b2` = **16² / 4⁴ / 2⁸** (`SplitTree.swift`). All three reach `K = 256` as collapse-views of one median-cut `SplitTree` (`factor^depth = 256`: 16²=256, 4⁴=256, 2⁸=256).

> **RULE-BRANCHING-CANONICAL (design-language law).** Every palette tool — treemap, grid, editor, and the cube — MUST express the 256 colours through these three branchings, never an ad-hoc grouping. They are the single, design-language-sanctioned way to factor K. When the cube gains slice analysis (§0.3), any colour grouping / level-of-detail it offers uses the active `PaletteBranching`, so it reads consistently with the treemap and grid.

### 0.3 SHIPPED — frame-isolation transparency for palette study (RULE-CUBE-ISOLATE)

The cube's **analysis mode**: focus one frame opaque and make the rest transparent, so the user can **isolate a single frame and study its colour palette in 3D** (distinct from the playful 2D↔3D reveal). It is what earns the cube its place beside the treemap and grid as an inspection lens. Controls: a shape-changing "isolate" glass toggle (`square.stack.3d.up[.fill]`) + a **Ghost** slider (0 = the other frames vanish entirely; up to ~0.4 = they linger as a faint translucent context cloud). The focus frame is the playback `cursor` (the near face); scrub to choose it.

**Renderer.** The raymarch composites front-to-back: each voxel's α is `1.0` everywhere *except* in isolate mode, where the focus frame stays α=1 and other slices take `ghostAlpha`. Because α=1 makes the over-operator saturate on the first hit, the non-isolate path is **byte-identical** to the old first-hit march — the 2D rest-pose identity (§0.1) is provably untouched (`VoxelRestPoseIdentityTests`).

> **GRID tension — SETTLED (owner sign-off 2026-06-03).** Opacity on a data cell normally violates GRID Law #2. Per-slice transparency was flagged here as a plausible *inspection-lens* exception needing explicit sign-off; the project owner requested it ("see the frame you want while the others are transparent, to study the palette"), so it ships as a **sanctioned analysis-mode exception** — alpha appears ONLY on non-focus slices in isolate mode, never on the focus frame and never outside this mode.

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
| **Orbit** | drag | bare gesture on the cube | yaw/pitch into `VoxelCubeState`; **disabled when `locked`**; gesture consumes the touch before the parent `ScrollView` |
| **Iso corner** | tap | `GlassIconButton` "cube.fill" top-trailing | snaps to the current 2:1 dimetric corner; tapping again **cycles the 4 canonical corners** (`VoxelIso.corner`, same 30° elevation) |
| **Lock** | toggle | `GlassIconButton` "lock.open"↔"lock.fill" top-trailing | freezes the orientation for study (orbit gesture no-op); shape changes with state |
| **Reset to 2D** | tap | `GlassIconButton` "cube.transparent" top-trailing | folds back to the flat rest pose and unlocks |
| **Playback** | play/pause | `GlassIconButton` (`.symbolEffect(.replace)`) | t driven by the **single** clock `frameIndex(at:rate:20,count:64)` (`PixelGrid.swift:34`) — frame-locked to the GIF hero; holds frame 0 under Reduce Motion |
| **Auto-rotate** | tap | segment in a `GlassToolbarCluster` | spins yaw on the clock and **eases elevation to 30°** → a 2:1 dimetric turntable; **frozen** under Reduce Motion (GLASS §6 RULE-GLASS-MOTION) |
| **Isolate frame** | toggle | `GlassIconButton` "square.stack.3d.up"↔".fill" | focus frame opaque, rest transparent (§0.3); **Ghost** slider sets non-focus α |
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
> has no first-launch compile hitch. The provenance filter / luma floor /
> auto-rotate persist in `AppSettings` (seeded into the view, written back on
> change). **Still deferred:** time-explode (§4) and the separate
> `Metal/VoxelCubePipeline.swift` split. The luma threshold is computed CPU-friendly per-ray (Rec.709 on
> the sRGB bytes) rather than the §3 precomputed-LUT-into-airMask form — a later
> optimisation, same result.

---

## 6. Accessibility & governance

- **A11y:** the cube container is **one** combined label ("64 by 64 by 64 voxel palette cube, frame i of 64"); each glass control owns its label; no per-voxel AX nodes (mirrors GRID §6.5 CellRing's single-owner rule).
- **Reduce Motion:** auto-rotate/explode freeze; playback holds frame 0 (mirrors `GIFCanvas`).
- **Reduce Transparency / Increase Contrast:** glass chrome degrades to a solid contrast-passing fill (GLASS §6 RULE-GLASS-REDUCE-TRANSPARENCY).
- **Decisions gate:** adding a third `RepresentationSelector` mode is a `RULE-GLASS-DECISIONS` / GRID `GATE-DECISIONS` item — signed off, not drifted in.

---

## 8. The 8-bit isometric ruleset (2:1 dimetric) — RULE-CUBE-ISO

The cube is the app's **3D representation of the GIF**, and its 3D look is governed
by the **isometric ruleset of 8-bit/16-bit videogames**. That look is two precise,
separable rules — both now enforced (`VoxelIso`, `voxel_raymarch`, `VoxelRestPoseIdentityTests`):

### 8.1 It is DIMETRIC at 2:1 — not true isometric (RULE-CUBE-ISO-ANGLE)
8-bit "isometric" games were never truly isometric. True isometric uses an
orthonormal camera at **elevation 35.26°**, whose floor diagonals have slope
`tan30° ≈ 0.577` — non-integer stairsteps that look wrong in pixel art. Every
classic engine instead used **azimuth 45°, elevation 30°**, because **`sin30° = 0.5`**
makes each floor edge step **exactly 2 px across : 1 down** — a slope a 6502/Z80 could
draw by halving. This is the canonical **hero pose**:

```
VoxelIso.yaw   = π/4   (45° azimuth)
VoxelIso.pitch = π/6   (30° elevation)   → world-X and world-Z each project to slope 0.5
```

The camera basis is **orthonormal** (yaw about world-Y, then pitch about the
*camera-right* axis — `voxelOrbit`, Rodrigues form). At `yaw=pitch=0` it is the
identity, so the flat rest pose stays byte-1:1 with the 2D GIF (§0.1). The "cube.fill"
glass button snaps to the hero pose; **auto-rotate eases elevation to 30° and spins
yaw** — a dimetric turntable, not a flat spin. Proven by `isoPoseIsExactly2to1Dimetric`.

### 8.2 It is CHUNKY — a fixed 128² art grid (RULE-CUBE-ISO-PIXELATION)
A retina-resolution orthographic box reads as a clean 3D solid, not 8-bit. The kernel
therefore quantises every drawable pixel to a fixed **`ART_RES = 128`** art-pixel grid
(all drawable pixels in one art cell share its centre's raymarch result), then
nearest-upscales. `128 = 2·64`, so **each voxel is exactly 2 aligned art-pixels** of its
single constant colour — the 2:1 dimetric edges resolve as visible 8-bit stairsteps, and
the flat pose stays pixel-exact (RULE-CUBE-2D-IDENTITY). The art grid is resolution-independent,
so the chunkiness is identical on every device.

### 8.3 Whole cube visible at iso — auto-fit window (RULE-CUBE-ISO-FIT, supersedes RULE-CUBE-FIXED-SCALE)
8-bit games frame the **whole** object. The orthographic half-window therefore
**auto-fits the cube's projected silhouette** at the current orientation
(`VoxelIso.fitHalfSpan` = max `|corner·basis|` over the 8 corners, +1-unit pad when
orbited). At the flat pose the corners project to ±32, so it returns **exactly 32** ⇒
one voxel = one GIF cell = the 2D identity; orbited toward the hero pose it grows to
~50.3 so the whole dimetric hexagon is framed (voxels shrink ~37%). One formula, no
discontinuity. This **replaces** the earlier fixed `halfSpan = 32` rule, which clipped
the cube's corners when orbited — the project owner chose "fit whole cube at iso"
(2026-06-03). Proven by `fitHalfSpanIsIdentityAtFlatAndFramesWholeCubeAtIso`.

> **Provenance.** The 2:1 angle, dimetric-vs-isometric distinction, and the
> 2-px-shift hardware rationale are from the isometric-pixel-art literature
> (slynyrd Pixelblog-41; Wikipedia "Isometric video game graphics"; pikuma).

---

## 7. References
- **GRID** — `docs/SIXFOUR-DESIGN-LANGUAGE.md` (Cardinal Law §0, Law #2 render surface §1/§4, §2.6 luminance, §7.2 EXEMPT-REVIEW-PITCH).
- **GLASS** — `docs/SIXFOUR-GLASS-LANGUAGE.md` (Boundary Law §0, §4 components, §6 accessibility, EXEMPT-GLASS-REVIEW).
- **Data** — `Encoder/DeterministicRenderer.swift:41-57`, `Encoder/GIFRenderer.swift:37-53`, `Generated/SignificanceContract.swift:50-66`, `UI/Screens/Capture/CaptureViewModel.swift:9-59`.
- **Reusable code** — `UI/Components/CameraPreview.swift` (UIViewRepresentable + gestures), `Metal/GPUContext.swift` (device/queue/library), `Metal/Shaders.metal` (compute kernels), `UI/Components/PixelGrid.swift` (`Color(srgb8:)`, `frameIndex(at:rate:count:)`), `UI/Components/PaletteGridView.swift:64-95` (`PaletteRepresentation` + `RepresentationSelector`), `Settings/AppSettings.swift:32/101/119` (persisted toggles).
- **App map** — `docs/APP-MAP.md`.
