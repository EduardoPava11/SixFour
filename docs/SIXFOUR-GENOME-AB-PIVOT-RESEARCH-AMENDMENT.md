# SixFour — Genome A/B Pivot: research-backed amendment (prior-art + 9 papers)

> Keywords: prior-art reconciliation, KataGo auxiliary-target decomposition, KataGo gated
> promotion, two-clock cadence retargeted onto θ btUpdate, exact period-64 Q16 cosine-LUT loop
> closure, MERIT cascade over s4_haar, cold-start ranking for sampleOrthogonalPair, rejected
> float/population machinery (CMA-ES / NEAT / CPPN-LVE).

> **One sentence:** the `~/CubeGIF` prior art and the 9 papers do **NOT** add a generator or a
> second orthogonality basis to the pivot — they *confirm* the already-decided three-object
> ontology (384-DOF σ-pair = generator; band-disjoint 384-D Haar-coefficient support = exact-0
> orthogonality; 770-D Bradley-Terry θ = ranker) and instead close the loop's **training** and
> **temporal** risks, landing entirely off-device or on kernels SixFour already owns.

**Status:** research-backed amendment (2026-06-16). **AMENDS — does not restate —**
`SIXFOUR-GENOME-AB-PIVOT-WORKFLOW.md` (the pivot). Every section here is a delta against that
plan; module names, laws, build steps, and the decision ledger (Q1–Q11) referenced below live
there in full and are NOT reproduced. Companion to the same docs the pivot lists
(`SIXFOUR-DISPLAY-FSM.md`, `SIXFOUR-ACTS-WORKFLOW.md`, `SIXFOUR-LOOK-LUT-WORKFLOW.md`,
`SIXFOUR-RGBT4D-REMAINING-WORKFLOW.md`). SixFour owns all code; the Haskell spec is the source of
truth, codegen-pinned. Per the camera-app rule, the bar stays **BUILD SUCCEEDED** + green gates;
on-device look/A/B legibility is the user's verification step.

---

## 0. What the prior art actually is (and what it is not)

The `~/CubeGIF` repository is the SixFour predecessor: a population-based, **19-frame**, **float**
GIF look engine. The amendment is grounded in its real code, not in a summary of it. The
load-bearing facts — verified against source — are:

- **It is 19-frame, not 64-frame.** `HierarchicalLambdaGenes.swift:117` (`T = …frames // 19
  frames`); the loop-closure trick is `cos(2π×t/19)` so that `cos(2π×18/19) ≈ cos(0)` —
  **approximate**, by its own comment (lines 155, 206, 934). SixFour's period is `2^6 = 64`, which
  makes the same closure **exact**; that is a SixFour property, not inherited evidence.
- **It is float and non-deterministic.** `Float.random` is the cold-start and mutation source
  (`GenePool.swift:325–326, 333, 519, 883, 890`); the genes carry float `spatialLambda`/
  `temporalLambda` (`DualGIFService`/`GenePool.swift:172–203`); CoreML runs `computeUnits = .all`
  (`DualGIFService.swift:111`) — i.e. ANE + GPU + CPU, the opposite of SixFour's byte-exact Q16
  contract.
- **It is population-based.** `recordABResult` (`GenePool.swift:719`) drives a per-gene float EMA
  (`recordSelection`, `alpha = 0.3`, line 301/308) and a generational `evolveGeneration`
  (line 730: `totalSelections % 10 == 0`, line 762) with crossover/mutation. There is **one θ per
  user** in SixFour — there is no population to evolve.

So the pivot's R1 (proposer) and R2 (orthogonality) are **NOT open gaps the research "solves."**
They are **design decisions** (pivot decision ledger Q1–Q4) that the research **must not regress
against**. The 9 papers' genuine, contract-safe contribution is to close the loop's *training* and
*temporal* risks — **R3** and **R5** — and to supply a cold-start heuristic + a gating safety net
for R1/R2 with **no architectural change**. Everything float/population (CMA-ES, NEAT
speciation/crossover, the CPPN-coordinate→latent reframe that risks resurrecting the **deleted**
`buresBarycenter`) is rejected outright.

