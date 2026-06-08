# SixFour — The Palette *Is* Motion: Collapse Levers & Color-Time Dynamics (first-principles derivation + workflow)

> Keywords: Wasserstein barycenter, displacement interpolation, McCann geodesic, Benamou-Brenier,
> optimal transport, palette-as-measure, RGBT, color cycling, brightness constancy, temporal Haar bands,
> octree LOD, wavelet packet cut-level, 256=4^4=2^8=16^2, collapse, flux advection.

**Status:** theory + workflow (2026-06-07). Companion to `SIXFOUR-JEPA-256-SUPERRES-WORKFLOW.md`.
**SixFour owns all code.** QUAD is a separate project, **reference only** — its R,G,B,T proposal is
*derived from first principles below* and reimplemented as SixFour-owned spec+golden+Zig.

This doc answers two questions the project kept circling:
1. **How can `256 = 4⁴ = 2⁸ = 16²` act as *levers in the collapse* of the 64 per-frame palettes — given
   that the palette *deltas between frames carry motion*?**
2. **How is there *spatial and temporal motion in color*?** (QUAD answered "R,G,B,T"; here we *derive* it.)

---

## 0. The one idea everything rests on: a palette is a measure

A frame's palette is not a list of colors — it is a **discrete probability measure** over OKLab space:

```
μ_t = Σ_{j=1..256} a_j δ_{x_j},   x_j ∈ OKLab (L,a,b),   a_j = pixel mass,   Σ a_j = 1
```

The 64 frames are therefore a **trajectory of measures** `μ_1 … μ_64` — a *curve in Wasserstein space*.
The ground cost is `c(x,y)=‖x−y‖²` in OKLab, which is the *right* cost because OKLab is built so that
Euclidean distance ≈ perceptual difference. **Cost and color space are matched.** Everything below is
the geometry of that curve. (This is precisely the "collapse = Wasserstein barycenter" framing already in
`sixfour-diversity-spec`; this doc supplies the math under it and the motion read-out it was missing.)

---

## 1. Question 2, derived first: where is the "motion in color"?

### 1.1 Two orthogonal projections of scene change
- **Spatial optical flow is blind to the palette.** Brightness/color constancy (Horn–Schunck 1981):
  a rigid, constant-color object that merely *translates* is a permutation of pixel positions → the color
  histogram is **invariant**. Flow lives in `(x,y)` and leaves `μ_t` unchanged.
- **The palette delta is blind to rigid motion but sees appearance change.** A *non-zero* `μ_{t+1}−μ_t`
  **requires a brightness-constancy violation**: illumination/exposure change, occlusion/disocclusion
  (new colors revealed), deformation, objects entering/leaving frame. These are exactly the cases flow
  cannot handle (Sevilla-Lara et al., *Channel Constancy*, ECCV 2014; BrightFlow, WACV 2023).

> **Result (the keystone):** spatial motion and color motion are **orthogonal, complementary projections**
> of the same scene change. Flow = *geometric* transport in `(x,y)`. Palette delta = *photometric /
> appearance* transport in OKLab. Neither is a superset; a constant-color in-silhouette deformation is
> invisible to both. **You need both axes to span motion — which is what R,G,B,T is.**

### 1.2 R,G,B,T derived
- **R,G,B** = the color/appearance axes: *where* mass sits in OKLab **and how it transports there over
  time**. The transport of color mass *is* the appearance-motion.
- **T** is **not a 4th spatial axis** — it is the **evolution axis** along which the measure moves, and
  that evolution is the appearance-motion itself. A "tesseract cell" is therefore **not a color** but a
  **(color-region × temporal-band) pair**: how that color's presence behaves in time.
- This `(color bin) × (temporal Haar band)` lattice is a **novel composition** of established primitives
  (color histograms × temporal wavelet of per-color time series, Töreyin–Çetin PRL 2006; spatiotemporal
  volume, Bolles–Baker–Marimont IJCV 1987). Present it as ours, not as a cited "RGBT histogram."

