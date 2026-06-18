# SixFour — Networks: Canonical Roster

> **Status:** canonical inventory of every learned/parametric organ in SixFour.
> `docs/STATUS.md` is the single status ledger and wins on any disagreement; this doc
> is the per-net detail page it points to. Spec source of truth is `spec/`; the only
> nets with a spec-pinned `NetIOSpec` (Net.hs → net_shape.py → NetContract.swift) are
> **METRIC** and **LOOK**. Last reconciled 2026-06-18.

## How to read this

A "slot" here is anything in the product that carries learned or parametric weights, or
that the docs talk about as if it were a net. Seven slots exist. Only two are **spec-pinned**
(have a `NetIOSpec` in `spec/src/SixFour/Spec/Net.hs`, regenerated into
`trainer/generated/net_shape.py` and `SixFour/Generated/NetContract.swift`). The rest live
only in trainer Python and/or Swift with **no cross-tier contract**. Each entry states:
spec status, NetIOSpec pinning, parameter count (**pinned** vs **est.**), trainer path, and
on-device consumer.

Two facts gate everything below and are easy to get wrong:

1. **The supervised MLX look-net training was ABANDONED 2026-06-17 and its trained
   artifacts were DELETED** (`look_net_trained.s4ln`, `atlas_net_trained.npz`,
   `synth_looknet_grayscale.gif`; see `NOTES.md` "Teardown" + `docs/STATUS.md`). The
   trainer *code* (`trainer/regimen.py`, `trainer/train_look_net_mlx.py`,
   `trainer/atlas_net_mlx.py`, `trainer/generated/look_net_mlx.py`) is **kept** but is
   Tier-1 Mac research code that will error on missing artifacts. The **forward oracle**
   (`Spec.LookNetEval` in Haskell + the `s4_load_look_net` Zig loader, fixture-verified
   against the regenerable golden `look_net.s4ln`, NOT a trained weight blob) is preserved.
   The new direction is the AlphaZero-shaped Atlas core; see
   `docs/SIXFOUR-ALPHAZERO-COLLAPSE-DESIGN.md`.
2. **The shipped global palette is the deterministic Zig collapse, not a learned genome.**
   `loadLookNet` has zero production callers (gated by `verify-doc-claims.sh`).

## Roster (7 slots)

