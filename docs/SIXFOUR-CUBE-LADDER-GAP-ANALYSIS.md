> **Status: GAP ANALYSIS + WORKFLOW (2026-06-16).** Design/plan document, not a status
> ledger — canonical built-state is [docs/STATUS.md](STATUS.md). This dissects the app to
> its base components, names the two orthogonal axes, maps built-vs-missing, and gives a
> phased, spec-first workflow to ship the three-GIF product {16³, 64³, 256³}.
> (There is no `MATH.md` in this repo; ignore any reference to one.)

# SixFour cube ladder — gap analysis + workflow

## 0. The product, in one sentence

A capture is **one 64×64×64 space-time index cube** (the "color mass"). The shipped
product is **three GIFs — 16³, 64³, 256³ — that are three rungs of one ×4 cube ladder**,
each rung renderable under either palette scope. Everything below is in service of that.

## 1. Dissection — the base components

Strip the app to four primitives. Everything else is UI or plumbing on top of these.

### 1.1 The substrate — the 64³ color mass (the thing we own)
The capture is a fully-populated `T·H·W = 64·64·64 = 262,144`-voxel index cube
([Shape.hs](spec/src/SixFour/Spec/Shape.hs): `T=H=W=64`, `K=256`). Its value is its
*completeness*, which is proven, not hoped:

- **Per-pixel opacity** — every voxel carries a real palette index, no transparency
  (`Spec.Significance` Def 21–23; the significance gate "every cell backed, no air").
- **Per-frame surjectivity** — *each* of the 64 frames independently uses all 256 colors
  (`CompleteVoxelVolume`, [Indices.hs](spec/src/SixFour/Spec/Indices.hs); shipped via
  `StageContract.swift`). This is your "max out the pixel colors" guarantee, formalized.
- **Population floor** — every slot is backed by ≥2 pixels (`lawSigAllSignificant`,
  *cannot fail* on the SixFour shape since `4096 ≥ 2·256`).

This is the directional source-of-truth: **information only ever flows *out* of the 64³
cube.** You never synthesize the canonical mass from a smaller tier.

### 1.2 Axis A — the resolution operator `R` (cube ladder, ×4)
A **directional** map between resolution tiers, over **two sub-axes that must move together**:
**space** (H×W) and **time** (frame count). The ladder is `16 ×4→ 64 ×4→ 256`
([Export.hs](spec/src/SixFour/Spec/Export.hs) `lawCubeLadder`, `packSides = [16,64,256]`).
Two directions, neither the inverse of the other:

- **Distill ↓ (64→16)** — lossy, information-reducing, gamut-closed (picks real indices).
- **Synthesize ↑ (64→256)** — gamut-closed magnification/interpolation, invents no color.

### 1.3 Axis B — the palette-scope operator `P` (per-frame ↔ global)
Independent of resolution. `per-frame → global` is the collapse
([Collapse.hs](spec/src/SixFour/Spec/Collapse.hs) maximin; `GroupRGBT` select); `global →
per-frame` is re-index (`reindexFrameQ16`). Both ship.

### 1.4 The product matrix (why orthogonality matters)
Because `R` and `P` are orthogonal, the deliverable is one matrix, not a pile of bespoke paths:

| | per-frame scope | global scope |
|---|---|---|
| **16³** distilled | R↓ · P_perframe | R↓ · P_global |
| **64³** native | identity · P_perframe (ships today) | identity · P_global (ships today) |
| **256³** synthesized | R↑ · P_perframe | R↑ · P_global |

Ship the three diagonal-ish artifacts you want from **shared `R` and `P` operators** — not
six rewrites. Today every cell is a separate code path; that is the core architectural gap.

## 2. Current state — what is actually built

