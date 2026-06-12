# SixFour — "JEPA" → 256³ Residual Super-Resolution: Architecture & Workflow

> Keywords for grep: JEPA, V-JEPA, 3D-JEPA, RQ-VAE, VAR, next-scale, residual quantization,
> wavelet super-resolution, flux advection, 4^4 tesseract, cube ladder, 64->256.

**Status:** design (2026-06-07). No code yet. This doc makes the architecture call and lays out a
spec-first build. It supersedes the framing in the pasted "H-JEPA / I-JEPA" analysis that kicked this off.

> **AMENDMENT 2026-06-12 (TWO-256³ correction).** This doc's singular "ship a 256³ render" framing is
> superseded: there are **TWO 256³ products**, each a literal **256×256×256** cube (256 px × 256 px ×
> 256 frames). **Product A = 256³ per-frame** (direct super-res of the per-frame cube, diversity-max =
> HD GIFA). **Product B = 256³ global** (seeded by comparing `64³ per-frame ⟷ 64³ global`; the measured
> per-frame↔global displacement is the residual that drives B = HD GIFB). The RQ-VAE / VAR architecture
> below serves **both**: A is the direct branch, B is the residual-seeded branch. Both tile/stream
> (16.7M voxels each, export-only), and **both are trainable AND shareable** (no archival-only split). §8.3
> below ("product or quality lever") is resolved: **both are products.** Source: `docs/SIXFOUR-APP-WIDGET-
> GAP-REPORT.md` §4 (pipeline) + §8 (Decisions 4 & 5).

---

## 0. TL;DR — the verdict

The goal: from a captured **64-frame, 64×64 burst**, let the user simplify color to **one global
palette** (authored at a coarse **16³ OKLab abstraction**) and **ship two 256×256×256 renders** (256px ×
256px × 256 frames each — Product A per-frame / Product B global; see AMENDMENT).

**This is not a JEPA problem.** JEPA predicts *embeddings* and refuses to synthesize pixels; shipping a
256³ cube is a *generative synthesis* problem. The architecture that matches the user's own intuition —
*"shared 4⁴=256 codebook + scale-tied residual, coarse→fine"* — already exists and is SOTA-validated:

- **RQ-VAE** (Lee et al. 2022, arXiv:2203.01941): one **shared codebook**, each depth quantizes the
  **residual** of the previous: `r_d = r_{d-1} − e(k_d)`, partial recon `ẑ^(d) = Σ_{i≤d} e(k_i)`.
  "Recursive quantization approximates `z` coarse-to-fine." Capacity `K^D` without growing `K`.
- **VAR** (Tian et al. 2024, arXiv:2404.02905): the same skeleton across **resolution** — next-scale
  prediction `p(r_1..r_K) = ∏_k p(r_k | r_{<k})`, shared codebook `Z` across scales, each scale = the
  quantized residual after coarser scales are upsampled and subtracted (`f ← f − φ_k(up(lookup(Z,r_k)))`).
- **arXiv:2510.02826** proves VAR's next-scale step *is* a Laplacian-pyramid / discrete-diffusion detail
  refiner — i.e. literally "predict the detail subband the coarse upsample missed." Exactly this design.

**The cited paper, arXiv:2409.15803 (3D-JEPA), is single-scale** (I-JEPA lifted to point clouds; no
pyramid, no wavelet, no scale-tying). Do not anchor on it. Its one reusable trick is the *context-aware
decoder* (cross-attention injecting context into every decoder layer), which we do not need.

**The build is therefore small:** a deterministic core you mostly already own (Haar + collapse + flux +
cascade) produces the next rung; a **thin additive residual predictor** corrects only what the
deterministic part provably cannot compute; a **single fixed-point VQ decoder pass** emits voxels.

---

## 1. The question restated in real coordinates

Two distinct cubes, kept apart (conflating them is the classic trap):

- **Cube A — the render cube (x, y, t):** the GIF/voxel field. SixFour today = `64×64×64` indices
  (`Spec/Indices.hs`). Target = `256×256×256`.
- **Cube B — the color codebook (OKLab):** the palette. SixFour today = 256 OKLab leaves. The "16³" the
  user edits is **not a palette** — it is the **OKLab histogram** (4096 bins), already in the repo as
  *"a probability simplex over the OKLab distribution, NOT a palette face"* (`L-NN-MASTER-DESIGN.md:145`).