| slot | what | spec-pinned NetIOSpec? | params | trainer | device consumer |
|------|------|------------------------|--------|---------|-----------------|
| METRIC | 3×3 PSD Stage-A distance | **YES** (`Net.hs slotMetricDims`) | **6 (pinned)** | `trainer/train_metric.py` | `MetricOrgan.swift` → `LearnedPSDMetric` |
| LOOK (E:>R:>D) | 10-D GMM tokens → 384-DOF σ-pair genome | **YES** (`Net.hs slotLookDims`) | ~115K (**est.**) | MLX, **ABANDONED**; oracle intact | **NONE** (`loadLookNet` 0 callers) |
| ATLAS policy | 13-D board+genome tokens → 1,524 move logits | **NO** | ~6K (**est.**) | `trainer/atlas_net_mlx.py` (proto) | **NONE** |
| ATLAS value — device | board[128] ‖ genome[384] → scalar (nonlinear MLP) | **NO** | **29,249 (pinned)** | `AtlasTrainer.swift` (MPSGraph, on-device) | the trainer itself (proven on iPhone 17 Pro) |
| ATLAS value — Mac (spec v1) | linear utility over 770-D atlasEmbedding → scalar | **NO** | ~770 (≈ θ dim) | spec'd only (`btUpdate`) | **NONE** (not built) |
| θ taste vector | 770-D Bradley–Terry learned utility | n/a (not a net) | **770 (pinned)** | `Spec.PreferenceUpdate.btUpdate` (spec'd) | **NONE** (orphaned spec) |
| GLRM | OLS preference kill-switch | n/a (not a net) | — | `Spec.GLRM` (spec-impl) | **NONE** (not wired) |

`DeltaCodebook` (the **1,524-move vocabulary**, `N_VOCAB = N_SLOTS·N_DELTAS = 127·12`) is the
policy's output **alphabet**, not a net; listed under Atlas policy.

---

## 1. METRIC — shipped, spec-pinned

- **Spec:** `Net.hs slotMetricDims` (`NetSlotMetric`). NetIOSpec: `input_dim=6, output_dim=0`,
  pinned in `trainer/generated/net_shape.py` (`METRIC`) and
  `SixFour/Generated/NetContract.swift` (`.metric`).
- **Params: 6 (pinned)** — the upper triangle of the 3×3 PSD matrix `M = L Lᵀ`
  (`metricPSDUpperTriangleCount`, asserted in `net_shape.py:assert_constants_match`).
- **Trainer:** `trainer/train_metric.py` (trains `L` via Cholesky).
- **Consumer:** `SixFour/Organs/MetricOrgan.swift` → `LearnedPSDMetric`, used by `KMeansLab.run`.
- This is the **only** slot with a complete trainer→contract→consumer spine.

## 2. LOOK (E:>R:>D) — spec-pinned form, training ABANDONED, no device consumer

- **Spec:** `Net.hs slotLookDims` (`NetSlotLook`); modules `LookNetE/R/D`, `LookNetCompose`
  (σ-equivariance theorem), `LookNetEval` (forward oracle). NetIOSpec: `input_dim=10`
  (GMM tokens), `output_dim=384` (`SIGMA_PAIR_DOF`; **NOT 768** — 768 is the flat 256·3 leaf
  space the genome reconstructs *into*). Aux dims `MODEL_DIM=64, CORE_DEPTH=8,
  SIGMA_PAIR_LEAVES=256, MAX_TOKENS=16384`. Pinned across Net.hs → net_shape.py →
  NetContract.swift (`lookSigmaPairDOF=384`).
- **Params: ~115K (est.)** — this is an **unsourced design figure** carried over from
  `docs/COLOR-ATLAS.md` / `docs/SIXFOUR-BACKEND-TENSOR-STACK-MAP.md`. No literal param count
  appears in `look_net_mlx.py` or `Spec.LookNet`, and no test asserts a bound. Treat as
  `~115K (est.)` everywhere until a `count_params()` measurement or a `Spec.LookNet` law pins it.
- **Trainer:** MLX path — `trainer/regimen.py` → `trainer/train_look_net_mlx.py`
  (loss `trainer/look_net_loss_mlx.py`). **ABANDONED 2026-06-17**: grayscale-L training did
  not converge; `look_net_trained.s4ln` and `atlas_net_trained.npz` were deleted. The code
  remains as Tier-1 Mac research and will error on the deleted artifacts.
- **Consumer:** **NONE on device.** `loadLookNet` has zero production callers
  (`SixFour/Native/SixFourNative.swift:82`, debt `looknet-load-unused`). The Haskell forward
  path (`LookNetEval`, 384-DOF `SigmaPairTree` decoder, Obfuscation keystone, PairTree
  round-trip) is **proven** but nothing runs it.
- **Forward oracle preserved:** `Spec.LookNetEval` pins the exact forward for golden-vector
  gates; the Zig `s4_load_look_net` loader is fixture-verified against the **regenerable
  golden** `look_net.s4ln` (not a trained artifact). This is the trunk the AlphaZero design
  calls "ABANDONED" — abandoned *weights*, preserved *forward spec*.

## 3. ATLAS policy — prototype only, NO spec contract (blocker)

- **Spec:** none pinned. `Spec.AtlasNetEval` (Haskell) is the AlphaZero-reframe forward oracle
  ported from `atlas_net_mlx.py`, but there is **no `NetIOSpec`**: `ATLAS_TOKEN_DIM=13`,
  `N_SLOTS=127`, `N_DELTAS=12`, `N_VOCAB=1524` live only as literals in
  `trainer/atlas_net_mlx.py:39–45` with **zero cross-tier contract protection**.
  `trainer/generated/net_shape.py` `ALL_SLOTS` has no Atlas entry; `NetContract.swift` has no
  Atlas enum case.
- **Shape (uncontracted):** 13-D board+genome tokens (10 base GMM dims + 3 σ-invariant
  curation scalars) → fused ctx[128] = 64 board ‖ 64 genome → node head 24→127 + delta head
  128→12 → factored **1,524**-move logits over `DeltaCodebook`.
- **Params: ~6K (est.)** — uncontracted, no `count_params()` call or assertion in
  `atlas_net_mlx.py`. Do not treat as pinned.
- **Trainer:** `trainer/atlas_net_mlx.py` + `trainer/train_atlas_mlx.py` (MLX prototype; today
  regresses policy to the oracle's top-8 one-ply lookahead, NOT MCTS visit counts — the
  visit-count target is unbuilt).
- **Consumer:** **NONE.** No on-device policy forward; `AtlasTrainer.swift:33` files policy
  heads as "follow-up work."
- **Blocker (`atlas-no-netiospec`):** either add `ATLAS_POLICY` to `Net.hs` with its exact
  NetIOSpec (and regenerate net_shape.py + NetContract.swift, gate the trainer), OR retire
  Atlas nets to a trainer-only research harness with no cross-tier contract claim.

## 4. ATLAS value — TWO versions; pin which is which

This slot is the single biggest cross-doc confusion. There are **two distinct value heads**:

### 4a. Device spike (PROVEN, current) — params **29,249 (pinned)**
- **Implementation:** `SixFour/Atlas/AtlasTrainer.swift`. A **nonlinear MLP**:
  board[128] and genome[384] each encoded (genome 384→64 linear+tanh), fused ctx[128] →
  value MLP 128→32→1. Input is the **384-D genome + 128-D board context**, NOT the 770-D
  atlasEmbedding.
- **Trainer:** MPSGraph `gradients(of:with:)` + SGD, **on the physical iPhone 17 Pro**
  (sim-gated; MPSGraph cannot execute in the simulator). Bradley–Terry pairwise logistic loss.
  Loss 0.7154 → 0.00075 over 300 steps, **12.4 ms/step, 6.3 s total**, loss trajectory
  bit-identical Mac↔iPhone (`docs/STATUS.md`).
- **Consumer:** the trainer itself; this is the proof-of-feasibility, not a wired inference path.

### 4b. Mac/spec v1 (DESIGN-ONLY) — linear-770
- **Spec:** `docs/SIXFOUR-ALPHAZERO-COLLAPSE-DESIGN.md §4.1/§4.4`: the v1 value head is a
  **LINEAR** utility over the **770-D atlasEmbedding** → scalar. Then it IS literally `btUpdate`
  (`Spec.PreferenceUpdate`, dims=770, η=0.05, λ=1e-3) and the three spec laws
  (`lawGradientFiniteDiff`, `lawThetaBounded`, `lawStepDecreasesLoss`) transfer for free.
  A nonlinear MLP-over-770 is a v2 option that needs NEW bounding laws.
- **Status:** **not built.** The proven device spike (4a) is a *different* head over a
  *different* input. Alignment work (`docs/SIXFOUR-ALPHAZERO-COLLAPSE-DESIGN.md §6 #1`):
  rewrite `AtlasTrainer`'s value graph to the linear-770 head over `atlasEmbedding`, delete the
  384-genome MLP path, add the `-η·λ·θ` L2 decay term, and re-measure latency (expected cheaper).
- **Params:** ~770 (the θ dimension), no `NetIOSpec`.

**Single source of truth for this slot lives in `docs/STATUS.md`** under "VALUE NET SPEC &
IMPLEMENTATION STATE" (added in this reconcile). Cite that, not a design doc, for current state.

## 5. θ taste vector — learned utility, not a net

- **What:** the 770-D Bradley–Terry taste vector `θ` (`Spec.PersonalGenome.pgTheta`,
  `Spec.PreferenceUpdate`). The per-device personalization genome. **Params: 770 (pinned)** by
  the spec dimension.
- **Status:** spec'd (`PersonalGenome` lifecycle: cold start, per-pick `btUpdate`, deterministic
  replay, KataGo-gated promotion). **Orphaned** — no Swift port/codegen/consumer
  (debt `no-ondevice-trainer-spec`). It is the *parameter vector* the v1 linear value head (4b)
  would learn; not itself an inference net.

