# SixFour NN Stack Map — 2026-06-19

Purpose: the single canonical map of SixFour's on-device NEURAL-NETWORK / learning stack — what learns, where, from what signal, and where the target roster sits against the four hard constraints. This is a MAP + target design, NOT an implementation.

> Defer to `docs/APP-MAP.md` for the whole app. This document covers ONLY the NN / learning surface.

---

## Hard constraints (non-negotiable)

These four musts override every design note, spec, and CLAUDE.md spine claim below. Where the as-built stack conflicts with one of these, the conflict is flagged, not silently reconciled.

1. **Per-frame only.** Per-frame palettes; NO global-palette collapse. No organ may re-introduce a single curated/global palette, a global 384-DOF genome, or a global "cube A".
2. **Learned 256-rung super-res of the picked candidate.** The exported output is a LEARNED 256-cube-rung super-res of the candidate the user picked — genome-conditioned high-frequency detail ABOVE the deterministic nearest-neighbour floor. Not a naive replicate.
3. **Every net learns on-device, per-user.** Every network learns on-device, per the individual user, from that user's own picks, via Apple frameworks (MPSGraph). There is NO required Mac/MLX/server base model. An MLX/Mac artifact may exist only as an OPTIONAL weight-factory / warm-start, never as a required base.
4. **Web-gaps need alignment.** Where functionality or a spec is MISSING (not merely unported), do NOT improvise. The gap goes to the RESEARCH-AND-ALIGN QUEUE (Part 4) for a web-search question + user sign-off BEFORE any build.

---

## Part 1 — As-built reality

Every network / learning component currently in the repo, by surface. Status legend: **live** = on the mounted live path; **dormant** = built/tested but zero live callers/mount sites; **stub** = present but returns floor / TODO / no weights; **abandoned** = training retired, blobs deleted; **spec-only** = Haskell spec + goldens, no port; **doc-only** = design note only.

### Surface: train-on-pick (the live learner)

| Component | Status | What trains it | On-device? | Location (file:symbol) |
|---|---|---|---|---|
| **PersonalTaste θ** (770-D Bradley-Terry taste vector: 256 leaves×3 ++ [coverage,beauty]) | **live** | One SGD step folded per A/B pick (`Spec.PreferenceUpdate.btUpdate`) | **YES** — pure-Swift/`Double` SGD, persisted JSON, per-user. Satisfies HARD MUST #3 directly. NOT MPSGraph; it is a linear BT utility, not a "network". θ is folded+persisted but is NOT fed into the LIVE candidate generator. | `SixFour/Atlas/PersonalTaste.swift:36`; live caller `ABCandidatePhaseField.swift:142-145` |
| **GLRM preference kill-switch** (OLS calibration gate) | **dormant** | N/A — deterministic OLS gate, not a learner | N/A. Wired ONLY into the dormant `AtlasTrainingSession.makeBatch`; does NOT gate the live `PersonalTaste` btUpdate. Self-tagged debt `glrm-wired-but-unused`. | `SixFour/Atlas/GLRM.swift`, `AtlasTrainingSession.swift:225` |
| **PersonalGenome / DecisionLog** (CMPE replay + federated bootstrap) | **live** (logging) / **partial** | Persists BT Compares with frozen 770-D embeddings per pick | DecisionLog CMPE-v2 JSON logging WIRED LIVE (per pick, embeddings frozen at pick time) — on-device, compliant. Promotion gate / binary SF64 codec spec-only. Federated aggregation (`fed_sim.py`) is Mac/server-only. | `SixFour/Atlas/DecisionLog.swift`; `spec/.../{DecisionLog,PersonalGenome}.hs`; `trainer/fed_sim.py` |

### Surface: propose candidates (the A/B generator)