---

## 1. Risks closed (R1–R5)

| Risk | Status | Closed by | Lands on |
|---|---|---|---|
| **R3** — on-device training: cold-start + verified preference-update + cadence | **CLOSED (concrete, spec-first)** | KataGo auxiliary-target decomposition + KataGo gated promotion + CubeGIF two-clock cadence, all **retargeted onto the existing `PreferenceUpdate.btUpdate`** (η=0.05, λ=1e-3) θ step | Mac/MLX θ-trainer (off-device); `Spec.PersonalGenome` (`btUpdate`, `replay`, checkpoint already wired) |
| **R5** — cube ladder {16,64,256} + 64-frame GIF-loop temporal coherence | **CLOSED (byte-exact)** | new `Spec.TemporalLoop` = **exact period-64 Q16 cosine LUT** + **MERIT** cascade over owned `s4_haar_*` + **VMC** motion-as-low-band residual + **StoryDiffusion** reframed as W₂-barycenter anchoring | `s4_haar_analyze`/`reconstruct`/`level_nodes`, `s4_global_collapse` (all owned) |
| **R1** — proposer gap ("θ only ranks, no generator") | **NOT a gap — premise rejected.** Live sub-gap (cold-start ranking) closed | σ-pair **IS** the decided generator (Q4); the `error "TODO"` in `sampleOrthogonalPair` closed by a deterministic capture-measure ranking | `Spec.GenomePair` (keystone, currently a stub) |
| **R2** — orthogonality (two 16³ candidates distinct AND valid) | **NOT a gap — category error.** No imported technique needed | band-disjoint 384-D Haar coefficient support = exact-0 (Q1/Q2); spatial-vs-temporal **demoted** to a band-PARTITION heuristic riding on top | `Spec.GenomePair` (selector only) |
| **R4** — 256³ synthesis / continuous space-time floor | **NOT closed by INR/LVE — deterministic floor retained** | `synthBeyond` nearest-neighbour floor stays canonical (Q9); ActINR/CPPN-LVE deferred or rejected | `Spec.ExportFamily` / `NetSynth256` (gated enhancement only) |

### R3 — how (the live training risk)

Three contract-safe moves, **all off the shipped Q16 forward**:

1. **Sample efficiency.** A single A/B pick is as data-starved as KataGo's one-bit game outcome.
   Add **TRAIN-TIME-ONLY auxiliary losses** — coverage, per-axis OKLab diversity, significance, a
   64-frame temporal-coherence residual, chosen cut-level — on the Mac/MLX θ trainer to localize
   gradients. Labels are cheap because the `Spec.Coverage` / `Spec.Significance` / `Spec.Entropy` /
   `Spec.Diversity` oracles already emit them deterministically (note: cheap-to-*generate* over a
   synthetic corpus, **not** a pre-existing labelled corpus — see §7 open conflicts). The aux heads
   are **never shipped**, so the on-device Q16 surface is unchanged.
2. **Cadence.** Keep CubeGIF's fast-clock (per-pick) / slow-clock (every-N) split, but **retarget**
   the fast clock from `GenePool` gene-EMA to a **Q16 `btUpdate` on the 770-D θ** per logged
   `Compare`. The slow clock is **not** population evolution (there is no population) — it is a
   **gated promotion checkpoint**.
3. **Cold-start safety.** KataGo gates a candidate net (promote only if it WINS). Reframed with no
   on-device opponent: a candidate θ must **reproduce the user's last K logged picks above a
   deterministic integer threshold** before promotion (offline replay test). CubeGIF's bare EMA has
   **no such gate**, so this is a genuine gap-filler. `Spec.PersonalGenome` already wires
   `btUpdate`/`replay`/checkpoint, so the landing spots exist.

### R5 — how (the temporal/multi-scale risk)

