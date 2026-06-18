# SixFour — Canonical Path Forward

> **Status of this document.** This is the single source of *direction* for SixFour. It does
> not replace `docs/STATUS.md`, which remains the canonical *status ledger* (what is built,
> proven, blocked). Where this doc and STATUS disagree on a fact, **STATUS wins**. Where this
> doc commits to a *direction*, that direction is canon until amended here.
>
> Written 2026-06-18, post the AlphaZero-collapse pivot (`docs/sixfour-alphazero-pivot.md`,
> 2026-06-17) and an adversarial critic pass that demoted a large pile of "reconciliation" back
> to honest design debt. The demotion is reflected throughout: the **spine** is canon, the
> **taste organ** is proposed-and-parked.

---

## 0. The decision

**SixFour ships one learned core: a Gumbel-AlphaZero policy+value predictor over the reversible
σ-pair LAB-collapse MDP, sitting strictly *above* a frozen deterministic maximin collapse floor,
read at three search budgets (`n=0`, `n=1`, `n=8–16`) that subsume every candidate approach.**
The core is a *bounded addition on a determinism floor*: every terminal genome is re-quantized
through the Q16 lattice (`lawTerminalQuantizationIdempotent`, `AtlasGame.hs:174`), so the net can
re-rank and tint but can never re-write the floor. The taste channel is **one Bradley-Terry
preference latent over the existing 770-D embedding** (`btUpdate`, `PreferenceUpdate.hs`), wired
A/B → posterior-of-record. The **v1 we actually ship is value-only search over a frozen policy**;
the policy trainer, the calibrated-posterior taste organ, and the perceptual warp are real,
desirable, and **explicitly parked as their own specs**, not smuggled in as settled
reconciliation.

---

## 1. The canonical core

### 1.1 The machine

One predictor `f_θ(s) = (p, v)` over the reversible σ-pair collapse MDP (`Spec.AtlasGame`),
above a frozen deterministic floor. The same machine is read at three operating points; that is
the entire unification (see §6):

| Budget | Configuration | Subsumes |
|--------|---------------|----------|
| `n=0`  | value head only, policy deleted, taste enters as a σ-locked LeafOverride δ | Candidate 3 (deterministic + δ) |
| `n=1`  | one-ply value lookahead with a gate exposed | Candidate 4 (gated residual contract) |
| `n=8–16` | Gumbel-Top-k root + Sequential Halving over the reversible simulator | Candidate 1 (AlphaZero) |

The structural invariant that makes these *one* machine: **terminal idempotent re-quantization**.
`quantizeQ16 (toQ16 q) == q` for every terminal (`lawTerminalQuantizationIdempotent`). Learning
is therefore a bounded addition, never a rewrite, of the deterministic surface.

### 1.2 I/O

- **State `s`** = `GameState` (`AtlasGame.hs`): the depth-7 256-leaf σ-pair tree (`AtlasState`),
  the 16³×6 curation board (`BoardQ16`, **done** — float-input gap closed), the cube-ladder rung,
  the ply counter.
- **Policy head `p`** (σ-*equivariant*): factored logits `nodeLogits[127] + deltaLogits[12]` over
  the `DeltaCodebook` reversible Q16-Haar Edit vocabulary. Top-k=8 routed through `atlasPolicy`.
  **Not yet trainable on the shipped path** (see §1.4, §7).
- **Value head `v`** (σ-*invariant*): a scalar Bradley-Terry strength over terminal genomes.
- **Emitted artifact**: the Q16 σ-pair genome at the search terminal → 256 leaves → collapsed onto
  the maximin floor → GIFB palette + R3D `.cube` LUT (the surfacing path that ships today).

σ-equivariance is **structural via `reconstructPaired`** (zero params spent on symmetry); this is
why the net stays tiny and why the abandoned supervised net's "equivariance-within-tolerance"
failure mode does not recur.

### 1.3 Deterministic floor vs learned addition

**DETERMINISTIC FLOOR — never learned, every terminal re-quantizes through it:**