| Component | Spec | Golden/Q16 | iOS ship | Notes |
|---|---|---|---|---|
| 64³ substrate + completeness | ✅ | ✅ | ✅ | `CompleteVoxelVolume`, per-frame significance |
| **R↓ spatial** 64²→16² | ✅ `downsample2D` (mode) | ✅ `lawDownsample*` | ⚠️ partial | iOS `LadderExport.working16` exists (optional Review export) |
| **R↓ temporal** 64→16 frames | ❌ **missing** | ❌ | ⚠️ thin | `GroupRGBT.groupsOf4` chunks 64→16 but only *selects*; no quartet **pool** |
| **R↑ spatial** 64²→256² | ✅ `replicate2D` | ✅ `lawReplicate*` | ✅ | primary export is 256×256, time identity |
| **R↑ temporal** 64→256 frames | ✅ `Upscale256` (blend) | ✅ golden checksum | ❌ **no Swift port** | spec+tests only, zero iOS consumers |
| **P** collapse (per-frame→global) | ✅ | ✅ Q16 | ✅ `renderGlobalPalette` | `s4_global_collapse`; RGBT select wired in Review |
| Three-GIF pack as the product | ✅ design (`packSides`) | — | ❌ | ships 1 GIF (256×256×64) + 2 optional rungs; **256³ tier absent** |

**Headline:** the ladder is **spatially complete and temporally fragmented**, and the
product is **one GIF, not three**.

## 3. The gaps (ranked)

- **G1 — Temporal distill operator (64→16 frames) does not exist.** `Export` resamples
  space only; `GroupRGBT` selects but never pools. The 16³ tier is therefore not a true
  cube — its time axis is an ad-hoc subsample (`working16`), not an RGBT-quartet distillation.
  *This is the keystone of your request.*
- **G2 — `R` and `P` are not factored as orthogonal.** `renderGlobalPalette` is a ~150-line
  parallel path; `LadderExport` re-derives leaves. The product-matrix cells are bespoke, so
  adding a tier or scope is O(rewrite), not O(compose).
- **G3 — `Upscale256` has no iOS port.** The 256³ temporal-synthesis tier is spec-proven but
  unshipped; the app's 256 output is spatial `replicate2D` with time held at 64.
- **G4 — No unified cube-ladder contract.** Distill and Synthesize live as scattered
  functions with no module stating both axes (space×time) together, nor the directionality
  laws that pin "these are not inverses."
- **G5 — The temporal-pool *semantics* are undefined.** "4 frames → 1 frame" could be mode,
  mean, maximin, or an OT/`freeSupportBarycenter` pool (the new `Spec.Barycenter`). Undecided.
- **G6 — Product not surfaced.** No single export action emits {16³,64³,256³}; the rungs are
  buried in the Review "Ship" disclosure and one rung (256³) is missing entirely.

## 4. The directional model to build toward  *(decided: fork from 64³)*

Make the 64³ cube the **pivot**, with two operators radiating from it (a **fork**, not a
chain — confirmed). The two directions are not symmetric, and that asymmetry is the design:

- **Distill ↓ (64³→16³) is DETERMINISTIC abstraction.** The classic coarsening kernel
  `(2×2)²→1` (a 4×4 spatial block → 1 cell) on the space axis, and the **RGBT quartet 4→1**
  on the time axis. Index-domain, gamut-closed, no learning — the reproducible "rollout."
- **Synthesize ↑ (64³→256³) is NN-GUIDED.** This is the AlphaGo split the repo already frames
  ([GIFA-GIFB-COLLAPSE-REDESIGN.md](GIFA-GIFB-COLLAPSE-REDESIGN.md) §2): the deterministic
  cube transitions are the **Markov chain**, and the look-NN is the **policy/value net** that
  proposes how to expand 1→4×4 in space and 1→4 in time *better than naive replication*.
  `Spec.Upscale256` is the deterministic blend baseline (the floor); the NN super-res is the
  learned lift on top — scored by `PaletteValue`, searched by `PaletteSearch`, exactly the
  AlphaGo loop. The 256³ tier is where the NN earns its place.

```
        Distill ↓  (deterministic abstraction)       Synthesize ↑  (NN-guided, AlphaGo)
16³  ◄───────────────────────────────  64³  ───────────────────────────────►  256³
  space: (2×2)²→1 = downsample2D [built]   space: 1→4×4 = replicate2D floor + NN lift
  time : RGBT quartet 4→1        [GAP G1]   time : 4→1 Upscale256 floor [built] + NN lift
```