## 6. GLRM — preference kill-switch, spec-implemented, NOT wired

- **Spec:** `spec/src/SixFour/Spec/GLRM.hs` **EXISTS and is implemented** (built here, not
  borrowed): an OLS regression of logged BT outcomes on `[coverage, beauty, ‖chroma‖²]`;
  `shouldTrain` STOPs when `R² < r2Floor` or the design is singular; `pairWeight` /
  `lawGalleryPairInformative` zero-weights uninformative gallery pairs.
- **Status: WIRED-IN-SPEC, UNUSED ON-DEVICE.** No Swift caller
  (`grep GLRM|fitOLS SixFour/**/*.swift` → 0). `AtlasTrainer.swift` must call it before any
  value-net preference training begins.
- **Correction:** earlier docs (incl. `SIXFOUR-ALPHAZERO-COLLAPSE-DESIGN.md:161` and
  `COLOR-ATLAS`) claim the kill-switch "does NOT exist in the repo." That is **stale** —
  the module exists; only the wiring is outstanding. See the STATUS.md edit below.

---

## Input-side determinism gap — BoardQ16 (blocker for policy inference)

`Spec.BoardQ16` (Haskell) exists — deterministic integer board-mass derivation (integer
binning + counts + one-rounding Q16 mass) that would close the float input gap to the policy
argmax. It has **ZERO Zig/Swift port**: `grep -rn 'BoardQ16|countsQ16|s4_board_q16' Native/src
SixFour/` returns nothing. Today `AtlasBoard.histogram` accumulates `1/n` (non-dyadic,
order-dependent) and bins via float `okLabBin` (1-ULP boundary flips), so float leaks at the
first policy matmul and argmax stability is unproven. Before any policy inference can be gated,
either port `BoardQ16` to Zig (`s4_board_q16`) + Swift (`AtlasBoard.histogram` overload) with a
`lawCountsOrderIndependent` golden, OR archive `Spec.BoardQ16` as design-only and note that
deterministic board histograms are prerequisite work. Tracked as debt `boardq16-no-port`.