Temporal coherence becomes a **PROVABLE integer identity**, strictly stronger than CubeGIF's
approximate `cos(2π×18/19)`. Period **exactly 64 = 2^6** means a Q16 cosine LUT indexed by
`t∈[0,63]` wraps `LUT[63·step] → LUT[0]` by integer identity (frame 63 abuts frame 0 exactly).
**This is a SixFour property of the power-of-two period, NOT inherited from CubeGIF.** Multi-scale:
the `{16,64,256}` ladder is a **MERIT-style cascade** (solve 16³ → exact ×4 integer upsample → feed
as a Q16 skip-residual into 64³, then 256³) realized over the **already-owned** `s4_haar_analyze` /
`reconstruct` / `level_nodes` with clean power-of-two ratios; `ExportFamily.hs` already names
`TemporalPool`/`NetSynth256` and `lawLadderConsistencyDownUp`. **Motion** = a low-frequency Q16
displacement residual via the owned `s4_haar` low band (**VMC** principle; diffusion dropped),
aligning with SixFour's existing palette-is-motion prior. **Loop appearance-consistency** is
**structural** — every per-frame palette is a child of ONE W₂-barycenter collapse
(`s4_global_collapse`) — **not** on-device attention (the **StoryDiffusion** shared-reference idea,
reframed).

---

## 2. Decisions revised (against the pivot ledger Q1–Q11)

| # | Decision | Was (pivot) | Now (amended) | Why |
|---|---|---|---|---|
| D1 | Cold-start proposal when n<8 Compares | §6 open risk; `sampleOrthogonalPair = error "TODO"`, no concrete mechanism | Deterministic **capture-measure** ranking: per-Haar-level coefficient variance of base genome `g0` selects the highest-energy disjoint band-sets `S_A`/`S_B`. θ-independent, pure, golden-pinned. θ re-ranks only once n≥8. | Closes the documented day-1 degradation cleanly and keeps the "NN proposes two" promise honest from the first capture **without inventing a generator**. KataGo's founder-warm-prior says ship a fixed Q16 prior, not `Float.random`; a capture-measure ranking is the integer-deterministic analogue. |
| D2 | What the slow clock (every-N picks) DOES | Implicitly inherited as population evolution (`totalSelections % 10 → evolveGeneration`) | A **gated θ-promotion checkpoint** (offline replay vs last K picks ≥ integer threshold). No population to evolve; the only slow-clock work is regression-safe promotion of a candidate θ. | SixFour ships ONE θ per user; CubeGIF's `evolveGeneration` has nothing to evolve under this ontology. KataGo gating fills the safety gap the bare EMA lacks, deterministic over the pick-log. |
| D3 | Temporal-loop coherence guarantee | `Spec.Cyclic.hs` is a **float** OT/entropy reference oracle on `Z_T × S_K` (no Q16 closure identity) | Add a **NEW `Spec.TemporalLoop`**: a fixed period-**exactly-64** Q16 cosine LUT whose wrap `LUT[63·step]→LUT[0]` is a provable integer identity (`lawTemporalLoopClosesExact`). Keep `Spec.Cyclic` as the float analysis oracle; do **NOT** conflate them. | `Spec.Cyclic` only characterizes a cyclic process statistically; it gives no byte-exact wrap. Exact closure is a SixFour property of period=2^6, explicitly NOT imported from CubeGIF's approximate 19-frame cosine. |
| D4 | Sample efficiency of the θ trainer | θ trained from the lone binary A/B outcome (one informative bit/pick); no auxiliary supervision named | Add **TRAIN-TIME-ONLY** aux losses (coverage / OKLab diversity / significance / temporal-coherence residual / chosen cut-level), with KataGo `c_g` up-weighting the scarce A/B target + L2 prior. Aux heads **never ship**. | A lone pick is data-starved like KataGo's one-bit outcome; sub-signals are already computed by deterministic oracles, so labels are cheap to *generate*. Zero Q16/determinism cost because nothing ships in the forward. (Corrects the "free labels" over-claim: cheap-to-generate, not pre-existing.) |
| D5 | Federated foreign-genome adoption regression safety | One logged BT `.compare` per foreign genome (Q5), receiver-confidence-weighted trust; repeated-blend collapse flagged only at the single-step trust weight | Layer **KataGo gated promotion over the blend path too**: a foreign-seeded candidate θ must pass the **same** offline replay-vs-recent-picks gate before it can move the shipped θ. | `lawHighLocalConfidenceResistsBlend` bounds one step, but the multi-sender policy is only sim-validated (`fed_sim`). The gate makes repeated-blend wash-out regression-safe with a deterministic integer verdict, **reusing the R3 mechanism**. |