### 1.3 The motion is literally fluid flow of color (Benamou–Brenier)
Color mass moving through OKLab over time obeys a **continuity equation** — it is a fluid:

```
∂_t ρ + ∇·(ρ v) = 0 ,     W₂²(μ_0,μ_1) = inf_{ρ,v} ∫₀¹∫ ρ‖v‖² dx dt   (Benamou–Brenier 2000)
```

`v_t` is the **velocity field of the color mass** = the motion. `∫ρ‖v‖²` is a single scalar **"amount of
color motion"** per frame-pair — a free motion-energy readout. *Motion in color is not a metaphor; it is
the optimal-transport velocity field of the palette measure.*

**Historical existence proof:** *color cycling / palette animation* (Mark Ferrari; Amiga/VGA CLUT) made
water, rain, fire flow with **pixels frozen and only the palette changing**. Motion provably lives in the
palette. Our pipeline is its dual: they *drive* motion from the palette; we *read* motion out of it.

---

## 2. Question 1: the collapse, and the factorization as a lever

### 2.1 Collapse = Wasserstein barycenter (the static "central pose")
The global palette is the **W₂ barycenter** of the 64 per-frame palettes (Agueh–Carlier 2011, eq. 1.1):

```
μ̄ = argmin_ν  (1/64) Σ_{i=1..64} W₂²(μ_i, ν)        (Fréchet mean in Wasserstein space)
```

This is **mass-transport averaging, not pixel averaging**: a translating blob is placed at its mean
position with shape intact, where a linear mean `(1/64)Σμ_i` would smear it into a streak.

> **Honest caveat (carry it):** the barycenter is the *Fréchet mean* = the **central / midpoint pose**, not
> literally "the stationary part." For monotone color drift it is the `t=½` pose, not a fixed background.
> Use it as the **reference frame we measure displacement against**, and call it that. (Also: Agueh–Carlier
> *uniqueness* needs an absolutely-continuous input, which 256-atom palettes are not — see §4 determinism.)

### 2.2 The motion field = displacement from the barycenter
Each frame is the barycenter pushed forward by its Brenier map (Agueh–Carlier Prop. 3.8):
`μ_t = (∇φ_t)_# μ̄`. Define the **color-mass motion field** on μ̄'s support:

```
v_t(x) = ∇φ_t(x) − x = T_{μ̄→μ_t}(x) − x          ( = log_{μ̄} μ_t , the Wasserstein/LOT tangent )
```

`v_{t+1} − v_t` is color-mass **velocity**. **This is exactly the user's claim made precise:** collapse
splits the palette trajectory into **(static barycenter μ̄) ⊕ (motion residual v_t)**. *The motion is in
the residual.*

### 2.3 `256 = 2⁸ = 4⁴ = 16²` — three trees, and the **cut-level is the lever**
These are three **multiresolution trees over the same 256-leaf codebook** (Mallat MRA; wavelet packets,
Coifman–Wickerhauser 1992; octree color quantization, Gervautz–Purgathofer 1988). Cutting a tree at level
`k` is a **low-pass / coarsening (LOD) operation**: the level-`k` *approximation* is how many color
clusters survive; everything finer is *detail/residual*.

> **The lever (answer to Q1):** the **(tree choice, cut level)** sets **how much motion detail is folded
> INTO the static global palette vs kept as live residual `v_t`.**
> - **Cut high (coarse, near root):** few clusters carry the palette → *more* motion bundled into μ̄ →
>   flatter, calmer render, less per-frame variation.
> - **Cut low (fine, near leaves):** many clusters → *less* bundled → more motion preserved as recoverable
>   residual for the temporal super-res.