The 64³ stays the source of truth: 256³ is synthesized **from 64³, never from the lossy 16³**
(so distill loss is never amplified — the reason the fork beats the chain).

**Directionality laws (what "must be directional" means, made provable):**
- `Synthesize ∘ Distill ≠ id` — down-then-up loses information (the honest, lossy distill).
- `Distill ∘ Synthesize = id` — up-then-down round-trips: `replicate2D` makes constant 4×4
  blocks and `downsample2D`'s mode recovers the source index exactly (already implied by
  `lawDownsampleConstantBlock`; not yet stated as a cross-law). So **Synthesize is a section
  of Distill** — the precise algebraic sense in which the ladder is one-way.
- Both directions are **gamut-closed** on both axes: they only ever emit indices that exist
  in the 64³ source, so every rung shares the source's palette and completeness — *no re-proof
  per tier* (the same argument `Export` already uses spatially, extended to time).

## 5. Workflow — spec-first, golden-gated, then port (your standard spine)

Each step follows the contract: `ghcid → cabal test → cabal run spec-codegen → spec-docs`,
then a hand-written Swift/Metal port verified against the emitted golden vectors.

**Phase 0 — The entropy analysis (§7). Decides scope (Q3) AND the RGBT pool weights (Q2).
Blocks Phase 1; cheap — pure composition of built primitives.**

**Phase 1 — Spec the missing temporal-distill primitive (closes G1, G5).**
- New `Spec.TemporalPool` (or extend `GroupRGBT`): an RGBT-**weighted, pluggable** pool
  `quartetPool :: PoolStrategy → RGBTWeights → [Frame] → Frame`, where `PoolStrategy ∈
  {Mode, Maximin, Barycenter}` (the "option palette" — all three live, selectable) and
  `RGBTWeights` are the per-channel weights the entropy analysis emits (§7). Default v1:
  `Mode` with entropy-derived weights (index-domain, golden-trivial); `Barycenter` (the new
  `Spec.Barycenter.freeSupportBarycenter`) is the registered richer upgrade.
- Laws: output length = 16; gamut-closed (index-domain ⇒ subset of source indices);
  group-scoped (mirrors `lawDeselectExcludesGroupFrames`); constant-quartet round-trips
  under `Mode`; weights normalize. Golden-pin each strategy.

**Phase 2 — Unify the cube ladder into one contract (closes G4, and frames G2).**
- New `Spec.CubeLadder`: `distill : 64³→16³ = downsample2D ⊗ quartetPool`,
  `synthesize : 64³→256³ = replicate2D ⊗ Upscale256-time`, both as space⊗time products.
- State the directionality laws from §4 here (`Distill∘Synthesize = id`, `Synthesize∘Distill ≠ id`,
  gamut-closure on both axes). This is where the math says "directional," provably.

**Phase 3 — Factor `R` ⟂ `P` (closes G2).**
- Re-express the renderer as `render(tier, scope) = encode(R_tier(P_scope(cube64)))` so the
  six matrix cells reuse two operators. `renderGlobalPalette`'s bespoke path collapses into
  `P_global` composed with the same `R` ladder the per-frame path uses.

**Phase 4 — Synthesize ↑ to 256³: deterministic floor, then NN lift (closes G3).**
- 4a: port `Upscale256`'s temporal-blend + prior-quantize forward pass to Swift/Metal; verify
  bit-for-bit against `Properties.Upscale256`'s golden checksum (`0x4b53edb975ab34ac`). This is
  the deterministic FLOOR.
- 4b (the AlphaGo lift): the look-NN proposes the 1→4×4 / 1→4 expansion above the floor, scored
  by `PaletteValue`, searched by `PaletteSearch` — the policy/value loop. Gated behind 4a so the
  256³ tier ships deterministically first and the NN is a measurable improvement, not a blocker.