---

## 3. Import from CubeGIF (with Q16 adaptations)

Each row is a **shape/principle** steal; the float/population/CoreML carrier is discarded. File
references are to the verified prior art under `~/CubeGIF`.

| What (principle only) | From file | As what (SixFour) | Q16 adaptation |
|---|---|---|---|
| **Two-clock cadence** (learn-every-pick / regenerate-every-N) | `~/CubeGIF/CubeGIF/Neural/GenePool.swift` `recordABResult` (≈L719; `totalSelections % 10` L730) | `Spec.PersonalGenome` orchestration → Swift `PersonalGenomeStore` + `AtlasTrainingSession` off-main flywheel | Modulo cadence is integer counter arithmetic — drop in as a **named Spec constant**. **Retarget FAST clock** from gene-EMA to a Q16 `btUpdate` on the 770-D θ per `Compare`. **Retarget SLOW clock** from `evolveGeneration` (no population) to a gated θ-promotion checkpoint. |
| **Online per-pick preference-update SHAPE** (O(1)/pick, cold-start-friendly) | `GenePool.swift` `AttentionGene.recordSelection` (≈L301; `alpha = 0.3` EMA L308) | `Spec.PreferenceUpdate.btUpdate` (**already exists**) invoked from `Spec.PersonalGenome.applyPick` | Port the **cadence/shape, NOT the math, NOT the target**. CubeGIF's `alpha=0.3` float EMA toward 1/0 is (a) non-deterministic, (b) not Bradley-Terry, (c) updates per-**gene** fitness — the wrong object. SixFour already has the real Q16 logistic step (η=0.05, λ=1e-3, sigmoid via the embedded-1D-LUT pattern) over the 770-D θ. Keep only the integer `winCount`/`selectionCount` counters. |
| **Gated promotion** (SWA snapshot + 200-game gate) | `KataGo_Accelerating_SelfPlay.pdf` (SWA EMA snapshots + gating test); gap vs `GenePool.swift` (**no gate**) | new `lawGatedPromotion` law-set in `Spec.PersonalGenome` + Swift candidate-θ promotion in `PersonalGenomeStore` | No on-device opponent → reframe "win 100/200 games" as an **offline replay test**: candidate θ must reproduce the last K logged picks above a deterministic integer threshold before promotion. SWA EMA snapshot → deterministic Q16 running average. CubeGIF's bare EMA has no gate, so this is **net new** safety. |
| **Spatial-vs-temporal A/B axis** (CONCEPT only: one semantic dominance axis → two intrinsically-distinct candidates) | `GenePool.swift` `ABStrategy` (≈L131; `spatialLambda`/`temporalLambda` L172–186) + `DualGIFService.swift` `generateDualGIFs` (≈L135) / `getBestGenes(.spatial / .temporal)` (L147–148) | a **band-PARTITION heuristic** inside `Spec.GenomePair.sampleOrthogonalPair` that picks WHICH disjoint band-sets `S_A` vs `S_B` go to A vs B | **DEMOTED** from "orthogonality basis" (category error) to a partition selector **riding on top of** band-disjoint Haar's exact-0 guarantee. Float `spatialLambda`/`temporalLambda` + float attention temperature + non-deterministic CoreML discarded; only "one axis → two valid distinct candidates" survives, realized as which Haar levels (coarse/low-freq vs fine/high-freq) seed `S_A` vs `S_B`. **Never replaces band-disjointness.** |
| **Versioned founder-blob cold-start** (warm prior + always-runs fallback) | `GenePool.swift` `loadKataGoFoundersIfNeeded` (≈L1193; Xavier `Float.random` fallback L883/890) | a pinned **Q16 founder θ golden blob** (mirroring the existing `s4_load_look_net` / `export_look_net_blob.py` container) loaded by `PersonalGenomeStore` | Payload becomes the **770-D θ** (and optionally founder band-partition presets), NOT float QKV genes. Replace `Float.random` Xavier fallback with a **fixed deterministic seed**. Spec a golden vector for the loaded founder θ. |
| **Cyclic temporal index encoding** (PRINCIPLE: encode t so frame N-1 abuts frame 0) | `~/CubeGIF/CubeGIF/NeuralPipeline/HierarchicalLambdaGenes.swift` `PositionEncoding.cyclic` (≈L214) + `CyclicPEGene` amplitude/phase (≈L268) | **new `Spec.TemporalLoop`** → codegen Swift/Zig (**NOT** into the existing float `Spec.Cyclic`) | Keep ONLY the principle, make it **EXACT**: a fixed Q16 cosine LUT of period **exactly 64 (=2^6)** so the wrap is a provable integer identity — strictly stronger than CubeGIF's `cos(2π×18/19)` at T=19. Discard float sin/cos and the amplitude/phase **mutation** knob (no genome to mutate under the θ-ranker ontology). |
| **Innovation-number monotone counter + per-gen log** (ONLY if structural crossover is ever adopted) | `~/CubeGIF/Sources/CubeGIFNeural/NEAT/CPPN.swift` `Connection.innovationId` (≈L253) + crossover (≈L675) | **shelved — NOT built**; recorded as a deferred substrate | Inherently deterministic and Q16-trivial, but it is **population-crossover machinery** the single-θ pivot does not need. Do NOT build preemptively; note as available if SixFour ever adopts a growable structural genome (it likely will not). |