Each tree gives a *different kind* of knob:
| Tree | Shape | What collapsing it does |
|---|---|---|
| **2⁸** binary Haar (depth 8) | finest octave control | smooth coarse↔fine motion-bandwidth sweep |
| **4⁴ = R,G,B,T** (depth 4) | **collapse along a chosen axis** | along **T** = temporal pooling → average motion *out* → static palette; along **R/G/B** = drop color resolution on one channel. A 4-knob mixer. |
| **16²** (two-level) | 16 themes × 16 variations | matches SixFour's existing 16×16 authoring grid UI |

### 2.4 Why this *is* the user's authorship lever (ties to agency)
Collapse (down) and super-res (up) are the **same ladder run in opposite directions**. The cut level
controls the down-map; *therefore it also controls the up-map* — how much of the 256³ temporal motion is
deterministically reconstructed from the residual bands vs smoothed away. **The 16³ histogram the user
edits IS this cut.** Editing there = **setting the motion-bandwidth of the entire render.** That is the
strongest possible single lever, because it sits at the waist both directions pass through.

---

## 3. The deterministic temporal super-res engine (64→256 frames)

Temporal upsampling = **sample McCann's displacement geodesic at more t** (McCann 1997, eq. 7):

```
μ_t = [ (1−t)·id + t·T ]_# μ_0 ,   T = Brenier map μ_0→μ_1
    = Σ_j m_j δ_{ (1−t) x_j + t y_σ(j) }        (each color slides a straight OKLab line, constant speed)
```

Deterministic, **mass-conserving, ghosting-free**, and strictly better than linear histogram cross-fade
(which double-images and desaturates). **This is the color analog of flux advection:** flux advects pixels
in `(x,y)` (geometric); displacement interpolation advects color mass in OKLab (photometric). Run **both**
and you have the full R,G,B,T motion — the two complementary projections of §1.1, recombined.

---

## 4. On-device determinism (iPhone, byte-exact Zig core)

Prefer the **1D closed forms** — exact, deterministic, no tuning parameter, `O(n log n)`:
- **W₂ on ℝ via inverse CDFs; OT map = monotone rearrangement (sort + match in order).** On the **L axis
  this is exact and free** — fits SixFour's existing **L→A→B** workflow (`a=b=0` ⇒ pure 1D on L).
- **Full OKLab:** sliced Wasserstein — project onto a **fixed** set of `K` directions, sort/advect each,
  average (Bonneel–Rabin–Peyré 2015). Deterministic iff the direction set is fixed.
- **1D barycenter is closed form:** `F⁻¹_{μ̄} = Σ λ_i F⁻¹_{μ_i}` (average of inverse-CDFs) — exact, cheap.
- Sinkhorn (entropic OT, Cuturi 2013, arXiv:1306.0895) on 256×256 is µs/pair but **blurs the plan**; only
  use it with **fixed λ + fixed iteration count** if a sharp 1D/sliced map isn't enough.