| Component | Status | What trains it | On-device? | Location (file:symbol) |
|---|---|---|---|---|
| **ABCandidates proposer** — `deltaPreservingPair` LIVE; `GenomePair.sampleOrthogonalPair` / `fromPalette` DORMANT | **live** (deterministic) | Nothing — does NOT learn or consume θ | **NO learning.** Live proposer = scheduled `IsoMove` translate by an annealed `MoveRadiusSchedule` radius, A=+a/B=−a chroma; deterministic, takes no θ. Spec'd keystone `GenomePair.sampleOrthogonalPair` (exact band-disjoint orthogonal σ-valid pair) + `ABCandidates.fromPalette(theta:)` are built+golden-gated with ZERO live callers. | `ABCandidates.swift:60`, `ABCandidatePhaseField.swift:227` |
| **ATLAS policy net** (factored node[127]×delta[12] = 1524-move logits) | **stub** | MCTS visit-count cross-entropy (intended); MLX prototype regresses to oracle top-8, NOT visit counts | **NONE on-device.** `Spec.AtlasNetEval` forward oracle only (no `NetIOSpec`); `atlas_net_mlx.py`/`train_atlas_mlx.py` Mac proto, trained `.npz` DELETED/absent. No on-device forward, no trainer, no consumer. v1 plan ships FROZEN. | `spec/.../AtlasNetEval.hs`, `DeltaCodebook.hs`, `trainer/atlas_net_mlx.py` |
| **LOOK-NN** (E→R→D σ-equivariant 384-DOF genome decoder) | **abandoned** | Supervised MLX-on-Mac (abandoned 2026-06-17, blobs deleted) | **NONE.** Full Haskell forward spec (`LookNetE/R/D/Compose/Eval`, `SigmaPairHead`) + Zig `s4_load_look_net` + Swift `loadLookNet` exist, but `loadLookNet` has ZERO production callers — a deploy seam with nothing to deploy. Sum-pools to ONE GLOBAL genome. | `spec/.../LookNet*.hs`, `SixFourNative.swift:82` |
| **ThetaToDelta** (θ → 384-DOF σ-pair override) + `s4_leaf_override` | **dormant** | N/A — deterministic decode of learned θ, not a learner | OWNED-BUT-UNWIRED: `Spec.ThetaToDelta` + Swift + Zig `s4_leaf_override` all DONE + golden-gated, ZERO callers. Live n=0 path uses leaf-space `PersonalTaste.leafTint` instead. | `SixFour/Atlas/ThetaToDelta.swift`, `Native/src/kernels.zig (s4_leaf_override)` |
| **PaletteSearch / GumbelSearch / AtlasGame** (search tier) | **stub** (spec-only) | N/A — search produces visit-count target that WOULD train the policy | **NONE.** Full Haskell specs+laws+goldens (GHCi-validated) but ZERO iOS consumers (debt `palette-search-design-only`). No integer-Metal-vs-Zig golden has passed on silicon; no `cube_lift` kernel (debt `no-metal-golden-gate`). | `spec/.../PaletteSearch.hs`, `GumbelSearch.hs`, `AtlasGame.hs` |

### Surface: pick / value scoring