---

## 4. Amended / new spec modules + laws

All four below are deltas; the pivot §2 module list and its existing laws are unchanged except
where named.

### 4.1 `SixFour.Spec.GenomePair` — **AMEND** (currently `sampleOrthogonalPair = error "TODO"`)

Implement `sampleOrthogonalPair` with a **deterministic cold-start `Ranking`** when θ is untrained
(n<8): per-Haar-level coefficient-variance of base genome `g0` selects the highest-energy disjoint
band-sets `S_A`/`S_B`; θ re-ranks once trained. Add the **spatial/temporal-flavoured band-partition
heuristic** (coarse/low-freq levels → `S_A`, fine/high-freq → `S_B`) as the selector that rides
**on top of** band-disjointness.

- `lawColdStartRankingDeterministic` — `sampleOrthogonalPair` with θ=0 (n=0) is a pure function of
  `g0`'s per-band variance, identical cross-device.
- `lawColdStartStillOrthogonal` — the cold-start `S_A`/`S_B` remain band-disjoint ⇒ `genomeInner =
  0` **EXACTLY** even before any `Compare`.
- `lawSelectorRidesOnDisjoint` — the spatial/temporal partition heuristic only chooses an
  **assignment** of already-disjoint band-sets; it can never produce overlapping support (existing
  `lawBandDisjoint` preserved).

### 4.2 `SixFour.Spec.TemporalLoop` — **NEW** (distinct from the existing float `Spec.Cyclic`)

A fixed period-**exactly-64** Q16 cosine LUT indexed by `t∈[0,63]`, realizing exact GIF-loop
closure as an **integer identity**. Carries the per-channel low-frequency Q16 displacement residual
(VMC principle) over the owned `s4_haar` low band. Codegen Swift/Zig.

- `lawTemporalLoopClosesExact` — `LUT[step·63]` wraps to `LUT[0]` by integer identity (**NOT** an
  ε; explicitly a SixFour period-2^6 property, **not CubeGIF-inherited**).
- `lawTemporalResidualLowFreq` — the temporal residual is **exactly** the `s4_haar` low band (high
  band dropped), deterministic Q16.
- `lawTemporalDeterministic` — pure function of `(t, genome)` ⇒ identical cross-device.

### 4.3 `SixFour.Spec.PersonalGenome` — **AMEND** (already wires `btUpdate`/`replay`/checkpoint)

Add the **gated θ-promotion checkpoint** (offline replay vs last K logged picks ≥ integer
threshold) on the slow clock; add the two-clock cadence constant. Extend the gate to cover
**foreign-genome-seeded** candidate θ (federated regression safety, D5).