**Phase 5 — Surface the product (closes G6).**
- One export action emits the pack {16³, 64³, 256³} at the user-chosen scope, from the shared
  operators. The 16³ is the compact "for the user" tier; 64³ the native; 256³ the deep render.

**Verification gate (every phase):** new `Spec.*` modules get a `Map` entry + 100% Haddock;
laws QuickCheck'd; `spec-codegen` shows zero drift on untouched contracts; Q16/index-domain
ops stay bit-identical Mac↔device.

## 5b. Experiments & answers (2026-06-16)

Phase 0's tool, run over a parametric synthetic battery (8 captures × 8 frames × 10-colour
palettes spanning static / pan / motion / burst / achromatic / chromatic / flicker / gamut-growth;
reproduce via [experiments/CubeLadderEntropyExperiments.hs](spec/experiments/CubeLadderEntropyExperiments.hs)).
Three experiments, three answers:

### Q2-weights — *adaptive, not fixed; chroma-dominant; one caveat*
RGBT weights swing hard with the capture (`wL` 0→89%, `wT` 0→14%), so **per-capture adaptive
weights are justified**, not a constant rule. Chroma (a,b) dominates colourful scenes; `wL`
dominates achromatic ones (89%). **Caveat surfaced by the data:** the temporal term is the
*centroid-trajectory variance*, so it reads `wT=0%` on `high-flicker` — symmetric hue-flip leaves
the mean stationary. **Recommended refinement:** define `wT` from mean *inter-frame Sinkhorn
divergence* (catches mean-preserving flicker), not centroid motion.

### Q2-strategy — *no single winner; regime-selected (validates "option palette")*
| regime | maximin | centroid | barycenter | winner |
|---|---|---|---|---|
| static / achromatic / chromatic-rich (near-identical frames) | 0 | 0 | small | maximin (tie) |
| slow-pan / fast-motion / gamut-expand (smooth temporal drift) | — | **best** | worse | **centroid (mean)** |
| color-burst (multi-modal in time) | 0.699 | 0.686 | **0.274** | **barycenter (OT)** |

The pluggable strategy is *required by the evidence*: **centroid** for smooth/unimodal drift,
**OT-barycenter** for multi-modal/bursty (a decisive ~2.5× win there, but it *costs* on smooth
cases — use only when multi-modality justifies it), **maximin** the gamut floor. Which to pick is
itself selectable from the temporal-divergence signal.

### Q3-scope — *tier-dependent and capture-dependent (validates per-tier design)*
Most captures agree across tiers, but `color-burst` flips: **PerFrame @64³ (cost 0.088) → Global
@16³ (cost 0.0)** — temporal pooling homogenises the burst, so the distilled tier tolerates a
global palette the native tier does not. So scope **must** be decided per tier. The pattern
vindicates the default: 64³ (high temporal detail) more often wants per-frame; 16³ (pooled) more
often tolerates global — and the tool decides per capture.

## 6. Design decisions — resolved

1. **256³ from 64³ (fork), NOT a chain.** ✅ Decided. Distill ↓ is deterministic abstraction;
   Synthesize ↑ is NN-guided (the AlphaGo Markov-chain + policy/value model). See §4.
2. **Quartet pool = RGBT-weighted, pluggable strategy.** ✅ Decided. Not one operator: a
   `PoolStrategy ∈ {Mode, Maximin, Barycenter}` × `RGBTWeights`. The weights are *not* guessed —
   the entropy analysis (§7) emits them from each channel's information content. v1 = `Mode`.
3. **Scope per tier = decided by the entropy analysis, not taste.** ✅ Method chosen (§7). The
   recommendation (16³ global · 64³ per-frame · 256³ global) becomes the *default the analysis
   validates or overrides per capture*, rather than a fixed guess.

## 7. The entropy analysis — the measurement that decides Q2 and Q3

The instinct is right: don't *guess* scope or pool weights — *measure the information*. The
elegant part: every primitive needed is already built and Rust-cross-checked, so this is pure
composition (a new `Spec.Entropy` analysis module, no new math).