A palette (Cube B) is the **codomain**; it cannot define the **field** (Cube A). So "the global palette
defines the bigger render" is only true in the constrained sense that the palette fixes *which colors are
allowed*; the spatial/temporal *structure* of the 64×-larger field has to come from the deterministic
upscale of the existing render plus a learned residual. That split is the whole design.

### 1.1 The user's settled constraints
- **4⁴ idea (from QUAD):** the codebook is **256 = 4⁴** entries; the cube ladder is `{16, 64, 256} =
  {4², 4³, 4⁴}` (×4 per linear axis). Commit to **×4 branching everywhere** — this dissolves the earlier
  "dyadic vs quaternary" conflict in SixFour's mixed 2⁸-Haar.
- **Spatial 64→256:** **deterministic enlarge** (no hallucination on the matched content).
- **Temporal 64→256:** **deterministic flux advection** (invented motion, but model-free & byte-exact).
- **Ship the two 256³ products** (A per-frame, B global; see AMENDMENT) — the container is *not* a GIF
  (GIF caps at a 256-color *palette* and at this size; the 256³ is a *256-index* cube, not a 256-entry
  palette; see §4.3).

### 1.2 The three "fours" — keep them distinct
| "4" | meaning | role |
|---|---|---|
| cube-ladder ratio ×4 | side 16→64→256 (×4 per linear axis, ×64 per 3D volume) | the **scale step** (VAR's `k`) |
| codebook 4⁴ = 256 | 4 axes × 4 levels = 256 entries = one byte | the **shared codebook** (RQ's `C`) |
| RQ depth D | # residual stages = # ladder rungs (2 steps / 3 levels) | the **residual depth** (RQ's `d`) |

They rhyme (the user likes that), but they are different axes. Do not collapse them in code.

---

## 2. Architecture verdict (why this, not that)

| Candidate | Verdict | Reason |
|---|---|---|
| **RQ/VAR residual quantization** over shared 256 codebook | **ADOPT (spine)** | *Is* the user's design; SOTA; discrete ⇒ byte-exact-friendly; single-pass decode. |
| Deterministic baseline + learned **additive residual** | **ADOPT** | SR canon: VDSR global residual (1511.04587), LapSRN per-level (1704.03915), DWSR wavelet subband (Guo 2017). "Greatly reduces training burden"; net only learns HF. |
| Flux advection = **forward/softmax splatting** | **ADOPT (temporal core)** | Niklaus & Liu CVPR'20 (2003.05534). Sound deterministic in-betweening. |
| **JEPA-latent residual + decoder** | **REJECT for synthesis** | JEPA refuses pixels; decoder = diffusion (heaviest on-device) or INR (float, per-voxel, not byte-exact). Keep predict-in-latent only as optional aux loss (§5.3). |
| **VAR next-scale transformer (generative)** | **GATE** | Only over the genuinely under-determined residual (disocclusion fill). Costs a phone-GPU transformer + loss of byte-exactness (sampling). Not on the default path. |
| 3D-JEPA (2409.15803), the cited paper | **NOT a fit** | Single-scale; no pyramid/wavelet/scale-tying. |

**Principle (your own Lloyd-Max finding, generalized):** *don't learn what you can compute.* Deterministic
flux+Haar+cascade do ~90% (the computable part); the learned residual touches only the provably
under-determined remainder. This is why the model is small and why most of the pipeline stays byte-exact.

---

## 3. The deterministic core (Zig, fixed-point, byte-exact)

Most of this you already own. The core produces the **predicted next-rung cube** before any learning.

### 3.1 Color — collapse + Haar upsample
- **Collapse 64 per-frame palettes → one global 256 palette:** `s4_global_collapse` (`kernels.zig:459`),
  already byte-exact (Haskell `Spec/Collapse.hs` ≡ Zig ≡ Swift). **Currently has zero callers — wire it.**
- **16³ authoring abstraction:** new kernel `s4_oklab_histogram_16` → 4096-bin OKLab histogram. The user
  edits *this* (coarse, editable); the global 256 palette is the maximin/Lloyd **selection** on the edited
  histogram. (Open lemma — §8.1.)
- **Color super-res = inverse-Haar detail subband.** Reuse `s4_haar_reconstruct` / `s4_haar_level_nodes`
  (`kernels.zig:540,581`, exact reversible integer lifting). The deterministic LL (approximation) is
  carried analytically; only `{LH,HL,HH}` detail is a candidate for the learned residual (DWSR pattern).

### 3.2 Space — deterministic enlarge
- Bake indices→OKLab (`s4_palette_oklab_to_srgb8` path), **tricubic upsample in color space**, re-quantize
  through the global palette (argmin = deterministic). Indices never interpolate; colors do. New kernel
  `s4_upsample_requantize`.

### 3.3 Time — flux advection (QUAD's motion model)
- Port QUAD's **Bias** motion field: `Momentum` (Q15 per-axis-cell velocity) + `Flux` (Q8.8 spatial drift),
  1232 B/quartet (`QUAD-Codec/src/bias.zig`). New SixFour kernels `s4_flux_estimate`, `s4_flux_advect`.
- In-between frame = **average/summation splat** along the flux field (Niklaus 2003.05534).
- **Cascade warm-start** (QUAD `Cascade.hs:27`): carry the *dimensionless* rates (Q15/Q8.8) up the ladder
  unchanged; reset only resolution-dependent palette state. **This is the self-similarity, done right:**
  dimensionless rates are resolution-invariant *by construction*, so carrying them across {16,64,256} *is*
  the renormalization invariance — **no weight-tying, no stationarity assumption to test** (for motion;
  color stationarity stays open, §8.1).

---

## 4. The learned residual (the only "AI" on the default path)

Pure advection + inverse-Haar leave exactly three computable-failure gaps. The learned model covers
**only** these — additive, small, supervised per rung (LapSRN deep supervision + Charbonnier).

### 4.1 Three residual heads
1. **Color detail subband (`r_color`):** predict the residual `{LH,HL,HH}` *codes* against the shared 256
   codebook that inverse-Haar upsample misses. LL passes through analytically. (DWSR.)
2. **Occlusion / importance mask (`Z`):** the softmax-splat collision resolver. Pure advection can't order
   many-to-one collisions (foreground vs background) — `Z` (seeded from brightness-constancy, then a tiny
   learned scale) lets the nearer voxel win. (Softmax Splatting.)
3. **Disocclusion hole-fill (`r_holes`):** target voxels no source maps to (revealed regions). Fill from
   the frame where they *are* visible (warped feature pyramid + small synthesis net). This is the *only*
   genuinely generative gap — and the only place the gated VAR head (§4.4) may earn its keep.

> Note what is **not** here: the net does **not** re-synthesize matched content, does **not** predict the
> index map (argmin is deterministic), does **not** output per-frame palettes (GIFA is fixed by capture).

### 4.2 Residual is RQ/VAR over the shared codebook
- One shared **256-entry** codebook (RQ `C`, K=256). Entries are the **data-driven global OKLab palette**
  (from §3.1), *not* a fixed 2-bit grid — the "4⁴" supplies the **addressing radix** (the depth-4
  quaternary tree over 256, matching SixFour's existing 4⁴ radix view) and the **residual depth**, while
  the entries stay perceptual.
- Per ladder rung, one **`φ_k` conv** (VAR) absorbs upsample/interp error — the cheapest possible learned
  correction on the deterministic upsample.

### 4.3 Synthesis path (byte-exact)
- **Single fixed-point VQ decoder pass** → actual voxels (no diffusion, no iterative sampling). Codebook
  lookup is integer; only `φ_k` is float and tiny → fix-point it in the Zig core for cross-device
  byte-exactness. This is the lightest on-device synthesizer of the three options (vs diffusion / INR).
- **Container:** 256³ exceeds GIF (256-color cap + size). Ship **APNG / HEVC / a `.quad`-style TLV
  master**, optionally down-sampled back to a 64³ GIF for the legacy surface.

### 4.4 Gated generative head (optional, off by default)
- Only if disocclusion fill (`r_holes`) needs *hallucinated* detail: wrap that residual in a **VAR
  next-scale transformer** (`∏ p(r_k|r_{<k})`) — SOTA quality, but a phone-GPU transformer and **loss of
  byte-exactness** (sampling). Restrict it to the under-determined residual; never the whole cube.

---

## 5. Training

### 5.1 Losses
- **Reconstruction:** per-rung **Charbonnier** `ρ(x)=√(x²+ε²)` with **deep supervision** at {16,64,256}
  (LapSRN, 1704.03915), computed on the *residual* (`y_s − x_s`), never the full signal (VDSR, 1511.04587).
- **Commitment (RQ Eq. 7):** `L_commit = Σ_d ‖z − sg[ẑ^(d)]‖²` — summed over every partial depth so each
  prefix is itself a valid coarse code. **EMA codebook** update (matches `feedback_nn_training_approach`).
- **Perceptual:** ΔE in OKLab (you already have `okLab` loss in QUAD-Spec `Quad/NN/Loss.hs`).

### 5.2 Data
- QUAD/QUAD-Codec already has a **synthetic burst generator** (`synth.zig` `s4_synth_burst`) and the cube
  ladder — use it as the training data engine (matches `feedback_dither_abstraction`: capture/define real
  data first). Pair `(coarse rung, fine rung)` from real + synthetic bursts.

### 5.3 JEPA's only surviving role
- Optional **predict-in-latent auxiliary loss** on the code embeddings (cosine, 3D-JEPA Eq. 3 template) for
  representation regularization. **Off the synthesis path.** Drop if it doesn't move validation.

### 5.4 The honest ceiling (carry over from L-NN research)
- On MSE the deterministic part is near-optimal (Lloyd-Max ceiling). **Validate the residual on the gaps it
  exists for** (disocclusion fidelity, collision ordering, HF detail), not on global MSE — where it will
  look like a rounding error and tempt you to conclude "the NN does nothing."

---

## 6. Port map — what to mine from QUAD into SixFour

**SixFour owns all of this code.** QUAD is a **separate project** and a **reference only** — we read its
patterns and **reimplement them as SixFour's own kernels**, spec-first under `Spec.*` and `Native/`. No
shared core, no cross-linking, no "host in QUAD." SixFour is the app that ships; everything lands in
SixFour's repo as SixFour code.

| Need | Already in SixFour | Pattern to PORT (reimplement) from QUAD reference |
|---|---|---|
| Global palette collapse (byte-exact) | **`s4_global_collapse`** (`kernels.zig:459`) | — |
| Reversible integer Haar + level nodes | **`s4_haar_*`** (`kernels.zig:497`) | — |
| Shared 256 OKLab codebook, radix views | **palette stack, 4⁴/16²/2⁸ radix** | the 4⁴ addressing idea (concept only) |
| 16³ histogram authoring, significance | `s4_significance_fill`; **(new)** `s4_oklab_histogram_16` | — |
| Cube ladder {16,64,256}, 256³ target | **(new)** SixFour `Spec.CubeLadder` + kernels | QUAD `Cube.hs` (idea) |
| Motion field (Momentum/Flux) + advection | **(new)** SixFour `s4_flux_estimate/advect` | QUAD `bias.zig`, `MomentumSmoother.hs` (algorithm) |
| Cascade warm-start (scale-tied rates) | **(new)** SixFour `Spec.Cascade` + kernel | QUAD `Cascade.hs:27` (algorithm) |
| 256³ master container | **(new)** SixFour writer (APNG/HEVC/TLV) | QUAD `container.zig:99` (TLV layout idea) |
| Synthetic training bursts | **(new)** SixFour `synth` exe | QUAD `synth.zig` (generator idea) |

**Rule:** when a row says "PORT from QUAD," that means *study QUAD's reference, then write a fresh
SixFour Haskell spec + golden vectors + Zig kernel that SixFour owns and tests.* The QUAD files are
documentation, not a dependency. Reuse follows SixFour's own methodology (`SIXFOUR-SPEC-METHODOLOGY.md`)
and the existing owned Zig core (`sixfour-zig-quantized-core`).

---

## 7. Workflow — spec-first phases

Each phase follows `SIXFOUR-SPEC-METHODOLOGY.md`: **Haskell oracle → golden vectors → byte-exact Zig →
Swift/Metal**. Stay Layers 0–2 + golden vectors. A phase ships only when its golden gate is green.

- **Phase 0 — Stationarity & scope probe (measure before you commit).**
  Build `s4_oklab_histogram_16/64/256` + `Spec.Histogram` (Haskell golden). On **real captured bursts**,
  measure whether color detail-coefficient statistics are stationary across the two ×4 steps (the open
  commuting-square lemma, §8.1). *Go/no-go on tying the color residual across rungs.* Motion needs no such
  test (dimensionless rates, §3.3). **Deliverable: a data verdict, not theory.**

- **Phase 1 — Wire the deterministic spine (no learning).**
  Call `s4_global_collapse` (kill its zero-caller status) → global 256 palette. Add
  `s4_upsample_requantize` (color/space) and port `s4_flux_estimate` / `s4_flux_advect` + cascade from
  QUAD. Produce a **fully deterministic 64³→256³** render. *This alone may be shippable* — measure its
  quality before building any net.

- **Phase 2 — RQ residual skeleton (color detail subband).**
  `Spec.ResidualQuant` (RQ recursion, shared 256 codebook, commitment loss, EMA) + golden vectors + Zig
  `s4_rq_encode/decode`. Learn only `r_color = {LH,HL,HH}`. Deep-supervised Charbonnier. Fix-point the
  decoder for byte-exact synthesis.

- **Phase 3 — Motion residual (occlusion + holes).**
  Add the softmax-splat importance mask `Z` and disocclusion hole-fill `r_holes`. This is where advection
  stops being enough. Validate on the gaps (§5.4), not global MSE.

- **Phase 4 — Container + ship.**
  256³ master (APNG/HEVC/`.quad` TLV) + 64³ GIF down-sample for the legacy surface. Editor re-render from
  the master (non-destructive, QUAD `.quad` pattern).

- **Phase 5 — (gated) generative disocclusion head.**
  Only if Phase 3's hole-fill is visibly under-determined: VAR next-scale transformer over `r_holes` codes
  only. Accept non-byte-exactness there; keep the rest deterministic.

---

## 8. Open questions / risks

- **8.1 Color commuting-square lemma (the real Phase-0 risk).** Does the 256-palette computed at the 16³
  histogram equal the 256-palette at 64³ under an eigenspace law (`L-NN-MASTER-DESIGN.md:160`)? If **not
  stationary**, the color residual must *not* be tied across rungs — per-rung heads instead. Motion is
  fine regardless (dimensionless rates). **Measure on real data first.**
- **8.2 Byte-exactness vs the gated VAR head.** Sampling breaks cross-device determinism. Keep it walled
  off to the disocclusion residual; everything else stays fix-point.
- **8.3 64-canon break.** A 256³ shipped artifact breaks the cube-UI law, VoxelCubeView (64³), and the
  "64-frame burst" identity. **RESOLVED 2026-06-12 (AMENDMENT):** both 256³ are **products** (A per-frame,
  B global), each **export-only** — the interactive/canon surface stays 16³/64³, so the cube-UI law is
  preserved while export decodes the new product surface. The earlier "down-sample back to 64³ to keep the
  canon" option is no longer the plan.
- **8.4 Disocclusion honesty.** Advected motion is *invented*; large disocclusions = large hallucination.
  Cap the temporal upscale where flux confidence is low rather than fabricating motion wholesale.
- **8.5 "Don't out-engineer the deterministic baseline."** Phase 1 may already be good enough. Gate every
  learned head on a measured win over the deterministic core (the Lloyd-Max discipline).

---

## 9. References (arXiv)
- RQ-VAE / Residual Quantization — **2203.01941** (Lee et al. 2022)
- VAR / next-scale prediction — **2404.02905** (Tian et al. 2024)
- Multi-scale AR = Laplacian/discrete/latent diffusion — **2510.02826**
- VDSR (global residual) — **1511.04587**; LapSRN (sub-band pyramid, Charbonnier) — **1704.03915**
- Deep Wavelet SR (LH/HL/HH residual + inverse WT) — Guo et al. 2017 (IEEE)
- Softmax Splatting (forward warp, importance, hole-fill) — **2003.05534** (Niklaus & Liu, CVPR'20)
- 3D-JEPA (the cited paper; single-scale, not a fit) — **2409.15803**
- I-JEPA **2301.08243** · V-JEPA **2404.08471** · V-JEPA 2 **2506.09985** · Discrete-JEPA **2506.14373** ·
  AeroJEPA (INR decoder) **2605.05586** — JEPA family, kept off the synthesis path.