- `lawGatedPromotion` — a candidate θ is promoted ONLY if it reproduces the last K logged picks ≥
  threshold; the verdict is a reproducible integer comparison over the deterministic pick-log.
- `lawPromotionMonotoneCadence` — the promotion checkpoint fires on a fixed integer cadence (named
  Spec constant), deterministic.
- `lawBlendGatedToo` — a foreign-seeded candidate θ passes the **same** gate before moving the
  shipped θ (reuses `lawBlendIsACompare`).

### 4.4 Mac/MLX θ-trainer aux losses — **TRAIN-TIME ONLY** (Haskell-spec'd loss, codegen MLX; never shipped)

Add weighted auxiliary losses (coverage / per-axis OKLab diversity / significance / 64-frame
temporal-coherence residual / chosen cut-level) to the θ training objective, with KataGo `c_g`
up-weighting the scarce A/B target + an L2 prior. Labels are generated by the existing
deterministic oracles over a synthetic corpus.

- `lawAuxNeverShipped` (train-time-only — **no shipped Q16 law**) — the aux heads are absent from
  the codegen Swift/Zig forward; only the 770-D θ ships, so the determinism surface is zero.
- *Reuse:* `Spec.Coverage` / `Spec.Significance` / `Spec.Entropy` / `Spec.Diversity` emit the
  labels deterministically.

---

## 5. Build-order deltas (against the pivot §3 sequence)

The eight pivot steps are unchanged in identity and gate discipline; these are scope edits and one
new sub-step.

