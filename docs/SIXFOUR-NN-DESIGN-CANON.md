# SixFour — NN Design Canon

> **Canonical reference for the SixFour neural-net design.** Single source of truth
> for what the nets ARE, what is SHIPPED vs DESIGN-ONLY vs ABANDONED, and which param
> counts are pinned vs estimated. Status authority is `docs/STATUS.md` (gated by
> `scripts/verify-doc-claims.sh`); this doc must agree with it. Spec authority is the
> Haskell `spec/` modules (browse from `SixFour.Spec.Map`). All `file:line` cites
> verified against source 2026-06-18. PLAIN punctuation only.
>
> **Supersedes:** `SIXFOUR-ARCHITECTURE-MAP.md`, `SIXFOUR-LOOK-VALUE-UNIFICATION.md`,
> `L-NN-MASTER-DESIGN.md`, `SIXFOUR-STATE-INSPECTION-2026-06-17.md`. Consolidates the NN
> portions of `SIXFOUR-BACKEND-TENSOR-STACK-MAP.md`, `SIXFOUR-ALPHAZERO-COLLAPSE-DESIGN.md`,
> and `COLOR-ATLAS.md` into one place. The deep build sequence lives in
> `SIXFOUR-ALPHAZERO-COLLAPSE-DESIGN.md` §8–§9; this doc is the orientation + ledger.

---

## 0. The reframe (read this first)

The supervised MLX look-net is **ABANDONED** (2026-06-17). It regressed a 384-DOF σ-pair
genome on a grayscale-L nucleus, did not converge to a usable look, and its trained
artifacts were DELETED. The core is reframing **AlphaZero-shaped**: a (policy, value) pair
over a turn-based state machine whose moves are reversible OKLab edits, with Bradley-Terry
A/B preference as the reward. The σ-pair / σ-equivariant **ideas** are ported; the MLX
**weights** are not. No `mlx-swift`, no CoreML black box, no ANE opaque runtime ever ships
(`CLAUDE.md` Tier-2 contract).

What actually runs on a device today: the **deterministic Zig collapse**
(`s4_global_collapse`, maximin) emits the shipped global palette, and an **MPSGraph value-net
training spike** runs on the iPhone 17 Pro (train-only, does not yet select a palette). Every
other NN component below is design + spec + golden-oracle, not a shipped forward pass.

Three formerly-contested framings are now RESOLVED (see §6):
1. **GAN is dropped.** Spec (`Loss.hs`, `Map.hs:25`) is canon; the GAN text in `trainer/regimen.py` is stale dead-MLX documentation.
2. **Genome source is the AlphaZero collapse-game**, not supervised MLX. No trained look-net weights exist.
3. **The output space is the 384-DOF σ-pair genome.** The 768/256-leaf confusion is a layer confusion, resolved in §3.

---

## 1. The NN roster

