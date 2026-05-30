> **⚠ SUPERSEDED (2026-05-30) by [`L-NN-MASTER-DESIGN.md`](L-NN-MASTER-DESIGN.md), the design of record.**
> This doc's *research verdicts* (deterministic argmin index, Lloyd-Max MSE ceiling, OT-not-GAN,
> GAN-by-scale) are KEEP and still cited by the master. Its top-level "the L-NN is the deliverable"
> framing is RETIRED — L is **Step 1 of 3** (L→A→B). See the master §6 supersession map.

# L-NN — deep research, design refinement, training workflow & M1 CLI

The L-NN is the **achromatic (σ-invariant) nucleus**: a 64-frame OKLab burst →
one **global grayscale** 256-level palette + a per-pixel index map → a single
global-palette 64×64 GIF. It is the reusable CORE of the future A/B (chroma)
layers, so its architecture and training spine matter more than its grayscale
numbers. This doc records the literature verdicts, a critical reframe of what
"beating the baseline" means, the refined design those imply, the cross-machine
workflow (design on this Mac + M3, train on M1), and the M1 training CLI that
falls out of the design + regimen.

Research run: 2026-05-30 (deep-research harness, 23 sources, 25 claims
adversarially verified, 21 confirmed / 4 killed). Citations are inline.

---

## 0. TL;DR verdicts (what the evidence dictates)

| Question | Verdict | Confidence |
|---|---|---|
| **Index map: learned or deterministic?** | **Deterministic argmin.** For a sorted 1-D palette, nearest-level is pointwise MSE-optimal; soft assignment exists *only* for training gradients, hard argmin at inference. No source shows a learned index map beating argmin for a fixed palette. | High |
| **Input: pixel volume or token pool?** | **Pooled distributional statistic is correct for a GLOBAL palette** (the global palette IS the lightness marginal). The negative set-encoder result is about discarding *spatial* structure, which a global palette ignores by definition. But pre-quantizing to per-frame palettes before pooling is a (small) lossy step. Feed the **pooled lightness histogram / weighted samples** — the minimal sufficient statistic. | Medium-High |
| **Training objective: GAN or OT?** | **Drop / demote the GAN.** OT (sliced/entropic Wasserstein) is a single non-minimax loss, empirically *more* stable than improved WGAN; documented palette-GAN failure modes (discriminator memorization/overpowering) are a liability with no demonstrated benefit at this scale. | High |
| **Adaptive palette size via halting?** | **Unadjudicated by literature.** No verified evidence on PonderNet/ACT vs rate-distortion/MDL for codebook size. Keep halting decoupled (a complexity *readout*), and add the principled alternative: rate-distortion-knee sizing. | Low (open) |
| **The real baseline** | **Lloyd-Max (1-D k-means) on the pooled lightness histogram, not the Wasserstein barycenter.** The product metric is per-pixel L-MSE; Lloyd-Max is MSE-optimal; the barycenter minimizes a *different* objective (W₂ to per-frame dists). | High (math) |

The blunt consequence (§2): **on L-MSE, a deterministic algorithm (Lloyd-Max) is
the ceiling and the NN cannot beat it.** "Beats the barycenter 5/6" is a soft win
against a baseline that was never MSE-optimal. The L-NN's justification is *not*
grayscale MSE supremacy — it is (a) validating the architecture/training spine for
the genuinely-hard chroma layers, and (b) the per-user/diversity machinery where
no single deterministic answer exists. The training and the CLI must be honest
about this.

---

## 1. Findings (cited)

### 1.1 Input representation
- **Set/pooling encoders that discard spatial structure can underperform.** The
  only direct test — GIFnets (CVPR 2020) — found a permutation-invariant PointNet
  *worse than both median-cut and a spatial CNN* for palette extraction at every
  palette size (Np=16: median-cut 28.10 / PointNet 26.05 / Inception 29.24 dB;
  Np=256: 37.80 / 33.09 / 38.08). **Caveat (verifier):** single uncontrolled
  ablation, on raw 3-D RGB single images, does *not* isolate permutation-invariance
  and does *not* test a token-pool over a burst or 1-D lightness — suggestive, not
  dispositive. [GIFnets, openaccess.thecvf.com/.../Yoo_GIFnets_..._CVPR_2020]