- **Step 2 (`Spec.GenomePair` keystone) — EXPAND scope.** It is currently a stub
  (`sampleOrthogonalPair = error "TODO"`). Add the deterministic cold-start capture-measure
  `Ranking` (per-Haar-level coefficient variance of `g0`) + the spatial/temporal band-partition
  selector + `lawColdStartRankingDeterministic` / `lawColdStartStillOrthogonal`. **This is what
  makes the A/B screen have REAL candidates day-1** (closes the pivot §6 "θ ranks but does not
  generate" hard dependency).
- **Step 3 (`Spec.PersonalGenome`) — ADD.** the gated θ-promotion checkpoint (`lawGatedPromotion`)
  + the two-clock cadence constant + the KataGo aux-loss hooks **on the Mac/MLX trainer ONLY**. The
  shipped per-pick `btUpdate` is unchanged; the additions are the regression gate and the
  off-device sample-efficiency layer.
- **NEW Step 5.5 — `Spec.TemporalLoop`** (between steps 5 and 6). The period-64 Q16 cosine-LUT
  loop-closure module + low-freq temporal residual over the `s4_haar` low band; codegen Swift/Zig
  with golden wrap-identity vectors. **Slots before `GenomeCarrier`** because `ExportFamily`
  (step 8) consumes it for the 64-frame rungs.
- **Step 7 (`Spec.GenomeBlend`) — ADD `lawBlendGatedToo`.** Route foreign-seeded candidate θ
  through the same step-3 promotion gate, closing the repeated-blend consensus-collapse open risk
  beyond the single-step trust weight.
- **Step 8 (`Spec.ExportFamily`/`TemporalPool`/`NetSynth256`) — CONSUME `Spec.TemporalLoop`** for
  exact 64-frame loop closure on all rungs. Keep `synthBeyond` as the 256³ floor (**Q9 unchanged**)
  — do **NOT** pull in ActINR/`Upscale256` as the primary path. `NetSynth256` stays the gated,
  golden-pinned-equal-at-zero-genome enhancement.

---

## 6. Papers to fetch

| Paper | Why fetch | Priority |
|---|---|---|
| **HyperNEAT** (Stanley, D'Ambrosio, Gauci 2009) | The genuine indirect-encoding-over-a-geometric-substrate paper. The findings repeatedly invoke a "CPPN-coordinate→latent" reframe that **CubeGIF does NOT actually implement** (its CPPN emits 6 attention scalars, no latent/frozen-GAN). Fetch to judge honestly whether a coordinate→substrate front-end could EVER reconcile with the Q16 σ-pair **without resurrecting `buresBarycenter`** — likely confirms rejection, but it is the load-bearing citation behind the disputed reframe. | Required (to settle the dispute) |
| **ES-HyperNEAT** (Risi & Stanley 2012) | Adds substrate density/resolution evolution = exactly the `{16,64,256}` multi-resolution ladder question (R5/R4). Fetch to see whether its resolution-agnostic substrate offers anything the deterministic MERIT cascade over `s4_haar` does not — to strengthen the cascade decision or surface a missed option. | Medium |
| **SIREN / periodic-activation INR** (Sitzmann et al. 2020) | The findings lean on ActINR (WIRE/Gauss activations) for the continuous space-time floor (R4); SIREN is the foundational periodic-activation INR and its exact-periodicity behaviour bears directly on the period-64 loop-closure decision and on judging whether a deferred Q16-LUT'd-INR export asset is worth it. **Fetch only if continuous temporal super-res becomes a committed requirement** (currently deferred per Q9). | Conditional (defer-gated) |
| **PonderNet / Mixture-of-Recursions** adaptive-compute (already in SixFour memory as look-NN design) | Re-fetch **only if** the slow-clock promotion cadence wants a learned halting signal rather than a fixed modulo. The deterministic integer cadence is the contract-safe default. | Low |

---

## 7. Open conflicts — flagged for owner decision

These change the math or the blast radius and are **not** settled by this amendment.

- **R1/R2 PREMISE ⚑.** The findings assert SixFour "is missing a generator" and that
  spatial-vs-temporal is "a second orthogonality basis"; the decision ledger (Q1–Q4) already
  settled σ-pair = generator and band-disjoint-Haar = exact orthogonality. **RULING NEEDED:**
  confirm the adversarial reading (R1/R2 are NOT open architectural gaps — only the
  `sampleOrthogonalPair` cold-start ranking and the still-stubbed keystone are live), so we do NOT
  bolt a second float generator in front of the σ-pair.
- **COLD-START RANKING SOURCE ⚑.** The proposed day-1 heuristic (per-Haar-level coefficient
  variance of `g0`) is a recommendation, not a decided law. **RULING NEEDED:** is capture-measure
  per-band variance the right θ-independent ranking, or should day-1 use a **fixed founder
  band-partition preset** (KataGo-founder style) instead? Affects `lawColdStartRankingDeterministic`'s
  definition.
- **NetSynth256 vs ActINR ⚑.** Q9 ships the `synthBeyond` floor as canonical and defers any learned
  256³. The ActINR/SIREN findings tempt a continuous-INR floor. **RULING NEEDED:** is continuous
  temporal/spatial super-resolution a committed product requirement? If **NO**, the INR cluster
  stays fully deferred and the SIREN/ES-HyperNEAT fetches are optional. If **YES**, a
  frozen-Q16-LUT INR export asset becomes a real (HIGH-effort) work item.
- **AUX-LABEL CORPUS ⚑.** KataGo aux targets need a Mac-side (input→aux-label) corpus that **does
  not yet exist**; the oracles emit labels deterministically but no training corpus is built.
  **RULING NEEDED:** commit to generating a synthetic A/B corpus (via the Zig oracles over synthetic
  captures) for the off-device θ trainer, or defer aux losses until real user pick-logs accumulate?
  Affects step-3 scope.
- **TEMPORAL MODULE BOUNDARY ⚑.** `Spec.Cyclic.hs` (float OT/entropy oracle) and the proposed
  `Spec.TemporalLoop` (Q16 period-64 LUT) overlap in name/intent. **RULING NEEDED:** confirm they
  stay **SEPARATE** (Cyclic = float analysis oracle, TemporalLoop = shipped Q16 closure) and do not
  merge — merging would drag float into the shipped temporal path.

---

*This amendment adds no architecture the pivot did not already decide. Its net effect: **R3** and
**R5** get concrete, spec-first, byte-exact closures; **R1/R2** get a cold-start heuristic + a
gating safety net but no architectural change; **R4** stays the deterministic cascade floor
(`synthBeyond`), not an INR/LVE search.*