**Built primitives it reuses:**
- `Spec.Diversity.gaussianColorEntropy` — `H(P) = ½ln((2πe)³|Σ|)`, the differential entropy of a
  palette's Gaussian fit (and `effectiveDim`, the participation ratio = how many color
  dimensions are actually live).
- `Spec.Sinkhorn.sinkhornDivergence` / `Loss.fidelityLossSinkhorn` — the *exact* discrete-OT cost
  of reconstructing a frame from another palette (the new work this session).
- `Spec.Coverage.gamutCoverageFraction` — gamut occupancy on the 16³ voxel grid.

### 7a. Channel entropies → the RGBT pool weights (answers Q2)
For each axis, measure how much information it carries across the capture:
- Per-channel spatial entropy: the marginal variance/entropy along **L, a, b** (from the
  covariance diagonal that `gaussianColorEntropy` already forms).
- Temporal entropy along **T**: the variance of a quartet's 4 frames (how much they differ).

Normalize the four numbers → `RGBTWeights`. **High-entropy channel ⇒ higher pool weight** (it
carries more of the scene, so the quartet pool should preserve it). A channel that barely varies
gets down-weighted. This makes the pool *adaptive to the capture* instead of a fixed rule.

### 7b. The per-frame ↔ global entropy gap → scope per tier (answers Q3)
The cost of a global palette is the information the 64 per-frame palettes hold that one global
palette cannot. Measure it directly with the new Sinkhorn fidelity:

```
scopeCost(tier) = mean over 64 frames of  fidelityLossSinkhorn(globalPalette, frame_t)
```

- `scopeCost` **small** (frames reconstruct well from one global palette — low inter-frame
  divergence) ⇒ **ship GLOBAL**: same fidelity, one 768-byte table instead of 64, smaller file.
- `scopeCost` **large** (frames diverge — each needs its own gamut) ⇒ **ship PER-FRAME**: the
  global compromise would visibly degrade frames.

**Decision rule:** ship global on a tier iff `scopeCost(tier) < τ`, where `τ` is the perceptual
floor (tie it to the 8-bit / dither noise level — below it, the loss is invisible, so the cheaper
global scope is free). Compute `scopeCost` per tier because distill/synthesize change the gamut:
a 16³ distilled cube may tolerate global where the 64³ does not.

**Why this is the honest answer to "which path":** it replaces a taste call with a per-capture
measurement, using entropy for the *weights* and OT-fidelity for the *scope threshold* — and both
fall out of code that already exists and is golden-gated.

### 7c. Workflow placement — ✅ BUILT (2026-06-16)
This was **Phase 0**, now landed: [`Spec.Entropy`](spec/src/SixFour/Spec/Entropy.hs) composes the
three primitives + 5 QuickCheck laws (weights non-negative & sum to 1; `scopeCost ≥ 0`;
`scopeCost = 0` exactly when every frame equals the global palette; verdict respects τ). All pass;
100% Haddock; zero codegen drift. Its outputs (`RGBTWeights`, per-tier `Scope` verdict) feed Phase 1.

**First measurement (3 illustrative synthetic captures) — the tool behaves exactly as designed:**

| capture | wL | wa | wb | **wT** | scopeCost | verdict |
|---|---|---|---|---|---|---|
| static (frames identical) | 46.5% | 29.3% | 24.2% | **0.0%** | 0.0 | **Global** |
| temporal sweep (L ramps over time) | 32.3% | 17.7% | 17.7% | **32.3%** | 0.158 | **PerFrame** |
| chromatic-rich (big a/b, flat L & time) | **0.0%** | 50% | 50% | 0.0% | ~0 | **Global** |

It zeroes `wT` when frames don't change and raises it to ~⅓ when the scene moves; zeroes `wL` when
lightness is flat and routes all weight to chroma; and flags **PerFrame only when frames genuinely
diverge**. Next: run on the `spec-gen` synth battery / a real capture (heavier — 256-colour × 64
frames wants reduced Sinkhorn iterations or coarse-palette subsampling), then feed Phase 1.
