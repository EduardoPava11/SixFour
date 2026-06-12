# SixFour Palette Explorer — Honest Dimensionality Upgrade

> ▶ **CONSOLIDATED (2026-06-12):** architecture authority is now
> [`SIXFOUR-WIDGETS.md`](SIXFOUR-WIDGETS.md) (Family 2 — Delta Control; the 16²/4⁴/2⁸
> see/control/learn faces). This doc is the *honesty/dimensionality detail* under that
> family. SIXFOUR-WIDGETS wins on architecture.

**Status:** Design (spec-first). Extends `docs/palette-explorer-2d-3d-4d-design.md`; governed by `docs/SIXFOUR-DESIGN-LANGUAGE.md` (GRID) and `docs/SIXFOUR-TOTAL-PIXELATION.md` (glass retired; the former GLASS doc is archived at `docs/archive/SIXFOUR-GLASS-LANGUAGE.md`).
**Date:** 2026-06-01
**Contract:** Tier-2 (ships) — zero third-party deps, Apple frameworks + `simd` only; every new numeric is a Haskell-spec golden before any Swift lands.

---

## 0. The thesis: three different things are all called "dimension"

SixFour must DISPLAY HIGHER DIMENSIONS honestly. The blocker is not rendering technology — it is a conflation baked into the UI copy. Disentangle once, then build:

| Name | What it is | Honest ceiling | How a 2D screen shows it |
|---|---|---|---|
| **DATA dim** | A colour is OKLab `(L,a,b)` — **3D**. A GIF is `x,y,t` — **3D**. The GIF is a 64×64×64 field of 3D colours. | palette **4D** = `(L,a,b)` + time; GIF **3D** = `x,y,t` | orthographic projection (distance is real) + interaction for the axes that don't fit |
| **ADDRESSING dim** | `256 = 16² = 4⁴ = 2⁸` are **radix factorizations of the 256-index space**. ONE median-cut `SplitTree` read at three granularities (`collapseK = 4/2/1`, `factor^depth = 256`). | "2⁸ = 8D" means an address is **8 split bits over the SAME 3-space** | nesting (dimension-stacking / treemap) or a Morton bit-interleave reorder |
| **REPRESENTATION** | the screen is **2D**. | — | projection + slicing/brushing + non-positional channels |

**The exponent in `2⁸` is depth-of-tree, never data dimensionality.** Each split cuts the *widest* of `L/a/b` at a median plane (`SplitTree.widestAxis`), so the 8 levels are 8 binary decisions over 3 perceptual axes — not 8 independent features. `2⁸=8D` is the relabel-the-bits trap, and the app's own copy currently falls into it.

---

## 1. Critique of the current tools (be critical)

Verified against the code. Five sites where claim diverges from fact:

1. **`SplitTree.swift:52`** — `.b4` blurb "Quadtree … (two OKLab axes per split)" is **false**: `widestAxis` picks ONE axis per binary split; greyscale splits `L,L,L,L`. Also courts the `SplitTree`↔`Quad4` conflation §3-rule-1 forbids (the NN `Quad4` is a 513-DOF lossy opponent projection, a different object).
2. **`SplitTree.swift:51`** — `.b16` "Flat 16×16 grid" invites a coordinate reading; it is two collapsed binary *nesting* levels. The real coordinate grid is the separate `GridLayout`/`PaletteGridView`. Two tools, one "16²" label.
3. **`PaletteTreeView.swift:63-78`** — split planes drawn by depth but **never labelled** with the `(axis,pos)` they carry. Structure is faithful; its meaning is invisible.
4. **`PaletteGridView`** — fails the §2.2 ship gate: no per-cell `accessibilityValue`; bins per-frame (colours migrate) instead of fixed-canonical-range.
5. **`VoxelCubeView.swift:7`** — mislabeled "3D member of the palette-explorer family"; it renders GIF `x,y,t` pixels, not the 256-colour OKLab palette. It is genuinely the *honest* `x,y,t` explorer (orthographic, fixed scale, 2D↔3D rest identity, one discrete per-face brightness, no opacity on a voxel) — the label is the bug, and the promised `PaletteCloudView` is unbuilt.

**Net:** the app under-claims where it is honest (the cube), and is silent where it should annotate (the branchings). It contains **no** distance-faking embedding (no t-SNE/SOM/PCA) — correct, and must stay that way.

---

## 2. Disallowed (the be-critical mandate)

