# SixFour Palette Explorer — Unified 2D / 3D / 4D Visualisation Design

**Status:** Design (spec-first). Supersedes the ad-hoc PaletteSphereView spike and the stale "palette globe" framing.
**Date:** 2026-05-31
**Contract:** Tier-2 (ships) — zero third-party deps, Apple frameworks + `simd` only; all numerics trace to the Haskell spec and are golden-pinned before any Swift lands.

---

## 0. The unified vision

Today the Review screen exposes the palette through **two orthogonal glass selector axes**:

- **Scope** (`PaletteScope.perFrame | .global`) — *which* palette: the 64 animated per-frame palettes (NN input) vs. the one collapsed global palette (NN output, edited "by hand" in `GlobalPaletteEditor`).
- **Branching** (`PaletteBranching.b16 | .b4 | .b2` = 16² / 4⁴ / 2⁸) — *which nesting genome* of the one canonical binary `SplitTree`.

This design adds **one more orthogonal axis — Representation (dimension)** — turning the two existing renderers into one coherent **Palette Explorer** with three dimensional modes that all read from the same verified backbone (`CaptureOutput.palettesForDisplay` + `SplitTree.build`):

| Representation | Renderer | What it answers |
|---|---|---|
| **2D — Structure** (`.treemap2D`) | existing `PaletteTreeView` (per-frame) / `GlobalPaletteEditor` (global) | "How does median-cut nest the 256 colours?" |
| **2D — Coordinate** (`.grid2D`) | **new** `PaletteGridView` (16×16, user-assignable x/y axes) | "Where does each colour sit on two axes *I* chose?" |
| **3D+4D — OKLab Temporal Cloud** (`.cloud4D`) | **new** `PaletteCloudView` (point cloud + time) | "What is the actual perceptual gamut, and how does it move over the 64 frames?" |

**Invariants preserved across all modes:**
- Scope (per-frame / global) and Branching (16²/4⁴/2⁸) toggles keep working exactly as today; the user's branching genome choice still drives nesting granularity (treemap borders, grid split-digit axes, cloud shells).
- The branching ("history"/genome) semantics and the `SplitTree` golden vectors are untouched — every new mode is a *view* of the same tree, never a parallel colour path.
- **Glass is chrome, content is content.** Every selector and actuator wears Liquid Glass (`GlassEffectContainer` + `.glassEffect(.regular.interactive(), in: Capsule())`, `.isSelected`); every data rendering (Canvas) gets *no* glass — only `RoundedRectangle(cornerRadius: SFTheme.cardCorner)` + `SFTheme.hairline`.
- Chrome is **contextual**: branching selector shows only when it changes the active mode; the grid's X:/Y: pickers show only in `.grid2D`; scrub/trail/overlay cluster shows only in `.cloud4D`. The Review screen never shows five capsule rows at once.

---

## 1. What "4D" means here — RESOLVED

> **Decision: 4D = OKLab 3-space (L, a, b) + TIME (the 64 frames) as the fourth axis.** Not "deeper genome nesting." Not "+time *and* nested genome." The fourth dimension is **time**, made into a first-class, user-scrubbable axis.

Rationale, and why this beats the alternatives:

- The genome nesting (16²/4⁴/2⁸) is **not a dimension** — it is a reparametrisation of the *same* 768/513-DOF leaf space (`FlatPalette` 768, `PairTree` 768, `Quad4` 513). Calling it "4D" would double-count an axis we already have (Branching). Nesting therefore stays as an *overlay control* inside whatever spatial mode is active, not as the fourth axis.
- The three genuinely independent quantities are **(perceptual position) × (time)**. OKLab is the app's native, golden-verified space; the pipeline literally maximises OKLab coverage/diversity. So the three spatial axes = L, a, b at their *true* coordinates (screen distance = perceptual distance), and the fourth = frame index 0..63.
- Time is the one axis **every existing tool is blind to**: the treemap animates implicitly but is frame-agnostic in meaning; `GlobalPaletteEditor` is explicitly frame-agnostic. Promoting time to a scrubbable playhead with optional motion trails is the real new capability.

So the explorer is **3D-spatial + 1D-temporal = "4D"**, surfaced as a single `.cloud4D` mode (the 3D cloud *is* the 4D view with the time axis at a chosen/animating playhead). There is no separate "3D vs 4D" selector — 3D is the cloud frozen at one frame; 4D is the cloud scrubbing/playing through 64.

---

## 2. Mode designs