> Consequence worth noting: the W₂ **barycenter collapse is computable deterministically** (1D/sliced).
> Per the Lloyd-Max discipline (*don't learn what you can compute*), this can **replace the deferred
> NN collapse** (`NetSlotCollapse`) — the current shipped `s4_global_collapse` is *maximin/diversity*, not
> a barycenter; this workflow adds the barycenter as an owned deterministic kernel.

---

## 5. Workflow — spec-first phases (all SixFour-owned)

Each phase: **Haskell `Spec.*` oracle → golden vectors → byte-exact Zig kernel → Swift/Metal**, Layers
0–2 + goldens (`SIXFOUR-SPEC-METHODOLOGY.md`). Reuse owned `s4_haar_*` (`kernels.zig:497`) and the
maximin `s4_global_collapse` (`kernels.zig:459`).

- **Phase 0 — Palette-as-measure.** `Spec.PaletteMeasure`: palette = discrete OKLab Q16 measure (support
  + mass). Golden vectors. The shared type for everything below.
- **Phase 1 — W₂ collapse (barycenter), 1D-first.** `Spec.WBarycenter` + `s4_wbarycenter_1d` (inverse-CDF
  average on L), then sliced for full OKLab. Deterministic global palette = the central pose μ̄. *Decide:
  barycenter replaces or co-exists with maximin collapse (diversity vs centrality are different objects).*
- **Phase 2 — Displacement / motion field.** `Spec.Displacement` + `s4_ot_map_1d` (monotone rearrangement)
  → `v_t = T_{μ̄→μ_t} − x`. Emit per-frame color-mass velocity + scalar motion-energy `∫ρ‖v‖²`. **This is
  the motion extractor.**
- **Phase 3 — Temporal bands (the T axis).** Per-color 64-length presence curve → **temporal Haar**
  (reuse `s4_haar_*` on the *time* axis) → 4 bands. Physical reading (interpretive, not theorem; watch
  aliasing): **DC = static palette / low = lighting drift / mid = object motion·(dis)occlusion / high =
  flicker·fast·noise.** This realizes QUAD's **T** as 4 temporal-frequency bands.
- **Phase 4 — The collapse lever.** `Spec.CollapseLever`: `(tree ∈ {2⁸,4⁴,16²}, cut-level)` → how much
  `v_t` residual folds into μ̄. The user's control surface; wire to the 16³ histogram editor + existing
  radix views. 4⁴ exposes the R,G,B,T 4-knob mixer; 16² maps to the 16×16 grid UI.
- **Phase 5 — Deterministic temporal super-res (color).** `Spec.DisplacementInterp` +
  `s4_displacement_interp`: sample McCann geodesics 64→256 along OT maps. The byte-exact color-motion
  engine; complementary to spatial flux advection.
- **Phase 6 — Couple to spatial flux (full R,G,B,T render).** Combine OKLab displacement (appearance) with
  `(x,y)` flux advection (geometry, from the 256-superres workflow) → unified 256³ motion. Disoccluded
  voxels (no source under either projection) are the *only* genuinely under-determined remainder → the
  single small learned/gated head from the companion doc.

---

## 6. Caveats to keep honest
- **Barycenter ≠ stationary** for monotone drift (it's the midpoint pose). It is the *reference*, §2.1.
- **Atomic-measure uniqueness fails** — use 1D/sliced (unique monotone map) or fixed-λ Sinkhorn, §4.
- **Flow ⟂ histogram, complementary not hierarchical** — some motion is invisible to both, §1.1.
- **Band→cause is interpretive**, not a theorem (aliasing; histogram is position-blind), §3-Phase 3.
- **`(color × temporal-band)` lattice is our novel composition**, not a cited prior "RGBT histogram," §1.2.

## 7. References
- Agueh & Carlier 2011, *Barycenters in the Wasserstein space*, SIAM J. Math. Anal. 43(2) (eq. 1.1; Prop. 3.5/3.8).
- McCann 1997, *A Convexity Principle for Interacting Gases*, Adv. Math. 128 (Def. 1.1, eq. 7 — displacement interpolation).
- Benamou & Brenier 2000, *A computational fluid mechanics solution…*, Numer. Math. 84 (kinetic-energy / continuity form).
- Cuturi 2013, *Sinkhorn Distances*, arXiv:1306.0895 · Cuturi & Doucet 2014, *Fast Wasserstein Barycenters*, arXiv:1310.4375.
- Bonneel, Rabin, Peyré, Pfister 2015, *Sliced and Radon Wasserstein Barycenters*, JMIV 51(1) (palette = measure; sliced OT).
- Horn & Schunck 1981, *Determining Optical Flow* (brightness constancy) · Sevilla-Lara et al. 2014, *Channel Constancy*, ECCV.
- Töreyin & Çetin 2006, temporal wavelet flame/flicker, Pattern Recognition Letters · Bolles–Baker–Marimont 1987, EPI volume, IJCV.
- Mallat, *A Wavelet Tour of Signal Processing* (MRA) · Coifman & Wickerhauser 1992, best-basis · Gervautz–Purgathofer 1988, octree quantization.
- Color cycling / palette animation — Mark J. Ferrari; Huckaby, *Old School Color Cycling with HTML5*.