| Component | Status | What trains it | On-device? | Location (file:symbol) |
|---|---|---|---|---|
| **AtlasTrainer** (MPSGraph Bradley-Terry VALUE net) — V(board[B,4096,6], genome[B,384])→scalar | **dormant** | MPSGraph reverse-mode autodiff + SGD on BT `Compare` pairs | **YES by design** via MPSGraph (Apple, zero deps), device-proven **12.4 ms/step on iPhone 17 Pro**, sim-gated off. BUT DORMANT: constructed only by `AtlasTrainingSession→AtlasTrainingField`, which has ZERO mount sites. Never executes live; V feeds no ranking. | `SixFour/Atlas/AtlasTrainer.swift`, `AtlasTrainingSession.swift:396` |
| **PaletteValue / PaletteOracle** (deterministic value oracle: Ou-Luo pair-beauty + OKLab Gaussian entropy) | **dormant** (partially live) | N/A — IS the fixed target, not a learner | `paletteReward` consumed only by goldens until deferred `PaletteSearch` lands; only `beautyLossLeaves` is on a live path (`PersonalTaste.embedding`'s beauty coord). | `SixFour/Palette/PaletteValue.swift` |

### Surface: capture (palette extraction)

| Component | Status | What trains it | On-device? | Location (file:symbol) |
|---|---|---|---|---|
| **METRIC organ** (learned 3×3 PSD OKLab distance, `LearnedPSDMetric`) | **dormant** | Mac-side `train_metric.py` (MLX Cholesky, supervised triplet loss — NOT user picks) | **NONE on-device.** Shipped as JSON, loaded read-only, AND never instantiated: `MetricOrgan` loader has 0 construction sites; `KMeansLab` defaults to Euclidean. One of only two spec-pinned `NetIOSpec`s. | `SixFour/Organs/MetricOrgan.swift`, `spec/.../Net.hs`, `trainer/train_metric.py` |

### Surface: 256 super-res (the exported winner)

| Component | Status | What trains it | On-device? | Location (file:symbol) |
|---|---|---|---|---|
| **NetSynth256** (learned 256-cube super-res) | **stub** | Nothing — no trainer, no weights, no MPSGraph graph | **NONE.** `hasLearnedWeights==false` (hard-coded), `synthesize()` returns floor byte-for-byte. Not wired: live export uses `ABExport.encodeChosenLook→GIFEncoder(upscale:4)` naive 4× replicate; `NetSynth256`'s only caller `ABExportFamily.assemble` is itself uncalled. **VERIFIED HARD MUST #2 VIOLATION.** | `NetSynth256.swift:14,19-23`; `PhaseField.swift:73`; `ABExport.swift:40` |
| **Upscale256** (deterministic two-cube 256³ endgame) | **stub** (spec-only) | N/A — deterministic recompute, not a learner | Full Haskell spec with laws+FNV golden; NO Swift/Zig port. Consumes a GLOBAL-palette cube A + per-frame→global paletteMap (HARD MUST #1 tension). Live export uses simple replicate instead. | `spec/.../Upscale256.hs` |

---

## Part 2 — Target stack

The unified roster mapped to the on-device loop:

```
  capture ──▶ propose candidates ──▶ render ≥2 16-rung GIFs ──▶ user pick / tournament
     │              │                                                    │
  (per-frame)   (taste-steered)                                     (BT signal)
     │              │                                                    ▼
     │              │                                          256-rung super-res
     │              │                                          of the WINNER (learned)
     │              ▼                                                    │
     │       θ steers proposer ◀───────── PersonalTaste θ ◀─────────────┘
     │       (ThetaToDelta / leafTint)        (one SGD step per pick, on-device)
     │              ▲                              │
     └──────────────┴──────────────────────────────
        the pick is the ONLY training signal; every net folds the same Compare
```

### On-device learning loop (text diagram)

```
USER PICK (A vs B)
   │
   ├─▶ DecisionLog.append  ── persists Compare {embedding_A, embedding_B, winner}  (CMPE replay)
   │
   ├─▶ [GLRM.shouldTrain]  ── OLS calibration gate: BLOCK if singular or R²<0.1   (target: gate the live loop too)
   │
   ├─▶ PersonalTaste.btUpdate(θ)  ── one CPU/Double SGD step on 770-D θ   (LIVE today)
   │        │
   │        ├─▶ ThetaToDelta(θ) → 384-DOF σ-pair override δ   (target: drives the proposer)
   │        │
   │        └─▶ [AtlasTrainer MPSGraph BT step on V]   (target: on-device value net, from same Compare)
   │
   └─▶ next round: proposer emits θ-steered candidates → render 16-rung → repeat
```

Per-network target role, loop stage, learning source, and how it learns on-device:

| Network | Target role | Loop stage | Learns from | How it learns ON-DEVICE |
|---|---|---|---|---|
| **PersonalTaste θ** | The live per-user taste learner; the n=0 personalization core. | train-on-pick | Every A/B pick (BT Compare) | Pure-Swift SGD step per pick, persisted JSON. Already compliant with HARD MUST #3. Target: also feed θ into the live proposer. |
| **ABCandidates proposer** | Generate the ≥2 / tournament A/B candidates at the 16-rung that the user picks between, taste-aligned + informative. | propose → render 16-rung | Picks, indirectly via θ (or a trained policy) | Target: θ-driven orthogonal `GenomePair` displacement (or learned proposer) steered by `ThetaToDelta`, never re-introducing a global palette. **Currently does NOT learn — RQ4.** |
| **ThetaToDelta** | Bridge that lets the taste learner drive the σ-pair GENOME, not just a flat leaf tint. | propose (inference-time, n>0) | Decodes learned θ (not itself a learner) | Deterministic σ-aware decode; activates when candidates become learned σ-pair genomes (canonical-path step 3+). Ready + golden-gated. |
| **AtlasTrainer (MPSGraph value net)** | On-device value head V(board, genome)→scalar; proof-of-capability for MPSGraph on-device training; ranks/scores candidates. | pick (value scoring) + train-on-pick | BT `Compare` pairs (same picks) | MPSGraph reverse-mode autodiff + SGD, on-device, no Mac base (12.4 ms/step proven). Target: re-target from the global board to the per-frame A/B loop. |
| **ATLAS policy net** | AlphaZero-reframe policy head: which reversible Haar Edit to take over the collapse MDP. | propose (move selection) | MCTS visit-count cross-entropy / expert iteration | Target: on-device forward + trainer. **Whether it is in scope at all is RQ4** (per-frame-genome pivot may supersede it). v1 = FROZEN. |
| **PaletteSearch / GumbelSearch** | "SEARCH generates options" keystone; feeds the A/B gallery at scale; produces the policy's visit-count training target. | propose (option generation) | N/A (search itself does not learn) | Target: on-device integer-Metal/Zig search; gated by a missing Metal-golden. **In-scope decision = RQ4.** |
| **NetSynth256** | HARD MUST #2 OUTPUT: learned genome-conditioned high-frequency detail ABOVE the deterministic floor. | 256 super-res (winner) | A/B picks (BT signal) | Target: thin additive gated residual head trained on-device from picks, bit-exact-equal-to-floor at zero genome. **Entirely unbuilt — RQ1.** |
| **Upscale256** | Deterministic (recompute, never interpolate) 256³ path — the non-learned companion/alternative to NetSynth256. | 256 super-res (deterministic path) | N/A (deterministic) | Target: re-derive for per-frame inputs (drop global cube A) or abandon for NetSynth256. **RQ3.** |
| **METRIC organ** | Stage-A learned perceptual distance feeding nearest-centroid palette extraction. | capture | (Currently Mac triplet, not picks) | Target: on-device-learned from picks, or retire. **RQ5.** |
| **LOOK-NN** | Original ★-core learned-look generator (set encoder → σ-pair genome). | propose (genome emission) | (Abandoned MLX supervised) | Target: re-home the 384-DOF σ-pair head onto the on-device MPSGraph trainer, or formally retire. **RQ5 + RQ2.** |
| **PersonalGenome / DecisionLog** | Replay (CMPE) + cold-start spine. | train-on-pick + cold-start | BT Compares with frozen embeddings | Logging is on-device + compliant. Federated population prior = OPTIONAL warm-start only (never required base). **RQ5.** |
| **PaletteValue / PaletteOracle** | Deterministic aesthetic objective a learned value head approximates; reward features. | pick (reward objective) | N/A (fixed target) | Reused verbatim when search/value head wires in. |
| **GLRM** | RLHF-hygiene gate guarding any preference net from chasing a phantom utility. | train-on-pick (gates) | N/A (deterministic OLS) | Target: route the LIVE PersonalTaste loop through `GLRM.shouldTrain` too. |

---

## Part 3 — Gaps

### (a) Spec-port gaps — spec exists, just needs a hand-written on-device port

These have a complete Haskell spec + goldens (or a built-but-unwired Swift/Zig component). No research is needed; they need wiring or a port. They are NOT in the research queue.

- **PersonalTaste θ → live proposer wiring.** θ is folded + persisted but `computeCandidates → deltaPreservingPair` takes no theta; `leafTint` runs only on the dormant `ABCandidates.fromPalette` / `AtlasState.choose` paths. Integration only. (`PersonalTaste.swift:36`, `ABCandidatePhaseField.swift:142-145`)
- **ThetaToDelta activation.** `Spec.ThetaToDelta` + Swift + Zig `s4_leaf_override` DONE + golden-gated, ZERO callers. Activates once candidates are learned σ-pair genomes. Integration only. (`ThetaToDelta.swift`, `Native/src/kernels.zig`)
- **GLRM on the live loop.** Sound + golden-gated (`Spec.GLRM`) but wired only into the dormant trainer. Decide + wire it to gate the live `PersonalTaste` btUpdate. Integration only. (`GLRM.swift`, `AtlasTrainingSession.swift:225`)
- **DecisionLog promotion gate / binary SF64 codec.** Spec'd, deferred. On-device logging already live. Port only. (`DecisionLog.swift`)
- **PaletteValue / PaletteOracle.** Spec-pinned, golden-gated, partially live; reused verbatim when search/value head wires in. No new work beyond wiring. (`PaletteValue.swift`)

### (b) Research-needed gaps — functionality / spec MISSING

These have NO usable spec body, an abandoned base, or an unresolved scope fork. They go to Part 4 and require user sign-off before any build.

- **NetSynth256 learned super-res (HARD MUST #2).** `hasLearnedWeights==false`; spec body (`Spec.ExportFamily synthDetail/synthBeyond256/lawZeroGenomeIsFloor`) is `error "TODO"`; no trainer/weights/graph. → **RQ1.**
- **MLX/Mac base spine vs on-device-only (HARD MUST #3).** CLAUDE.md mandates an MLX base + codegen still emits it; the only live learner is CPU, the MPSGraph learner is dormant. Central architectural fork. → **RQ2.**
- **Upscale256 per-frame re-derivation.** Spec consumes a GLOBAL cube A + per-frame→global map (HARD MUST #1 incompatible); no port. → **RQ3.**
- **Candidate proposer mechanism.** Live `deltaPreservingPair` does not learn; orthogonal `GenomePair`, learned proposer, and AlphaZero search are all dormant/spec-only; docs describe a different dormant path than what is live. → **RQ4.**
- **METRIC organ + LOOK-NN nucleus + federated prior re-home.** Three Mac-trained-from-synthetic artifacts with no on-device learning and no defined role under #3. → **RQ5.**

---

## Part 4 — RESEARCH-AND-ALIGN QUEUE (pending user sign-off)

> **PENDING ALIGNMENT — no web search run yet, per the user's instruction.** Each item is a missing capability + a proposed web-search question + the candidate approaches the repo already hints at + the user decision it blocks. Do NOT build any of these until the user signs off on the approach.

**1. RQ1 — On-device learned 256-cube super-res (NetSynth256) from picks.**
- *Missing:* No learned super-res. `NetSynth256.hasLearnedWeights==false` returns the floor byte-for-byte; live 256 export is a naive 4× replicate (`ABExport GIFEncoder(upscale:4)`). Spec body (`Spec.ExportFamily synthDetail/synthBeyond256/lawZeroGenomeIsFloor`) is `error "TODO"`. No trainer, no weights, no MPSGraph graph. This is the HARD MUST #2 deliverable, entirely unbuilt.
- *Proposed web-search question:* What network architecture + on-device (MPSGraph) training signal produces 64-cube→256-cube above-floor, genome-conditioned high-frequency detail learned from A/B picks (no Mac/MLX base), while preserving the bit-exact-equal-to-floor-at-zero-genome contract and staying per-frame-only?
- *Repo-hinted candidates:* `docs/SIXFOUR-256-SUPERRES-WORKFLOW.md` / `SIXFOUR-JEPA-256-SUPERRES-WORKFLOW.md` verdict = RQ-VAE/VAR residual quantization (NOT JEPA) as a thin additive gated residual above the deterministic floor, reusing QUAD 4⁴ + flux; floor already exists (`RGBT4DLift.synthBeyond` / `SixFourExport.replicate4x`); spec contract = the gated additive head.
- *Blocks:* The user's stated OUTPUT. RQ-VAE design assumes Mac/MLX pretrain (collides with #3); user must decide whether a tiny residual head can train on-device from BT signal or ship frozen, and whether it is learned at all vs deterministic (Upscale256).

**2. RQ2 — MLX/Mac base-model spine vs no-Mac on-device-only (HARD MUST #3 reconciliation).**
- *Missing:* CLAUDE.md spine mandates an MLX base net trained on Mac + on-device MPSGraph personalize, and the spec ACTIVELY codegens it (`Codegen.MLX → look_net_mlx.py`; `loadLookNet` deploy seam; `train_look_net_mlx/train_atlas_mlx/train_metric`). #3 forbids a required Mac/MLX base. The only on-device live learner (`PersonalTaste` θ) is CPU SGD, not the MPSGraph spine, and not a candidate/super-res generator; the MPSGraph `AtlasTrainer` that could generalize is dormant.
- *Proposed web-search question:* Can the Bradley-Terry value net AND a candidate-proposal/genome net be trained from scratch on-device with MPSGraph (no Mac/MLX base), and how is cold-start handled with zero pre-training — i.e. should MLX be demoted to an optional weight-factory/warm-start or retired entirely, and what replaces the abandoned LOOK-NN base?
- *Repo-hinted candidates:* `AtlasTrainer` already trains from a seed on-device (no Mac base) at 12.4 ms/step; `SIXFOUR-CANONICAL-PATH.md` (2026-06-18) already softens to "MLX is a weight factory, never required"; `PersonalGenome` federated bootstrap (`personalBeta=n/(n+50)`) as cold-start; `ThetaToDelta` bridges θ → 384-DOF σ-pair genome.
- *Blocks:* The central architectural fork. CLAUDE.md must NOT be silently overwritten; user decides whether to retire/demote the MLX spine and rewrite LOOK-NN/Atlas-policy/Metric accordingly. Blocks every other net's training story.

**3. RQ3 — Per-frame-only re-derivation of the 256-cube deterministic recompute (Upscale256) vs global.**
- *Missing:* `Spec.Upscale256` (deterministic 256³ endgame) is fully specified but consumes a GLOBAL-palette cube A + a per-frame→global paletteMap — incompatible with HARD MUST #1. No Swift/Zig port. Unclear whether the deterministic recompute survives the per-frame pivot or is abandoned for NetSynth256.
- *Proposed web-search question:* Does the deterministic Upscale256 recompute (slot-align + palette blend + prior-weighted quantize) need re-derivation for per-frame-only inputs (no global cube A), or is the deterministic 256³ path abandoned in favour of a learned NetSynth256 residual above the replicate floor?
- *Repo-hinted candidates:* `Spec.Upscale256 blendPalettesQ16/quantizePrior/alignSlots/applyAnchors`; the per-frame deterministic floor (`RGBT4DLift.synthBeyond`, reversible (2×2)×(2×2)→1 Haar) already exists per-frame and could replace the global-cube-A assumption; `SIXFOUR-PALETTE-IS-MOTION` McCann geodesic deterministic temporal super-res.
- *Blocks:* Determines whether the 256 super-res is deterministic, learned, or hybrid, and removes a latent HARD MUST #1 violation in the spec. Couples to RQ1.

**4. RQ4 — Candidate proposer: orthogonal genome vs isometry vs learned vs search.**
- *Missing:* The live A/B proposer (`deltaPreservingPair`, a fixed ±a-chroma `IsoMove`) is deterministic and does NOT learn from picks or consume θ — the "propose candidates" stage has no on-device learning (#3 gap). The spec'd keystone (`GenomePair.sampleOrthogonalPair` / `ABCandidates.fromPalette`) and the AlphaZero search tier (`PaletteSearch/GumbelSearch`) are dormant/spec-only. Docs (STATUS `ab-perturb-stub`, CANONICAL-PATH §1.4) describe a DIFFERENT dormant path than what is live.
- *Proposed web-search question:* What candidate-proposal mechanism should generate the ≥2 / tournament A/B candidates at the 16-cube rung so it LEARNS from the user's picks on-device — a θ-driven orthogonal `GenomePair` displacement, a learned proposal net, a value-guided search gallery (Gumbel-AlphaZero), or the current isometry move — and how does θ (or a trained policy) steer it without reintroducing a global palette?
- *Repo-hinted candidates:* `GenomePair.sampleOrthogonalPair` (golden-gated, dormant); `ThetaToDelta` θ→384-DOF override + `s4_leaf_override` (dormant bridge); `PaletteSearch/GumbelSearch` MCTS gallery (spec-only); `AtlasTrainer` value net to rank candidates (dormant); the 2026-06-18 per-frame-genome pivot direction.
- *Blocks:* The core loop's "propose candidates" organ AND whether the AlphaZero policy/search tier is in scope or superseded by the direct PersonalTaste+GenomePair proposal — a major scope fork the user must pick before any of these nets are wired.

**5. RQ5 — Metric organ + look-NN nucleus + federated prior: retire or re-home under on-device-only.**
- *Missing:* Three Mac-trained-from-synthetic artifacts have no on-device learning and conflict with #3: METRIC organ (Mac MLX triplet, JSON, never instantiated), the LOOK-NN nucleus (abandoned MLX, blobs deleted, loader 0 callers, emits a GLOBAL genome), and the PersonalGenome federated population prior (`fed_sim.py`, Mac/server aggregate). Their target role under "every net learns on-device per-user" is undefined.
- *Proposed web-search question:* Under HARD MUST #3 (no required Mac base, on-device per-user learning), should the learned OKLab distance metric and the look-NN σ-pair genome head be (a) retired, (b) re-homed onto the on-device MPSGraph trainer, or (c) kept as optional priors — and is a federated population prior an optional warm-start or a forbidden required base?
- *Repo-hinted candidates:* `AtlasTrainer` already uses the 384-DOF σ-pair shape on-device (could host a re-homed LOOK-NN head); `PersonalGenome personalBeta=n/(n+50)` federated warm-start; `KMeansLab` is generic over the metric (Euclidean default) so the metric could be on-device-learned; `trainer/train_metric.py` + `Spec.Net slotMetricDims`.
- *Blocks:* Which Mac-trained organs survive and whether they become on-device learners or get deleted — needed to stop the spec/codegen from continuing to gate an abandoned Mac spine, and to clarify federated-base compliance with #3.

---

## Part 5 — Constraint conflicts to resolve

The two headline tensions are **(1) the Mac/MLX base vs on-device-only spine** and **(2) naive-replicate vs learned-256-super-res**. All five, by severity:

**[BLOCKING] HARD MUST #2 — output must be a LEARNED 256-cube super-res.**
The live 256-rung export is a NAIVE 4× pixel-replicate, not a learned super-res. `ExportingPhaseField.export` (`PhaseField.swift:69-77`) → `ABExport.encodeChosenLook` → `GIFEncoder(upscale:4)` (`ABExport.swift:40`), a 4×4 index replicate at LZW-emit time. `NetSynth256` has `hasLearnedWeights==false`, returns floor byte-for-byte (`NetSynth256.swift:14,19-23`), and is never called on the export path (its only caller `ABExportFamily.assemble` is itself uncalled). The learned-detail spec (`Spec.ExportFamily synthDetail/synthBeyond256/lawZeroGenomeIsFloor`) is `error "TODO"`. No trainer, no weights anywhere. → resolve via **RQ1** (+ RQ3 for the deterministic-vs-learned fork).

**[BLOCKING] HARD MUST #3 — every net learns on-device, NO required Mac/MLX base.**
CLAUDE.md's "Train/deploy spine" mandates an MLX base net trained on Mac ("Train (base net): MLX on the M1") + on-device MPSGraph personalize, and the Haskell spec ACTIVELY codegens this Mac spine (`Codegen.MLX → trainer/generated/look_net_mlx.py`; the `s4_load_look_net`/`loadLookNet` deploy seam; `train_look_net_mlx.py`, `train_atlas_mlx.py`, `train_metric.py` all train Mac-side on 100% SYNTHETIC data toward deterministic oracles, NOT user picks). This is a required Mac/MLX base, forbidden by #3. The look-net abandonment is consistent with #3's intent, but the spine still stands in CLAUDE.md and codegen. → resolve via **RQ2** (do NOT silently overwrite CLAUDE.md).

**[NOTABLE] HARD MUST #3 — the live learner is neither a network nor MPSGraph.**
The ONLY thing that learns on the live path is `PersonalTaste` θ — a hand-written CPU/`Double` BT SGD step (`PersonalTaste.swift:36`), not MPSGraph, and a linear leaf-tint utility, not a candidate/super-res generator. The MPSGraph net that WOULD satisfy "every net via MPSGraph" (`AtlasTrainer`, `AtlasTrainingSession.swift:396`) is DORMANT (host `AtlasTrainingField` has zero mount sites; reachable only behind `colorAtlasEnabled && globalPaletteV2==false`). So no NETWORK learns on the live path, and the live learner is not MPSGraph — CLAUDE.md's claim that MPSGraph is the live on-device-training spine is currently false in the shipped loop. → resolve via **RQ2 / RQ4**.

**[NOTABLE] HARD MUST #3 — federated prior + synthetic training signal.**
The `PersonalGenome` cold-start uses a FEDERATED population prior (`personalBeta = n/(n+50)`) aggregated Mac/server-side (`fed_sim.py`); if treated as REQUIRED rather than an optional warm-start, it is a required off-device base, violating #3. Also every Mac trainer's signal is SYNTHETIC (`zig_native`/`atlas_synth`/`synth_classes`), never the user's real picks — the opposite of the per-user-from-picks contract. → resolve via **RQ5** (optional warm-start vs required base).

**[MINOR / WATCH] HARD MUST #1 — global-palette organs must stay unreachable.**
Multiple spec'd/built global-palette organs exist and must stay statically unreachable: (a) `AtlasTrainer`'s board carries `globalCoverage` over ONE curated GLOBAL palette (`AtlasCollapse`), reachable only behind `globalPaletteV2==false`; (b) LOOK-NN sum-pools to ONE GLOBAL 384-DOF genome (`Spec.LookNetCompose`); (c) `Spec.Upscale256` consumes a GLOBAL cube A; (d) `FarthestPointCollapse` / `s4_global_collapse` (`PaletteCollapse.swift:71`) still used by the unmounted Atlas curation surface. Today the LIVE mounted path is per-frame and global collapse is gated unreachable (`Feature.globalPaletteV2==false`), so #1 HOLDS. This is a per-frame-only WATCH, not a live violation: the NN stack must not re-introduce any of these when wired (couples to RQ3 / RQ4 / RQ5).