- **Why it doesn't bite us for the global L-palette:** a global palette is a
  *distributional* object — the spatial information PointNet was losing is exactly
  the information a global palette is *supposed* to marginalize out. The
  spatial structure that matters lives in the per-pixel **index map**, which we
  make deterministic argmin anyway (§1.2). So the set-pool is defensible **for the
  palette**, and the GIFnets warning lands on the *assignment*, which we don't learn.
- **Open question (unresolved):** does pooling over *pre-quantized* per-frame
  palette tokens (16,384 weighted OKLab Gaussians, Σ=0) lose lightness info vs the
  raw 262,144-pixel volume? No source answers this for our input. Practically: for
  L-only the sufficient statistic is the 1-D lightness histogram; the current
  Σ=0 weighted tokens *are* weighted samples of that marginal, so the content is
  right (if over-parameterized). The lossy step is the per-frame 256-level
  pre-quantization upstream — measurable (§4 diagnostic: pooled-histogram EMD
  between pre-quantize and post-quantize).

### 1.2 Learned vs deterministic assignment → **deterministic argmin**
- **Canonical two-phase decomposition.** Color quantization = palette generation +
  pixel assignment; assignment is nearest-neighbor search, accelerated by k-d
  trees / space-filling curves. [Celebi, "Forty years of color quantization," AI
  Review 2023, dl.acm.org/doi/abs/10.1007/s10462-023-10406-6]
- **Soft assignment is a training device, not a quality lever.** GIFnets uses a
  soft projection `Proj_s = Σ_j softmax(d_j/T)·P[j]` for differentiability and the
  *hard* `argmin_j |I−P[j]|²` at inference; Agustsson 2017 (Soft-to-Hard VQ,
  NeurIPS) anneals a continuous relaxation to its discrete counterpart purely to
  learn end-to-end. [arxiv.org/abs/1704.00648]