- **t-SNE / UMAP / SOM / trained autoencoder** — non-deterministic (un-golden-pinnable, off the Haskell contract), dishonest about distance, and pointless given a meaningful 3-space. **Never.**
- **Tesseract / 8-cube unfolding** or **PCP/SPLOM "with 8 axes"** — the 256-vertex hypercube is an unreadable hairball and its axes are split-bits, not features. The relabel-2D trap.
- **Hinton cell-size** — violates GRID Law #1 (one cell size).
- **VR / RealityKit / SceneKit** — off-contract (2D-screen target; breaks the byte-exact 2D match; the cloud is hand-written Canvas).
- **Any `mirror-pair` / `parent±δ` / `mean-of-leaves = root` language on the SplitTree** — those are PairTree/`Quad4`/σ properties the median-cut SplitTree does NOT satisfy (§3-rule-1). A root marker, if drawn, is "pooled mean (barycenter)" from `ClusterStatisticsOps.pooledMean`.
- **4⁴ drawn as lossless** — tag it "split-tree address (4-ary collapse)" or route through the `Quad4` spec with 768→513 ghost+arrow projection-error (§3-rule-2).

---

## 3. Proposals (each carries its honesty argument)

### P1 — Brushing + linking (medium)
One shared selected-index set (keyed by `IndexedColor.index`) through `GIFReviewView.paletteStructure()`. Tap a `NaryNode` subtree / grid cell / voxel region → the same indices light in every mode via an **opaque darker index step** (GRID Law #2; never alpha). Honest: every highlight is a real `descendants(at:k)` member shown at its true coordinate. Selection chrome is GLASS.

### P2 — Interactive SplitTree drill-down + `(axis,pos)` breadcrumb (medium)
Branching selector becomes the zoom-granularity knob (`collapseK` levels/tap). Tap pushes into a subtree; the split plane animates; a glass breadcrumb spells the address ("split L@0.52 hi · split a@0.11 lo …"). **The view that makes 2⁸/4⁴/16² honest** — the user watches 8 binary OKLab splits compose an address. Language guard: "split"/"half-set", never "mirror"/"mean=root".

### P3 — Treemap split-axis labelling (small, do first)
`CellGlyph` axis tags (`L/a/b`) + median pos on the shallow borders + a chrome legend. Purely additive truth from data the tree already computed. Lets us delete the false `.b4` blurb.

### P4 — OKLab Temporal Cloud (large, sanction-gated)
3 OKLab axes (true coords) + scrubbable time = honest **4D**; population→radius. Orthographic snap carries the "screen distance = perceptual distance" claim; perspective is "explore" with the claim removed. Motion trails = a colour's trajectory. Hand-written Canvas + `simd`, 256 dots. Reduce-Motion → static streak. `4⁴` hull tagged lossy. **Blocked on user sanction** (`feedback_sixfour_palette_viz`).

### P5 — Re-home the VoxelCube + cross-filter + small-multiples (medium)
Correct the docs: it is the `x,y,t` GIF-cube explorer. Keep orthographic default; perspective labelled. Add an ~8-frame (labelled-lossy) filmstrip + trails to defeat change-blindness. Generalize the `airMask` into a cross-filter shared by all three views, with an "N of 256 shown" readout.

### P6 — Grid honesty + prosection slice + Morton toggle (medium)
Ship-gate fixes: per-cell `accessibilityValue` + fixed-canonical-range binning (colours stay put). Add a glass 3rd-OKLab-axis prosection slider + chroma/hue band-pass (a true gamut slice). Layout toggle `rank / Morton / Hilbert` (deterministic permutations, golden-pinned). Label honestly: the grid is **ordinal placement** (uniform-by-rank), not a metric map. Morton is "address-order", not "8D".

---

## 4. Honesty test (apply to every future palette view)

> A projection becomes a LIE exactly when the viewer reads geometric meaning into a channel that doesn't carry it.

- Is screen-distance interpreted as data-distance? Then the map MUST preserve distance (orthographic only; never SOM/t-SNE/low-variance PCA).
- Does occlusion/collapse silently destroy points? Then provide a slice/threshold/front-most-wins pick.
- Is an ADDRESS bit being sold as a DATA feature? Then re-label: 8 bits over a 3-space.
- Is the SplitTree borrowing PairTree/`Quad4` mirror/mean/lossless language? Forbidden.

If a dimensionality **cannot** be honestly shown (e.g. "8 independent feature axes"), say so — it does not exist here. The best honest approximation is the address shown as nesting/drill-down, and the data shown as orthographic-3D + scrubbable time.

---

## 5. Phased plan

0. **Doc & label truth** — delete false blurbs, fix cube/globe labels, write the three-dimension disentanglement into NOTES.
1. **Treemap axis labels** (P3) — golden the `(axis,pos)` read; ship tags + legend + a11y.
2. **Brushing + linking** (P1) — shared index set, opaque-step highlight, single spoken summary.
3. **Drill-down + breadcrumb** (P2) — branching-as-zoom, address spelled, §3-rule-1 language guard.
4. **Grid honesty + prosection + Morton** (P6) — a11y gate, fixed binning, slice slider, layout toggle.
5. **Cube re-home + cross-filter + filmstrip** (P5).
6. **OKLab Temporal Cloud** (P4) — spec-first; **only if sanctioned**.

## 6. Contract alignment

- **Zero-dep:** ✅ all SwiftUI `Canvas`/`PixelImage`/`simd`/`TimelineView`; the cube keeps its hand-written Metal raymarcher.
- **GRID:** highlights/cells are opaque indexed (Law #2); chrome (breadcrumb, sliders, pills, legend) is GLASS; per-slice opacity stays a GATE-DECISIONS exception, never drifted in.
- **Canonical branching:** every new view rides ONE `SplitTree` via `collapse(k)`/`descendants(at:)`; `4⁴` always tagged lossy; `2⁸`/PairTree-σ language kept off the SplitTree.
- **Spec-first:** `(axis,pos)` read, fixed-range binning, Morton/Hilbert permutations, cloud OKLab→world constants + AABB hulls + `Quad4` ghost — all golden-pinned before Swift. `cabal test` gates.

---

## 7. Adversarial critic's verdict & required adjustments

An independent critic attacked every proposal with "is it really nD, or 2D-with-labels?" and verified all five audit sites against source. Survivors, with the corrections that MUST hold:

- **P3 (label split axes) — survives, DO FIRST.** Smallest, truest. Must surface the **data-dependent axis SEQUENCE** (e.g. greyscale → `L,L,L,L`), not just two shallow tags; the legend must state the sequence is emergent, not a fixed interleave.
- **P2 (drill-down + breadcrumb) — survives, the core honesty win.** Caveat: it does **not** show 8 dimensions — it shows that there are **not** 8. Discipline: the perception MUST live in the **split-PLANE/nesting geometry**, not the breadcrumb text (test: hide the text — is the cut still readable?). Keep a context treemap so it isn't a serial-only tour.
- **P1 (brushing + linking) — survives DEMOTED.** It is a **correlation / co-membership** instrument, NOT proof of OKLab compactness (no shipped view is metric-true until P4). Reword the honesty claim and sequence it **after** a metric-true view.
- **P4 (OKLab cloud) — survives, the ONLY genuinely-new perceivable axis (time); sanction-gated, LAST.** Reframe the claim: **2 axes on-screen + 1 by orbit + time by scrub**, not "simultaneous 4D." Make **orthographic the sticky default** (perspective-by-habit relaunders the distance lie). Concede the time axis collapses under Reduce-Motion.
- **P5 (re-home cube) — survives, but the win is SUBTRACTIVE** (stop mislabeling it), plus navigability — **not** new dimensionality. **DROP or hard-gate the per-slice opacity** mode; prefer opaque dark index steps (it's the one place a GRID Law #2 violation could drift in).
- **P6 — must be SPLIT.** **P6a** (prosection slider + the two grid ship-gate fixes: per-cell `accessibilityValue` + fixed-canonical-range binning) is **mandatory truth — promote it.** **Morton/Hilbert is REJECTED as specified**: it would interleave bits of `IndexedColor.index` (the arbitrary input-order tie-break key, `SplitTree.swift:29-31`), **not** the SplitTree lo/hi address whose 16²/4⁴/2⁸ factorization it claims to reveal. Reject unless **rekeyed to the actual SplitTree leaf-order/address**.

**Load-bearing disciplines (non-negotiable):** (1) the address-view's perception lives in geometry, not text; (2) any "distance" claim is valid ONLY under orthographic, which must be the sticky default; (3) no embedding (t-SNE/SOM/PCA), ever; (4) Phase 0 doc/label truth is the highest truth-per-line work and lands first.

---

## 8. P4 as-built (2026-06-01) — salvaged from a stalled workflow

P4 was built ahead of plan: `SixFour/UI/Components/PaletteCloudView.swift` (SwiftUI Canvas, 256 OKLab dots, orthographic-sticky + orbit + scrub + trails + brush, `#Preview` with synthetic data), wired as the `.cloud` `RepresentationSelector` mode, backed by a golden-pinned Haskell spec `SixFour.Spec.CloudProjection` (+ `Properties.CloudProjection`). Verified: Swift `BUILD SUCCEEDED`; **all 382 spec tests pass**, including the honesty laws (`worldDist = scale·oklabDist` isometry, orbit-preserves-distance, orthographic 1-Lipschitz, perspective-distorts, hull-contains-all, Quad4-ghost-zero-on-subspace).

An adversarial review confirmed it is **a genuine 3D+time projection, not 2D-with-labels**, and flagged fixes that have been applied: **(1)** trails were faded with alpha (a GRID Law #2 breach) → now **opaque** (age shown by darker index-step + smaller radius); **(2)** the "ported scalar-for-scalar / verified bit-for-bit" claim was retracted — `rotateYawPitch`/`oklabToWorld` match, but there is no codegen emitter/parity test yet. **Remaining debt (not shipped):** a `Codegen.CloudProjection` emitter + golden-vector parity test (closing the perspective-`eye` and population→radius-range divergences, which are explore/renderer concerns carrying no distance claim); and the **4⁴/Quad4 lossy AABB hull is spec'd but NOT drawn** — a future step, not a present feature.