- `s4_global_collapse` — the maximin collapse (**Gonzalez 1985 farthest-first, Lloyd-refined**;
  this is the floor per STATUS canon — *not* "Lloyd-Max MSE-optimal", see §7 correction).
- the reversible Q16-Haar lift/unlift (`s4_cube_lift_level` / `s4_cube_unlift_level`).
- the σ-pair `reconstructPaired` decode.
- the 16³ board mass (`s4_board_mass_q16`).

**LEARNED ADDITION — bounded, sits above the floor, cannot rewrite it:**

- policy logits (which reversible Haar Edit to take).
- the BT value scalar (taste ranking of terminals).
- a θ→δ LeafOverride **tint** (`LeafOverride.hs`, proven exact in Haskell; **no Zig kernel yet**).
  The δ can tint existing leaves (±8192 Q16 per generator) but **cannot re-select which colors get
  a leaf** — that structural reach is exactly what search budget `n>0` buys.

**Honest limit:** at `n=0` the core *tints but cannot re-choose* the base palette. Re-selection
requires search.

### 1.4 What the net is *today* vs what this plan commits to

STATUS canon, stated plainly so no one mistakes the plan for the build:

- The **only proven device net** is a **29,249-param nonlinear MLP** over `board[4096,6] ‖
  genome[384]` → scalar V (`AtlasTrainer.swift`, 12.4 ms/step on iPhone 17 Pro). This is **not**
  the "linear head over 770-D θ = `btUpdate` verbatim" the headline implies; it is a different
  architecture over different inputs with **no `NetIOSpec`** (blocker `atlas-nets-unpinned`).
- The **policy half has no trainer, no target, and no on-device path**
  (`AtlasTrainer.swift:33`); v1 is value-only over a policy that is **not yet trainable**.
- The **A/B path on device is the `ab-perturb-stub`** (`AtlasState.swift:177` `perturb()`, fixed
  ±0.04 a-axis, Q16 2621) — *not* `sampleOrthogonalPair`, *not* a posterior.

The `<130K / 2.2K` param budgets are **aspirational** (`looknet-param-count-est` unsourced).

---

## 2. How A/B nudges both training and inference

One Bradley-Terry preference channel through the 770-D θ feeds both sides. **The shipped
mechanism is the point-estimate `btUpdate` (`PreferenceUpdate.hs`, η=0.05, λ=1e-3, three laws);
everything richer is parked (§5).**

### 2.1 Inference (no retraining, bit-agreement preserved) — *shipped target*

1. **The pick updates the preference latent, not the weights.** `btUpdate` adjusts θ; the deployed
   integer graph never changes, so bit-agreement holds across devices.
2. **Taste enters decode as a σ-locked LeafOverride δ** via a closed-form linear θ→δ map (the real
   design hole in Candidate 3; owned here, **start linear, NOT a net, golden-gated**). Preference
   changes *which* δ, never the decode path.
3. **Cold-start** = federated warm-start, `personalBeta = n/(n+50)` (`fed_sim.py`, FedAvg,
   single-message Prio). This is the **measured** cold-start mechanism — *not* an empirical-Bayes
   shrinkage scalar from a covariance that does not exist (see §5).

### 2.2 Inference — *parked enrichment (Spec.TastePosterior, unbuilt)*

- Calibrated **Laplace posterior** `N(θ̄, LLᵀ)` over θ, **Double-Thompson** pair selection,
  posterior-of-record replacing random/stub pairing. **None of this exists in spec.** It is the
  largest single lever on "learns the user's look with few taps," and it is the headline item to
  *propose*, but it must earn its own `Spec.TastePosterior` with covariance/Cholesky/Thompson laws
  and golden vectors before it is canon.

### 2.3 Training (Tier-1 Mac → device)

- **v1 head training** = `btUpdate`/`btFit` over logged Compares (Mac-side warm-start + on-device
  online step). Real, spec-backed.