Param counts are flagged: **(pinned)** = a literal exists in source/STATUS; **(est.)** =
unsourced design estimate (the only repo range is `COLOR-ATLAS.md`'s loose "~16K–115K").

| net | role | I/O | params | trained where | inference where | status |
|---|---|---|---|---|---|---|
| **METRIC** | OKLab perceptual distance (PSD Cholesky) | 6 → in-place | **6 (pinned)** — `net_shape.py:23` | M1 `train_metric.py` | `MetricOrgan.swift` | **shipped** |
| **LOOK-NN** (E▸R▸D) | σ-equivariant genome decoder | 10-D GMM set ≤16384 → 384 σ-pair coeffs | ~115K (est.) | M1/MLX (ABANDONED) | hand-written Swift/Metal (unwired) | **ABANDONED supervised run; forward-oracle + Zig loader intact; no trained weights** |
| **ATLAS policy** (node+delta) | factored 1524-move policy | 13-D tokens + 384 genome → 1524 logits | ~6K (est.) | M1/MLX `train_atlas_mlx.py` | none (oracle only) | prototype; NOT spec-pinned (no `NetIOSpec`) |
| **ATLAS value** (Mac) | BT preference scorer | 128-D context → 1 | ~1K (est.) | M1/MLX `atlas_net_mlx.py` | none | prototype; NOT spec-pinned |
| **ATLAS value** (device spike) | per-device BT value | 4096×6 board + 384 genome → 1 | **29,249 (pinned)** — `AtlasTrainingSession.swift:76` | iPhone/MPSGraph `AtlasTrainer.swift` | none (train-only) | **spike-verified on device, train-only** |
| **PreferenceUpdate θ** | linear utility (not a net) | 770-D embed → utility | **770 (pinned)** — `PreferenceUpdate.hs` (256·3+2) | iPhone SGD | on-device fold | spec'd; device path is a stub (§5) |
| **GLRM** | OLS kill-switch (not a net) | 4 feat → 4 coeffs | 0 | — | gating only | spec'd (`Spec.GLRM`), not wired |

> **Pinning asymmetry (a real maintainer trap):** the generated `NetContract`
> (`Spec.Net.hs` → `trainer/generated/net_shape.py`) pins ONLY `METRIC` (in=6, out=0) and
> `LOOK` (in=10, out=384) with golden `NetIOSpec`s. The entire **Atlas roster has NO
> spec-pinned shape** — its dims live only in un-codegenned trainer Python
> (`ATLAS_TOKEN_DIM=13`, `N_VOCAB=1524`) and Swift literals. Atlas is not contract-protected
> the way LOOK/METRIC are. **Only METRIC (6), θ (770), and the device spike (29,249) are
> pinned; every other count is a design estimate** with no repo literal. The COLOR-ATLAS
> "30,954 stored + 33,411 frozen ⇒ ≈64K" totals are design arithmetic, not a measured
> contract. Recommended work: codegen `atlas_net_mlx.py` shapes from a Haskell `NetIOSpec`.

---

## 2. The Look-NN forward oracle (designed, not trained)

The look-NN is a permutation-invariant set encoder over per-frame palette tokens that emits
ONE global genome. Pipeline: 10-D GMM tokens (set of ≤ `MAX_TOKENS = 16384`) → L3 σ-masked φ
linear → sum-pool → L4 weight-shared σ-block-diagonal block applied `CORE_DEPTH = 8` times
(Mixture-of-Recursions, static unroll, control-flow-free / Metal-friendly) with PonderNet
halting → L5's 8 per-Haar-level heads → **384 σ-pair coefficients** →
`SigmaPairHead.reconstructPaired` → 256-leaf palette.

- **σ-equivariance is STRUCTURAL, not trained** (`Spec.LookNetCompose` theorem): the
  reflection `σ(L,a,b) = (L,−a,−b)` commutes with the net by hard block-diagonal masks
  (22×22 achromatic + 42×42 chromatic, ~45–55% pruned), not by a loss term. This is exactly
  what the supervised net only achieved "within tolerance" and is the design's main hedge.
- **Status: spec-complete, production-unwired, no weights.** The golden forward oracle is
  `Spec.LookNetEval` (the one concrete numeric forward; everywhere else the look-NN spec is a
  zero/identity contract). `SixFourNative.loadLookNet` has **zero production callers**
  (gated open debt `looknet-load-unused`), and there is **no on-device forward pass**.
- **The Zig loader code is KEPT.** `Native/src/root.zig s4_load_look_net` is a byte-exact
  `.s4ln` blob parser, fixture-verified against the **regenerable golden** `trainer/out/look_net.s4ln`
  (`Native/src/fixture_test.zig`, skip-if-absent). This golden is NOT a trained artifact. The
  trained blobs (`look_net_trained.s4ln`, `atlas_net_trained.npz`, `synth_looknet_grayscale.gif`)
  were DELETED per the teardown checklist in `SIXFOUR-ALPHAZERO-COLLAPSE-DESIGN.md` §8.

---

## 3. Generator space (384) vs leaf space (768) — the confusion, resolved

These are two layers, both true:

- The Look-NN emits **384 DOF**: 128 OKLab generator pairs as coefficients on a depth-7
  σ-pair Haar tree (`Spec.AtlasNetEval.sigmaPairDof = 384` at `:94`; `Spec.AtlasState.hs:72`
  "a depth-7 tree (384 DOF)"; `net_shape.py:35` `output_dim=384`).
- Reconstruction (`SigmaPairHead.reconstructPaired`, inverse Haar) expands to **256 leaves =
  768 OKLab coordinates** (`AtlasState.hs:103-104` `atlasLeaves = reconstructPaired`; even
  leaf = generator+δ, odd leaf = σ(generator+δ), σ-locked by construction).

The **NN operates in 384-generator space; the palette/board operate in 768-leaf space.** The
two are related by a non-orthogonal Haar transform and are **NOT interchangeable** (Gram-Schmidt
on leaves would destroy the σ-exactness). The 768 figure is the flat leaf count, never the
NN output dim. Pinned by `CLAUDE.md` "Palette: global vs per-frame", `net_shape.py`
(`DECODER_OUT_DIM == 384`, gated), and the laws:

- `atlasEmbedding` length == **770** (768 leaf reals + `[coverage, beauty]`), `lawEmbedding770` (`AtlasState.hs`).
- `atlasLeaves == reconstructPaired == 256` leaves (`AtlasState.hs:103`).
- decoder emits **384** (`AtlasNetEval.hs:95`, `net_shape.py:54`).

---

## 4. The Atlas game (the AlphaZero state machine)

A single-player search MDP per capture episode, plus a between-episode preference channel.
NOT two-player Go: no adversary, no alternating plies, no value-sign-flip. "AlphaZero" means
the (policy, value) + MCTS + expert-iteration TEMPLATE applied to a 1-player MDP whose reward
is fit from pairwise A/B preference (preference-based RL / RLHF-reward-model + planning).

- **State** `S = (rung, tree, board, ply)`: `rung ∈ {16³, 64³, 256³}` (cube ladder, `CubeLadder.hs`);
  `tree :: SigmaSearchState` a COMPLETE depth-7 σ-pair tree, ALWAYS 256 leaves (positions are
  coefficient configurations on a fixed-depth tree, never partial trees); `board :: Board16`
  the 16³×6 curation tensor; `ply` the move counter.
- **Move ADT** (`Spec.AtlasGame`, wraps the three existing systems without editing them):
  `GameMove = Edit PaletteSearch.Move | Curate AtlasMove.CurationMove | Rung RungDir`. The
  policy emits over `Edit` moves only (the 127×12 = 1524 `DeltaCodebook` vocabulary).
  `Compare` is NOT a `GameMove` — it is the reward, lifted out of the move algebra.
- **Determinism boundary is the Q16 TERMINAL genome hash, NOT per-move.** Two unrelated
  Haar systems are typed apart: the **integer spatial ladder** (`Rung`, `CubeLadder.liftLevel`,
  byte-exact, `@divFloor`) vs the **float search substrate** (`Edit`, `Move.mvDelta :: OKLab`
  Double, ε-reversible only). The canonical terminal is the Q16 `GenomeHash`; replay is
  bit-exact at the terminal, float-reversible in-search only. We do NOT claim per-move
  bit-exact reversibility.
- **Reward** (Bradley-Terry A/B): an episode ends with two terminal genomes A, B; a judge
  picks one (`Compare wHash lHash`), scored `P(A>B) = σ(u(A) − u(B))`. SELF-PLAY judge =
  `shapedReward` (bootstrap only, must gate β to HUMAN compares or the net collapses onto the
  oracle); HUMAN judge = the Review-screen pick.

The honest gap: **this is NOT a closed AlphaZero loop today.** The value half is proven on
device; the **policy half has no trainer, no target, and no on-device path** (the spec heads
exist as an oracle only). v1 ships value-only on device + a frozen pretrained policy.

---

## 5. The on-device personalization spine (proven + stubbed)

One tap (`AtlasState.choose`) fans out into two paths, both logging the same BT Compare.

- **Path 1 — value/θ update (PROVEN train-spike).** MPSGraph `gradients(of:with:)` + SGD
  trained the 29,249-param value net on a physical iPhone 17 Pro: BT loss 0.7154 → 0.00075
  over 300 steps, **12.4 ms/step, 6.3 s total**, loss trajectory **bit-identical Mac ↔ iPhone**
  (commit `ef0344e`, `AtlasTrainer.swift`). MPSGraph satisfies the Tier-2 zero-dep rule
  (Apple system framework). Gotcha encoded in code: MPSGraph cannot EXECUTE in the simulator;
  gate with `#if targetEnvironment(simulator)`.
  - **DESIGN DECISION (v1):** the value head is a LINEAR utility over the 770-D
    `atlasEmbedding`, so it IS literally `btUpdate` (`PreferenceUpdate.hs`, η=0.05, λ=1e-3,
    dims=770) and the three spec laws (`lawGradientFiniteDiff`, `lawThetaBounded`,
    `lawStepDecreasesLoss`) transfer for free. The proven 29,249 number is for the EXISTING
    384-genome MLP path and must be RE-MEASURED for the linear-770 head (it will be cheaper).
- **Path 2 — inference-time genome displacement (no retraining).** `applySigmaOverride(δ, g0)`
  reconstructs the palette from a 384-D σ-locked Q16 δ (even leaves = generator+δ, odd =
  σ(generator+δ)). BUILT, Zig+Swift byte-exact (`Spec.LeafOverride`).

**Spec'd-but-stubbed (~30% on device).** The A/B proposer is a STUB:
`AtlasState.perturb()` applies a **fixed ±0.04 OKLab chroma delta** (Q16 2621 on the a-axis,
sign alternating across slot pairs — `AtlasState.swift:170-180`), NOT the spec'd
`sampleOrthogonalPair` (disjoint-band orthogonal proposal with ranking, `Spec.GenomePair`,
no on-device caller). Also stub/spec-only: the `btUpdate` loop + `PersonalGenomeStore`, the
10-Compare promotion gate, full 770-D embeddings per `DecisionLog` record (today hash-only).

---

## 6. The GumbelSearch MCTS (the search tier)

Gumbel-AlphaZero (Danihelka et al. 2022) for the shipped search; classic persistent-tree PUCT
(`PaletteSearch.mctsStep`, kept verbatim) for the Mac expert-iteration harness. Branching is
capped at 8 (`AtlasOracle.policyWidth`), so root selection is **Sequential Halving** over all
8 children — near-exhaustive, provably non-regressive, no PUCT `c`/Dirichlet tuning, and the
search output is a valid policy-training target.

- **Cross-tier determinism via Q16 comparison keys.** `q16Key(v) = round(v · 65536)`
  (`GumbelSearch.hs:50`); equal keys ⇒ same 2⁻¹⁶ bucket, so a sub-key float wobble cannot flip
  a move (`lawArgmaxKeyDependsOnlyOnKeys`, `GumbelSearch.hs:31`). The GPU must quantize its
  fixed-order reduction to this integer key — the key, not the float, is the contract.
- **Split:** Tier A (CPU/Swift) owns the rose tree, Gumbel/Sequential-Halving, seeded
  tie-break (integer, pointer-chasing). Tier B (Metal) is a batched value oracle only —
  dynamics are KNOWN and reversible, so the GPU NEVER simulates dynamics (no MuZero latent
  model, which would also break the byte-exact contract).
- **Status:** `Spec.PaletteSearch` MCTS is spec-complete (336 LOC) with **zero iOS consumer**
  (open debt `palette-search-design-only`); the GPU value oracle does not exist.

---

## 7. The cross-tier agreement model + its open holes

Zig does NOT compile to Metal. The two tiers are separately ported and unified ONLY through
**golden vectors** — the parity gate is the agreement mechanism, not a shared IR (a
Zig→Metal/SPIR-V bridge would pull MoltenVK/SPIRV-Cross, violating Tier-2 zero-dep). Two
regimes: integer Q16 (exact, byte-for-byte: Haar lift, collapse maximin, OKLab) and float32
(ordinal-only: policy logits, value, histograms — agree on the DECISION via Q16 keys).

Named hazards: `@divFloor` (Zig/Haskell, floor toward −∞) vs Metal `/`/`>>` (truncate toward
zero) differ by 1 LSB on negatives and break the lift's floor-cancellation — every signed
Metal division MUST use an explicit `floorDiv` helper. `simd_sum` reassociation is
non-reproducible — require a fixed-order fold. Float histogram accumulation is order-dependent.

**Two open determinism holes (both gating any on-device policy/value selection):**

1. **`BoardQ16` has zero Zig/Swift port.** The integer-histogram contract is spec-complete
   (`Spec.BoardQ16`, `countsQ16`, `lawCountsOrderIndependent`) but there is no `s4_board_q16`
   in `Native/` and no Swift mirror, so the live device path `AtlasBoard.histogram` stays
   FLOAT (sums in input order — a 1-ULP nudge can flip a bin boundary). This is the float
   leak at the policy net's FIRST matmul input. Until ported, cross-device policy agreement
   is aspirational.
2. **No GPU byte-exact golden gate exists.** The only gated Metal is `field.metal`, and it
   gates against a Haskell/Swift CPU reference WITHIN FLOAT TOLERANCE, not a Zig byte-exact
   golden. The integer cube-lift kernel exists in Zig (`s4_cube_lift_level`, `kernels.zig:684`,
   inverse `:711`) but has no Metal port. So the GPU side of the determinism contract is
   currently **aspirational** — every proven byte-exact gate is CPU-tier (Zig/Swift/Haskell).
   The first byte-exact Zig→Metal gate (a `floorDiv` port of `s4_cube_lift_level` on a
   negative-heavy round-trip fixture) is the precedent every later GPU kernel follows.

Proven byte-exact gates today (CPU-tier, on real hardware): Q16 Haar lifting
(`rgbt4d_fixture_test.zig`, `RGBT4DGoldenTests.swift`), collapse maximin
(`CollapseGoldenTests.swift`), Q16 OKLab (`ColorFixed.hs` ↔ Zig), genome projections
(`GenomeFixedGoldenTests.swift`).

---

## 8. Build-order roadmap (ownership per phase)

The deep, spec-first, phase-by-phase sequence is `SIXFOUR-ALPHAZERO-COLLAPSE-DESIGN.md`
§8 (dead-MLX teardown) + §9 (phased build). Summary of the eight units of work, in honest
dependency order:

1. **Wire the existing `Spec.GLRM` kill-switch** into the preference-training path (it is
   BUILT — Gauss-Jordan OLS, `shouldTrain`, `r2Floor` — but called by no live trainer).
2. **Port `BoardQ16` to Zig + Swift**, replace `AtlasBoard.histogram`, gate
   `lawCountsOrderIndependent` (closes hole #1 in §7; the determinism prerequisite).
3. **Decide + wire the genome source.** `loadLookNet` has no weights. EITHER retrain a
   converging full-colour look-NN and re-export a real `.s4ln`, OR commit to the AlphaZero
   collapse-game as the generator. Until one lands, the genome path has nothing to load.
4. **Replace `perturb()` with `sampleOrthogonalPair`** + wire `btUpdate`; extend `DecisionLog`
   to store full 770-D embeddings; ship the disjoint-band A/B proposer.
5. **Stand up the first byte-exact Zig→Metal golden gate** (Metal port of `s4_cube_lift_level`
   via `floorDiv`; closes hole #2 in §7; the GPU precedent).
6. **Build the Gumbel-search GPU value oracle** on that gate (batched frontier, Q16 keys).
7. **Close the AlphaZero loop on device** (policy + value oracle + MCTS over `DeltaCodebook`,
   A/B reward, 10-Compare replay promotion). Atlas nets first need spec-pinned `NetIOSpec`s.
8. **Add `GenomeBlend` + `GenomeCarrier`/`ExportFamily`** (foreign looks enter as one BT
   Compare; genomes ship in the S4GN carrier; export the three ladder rungs). These three
   modules are spec-only with zero on-device consumers today.

---

## 9. Known debt (cross-link)

The authoritative open-debt table is `docs/STATUS.md` "Open debt". NN-relevant rows:
`looknet-load-unused` (high), `no-look-category-taxonomy` (high), `no-ondevice-trainer-spec`
(high), `palette-search-design-only` (med), `palette-value-unused` (med), `empty-training-data`
(high). The two determinism holes (§7) and the `perturb()` stub (§5) are tracked in
`SIXFOUR-BACKEND-TENSOR-STACK-MAP.md` §5–§7 and should be promoted into STATUS.md as the
AlphaZero path is wired.

---

## Appendix — verified facts (checked against source this pass)

- `Spec.GLRM.hs` EXISTS (its own header notes it was written because COLOR-ATLAS wrongly cited it as shipped). It is spec-only, not wired into a live gate.
- Supervised MLX training ABANDONED (STATUS.md:185); `look_net_trained.s4ln` / `atlas_net_trained.npz` / `synth_looknet_grayscale.gif` DELETED. Only `.s4ln` on disk is the regenerable golden `look_net.s4ln`.
- Device value spike = **29,249 params** (`AtlasTrainingSession.swift:76`), 12.4 ms/step, Mac↔iPhone bit-identical.
- `GumbelSearch.hs`: `q16Key` at :50, `lawArgmaxKeyDependsOnlyOnKeys` at :31.
- `s4_cube_lift_level` IMPLEMENTED in Zig (`kernels.zig:684`, inverse :711); Metal port absent.
- `NetContract`/`net_shape.py` pins ONLY METRIC (in=6) and LOOK (in=10, out=384); Atlas nets NOT spec-pinned (`ATLAS_TOKEN_DIM=13`, `N_VOCAB=1524` live only in trainer Python).
- `BoardQ16` has zero Zig/Swift port — the live float-determinism hole on `AtlasBoard.histogram`.
- Maximin IS the collapse canon (the "maximin ≠ Wu" bug is disproven).
- `AtlasState.swift` A/B candidate B is a `perturb()` STUB (Q16 2621 fixed chroma), not `sampleOrthogonalPair`.
- GAN: `Map.hs:25` lists `Spec.Loss` as "OT/reconstruction; GAN dropped" (canon); `trainer/regimen.py:14,54` still says "ε-annealed GAN + halting" (stale dead-MLX text).