## GPU gate honesty

There is **no byte-exact GPU golden gate today.** The only gated Metal kernel is `field.metal`,
gated against a Haskell/Swift CPU reference **within float tolerance**, not a Zig byte-exact
golden. The planned integer cube-lift Metal kernel (`Cube.metal` `cubeLiftLevelKernel`) would be
the *first* byte-exact Metal↔Zig↔Haskell golden; **it does not exist yet.** GPU net kernels are
**fp32 ordinal-only**: the cross-device contract is argmax/`sign(V_w−V_l)` agreement on a fixed
Q16 comparison key, NOT byte-exact logits. Byte-exact gates are reserved for the CPU/Zig integer
tier. Do not describe a kernel's parity gate as existing before the golden is written.
Tracked as debt `no-gpu-byte-exact-golden`.

## A/B device path is a stub

`Spec.GenomePair` (`sampleOrthogonalPair`, two orthogonal-by-disjoint-support σ-valid A/B
candidate displacements) is **DESIGN-ONLY**: `grep sampleOrthogonalPair|GenomePair
SixFour/**/*.swift` → 0. The on-device A/B nudge is a fixed-delta **stub**:
`AtlasState.swift:96` calls `Self.perturb(candidateA)` (`AtlasState.swift:177`, a placeholder
fixed-chroma delta), not the spec'd `GenomePair`. Treat A/B as a prototype until
`AtlasState.swift` calls `sampleOrthogonalPair`. Tracked as debt `genomepair-design-only`.

## GAN framing — contested, must be pinned

`Spec/Map.hs:25` lists `Spec.Loss` as **"OT/reconstruction; GAN dropped."** But the MLX trainer
still *describes* a GAN: `trainer/regimen.py:14,54` calls Stage 2 "ε-annealed GAN + halting" and
passes `lam_adv`/`dlr`/`eps_start`/`eps_end` hyper-parameters. Meanwhile
`trainer/look_net_loss_mlx.py:1–24` implements **three non-GAN terms only** (Bures fidelity,
coverage, Ou-Luo beauty) with **no discriminator and no adversarial reference**. So the loss the
trainer actually minimizes is OT/reconstruction (matching the spec); the GAN language in
`regimen.py` is **vestigial**. Since the look-net trainer is abandoned, the resolution is to
**strike the GAN framing from `regimen.py`** (docstring line 14 + Stage-2 banner line 54 + the
`lam_adv`/`dlr`/`eps_*` args), making the code match `Spec.Loss`. Do not reintroduce a GAN
without a discriminator design and a `Spec.Loss` law. Tracked as debt `gan-framing-contradiction`.

## DESIGN-ONLY spec modules (no on-device consumer)

`Spec.GenomeBlend`, `Spec.GenomeCarrier`, `Spec.ExportFamily` are spec'd (`Map.hs §4`) with **no
caller** in `SixFour/Atlas` or `SixFour/Generated`. Reserved for federated genome import (v2+).
These are NOT shipped; do not describe them as on the live device path.

## Cross-reference index

| topic | spec | trainer | swift | status ledger |
|-------|------|---------|-------|---------------|
| METRIC | `Net.hs slotMetricDims` | `train_metric.py` | `MetricOrgan.swift` | STATUS BUILT |
| LOOK form | `Net.hs slotLookDims`, `LookNetEval` | `look_net_mlx.py` (abandoned) | `SixFourNative.swift:82` (unused) | STATUS DESIGN-ONLY |
| ATLAS policy | `AtlasNetEval` (no NetIOSpec) | `atlas_net_mlx.py:39–45` | — | this doc §3 (blocker) |
| ATLAS value (device) | — | `AtlasTrainer.swift` | `AtlasTrainer.swift:199` | STATUS "VALUE NET" block |
| ATLAS value (v1 spec) | ALPHAZERO §4.1 | — | — | this doc §4b |
| θ taste | `PersonalGenome`, `PreferenceUpdate` | — | — | debt `no-ondevice-trainer-spec` |
| GLRM | `GLRM.hs` | — | — | STATUS `glrm-wired-but-unused` |
| BoardQ16 | `BoardQ16.hs` | — | — | debt `boardq16-no-port` |
| GenomePair | `GenomePair.hs` | — | `AtlasState.swift:96` (stub) | debt `genomepair-design-only` |