- **Loss-head menu (parked):** DPO/BT baseline, **IPO** (bounded squared loss, the few-tap regime
  where DPO degenerates `π_l→0`), **KTO** (unpaired — solo swipe-to-LOOK keep/dismiss as signal).
  **No IPO/KTO/DPO preference-loss head exists in spec** (the IPO/KTO grep hits are the *look-net*
  Bures/coverage/beauty `Loss.hs`, unrelated). These are pluggable-over-θ/δ *proposals*, not a
  head-swap socket that exists.
- **Expert iteration (v2, parked):** policy regresses to MCTS visit counts; value to backed-up BT
  returns; KataGo-style aux targets (coverage, beauty — zero labeling cost) densify sparse
  preference.

### 2.4 BLOCKING PREREQUISITE — the human/synthetic Compare split

The anti-collapse safety claim "β ramps on human Compares, never synthetic `shapedReward`
Compares" names a field **that does not exist**. The implemented field is **`awCompares`
(`AtlasOracle.hs:203`), which counts ALL compares including synthetic**, and `betaBlend(awCompares)`
blends on that total. **As written today, the ramp would let the net imitate the heuristic it was
meant to beat.** Adding the human-vs-synthetic Compare split to `AtlasOracle` and the wire format
is a **blocking prerequisite** before any β ramp gates training. This is a build item, not a
property.

---

## 3. Bit-exact / SIMT contract for the core

**Contract: integer-exact at the terminal, float-ordinal-only in search.** Already pinned by
`lawTerminalQuantizationIdempotent`.

- **Q16 is the only cross-device equality.** Terminal `GenomeHash`, `s4_global_collapse`,
  `s4_board_mass_q16`, `s4_cube_lift_level` are byte-exact Zig ≡ Swift ≡ Haskell ≡ Metal. Float
  Edit moves drift in low bits as **search guidance only**. We never advertise bit-exact float NN
  across devices — it is **physically unattainable** (NVIDIA/MLX), and claiming it would violate
  the doc-claims gate's spirit (§7, §5).
- **CPU-tree ↔ GPU-value boundary is a Q16 comparison key:** `q16Key v = round(v·65536)`
  (`GumbelSearch.hs:51`), with `lawArgmaxKeyDependsOnlyOnKeys`. Fixed-order tree reduction so
  CPU-sequential and GPU-tree agree on the integer tie key.
- **Every nonlinearity = fixed-point integer polynomial/LUT** (I-BERT/I-ViT style); constants
  **codegen'd from the single Haskell spec to both Zig and Metal**, never hand-duplicated (the
  silent ~1e-3 drift footgun). Integer Newton sqrt (≤4 iters) for norms.
- **Kulisch wide accumulator** (i64/i128 full Q16×Q16 products, single final round-shift) →
  order-independent reductions by construction; width ≥ `2·frac + ⌈log₂N⌉ + sign`, proven
  non-overflowing, golden-tested at extreme corners.
- **MLX is a weight factory, never a numerical oracle.** MLX float → deterministic Q16 quantizer
  (the spec) → Zig/Metal integer forward is the reference. **QAT (or a verified error bound) is
  mandatory**: float→Q16 can flip the argmax of `g + logits + σ(q)` at near-ties, silently
  breaking Gumbel's policy-improvement guarantee *while bit-agreement still passes*. Golden vectors
  must specifically probe **near-tie action rankings**.
- **Two-mode TAO harness:** strict byte-equality for integer kernels; operator-specific
  region-accept `max(IEEE-754 portable bound, p99.9)` for the float value/policy head only. Plus an
  **adversarial hazard-trap golden** forcing `a*b+c` vs `fma` and parallel-vs-serial reduction
  divergence, asserting the pinned **Metal fast-math-OFF / FP-contract-OFF** flags are actually in
  effect (the `DEVELOPMENT_TEAM`-pinning lesson, applied to compiler flags).
- Each new scalar float touchpoint (BT σ, and later IPO squared term / KTO prospect value) gets a
  fresh Q16 reassociation / `@divFloor` golden vector.