### 2.1 `.treemap2D` — Structure (unchanged)
The shipping `PaletteTreeView` median-cut treemap (per-frame) and `GlobalPaletteEditor` multiresolution nudge editor (global). No spec change, golden vectors intact. This is the "structure" reading: cell position encodes tree membership/ordering, **not** a colour coordinate — and the doc must keep saying so.

### 2.2 `.grid2D` — Coordinate (new)
A flat **16×16 = 256-cell grid where the user assigns what x and y MEAN.** This is the literal "settable-axis grid" the user asked for; it does **not** exist today (the treemap's 16² is two collapsed binary levels, not a coordinate grid).

- **Axes:** a `GridAxis` enum chosen independently for x and y:
  - *Perceptual:* OKLab L, a, b; OKLCh chroma `C = hypot(a,b)`; OKLCh hue `h = atan2(b,a)` (the one new scalar — pure derived function of verified a/b, golden-pinned with an explicit **hue-origin / wrap convention**).
  - *Structural:* split-digit hi / lo — the base-`factor` digit decomposition of a leaf's address in the canonical `SplitTree` (so 16²/4⁴/2⁸ become explicit 2-axis digit placements). **Labelled "split-tree address (n-ary collapse)," never "the Quad4 genome"** (see §3).
  - *Statistical:* population/significance (from `perFrameCells[frame][k].count`), original slot `index`.
- **Binning:** **fixed canonical OKLab range is the spec'd default** (so "axes fixed in meaning" actually holds and colours *migrate* against a stable lattice across the 64 frames). Per-frame-quantile is a secondary, explicitly-labelled toggle. Quantise each axis into 16 bins; place into the 16×16 array; resolve the rare double-occupancy by the pinned `(coord, index)` tie-break + a **spec-pinned, O(256)-bounded nearest-empty-cell scan order**.
- **Rule:** x and y must differ; picking the same dimension **auto-swaps** (never a silent dead-end).
- **Default:** x = OKLab a, y = OKLab L (a readable hue-by-lightness layout).
- **Animation:** identical `TimelineView(.animation, minimumInterval: 1/20)` + reduce-motion freeze-on-frame-0 as the treemap.
- **Perf:** cache the (x-scalar, y-scalar) arrays once per frame index; single full Canvas redraw per tick (never 256 individually-animated views).
- **Accessibility (ship gate):** the grid's whole premise — "(row, col) is a *fact* about the colour" — fails if cells are invisible to VoiceOver. The treemap's single `children: .ignore` summary is **not sufficient here.** Each occupied cell gets an `accessibilityValue` ("row r, col c, OKLab L/a/b, N px") via an accessibility-children representation or a rotor.

### 2.3 `.cloud4D` — OKLab Temporal Cloud (new, 3D + time)
Each of the 256 colours sits at its **true OKLab coordinate** (L = vertical, a/b = horizontal chroma disc); the user orbits/zooms a self-coloured, depth-sorted point cloud and scrubs/plays the 64-frame time axis with optional fading motion trails.

- **Spatial basis is fixed by contract** (L→up, a→x, b→z): the value is that the axes mean exactly OKLab and never drift — the explicit fix for the treemap's "nothing is held fixed to read."
- **Fidelity honesty:** "screen distance = perceptual distance" holds only under **orthographic** projection. Default to an orthographic top-down (a/b) / side (L) snap where the claim is true; offer perspective orbit only as an explicitly-labelled "explore" mode. Do **not** attach the fidelity claim to the perspective view.
- **Renderer:** pure SwiftUI `Canvas` + `simd` (hand-written yaw/pitch 3×3 rotate → projection → painter's back-to-front sort → `fill(Path(ellipseIn:))`). **No SceneKit / RealityKit / Metal** — 256 dots is trivially within budget; Canvas keeps it deterministic and contract-clean. This is the OKLab-correct realisation of the "OKLabVoxelBrowserView" that commit 7e79330 named as PaletteSphereView's replacement but never built.
- **Density:** point radius ∝ real `perFrameCells[frame][k].count` (population / significance). **Delete the in-view sRGB KDE** the old globe used. Guard the legacy GPU path where `perFrameCells` is empty (uniform radius + "no significance data" badge, not a silent KDE).
- **Time (the 4th axis):** glass scrub slider + play/pause (`GlassToolbarCluster`) over `TimelineView` at 20fps. A "trail length" pill (0 / short / long; default 0) draws each slot's last N OKLab positions as a fading polyline — a colour's *trajectory* through the burst.
- **Genome overlays** (driven by the same `PaletteBranching` selector → `collapse(collapseK)` / `descendants(at:)`): subtree hulls (deterministic **OKLab AABB**, not float gift-wrap) at the chosen grain. The 4⁴ opponent-quadrant `±δ₁±δ₂` gnomon and the 768→513 projection-error **ghost points + displacement arrows** are gated behind the nesting pill, **off by default**, and routed through the existing `Quad4` spec port — never a fresh Swift derivation.
- **Bug fixes carried in:** capture live Canvas size via `GeometryReader`/`onGeometryChange` (the old `lastSize` defaulted to 300×260 and was never updated); add front-most-wins (smallest-z) tie-break so picks land on the visible dot in dense clusters.
- **Accessibility (ship gate):** one `accessibilityElement(children: .ignore)` + spoken summary (mirror `PaletteTreeView`), **not** 256 focusable dots. Reduce-motion must **hard-disable** MORPH/trails *and* any auto-orbit (not merely freeze frame 0); render trails as a faded static streak at frame 0 so the temporal signal isn't motion-gated away. The flat treemap/grid remains the primary accessible path — the cloud must never be the *only* palette view.

---

## 3. Genome faithfulness — the math every mode must respect

The three "branchings" reorganise the **same 256 OKLab leaves**:

- **16² `FlatPalette`** — 768 DOF, identity, lossless.
- **2⁸ `PairTree`/Haar** — 768 DOF, lossless orthogonal transform (parent ± δ mirror pairs).
- **4⁴ `Quad4`** — **513-DOF subspace**, opponent-quadrant (Hering a/b) bias. `quad4Analyze` is a **lossy projection** on arbitrary leaves.

**Two hard rules for the new modes:**

1. **Do not conflate `SplitTree` with `PairTree`/`Quad4`.** The median-cut `SplitTree` is *distinct* from the NN's Haar tree (the spec says so verbatim). `SplitTree` branch nodes carry `(axis, pos)` = a median **split plane**; its two children are lo/hi **half-sets**, NOT `parent ± δ` mirror pairs — and **"mean of leaves = root" is a PairTree/σ property the SplitTree does NOT satisfy.** In the cloud, render `SplitTree` internal structure as split-plane / half-set hulls. Any "mirror-pair" or "balanced-mean" language belongs only on a *separately-labelled* Quad4/PairTree overlay sourced from the NN-genome spec. If a root marker is drawn, label it "pooled mean (barycenter)" and source it from `ClusterStatisticsOps.pooledMean` — never assert it as a SplitTree invariant.

2. **Never draw 4⁴ as if lossless.** When split-digit (4-ary) axes are active in the grid, or the 4⁴ shell is active in the cloud, either (a) render the `quad4Analyze → reconstruct` *shifted* colours (true Quad4 genome), or (b) label it "split-tree address (4-ary collapse)" exactly as the treemap does — **never "the Quad4 genome" over raw leaves.** The 768→513 ghost/arrow visualisation is the strongest spec-aligned idea; keep it, tagged as the NN genome and separate from the SplitTree overlay.

---

## 4. Feasibility & contract alignment

- **Zero-dep:** ✅ all three modes are SwiftUI `Canvas` + `simd` + `TimelineView`. No SPM/CocoaPods/Carthage; no SceneKit/RealityKit/Metal needed.
- **20fps perf:** ✅ bounded by the same per-frame work the treemap already ships. Hard requirements: cache per-frame axis scalars (grid); precompute ALL 64 frames' geometry (hull AABBs, edge midpoints, endpoint sRGB fills, quad4 ghosts) off-main in `.task`, render tick = lookup+project+sort only (cloud); bound the grid collision scan to O(256); never model 256 individually-animated views; lerp display in sRGB (don't call full `okLabToSRGB8` 256× per 50ms tick).
- **Accessibility:** the two new modes raise the bar above the treemap's single-summary pattern — **per-cell `accessibilityValue` (grid)** and **collapsed-summary + reduce-motion static fallback (cloud)** are explicit ship gates, not nice-to-haves.
- **Spec alignment:** new numerics — OKLCh hue (with wrap-origin), chroma, fixed-range quantile binning, deterministic collision resolution, OKLab→world axis constants, AABB hull vertices, temporal lerp, perspective constants, Quad4 ghost reconstruction, σ-reflect action — **must be spec'd as laws + golden vectors first** (`Spec.GridAxis`; reuse `Quad4.quad4Analyze`, `PairTree.sigmaReflect`). Verified bit-for-bit before any Swift port. Existing OKLab transforms (`srgb8ToOKLab`/`okLabToSRGB8`/`okLabDistanceSquared`) are already golden-verified.
- **Sanction:** ⚠️ `feedback_sixfour_palette_viz` steers in-app palette viz toward the Rust `~/SixFour/studio` tool and parked/removed PaletteSphereView for being unsanctioned. **The `.cloud4D` (3D) mode is blocked on explicit user sanction before any code.** The `.grid2D` mode is a 2D content renderer in the same family as the shipping treemap and is lower-risk, but should also be confirmed. Frame the cloud as the OKLab-correct realisation of the planned-but-unbuilt replacement, and keep the heavier experimental cloud in the studio as the default if sanction is withheld.

---

## 5. Settings & integration

- New versioned `AppSettings` keys mirroring the existing pattern: `sixfour.paletteRepresentation.v1`, `sixfour.gridAxisX.v1`, `sixfour.gridAxisY.v1` (and reuse `paletteScope`/`paletteBranching`). Mirror in `SettingsView`.
- `paletteStructure()` in `GIFReviewView` is restructured from a 2-case `switch (scope)` into a 2-level selection: **Representation first**, then per-representation chrome (scope where relevant, branching for treemap/cloud, X/Y for grid). The taller cloud/grid drop into the existing `VStack(spacing: 14)` ScrollView section with no layout surgery.

---

## 6. Documentation drift to fix (do this regardless)

1. **`GIFReviewView.swift:5-7`** — docstring says the screen stacks *"the palette globe (the 256 colours as rotatable circles — the verifier you can see)."* No globe renders; lines 78/81 render `PaletteTreeView` (treemap) / `GlobalPaletteEditor`. Rewrite to describe the actual scope/branching palette-structure tool (and, once shipped, the representation axis).
2. **`GIFReviewView.swift:27`** — comment *"GIF + globe + status are together taller…"* — replace "globe" with "palette tool."
3. **Memory `sixfour-palette-sphere-tool.md`** — describes `PaletteSphereView` as a present on-device tool. It was **removed** (commit 7e79330) and never replaced. Mark deprecated and point to this design (the OKLab-correct revival, pending sanction).
4. **`docs/global-palette-skeleton-design.md`** (≈ lines 30/33/60/61) — still marks `quad4Analyze` / the 4-ary forward transform and round-trip law as "TO ADD"; they **exist** in `Quad4.hs`. Also still marks `FlatPalette` and the unified `BranchedPalette` sum type as "TO ADD" — confirm/update against current spec.
5. Note the **un-wired 384-DOF `SigmaPairTree`** (open question #1) wherever the 2⁸ genome is described, so viz copy doesn't imply a 384-DOF σ-pair head exists.

---

## 7. Build plan (spec-first, ordered)

1. **Spec — `Spec.GridAxis`** (Haskell, golden vectors): scalar projections (L/a/b/chroma; **hue with pinned wrap-origin**), fixed-canonical-range balanced-quantile binning, deterministic O(256) nearest-empty-cell collision resolution reusing the `(coord, index)` tie-break. `cabal test` green.
2. **Spec — genome ghost path:** confirm/expose `Quad4.quad4Analyze`/`reconstruct` and `PairTree.sigmaReflect` actions with golden vectors for the cloud's 4⁴ projection-error and σ-mirror. Fix `global-palette-skeleton-design.md` drift (§6.4).
3. **Codegen + gate:** `cabal run spec-codegen` → regenerate contracts; do not hand-edit `SixFour/Generated/`.
4. **Doc-drift fixes** (§6.1–6.3, 6.5) — independent, land immediately.
5. **Swift — grid:** `SixFour/Palette/GridLayout.swift` (pure `GridAxis` + `bin(...)`, verified bit-for-bit vs goldens) → `SixFour/UI/Components/PaletteGridView.swift` (Canvas + per-frame scalar cache + per-cell a11y).
6. **Swift — cloud (only if sanctioned):** `SixFour/UI/Components/PaletteCloudView.swift` — port the old projection skeleton with REAL OKLab positions, off-main per-frame geometry precompute, AABB hulls, population-driven radius, fixed hit-test, collapsed-summary a11y + reduce-motion static fallback.
7. **Settings:** add `paletteRepresentation`/`gridAxisX`/`gridAxisY` keys to `AppSettings`; mirror in `SettingsView`.
8. **Review integration:** add the Representation glass selector (clone `ScopeSelector` capsule pattern) and restructure `paletteStructure()` into contextual 2-level chrome; reuse `BranchingSelector`/`ScopeSelector`/`GlassToolbarCluster` unchanged.
9. **Build gate:** `cabal build && cabal test && cabal run spec-codegen` → `xcodegen generate` → `xcodebuild -scheme SixFour -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build`.