- **No evidence a learned index map beats argmin for a fixed palette**, and for a
  *sorted 1-D* palette argmin is trivially pointwise-optimal (it minimizes each
  pixel's squared error independently). **Decision: the index map is deterministic
  argmin** (already what `global_palette.global_reindex` does); soft-OT stays only
  inside the training loss.

### 1.3 Training objective → **OT/reconstruction, drop the GAN**
- **OT replaces the saddle point with a single, more-stable loss.** Sliced-
  Wasserstein generative modeling is "a single objective rather than a saddle-point
  formulation" and "significantly more stable compared to even the improved
  Wasserstein GAN." In 1-D the sliced reduction is *exact* (sort + match), so for
  the L-axis the OT loss is closed-form and cheap. [Deshpande et al., CVPR 2018,
  arxiv.org/abs/1803.11188]
- **Palette-GAN failure modes are concrete.** PaletteNet (CVPR-W 2017): "the size
  of D_orig is too small and causes D to cheat by memorizing all the pairs … D
  performing strikingly well and not easily fooled ever after 1 epoch"; they needed
  a classification term + two-phase (pretrain-then-adversarial) training because
  "if either … becomes too powerful, the competitive learning breaks."
  [openaccess.thecvf.com/.../Cho_PaletteNet_..._CVPR_2017]
- **When a discriminator IS legitimate:** in PalGAN (ECCV 2022) the adversary
  targets the colorized *image*, never the palette tensor, and the palette
  predictor itself trains self-supervised with plain L2. [arxiv.org/abs/2210.11204]
  Mapping to us: our discriminator already operates on the *rendered frame* (right
  target), but (i) it's trivially small, (ii) `lam_recon=200` vs `lam_adv=1`
  means the recon term already dominates 200:1, so the net is *de facto* an
  OT-regressor with a vestigial GAN, and (iii) a discriminator parked at its
  uninformative fixed point (D≈2ln2, adv≈ln2) is **not** "healthy Nash" — it's the
  signature of an adversary contributing nothing. **Decision: remove the GAN from
  the L milestone** (keep the hook for later QD/diversity, where adversarial/
  diversity objectives earn their place); make the objective an explicit
  OT/reconstruction loss.
- **Regularized OT is the robust form.** Unregularized discrete OT for color
  "creates artifacts and amplifies noise in flat areas"; regularizing the transport
  plan removes them, and mass-relaxation makes it robust to per-frame histogram
  mass mismatch. [Ferradans et al., SIAM J. Imaging Sci. 2014, arxiv.org/pdf/1307.5551]
  → keep the entropic ε on the soft-OT term; ε-anneal has a rigorous floor:
  annealed Sinkhorn reaches true OT only if β→∞ *and* β_t−β_{t-1}→0; error =
  entropic Θ(1/β) + relaxation Θ(β_t−β_{t-1}), optimal-but-slow β∝√t. So **too-fast
  ε-anneal leaves residual relaxation error** — our geometric anneal should be
  checked against a √t schedule. [Chizat 2024, arxiv.org/html/2408.11620v1]

### 1.4 Adaptive palette size — **open**
- No surviving verified claim addressed PonderNet / ACT / Mixture-of-Recursions vs
  rate-distortion / MDL / entropy-coding-aware sizing. The literature is silent at
  the resolution we need. Treat halting as a **complexity readout** (decoupled from
  output, as the code already does) and add the principled, interpretable
  alternative as the *target* the halt head regresses to: the **rate-distortion
  knee** — the K at which marginal distortion reduction per added level falls below
  a threshold (the elbow of the distortion-vs-K curve, computable from Lloyd-Max at
  K=1..256). This makes "how many levels does this scene need" a defined quantity,
  not a free-floating scalar.

### 1.5 Diagnostics — **beyond MSE**
- Celebi 2023: "conventional pixel-based metrics may not adequately capture
  perceptual quality"; CIEDE2000 (and its spatial extension) correlate >0.8 with
  subjective CQ ratings. For lightness-only, **CIEDE2000 reduces to ΔL\* on the
  achromatic axis** — that is our perceptual error. Pair it with **EMD/Wasserstein-
  to-target** (measure the win in the baseline's own currency), **coverage** (used
  levels), and **dynamic-range utilization** ([Lmin,Lmax] span vs input span).
- GAN-health (only if a GAN is kept): D-loss trajectory vs 2ln2, gradient-norm
  balance, and the qualitative "discriminator overpowered" check from PaletteNet.

### 1.6 OT baseline theory
- 1-D OT is solved exactly by sorting (closed-form quantile coupling); the
  256-level lightness **barycenter is exactly quantile-averaging** of the per-frame
  lightness histograms. The OT framework yields a shared cross-image palette via
  barycenter normalization. [Coeurjolly/Digne sliced-OT; Ferradans 2014]
- **To beat the barycenter, the net must exploit per-capture structure the fixed
  averaging rule ignores.** It does — but the per-capture MSE-optimal answer is
  Lloyd-Max, not the NN (see §2).

### What got killed (don't cite these)
- "A learned CNN palette predictor beats median-cut at every size" — **refuted 1-2**
  (the GIFnets numbers actually show the learned net *behind* median-cut at small
  palettes once you read the table correctly).
- "VAE-GAN scored worse than plain VAE on palette MOS" — **refuted 1-2** (suggestive
  only; the robust anti-GAN evidence is PaletteNet's memorization, 3-0).
- "Per-pixel assignment is deterministic argmin [MDPI source]" — **refuted 0-3** at
  the *source* level (bad citation), though the *substance* is upheld by Celebi +
  GIFnets. Use the good sources.
- "Soft-to-hard quantization matches SOTA hard pipelines" — **refuted 1-2**.

---

## 2. The critical reframe: the Lloyd-Max ceiling

The current trainer optimizes (dominantly) **per-pixel L-MSE** and is judged
against the **Wasserstein barycenter**. But:

1. The product quality metric for a fixed global palette + argmin assignment is the
   **scalar-quantization distortion** of the pooled lightness samples.
2. The **MSE-optimal 256-level scalar quantizer of a 1-D distribution is Lloyd-Max**
   (1-D k-means). It is deterministic and needs no training.
3. The **Wasserstein barycenter is a different optimum** (it minimizes W₂ to the
   per-frame distributions, not pooled MSE). So **barycenter is a *weaker* baseline
   than Lloyd-Max for the MSE metric.** Beating it is easy and not very meaningful.

**Therefore: on L-MSE the NN's ceiling is Lloyd-Max, and it cannot exceed it.** The
best the L-NN can do is *approximate Lloyd-Max per-capture*. If we only ever
measure MSE-vs-barycenter, we are grading on a curve.

This is not a reason to abandon the L-NN — it is a reason to be **honest about why
it exists**:
- **Architecture validation.** L is the σ-invariant special case of the chroma
  problem. Getting the encoder→recursion→decoder→reconstruct spine + the training
  loop + the golden-gated codegen working on L is the de-risking for A/B, where the
  objective is genuinely non-deterministic (relational beauty Ou-Luo, symmetry,
  coverage) and no closed-form optimum exists.
- **Per-user / diversity.** The product wants a *gallery* of looks (MAP-Elites /
  per-user variance), not the one MSE-optimal palette. That is where learned +
  diversity/adversarial objectives are justified — and where Lloyd-Max has nothing
  to say.
- **Adaptive compute.** On-device latency via halting (a deployment property, not
  a quality one).

**What this changes in practice:** the trainer's objective for L should be an
honest OT/reconstruction loss, and the CLI must report the **Lloyd-Max gap** (how
close the NN gets to the real ceiling) alongside the barycenter comparison — and
frame a small positive Lloyd-Max gap as *success* (the spine works), not failure.

---

## 3. Refined L-NN design (what to change)

Minimal, evidence-driven deltas to the current trainer. None require touching the
Haskell σ-equivariance theorem; they are objective/diagnostic changes.

1. **Objective: replace the GAN with an explicit OT/reconstruction loss.**
   - Drop `Discriminator`, `lam_adv`, the D optimizer, `d_loss_fn`. (Keep the code
     in git history; re-introduce a *diversity* critic only at the QD/gallery stage.)
   - Primary loss = soft-OT transport cost (the existing `recon`, which in 1-D *is*
     the entropic-W₂ fidelity) + the Bures/moment anchor (keep — cheap anti-collapse)
     + halting KL (keep, decoupled).
   - Verify the ε-anneal against a √t schedule (Chizat) — geometric may anneal too
     fast and leave relaxation error; add `--eps-schedule {geometric,sqrt}`.
2. **Index map: deterministic argmin at inference (already true), soft-OT only in
   the loss (already true).** No learned assignment. Document it as a *decision*,
   not an accident.
3. **Input: keep the pooled-token set encoder for the palette** (justified §1.1),
   but add a diagnostic that quantifies the pre-quantization information loss
   (pooled-histogram EMD pre- vs post-per-frame-quantize) so we *know* the cost.
   Optionally offer a `--input {tokens,histogram}` where `histogram` feeds the
   256-bin pooled lightness histogram directly (the minimal sufficient statistic) —
   an A/B the regimen can run.
4. **Halting: keep decoupled; add the rate-distortion-knee target.** Compute the
   distortion-vs-K curve from Lloyd-Max (K=1..256) per capture; define the knee K\*;
   train the halt head to predict log2(K\*) (a defined target replacing the free
   geometric prior). This makes E[d] *mean something*.
5. **The real baseline is Lloyd-Max.** Add `lloyd_max_l(burst, k)` to
   `global_palette.py` (1-D k-means on pooled lightness) and make it the primary
   comparison in the gate and CLI; keep the barycenter as a secondary reference.

---

## 4. Diagnostics the trainer must compute (the "critical" core)

Per held-out capture and per `SynthClass`, beyond MSE:

- **Fidelity ladder (MSE):** learned vs **Lloyd-Max (ceiling)** vs barycenter-256
  vs barycenter-128 vs per-frame-grayscale floor. Report `learned/lloydmax` (the
  honest gap) and `barycenter/learned` (the soft win).
- **Perceptual:** mean & p95 **ΔL\*** (CIEDE2000 on the achromatic axis).
- **OT-to-target:** 1-D **W₁/EMD** between the NN palette (as a distribution) and
  the pooled lightness distribution.
- **Palette health:** distinct-level count (degeneracy if ≪256), min inter-level
  gap (collapse), sorted-monotone check, **coverage** (levels with ≥1 assigned
  pixel across the burst), **dynamic-range utilization** (palette span ÷ input
  span).
- **Halting:** E[d], its variance across the corpus, and E[d] vs the rate-
  distortion knee K\* (is the NN's complexity estimate calibrated?).
- **Overfit signal:** train-corpus MSE vs held-out MSE gap, per class.
- **(If GAN ever returns) GAN-health:** D-loss vs 2ln2, |∇G|/|∇D| ratio.

**Red-flag rules (auto-fail / warn):**
- distinct levels < 0.9·256 → palette degeneracy (WARN).
- learned MSE > Lloyd-Max·1.5 → spine underperforming its own ceiling (WARN).
- learned MSE ≥ barycenter-256 on any class → below the *soft* floor (FAIL).
- dynamic-range utilization < 0.8 → palette not spanning the scene (WARN).
- held-out/train MSE ratio > 1.5 → overfitting the tiny synthetic corpus (WARN).
- E[d] pinned at 0 or 8 across all classes → halting collapsed/uninformative (WARN).

---

## 5. The cross-machine workflow

Three roles, one source of truth (the Haskell spec), golden-vector-pinned.

```
        ┌─────────────────────────  DESIGN  (this MacBook + M3)  ─────────────────────────┐
        │  • Haskell spec = source of truth (Spec/*.hs): objective, AxisNet, σ-laws.       │
        │  • Edit MLX trainer (trainer/*.py) + Codegen (spec/src/SixFour/Codegen/*).       │
        │  • `cabal test` + `cabal run spec-codegen` (no-diff) gate every change.          │
        │  • Iterate the DESIGN here; never hand-edit generated files.                     │
        └───────────────────────────────────┬─────────────────────────────────────────────┘
                                  git push    │   git pull
        ┌───────────────────────────────────▼─────────────────────────────────────────────┐
        │                         TRAIN  (MacBook M1 — the trainer)                        │
        │  `git pull` → `zig build && zig build test` → `uv sync` → `regimen.py`           │
        │  Stage 1 PRE-TRAIN gates → Stage 2 TRAIN (live CLI §6) → Stage 3 QUALITY gate     │
        │   (vs Lloyd-Max, per class) → Stage 4 EXPORT blob (only if ACCEPTED).            │
        │  CLI streams live state + critique; writes a run report JSON for the design loop.│
        └───────────────────────────────────┬─────────────────────────────────────────────┘
                                  run report  │   (blob + report.json committed/shared)
        ┌───────────────────────────────────▼─────────────────────────────────────────────┐
        │                         VERIFY  (any machine)                                    │
        │  • golden gates (`check_golden.py`) — MLX==torch==Haskell @1e-6.                  │
        │  • blob loads via Zig `s4_load_look_net` (rc=0).                                  │
        │  • `eval_l_quality.py` extended: vs Lloyd-Max + barycenter + floor, held-out.     │
        │  • report.json feeds the next DESIGN iteration (the critical loop closes here).   │
        └──────────────────────────────────────────────────────────────────────────────────┘
```

- **Design machine ≠ train machine** is deliberate: the M1 is the canonical training
  hardware (reproducible byte-for-byte from seeds + pinned `uv.lock`); the M3/this
  Mac is for spec + trainer authoring and for *reading the critique*, not for
  producing ship weights.
- **The loop is closed by the run report**, not by watching the M1. The CLI's job is
  to make a remote/asynchronous run *legible after the fact* and *interruptible
  early* if it is going wrong.

---

## 6. The M1 training CLI (`regimen.py` front-end)

The CLI is **the product of the NN design (§3) + the diagnostics (§4) + the regimen
stages (§5)** — it surfaces exactly the quantities the refined design makes
meaningful, and it is *critical by construction* (it argues against the run).

### 6.1 Modes
- `regimen.py` — full run, **live dashboard** (default) + final critique + report.
- `regimen.py --smoke` — fast structure check (existing).
- `regimen.py --quiet` — stream metric lines only (for logging / headless / CI).
- `regimen.py --report-only out/run-<ts>.json` — re-render the critique from a saved
  report (read on the design machine).

### 6.2 Live dashboard (during Stage 2 TRAIN)
A single repainting TUI (stdlib only — `curses`/ANSI, no deps; trainer tier allows
deps but a zero-dep CLI is cheap and portable). Panels:

```
 SixFour L-NN regimen — step 840/1400   ε 3.1e-3 (sqrt-anneal)   elapsed 2m11s   M1
 ┌ LOSS ───────────────────────────────┐ ┌ PALETTE (held-out probe) ───────────────┐
 │ recon  1.07e-5  ▁▂▃▃▂▂▁▁  ↓          │ │ distinct 247/256   span [0.04,0.96]      │
 │ bures  3.1e-4   ▁▁▁▁▁▁▁▁             │ │ DR-util 0.97   coverage 251/256          │
 │ halt   0.18     ▅▄▃▃▂▂▂▂             │ │ levels  ▁▁▂▂▃▃▄▅▅▆▆▇▇██  (sorted L)       │
 │ (GAN removed — OT objective)         │ │ min-gap 1.2e-3   monotone ✓              │
 └──────────────────────────────────────┘ └──────────────────────────────────────────┘
 ┌ FIDELITY LADDER (held-out, this step) ──────────────────────────────────────────────┐
 │           learned   lloyd-max*   bary-256   bary-128    floor                         │
 │  L-MSE    7.9e-6    6.8e-6       1.05e-5    1.9e-5      5.5e-6                         │
 │  gap to ceiling (learned/lloyd-max) = 1.16×    soft win (bary256/learned) = 1.33×     │
 │  ΔL* mean 0.011  p95 0.027     W1-to-target 4.2e-3                                    │
 └──────────────────────────────────────────────────────────────────────────────────────┘
 ┌ HALTING ─────────────────────────────┐ ┌ CRITIQUE (live red-flags) ──────────────┐
 │ E[d] 5.9 / 8   knee K* ≈ 200 (d 7.6) │ │ ✓ no degeneracy   ✓ DR-util ok           │
 │ calibration |E[d]-log2K*| = 0.4      │ │ ⚠ halt E[d] below knee (under-sizing)    │
 └──────────────────────────────────────┘ │ ✓ no overfit (held/train 1.08×)          │
                                          └──────────────────────────────────────────┘
 * lloyd-max = the real MSE ceiling (deterministic). barycenter is the soft baseline.
```

Refresh cadence: every `log_every` steps recompute the held-out probe (one capture
per class, cached) — keep it cheap so the dashboard stays live.

### 6.3 Final critique (after Stage 3 QUALITY gate)
Per-class table + an explicit verdict that is **honest about the ceiling**:

```
 PER-CLASS ACCEPTANCE (held-out, n=4/class)
 class        learned    lloyd*     bary256   gap↑ceil  win/bary   ΔL*p95   verdict
 wide_color   8.1e-6     6.9e-6     1.1e-5    1.17×     1.36×      0.029    PASS
 wide_gray    5.2e-6     4.8e-6     7.0e-6    1.08×     1.35×      0.018    PASS
 narrow       2.1e-6     1.9e-6     2.9e-6    1.11×     1.38×      0.012    PASS
 lowkey       9.7e-6     8.0e-6     1.3e-5    1.21×     1.34×      0.034    PASS  ⚠ hardest
 highkey      9.1e-6     7.6e-6     1.2e-5    1.20×     1.32×      0.031    PASS
 mid_color    4.0e-6     3.6e-6     5.4e-6    1.11×     1.35×      0.016    PASS
 highchroma   6.3e-6     5.5e-6     8.4e-6    1.15×     1.33×      0.022    PASS

 VERDICT: ACCEPTED ✓  (beats soft baseline on 7/7 classes ≥75%)
 HONEST READ: mean gap to the Lloyd-Max ceiling = 1.15× — the spine approximates the
   MSE-optimal quantizer to within 15%. This is the SPINE working, not MSE supremacy
   (Lloyd-Max is deterministic and unbeatable on MSE). The win vs barycenter (1.34×)
   is real but the barycenter is not the MSE-optimal baseline; do not over-read it.
 NEXT LEVER: close the ceiling gap with more captures/steps; or accept it — the L
   milestone's purpose is architecture validation for A/B, met here.
```

### 6.4 Run report (`out/run-<ts>.json`)
Machine-readable: hyperparameters, git SHA, per-step loss trace, per-class final
metrics (all of §4), the verdict, and the red-flags fired. This is what travels
back to the DESIGN machine to close the loop (§5) — the design iteration reads the
report, not the live screen.

### 6.5 Why this is "critical of the training"
- It compares against the **true ceiling (Lloyd-Max)**, not just the flattering
  barycenter, so a soft win can never masquerade as a real one.
- It fires **red-flags** (degeneracy, under-utilization, overfit, halting collapse)
  during the run, so a bad run is killable early.
- The final verdict states the **honest read** — the L-NN's value is the spine, not
  the grayscale MSE — so the number is never oversold.
- Same-distribution caveat is explicit: synthetic held-out is *still same-generator*;
  the report flags that real-capture validation is the only true test.

---

## 7. Open questions carried forward
1. Pre-quantization information loss (token-pool vs raw volume) — quantify (§3.3).
2. 1-D argmin optimality — mathematically true (pointwise), worth a one-line proof
   in the spec rather than a citation (the literature only says "standard").
3. Adaptive size — PonderNet vs rate-distortion-knee is unsettled; the knee target
   (§3.4) is the principled interim.
4. Real-capture validation — every number here is synthetic same-generator; the QD/
   per-user loop and a captured validation set are the only escape from grading on a
   curve.