**Keystone unknown:** there is **no integer-Metal-vs-Zig golden in the repo**, and **no
`cube_lift` kernel in `SixFour/Metal/`** (only `field.metal`). The entire GPU value/policy oracle
(steps 7–8) is **blocked on a gate that has never passed once on silicon** (`no-metal-golden-gate`,
STATUS high blocker). §4 step 6 is that gate; it must land on **real A19/M silicon, not the
simulator**.

---

## 4. The build plan

Dependency-ordered. Each step is independently shippable, strictly above the floor, and de-risks
the next. **Reordered from the original proposal**: the proven value/collapse work goes first; the
brand-new perceptual warp is deferred (it inverted the de-risking order, §7).

| # | Step | Debt id / gate | Net? | State |
|---|------|----------------|------|-------|
| **D** | `BoardQ16` float-input gap | — | no | **DONE** (`s4_board_mass_q16` present, golden) |
| **D** | GLRM kill-switch built **+ wired** | `glrm` | no | **DONE** (`GLRM.swift` golden-gated; gates `AtlasTrainingSession.makeBatch` — blocks real-data training on no-signal picks; commit `4528881`). Extending the gate to a future per-pick `btUpdate` path is a small follow-up when that path lands. |
| **D** | **`s4_leaf_override`** Zig kernel (mirrors `LeafOverride.hs`, no tolerance) + `SixFourNative.leafOverride` caller, golden-gated Zig≡Swift≡Haskell (`LeafOverrideGoldenTests` + `kernels.zig` unit test) — the σ-locked taste tint at `n=0`. | (new) | no | **DONE** (kernel + binding + golden; not yet routed into a live A/B capture — that is step 2) |
| 2a | **θ→δ map** — closed-form σ-aware taste-ascent gradient `θ(770)→δ(384-DOF)`, spec-first (`Spec.ThetaToDelta`, 5 laws incl. finite-diff gradient) → Swift `ThetaToDelta` (round-half-to-even, clamped ±8192), golden-gated vs Haskell. Composes with `s4_leaf_override`. | (new) | head only | **DONE** (commit pending; spec+Swift+golden) |
| 2b | **A/B capture → `btUpdate` + apply δ** — replace the `perturb()` stub: capture the pick, fold θ via `btUpdate`, derive δ via `ThetaToDelta`, apply via `leafOverride`. The v0 unified core at **n=0** (literally Candidate 3). Extend `DecisionLog` DECN to store 770-D embeddings. | `ab-perturb-stub` | head only | NEXT |
| 3 | **Pin the implemented value net.** Give the proven 29,249-param board‖genome→V MLP its `NetIOSpec`; reconcile (or formally retire) the "linear-770 = btUpdate verbatim" claim against the architecture actually on device. | `atlas-nets-unpinned`, `atlas-value-spec-drift` | head | — |
| 4 | **Human/synthetic Compare split** — add `awHumanCompares` (or equivalent) to `AtlasOracle` + wire format; re-gate `betaBlend` on human Compares only. **Blocking for any β ramp.** | (new, §2.4) | no | — |
| 5 | **First byte-exact integer-Metal-vs-Haskell golden on `cubeLiftLevelKernel`/`cubeUnliftLevelKernel`** — the keystone determinism gate. Explicit `floorHalf` for the MSL-truncates-toward-zero vs `@divFloor`-toward-−∞ trap; fast-math OFF; three-way fan (Metal == golden == Zig == Swift) on a **negative-heavy fixture + boundary quads**; `unlift(lift(g))==g`; **on real silicon**. Gates the entire GPU value oracle. | `no-metal-golden-gate` | no | — |
| 6 | **`Spec.AtlasGame` glue + Metal value-forward oracle.** Wrap the three disjoint move systems (Edit \| Curate \| Rung) without editing PaletteSearch/AtlasMove; lift `Compare` out of the move algebra as the reward emitter; hand-write the Metal value forward with its integer-Metal golden (built on step 5's contract). | — | value forward | — |
| 7 | **Gumbel-search-over-frozen-policy at gallery time (v1).** Gumbel-Top-k root sampling (≤8) + Sequential Halving (`n=8–16`, no PUCT/Dirichlet) over the real reversible simulator; completed-Q fills unvisited actions; emit the (A,B) terminal pair with most-informative utility difference. **v1 headline: value-only search over a frozen pretrained policy.** | — | policy frozen + value | — |

Steps 1–2 require **no net** — the unified core's v0 ships before any training spine exists.
The perceptual warp (`s4_oklchplus_warp`) and the calibrated-posterior taste organ are **§5**, not
this plan, until they have specs and citations.

---

## 5. Parked / off-path

Notes-first; salvage iteratively. **Top of this list are the items the original synthesis disguised
as "reconciliation" but which have ZERO footprint in `spec/`, `trainer/`, or the design doc** —
they are net-new design debt, each owing its own spec + in-repo citation before it can be canon.

### 5.1 Proposed-but-unbuilt taste/perceptual surface (demoted from "canonical core")

| Item | Tag | Why parked |
|------|-----|-----------|
| **`s4_oklchplus_warp` + `Spec.OklchPlus`** (3-param L-power + C-Naka-Rushton perceptual warp, "near-CIEDE2000") | `PROPOSE-SPEC` | **Zero oklch/CIEDE2000/Naka-Rushton hits anywhere.** Entirely external research import. Owes: a spec (monotone / identity-at-unit-params / byte-exact-LUT laws), an **offline gamut re-fit on SixFour's actual capture gamut** (sRGB-fitted constants must not be adopted raw), an in-repo CIEDE2000 citation, and a GLRM kill-switch. **Do NOT front the plan with it** — it was the least-grounded, most-novel item placed first. |
| **`Spec.TastePosterior`** (Laplace BT posterior `N(θ̄,LLᵀ)`, Q16 covariance + low-rank Cholesky, Double-Thompson pairing) | `PROPOSE-SPEC` | `PreferenceUpdate.hs` is **point-estimate `btUpdate` only** — no covariance, Cholesky, posterior, or Thompson. This is net-new math, not connective tissue. It *is* the biggest taste lever; build it as its own spec, do not claim it is reconciled. |
| **IPO / KTO preference heads** | `PROPOSE-SPEC` | No IPO/KTO/DPO *preference* loss exists; the grep hits are the look-net beauty/coverage loss. No "head-swap socket over θ/δ" exists. |
| **Ou-Luo harmony cold-start prior over σ-pair structure** | `PROPOSE-SPEC` | Ou-Luo exists only as the look-net `beautyLoss` heuristic (`Loss.hs`, Color Res. Appl. 2006), **not** a preference cold-start prior. Reframe is fine; presenting it as an existing known-good baseline is not. |
| **Empirical-Bayes shrinkage cold-start** | `PROPOSE-SPEC` | The measured mechanism is `fed_sim.py` FedAvg + `n/(n+50)`. A shrinkage scalar from a Q16 covariance that does not exist is unsupported. |

### 5.2 Built-and-dormant (salvage-ready infrastructure)

| Item | Tag | Salvage |
|------|-----|---------|
| **RGBT-4D Cube-Ladder** | `PARK-DORMANT` | Spec + Zig kernels (`s4_rgbt_lift_quad`/`unlift`, `s4_cube_lift_level`/`unlift`) + Swift port COMPLETE and golden-gated; `rgbt4dEnabled` OFF, 0 callers. Activate by: facade methods on `SixFourNative`, wire `RGBT4DLift.swift`, Settings toggle, Phase-5b Metal circular-stencil kernel. Reuse all proven byte-exact fixtures. |
| **`s4_load_look_net` loader** | `PARK-DORMANT` | Implemented, fixture-verified, zero callers. Reuse the S4LN format + parser + round-trip golden when a retrained net produces real weights. |
| **Two 256³ products (GIFA/GIFB)** | `PARK-DORMANT` | `Spec.ExportFamily`/`Upscale256`/`CubeLadder` + `synthBeyond` floor proven; no on-device 256³ export port. Salvage spec + Q16 proofs (`lawLadderConsistencyDownUp`, `lawTier256FloorIsNearestNeighbour`, `lawZeroGenomeIsFloor`); both rungs carry the same genome block (federation-ready). |
| **`PaletteSearch` MCTS + `PaletteOracle`** | `PARK-DORMANT` | Spec-complete (rose-tree, PUCT, seeded ties, `greedyGallery` DPP). Zero iOS consumers. Wiring needs a real learned policy/value + a swipeable-gallery UI. The Oracle is the plug point for the learned heads. |
| **`PaletteValue` value head** | `PARK-DORMANT` | Deterministic aesthetic objective (`beautyLossLeaves` + `gaussianColorEntropy`), golden-tested, zero runtime callers. **This is the objective the learned value head approximates** — reuse verbatim when search wires in. |
| **`GenomeBlend` / `GenomeCarrier` / `ExportFamily`** | `PARK-DORMANT` | Federated-import specs, fully designed, zero consumers. Salvage 6+8 laws, S4GN codec, replay-deterministic composition. Dependency for federated genome adoption (v2+). |
| **Atlas policy net** | `PARK-DORMANT` | Forward oracle (`Spec.AtlasNetEval`) + game interface + factored logits `node[127]×delta[12]`. **No `NetIOSpec`** (`ATLAS_TOKEN_DIM`/`N_VOCAB` live only in trainer Python). Blocker: add `ATLAS_POLICY` to `Spec.Net.hs` or retire to trainer-only. (Step 7 needs this trained; it is not yet trainable.) |
| **`GenomePair` A/B spec** | `PARK-DORMANT` | `sampleOrthogonalPair` (two disjoint parity-interleave generator bands, exact-0 inner product) designed; device path is the `perturb()` stub. Wiring is O(100 LOC): port with fixed seed, integrate `AtlasState.choose`, extend `DecisionLog` DECN to store full 770-D embeddings (currently hash-only). |

### 5.3 Salvage-ideas-only / abandoned

| Item | Tag | Note |
|------|-----|------|
| **Look-NN supervised MLX trainer** | `SALVAGE-CANDIDATE` (abandoned) | Trained artifacts DELETED 2026-06-17; trainer errors on them. Salvage *ideas* (384-DOF σ-pair, σ-equivariance proof, PonderNet halting) into the Atlas core. Forward oracle specs + `s4_load_look_net` KEPT. |
| **Mac-only MLX training path** | `PARK-DORMANT` | Tier-1 research; never ships. Successor design = `Spec.AtlasNetEval`/`AtlasGame`/`GumbelSearch`; device spike = `AtlasTrainer.swift` (proven). |
| **Rust `studio` baseline (1+1-ES)** | `PARK-DORMANT` | Non-NN gamut-coverage floor; **incompatible with current spec** (768-flat genome, not 384-DOF σ-pair). Needs `SIGMA_PAIR_DOF=384` contract update before reuse. |
| **CoreML / ANE training fallback** | `PARK-DORMANT` | Reference only; does not ship. On-device = MPSGraph (first-party). |

### 5.4 Rejected / out of scope

- **Candidate 2 (supervised MSE regressor) — REJECTED, not parked.** No preference channel;
  re-commits the Lloyd-Max-ceilinged MSE objective that killed the grayscale-L net (abandoned
  2026-06-17). Harvest **only** its forward oracle (`reconstructPaired`, `s4_load_look_net`).
- **Candidate 4's standalone ~115K-param residual net — NOT BUILT.** The BT value head *is* that
  residual; the in-repo param budget is unsupported. (Its *contract* — deterministic base + gated
  correction + perceptual target + integer terminal — is adopted.)
- **`VoxelCubeView` 3D raymarcher — DELETED** (2026-06-07, `DELETE-CANDIDATE`). State retained for
  the flat 2D rasterizer; if a 3D explorer returns, build fresh on the lattice/cell-grid.
- **MLX-Swift on device — RULED OUT** (`DELETE-CANDIDATE`). Architectural boundary; MLX stays
  Mac-side. On-device training = first-party MPSGraph only.
- **Float NN bit-exactness across devices — out of scope by physics.** Never claimed.

---

## 6. How this reconciles all four candidate approaches

**Skeleton: genuinely one machine.** `lawTerminalQuantizationIdempotent` forces every terminal
through the Q16 floor, so "learning is a bounded addition on a deterministic floor" is a real,
spec-backed unifier — not rhetoric. The three operating points are a clean, defensible subsumption:

- **Candidate 3** (deterministic + LeafOverride δ) = this core at **`n=0`, policy deleted**.
- **Candidate 4** (gated residual) = this core at **`n=1`, GLRM gate exposed**.
- **Candidate 1** (AlphaZero) = this core at **`n=8–16` Gumbel-tree**.
- **Candidate 2** (supervised MSE regressor) = the one true **rejection** (§5.4); only its forward
  oracle is harvested.

**Honest correction to the original synthesis.** The original framing also claimed to reconcile a
"Candidate 2 taste lens" (Laplace-BT posterior + Double-Thompson + IPO/KTO) *into* the existing
stack and crowned it "where the taste lens is won." That taste organ has **zero footprint** in
`spec/`, `trainer/`, or the design doc. It is **net-new research appended as reconciliation**, and
it is **demoted to §5.1 (proposed-spec)**. The reconciliation that *is* real is the skeleton + the
point-estimate `btUpdate` channel that genuinely exists. The richer taste organ is the right *next
research bet*, not a settled merge.

---

## 7. Open questions + the research that informed this

### 7.1 In-repo grounding (verified)

- `lawTerminalQuantizationIdempotent` — `spec/src/SixFour/Spec/AtlasGame.hs:174` ✓
- `q16Key v = round (v*65536)`, `lawArgmaxKeyDependsOnlyOnKeys`, `sequentialHalving` (no
  PUCT/Dirichlet) — `spec/src/SixFour/Spec/GumbelSearch.hs:51` ✓
- `btUpdate` (η=0.05, λ=1e-3, dims=770), `btFit` (documented non-law) —
  `spec/src/SixFour/Spec/PreferenceUpdate.hs` ✓
- `s4_global_collapse`, `s4_cube_lift_level`, `s4_board_mass_q16` present;
  `s4_oklchplus_warp`, `s4_leaf_override` **absent** — `Native/src/kernels.zig` ✓
- `awCompares` is the only Compare counter and counts ALL compares;
  `awHumanCompares` **does not exist** — `AtlasOracle.hs:203` ✓ (→ §2.4 blocking prerequisite)
- Proven device net = 29,249-param nonlinear MLP over `board[4096,6] ‖ genome[384]` → V, no
  `NetIOSpec` — `SixFour/Atlas/AtlasTrainer.swift` ✓ (→ §1.4, step 3)
- Ou-Luo = look-net `beautyLoss` heuristic only (Color Res. Appl. 2006), **not** a preference
  prior — `spec/src/SixFour/Spec/Loss.hs:25–28` ✓

### 7.2 External research that *informed the design* (cite in-repo before adopting)

These are **not yet grounded in the repo** and each is parked (§5.1) pending its own spec + a
citation landed in-repo:

- **Maximin floor lineage.** STATUS canon names the floor **Gonzalez 1985 farthest-first,
  Lloyd-refined**. Maximin is a **2-approximation heuristic, not MSE-optimal**; calling it
  "Lloyd-Max / MSE-optimal" conflates the maximin seed with 1-D Lloyd-Max optimality and overstates
  it. Correction adopted in §1.3. (Open: does a 1-D Lloyd-Max refinement actually sit on the
  shipped path, or only the maximin seed? Resolve before any "no net beats the floor" claim.)
- **Gumbel-AlphaZero / policy improvement under quantization** (Danihelka et al. 2022). Informs §3's
  near-tie QAT requirement; the policy-improvement guarantee is what float→Q16 argmax flips can
  silently break.
- **Preference optimization in the few-tap regime** (DPO; IPO bounded-loss; KTO unpaired). Motivates
  §2.3's parked head menu; not in spec.
- **Calibrated BT posterior + Double-Thompson dueling-bandit pairing.** Motivates §2.2's parked
  `Spec.TastePosterior`; not in spec.
- **Oklch / Naka-Rushton / CIEDE2000 perceptual warp.** Motivates the parked `s4_oklchplus_warp`;
  the 3-param form and CIEDE2000-equivalence claim are **uncited in-repo** and the constants are
  sRGB-fitted (require gamut re-fit).
- **Cross-device float non-determinism** (NVIDIA/MLX). Grounds §3's refusal to advertise float-NN
  bit-exactness.

### 7.3 Open questions

1. **Policy trainer.** v1 is value-only over a policy with **no trainer, no target, no on-device
   path**. What produces the "frozen pretrained policy" in step 7? (Candidate: expert-iteration to
   one-ply top-8 oracle as a stopgap, then visit-count regression in v2.)
2. **Value-net architecture of record.** Is the shipped head the 770-D linear `btUpdate` or the
   proven 29,249-param board‖genome MLP? They differ in inputs and class. Step 3 must pick one and
   pin its `NetIOSpec` (`atlas-value-spec-drift`).
3. **θ→δ map.** Start linear (golden-gated) — does linear suffice, or does it need the σ-pair
   structure baked in? Resolve empirically at `n=0` before adding capacity.
4. **Does `n=0` tinting feel like personalization,** or does taste demand `n>0` re-selection? This
   gates how hard to push search vs. the δ tint.
5. **Param budget.** `<130K / 2.2K` is unsourced (`looknet-param-count-est`). Measure against the
   29,249-param reality.

---

## Confidence & caveats (verified vs. design)

**VERIFIED (spec/kernel/STATUS-backed, safe to build on):**

- The spine: one policy+value predictor as a bounded addition above a Q16-idempotent maximin floor,
  read at `n=0/1/8–16`. Spec-backed by `lawTerminalQuantizationIdempotent`, `q16Key`,
  Compare-as-reward.
- The three present kernels (`s4_global_collapse`, `s4_cube_lift_level`, `s4_board_mass_q16`) and
  the `btUpdate` point-estimate channel.
- The rejection of Candidate 2 and the harvest of its forward oracle.
- The zero-dep contract (MPSGraph/Metal/Zig only; no MLX-swift/CoreML on device).
- **DONE:** `board-q16` (float-input gap closed), `glrm` kill-switch built (wiring is step 1).

**DESIGN / PROPOSED (no in-repo footprint — do NOT treat as settled):**

- The entire enriched **taste organ** (Laplace posterior, Double-Thompson, IPO/KTO heads, θ→δ map,
  Ou-Luo prior, empirical-Bayes shrinkage) — greenfield specs, §5.1.
- The **`s4_oklchplus_warp`** perceptual warp — new kernel, new spec, uncited CIEDE2000 claim,
  needs a gamut re-fit; deferred out of step 1.
- The **policy trainer** and the `<130K/2.2K` param budgets — aspirational.

**BLOCKERS (must clear before the relevant step is safe):**

- **`no-metal-golden-gate`** — no integer-Metal-vs-Zig golden has ever passed on silicon; no
  `cube_lift` kernel in `SixFour/Metal/`. Gates the entire GPU oracle (step 5 is the gate).
- **Human/synthetic Compare split** — `awCompares` counts both; without the split the β ramp lets
  the net collapse onto the heuristic it was meant to beat. **Blocking prerequisite** (step 4).
- **`atlas-nets-unpinned` / `atlas-value-spec-drift`** — the proven head differs from the headline
  head and has no `NetIOSpec` (step 3).

**One-line honest headline:** *Gumbel-search over a learnable Bradley-Terry value on a frozen
deterministic maximin floor; v1 ships value-only search over a frozen policy, with the calibrated
taste organ and the perceptual warp as the next, separately-specced research bets — not as settled
reconciliation.*
