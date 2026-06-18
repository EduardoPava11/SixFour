# SixFour — Backend Tensor-Stack Map & Vocabulary

## 0. Vocabulary (the words to use)

- **Q16** — 16.16 fixed-point integer (int32 LE, scale 2^16); the device-reproducible arithmetic. Floats live only in the Haskell spec + the Mac trainer.
- **golden vectors** — bit-exact test fixtures emitted by the Haskell spec; the ONLY mechanism unifying Zig/Swift/Metal ports (no shared IR).
- **collapse** — per-frame palettes → one global palette; the **P operator**. The *shipped* path is deterministic **maximin** (Gonzalez 1985 farthest-first, `s4_quantize_frame`/`s4_global_collapse`) + Lloyd; this IS the `Spec.Collapse`/`Spec.QuantFixed` canon (the "maximin ≠ Wu" bug is disproven). A Wasserstein-barycenter / Sinkhorn collapse is a *trainer-side* construct, not the device default.
- **cube ladder** — reversible 2D-Haar spatial tiers {16³, 64³, 256³}; tier16↔tier64 lossless, tier256 (`synthBeyond`) the ONE non-invertible super-res step.
- **R/G/B/T operators** — Haar sub-bands (LL/LH/HL/HH) over the RGBT4D buffer (spatial + temporal); RGBT-4D landed but is dormant on device.
- **σ-pair genome** — the Look-NN's 384-DOF output (`SIGMA_PAIR_DOF`): 128 generators, Haar-decomposed, reconstructing a σ-symmetric 256-leaf palette (even leaf = generator+δ, odd = σ(generator+δ), locked by construction).
- **generator space vs leaf space** — 384 generator coeffs (128 OKLab pairs) ≠ 768 leaf coordinates; related by non-orthogonal Haar, NOT interchangeable.
- **GMM tokens** — 10-D per-frame palette summaries (`GMM_TOKEN_DIM = 10`); the permutation-invariant Look-NN input (set of ≤ `MAX_TOKENS = 16384`).
- **nudge** — generator-space δ override, σ-locked, applied at inference WITHOUT retraining (`applySigmaOverride` / `Spec.LeafOverride`).
- **θ (taste vector)** — 770-D per-device Bradley-Terry utility; learned by on-device SGD; never spliced foreign.
- **Bradley-Terry (BT) Compare** — one A/B pick logged as (winner, loser); the universal reward signal for both θ and the value net.
- **personalBeta** — `n/(n+50)` warm-start ramp weighting θ vs cold-start color-energy ranking (the dominant cold-start policy per `fed_sim`).
- **q16Key** — `round(v · 65536)`; quantizes a float to an integer decision key so sub-ULP wobble cannot flip a cross-tier argmax.
- **σ-equivariant** — Look-NN structure where reflection commutes with the net by proof (`LookNetCompose`), not by loss.
- **GLRM** — deterministic OLS kill-switch over [coverage, beauty, chroma²]; STOP value training if R² < `r2Floor`. EXISTS as `Spec.GLRM.hs` (built here, not borrowed).
- **DeltaCodebook** — finite 1524-move vocabulary (127 node × 12 delta) shared by policy + search; not a net.
- **federated genome** — a foreign look enters as exactly one BT Compare, replay-deterministic (`GenomeBlend`), never spliced.

## 1. Where everything is (file map by tier)

**Spec tier (Haskell — source of truth, ~112 modules; 834 tests green):**
- `spec/src/SixFour/Spec/Map.hs` — orientation index for the whole spec.
- `spec/src/SixFour/Spec/Net.hs` — the NN-slot CONTRACT; pins exactly two slots: `NetSlotMetric` + `NetSlotLook` (Atlas is NOT here — see §2).
- Look-NN: `LookNetE.hs` (encoder), `LookNetR.hs` (recursion), `LookNetD.hs` (decoder), `LookNetCompose.hs` (σ-equivariance theorem), `SigmaPairHead.hs` (reconstruction), `Loss.hs`, `LookNetEval.hs` (golden forward oracle).
- Atlas: `AtlasNetEval.hs` (policy+value oracle), `AtlasGame.hs`, `DeltaCodebook.hs`, `GumbelSearch.hs` (`q16Key` :50, `lawArgmaxKeyDependsOnlyOnKeys` :31, Sequential Halving).
- Q16 cores: `ColorFixed.hs` (OKLab, icbrtQ16), `RGBTLift.hs`/`CubeLadder.hs` (Haar lifting), `Collapse.hs`, `BoardQ16.hs` (integer histogram contract, NOT yet ported).
- A/B + preference: `PreferenceUpdate.hs` (btUpdate θ), `PersonalGenome.hs`, `GenomePair.hs`, `LeafOverride.hs`, `GenomeBlend.hs`, `GLRM.hs` (the OLS kill-switch — present).

**Trainer tier (Python/MLX on M1):**
- Look-NN: `trainer/train_look_net_mlx.py`, `look_net_loss_mlx.py`, `regimen.py` (orchestration + gates), `trainer/generated/look_net_mlx.py` (codegen from Haskell).
- Atlas: `atlas_net_mlx.py` (policy+value prototype; `ATLAS_TOKEN_DIM=13`, `N_VOCAB=1524`), `train_atlas_mlx.py`, `atlas_synth.py` (synthetic oracle data).
- Data: `synth_classes.py` (stratified GIF corpus), `export_look_net_blob.py` (.s4ln serializer), `fed_sim.py` (federation simulation only).
- METRIC: `train_metric.py`. Codegen contract: `trainer/generated/net_shape.py` (pins METRIC + LOOK only).

**Zig core tier (`Native/`):**
- `Native/src/root.zig` — `s4_load_look_net` blob parser (no-copy, byte-exact); loader CODE kept though no trained blob exists.
- `Native/src/kernels.zig` — `s4_global_collapse` (maximin), Haar lift/unlift, Q16 OKLab matrices, and `s4_cube_lift_level` (`:684`, implemented, with exact inverse `:711`). The Metal port of this kernel is what's absent, not the Zig kernel.
- `Native/src/rgbt4d_fixture_test.zig` — cross-language golden gate (Zig ≡ Haskell), now lit.

**Swift/Metal app tier (`SixFour/`):**
- `SixFour/Organs/MetricOrgan.swift` — METRIC PSD load.
- `SixFour/Native/SixFourNative.swift` — `loadLookNet` (declared, zero production callers).
- `SixFour/Atlas/AtlasTrainer.swift` (+`AtlasTrainingSession.swift`) — MPSGraph on-device value training + btUpdate SGD.
- `SixFour/Atlas/AtlasState.swift` — A/B `choose`, Compare logging.
- `SixFour/Metal/field.metal` — tolerance-gated field shader; `Shaders.metal` — float color transfers (NOT the integer cube kernels).
- Tests: `CollapseGoldenTests.swift`, `RGBT4DGoldenTests.swift`, `GenomeFixedGoldenTests.swift`, `NearestCentroidTests.swift`.
- Canon: `docs/STATUS.md`; key designs `SIXFOUR-ALPHAZERO-COLLAPSE-DESIGN.md`, `COLOR-ATLAS.md`, `ON-DEVICE-TRAINING.md`, `SIXFOUR-METAL-FIELD-SPEC-ALIGNMENT.md`.

## 2. The NN roster

Param counts are flagged: **(pinned)** = grounded in source/STATUS; **(est.)** = unsourced design estimate (the only repo range is COLOR-ATLAS.md's loose "~16K–115K").

| net | role | I/O | params | trained where | inference where | status (per STATUS.md canon) |
|---|---|---|---|---|---|---|
| METRIC | OKLab perceptual distance (PSD Cholesky) | 6 → in-place | 6 (pinned) | M1 `train_metric.py` | `MetricOrgan.swift` | shipped |
| LOOK-NN (E▸R▸D) | σ-equiv genome decoder | 10-D GMM set ≤16384 → 384 σ-pair coeffs | ~115K (est.) | M1/MLX `train_look_net_mlx.py` | hand-written Swift/Metal (unwired) | **ABANDONED** — supervised MLX run did not converge; trained `.s4ln` DELETED. Spec/forward-oracle intact; no trained weights exist. |
| ATLAS policy (node+delta) | factored 1524-move policy | 13-D tokens + 384 genome → 1524 logits | ~6K (est.) | M1/MLX `train_atlas_mlx.py` | none (oracle only) | prototype; NOT spec-pinned (no `NetIOSpec`) |
| ATLAS value (Mac) | BT preference scorer | 128-D context → 1 | ~1K (est.) | M1/MLX `atlas_net_mlx.py` | none | prototype; NOT spec-pinned |
| ATLAS value (device spike) | per-device BT value | 4096×6 board + 384 genome → 1 | **29,249 (pinned)** | iPhone/MPSGraph `AtlasTrainer.swift` | none (train-only) | spike-verified on device (train only) |
| PreferenceUpdate θ | linear utility (not a net) | 770-D embed → utility | 770 (pinned) | iPhone SGD | on-device fold | spec'd; device path is a stub (§6) |
| GLRM | OLS kill-switch (not a net) | 4 feat → 4 coeffs | 0 | — | gating only | spec'd (`Spec.GLRM`), not wired |

> **Spec-pinning asymmetry (gap a maintainer needs):** the generated `NetContract` (`Net.hs` → `net_shape.py`) pins ONLY `METRIC` and `LOOK` with golden `NetIOSpec`s. The entire Atlas roster (policy + value) has NO spec-pinned shape — its dimensions live only in un-codegenned trainer Python (`ATLAS_TOKEN_DIM=13`, `N_VOCAB=1524`) and Swift literals. Atlas is not contract-protected the way LOOK/METRIC are.

**METRIC** — a 6-float PSD matrix (a Cholesky factor) consumed by `KMeansLab.run` as its distance; the only learned component shipped to device.

**LOOK-NN (E▸R▸D)** — the designed genome decoder. Permutation-invariant GMM tokens → L3 σ-masked φ linear → sum-pool → L4 static-unrolled shared block (×8) with PonderNet halting → L5's 8 per-Haar-level heads → 384 σ-pair coefficients → `SigmaPairHead.reconstructPaired` → 256-leaf palette; σ-equivariant by theorem (`LookNetCompose`). The forward oracle (`LookNetEval.hs`) and the Zig loader are intact, but the supervised MLX trainer was **abandoned today** and produced no usable weights — this is a designed-and-specced net with no trained artifact.

**ATLAS policy (node+delta)** — factored AlphaZero policy over `DeltaCodebook` (127 node × 12 delta), σ-equivariant, reusing the Look-NN backbone. Prototype trainer only; oracle in `AtlasNetEval.hs`.

**ATLAS value (Mac)** — BT scalar utility over (board, genome); the cold-start companion to the policy, trained together from synthetic oracles.

**ATLAS value (device MPSGraph spike)** — the same BT value, trained on-device with Apple's MPSGraph (zero third-party deps). Proven on a physical iPhone 17 Pro: **29,249 params**, BT loss 0.7154 → 0.00075 over 300 steps, **12.4 ms/step (6.3 s total)**, trajectory bit-identical Mac ↔ iPhone. It trains; it does not yet select palettes.

**PreferenceUpdate θ** — not a net: a 770-D linear utility vector (256 leaves × 3 OKLab + coverage + beauty) updated by exact BT-logloss + L2 SGD; the θ vector IS the model. Replay-deterministic from `coldStartGenome` + ordered log.

**GLRM** — not a net: a deterministic Gauss-Jordan OLS over [coverage, beauty, chroma²] run BEFORE any value-net training; if R² < `r2Floor` (or singular design), STOP. **It exists** (`Spec.GLRM.hs`, written precisely because COLOR-ATLAS had referenced it as shipped when it wasn't); it is spec-only, not yet wired into a live training gate.

## 3. Training, mapped

**Two-stage spine.** Stage 1 = the **Look-NN base** on M1 via MLX (`regimen.py`); Stage 2 = the **per-user Atlas value/policy delta** on iPhone via MPSGraph. The base net is global and shared; the delta is personal and never leaves the device unspliced.

**Stage 1 — Look-NN (M1/MLX) — ABANDONED as of 2026-06-17.** The pipeline is real and its mechanics below are accurate to `regimen.py`, but the supervised grayscale-L run **did not converge to a usable look** and the trained outputs (`look_net_trained.s4ln`, `atlas_net_trained.npz`, `synth_looknet_grayscale.gif`) were DELETED. Treat this stage as design + dead trainer, not "production-ready." As designed: `regimen.py` runs pre-train gates, then trains on synthetic GIFs (stratified via `synth_classes.py`), decoding pixels through `zig_native` so the input path is the exact device path. The trainer code is GAN-shaped (a Mac-only discriminator judging global vs per-frame palette, ε-annealed); note the spec INDEX (`Map.hs`) lists `Spec.Loss` as "OT/reconstruction; GAN dropped", so the GAN framing is contested between trainer code and spec. Designed losses: Bures-Wasserstein W2 fidelity, Ou-Luo beauty (over 128 σ-pairs), discrete coverage (monitored, not differentiated), Sinkhorn render (ε 0.02→0.00015), Bures anchor, PonderNet halting KL. Halting is a regularizer, not a target; output uses full depth-8 reconstruction. (No trained weights survive.)

**Stage 2 — Atlas on-device (iPhone/MPSGraph, spike-verified).** Trains per-user V(board, genome) from Compare pairs. Loss: BT logistic `mean softplus(−(V_win − V_lose))`, gradient via MPSGraph reverse-mode autodiff + SGD assign ops. Net: board [B,4096,6] per-bin linear (6→64) + mean-pool + tanh, concatenated with a genome encoder (384→64, ≈24,640 params alone), → value MLP (128→32→1); total **29,249**. fp32, lr=0.25, batch=100, xorshift64 init. Verified on iPhone 17 Pro, 12.4 ms/step.

**AlphaZero expert-iteration loop.** `AtlasGame`/`AtlasOracle` frame collapse as MCTS over the `DeltaCodebook` 1524-move space; the policy proposes moves, the value scores frontier genomes, A/B picks supply the reward. Today this loop trains cold-start from synthetic oracles (`atlas_synth.py`) on Mac; the on-device half trains value only.

**GLRM kill-switch.** Per COLOR-ATLAS §5: before ANY value-net training on user prefs, regress BT outcomes on [coverage, beauty, chroma²]; no stable linear signal → STOP. `Spec.GLRM` implements this (it exists). Remaining work is WIRING it into the live preference-training gate, not building it.

**Federation.** `fed_sim.py` is pure simulation (BT, 770-D linear), not on-device data; it measured FedAvg-beats-local thresholds (K≥4 shared taste) and confirmed β=n/(n+50) as the dominant cold-start policy. The real path (secure aggregation + central DP + FedBiscuit) is unimplemented; foreign looks are designed to enter as one `GenomeBlend` Compare.

**What actually runs today:** the **Atlas value spike** on iPhone 17 Pro (train-only). The Look-NN trainer is abandoned with artifacts deleted; policy heads / full Atlas network are prototype only.

## 4. Inference, mapped

**Zero-dep forward-pass rule.** No mlx-swift, no CoreML, no ANE: every production forward pass is hand-written Swift/Metal, enforced by code review (`CLAUDE.md`). MLX stays on Mac (Tier 1, research-only); CoreML/ANE paths exist for reference only.

**Weight-blob loading (`.s4ln`).** Format from `export_look_net_blob.py`: little-endian header (magic `S4LN`, version 1, `tensor_count = 13`) + 13 tensor records (name, shape, row-major float32, no padding). The 13 = `TENSOR_ORDER = [phi, w1, w2, halt_w, halt_b] + head0..head7` (5 + 8); the Zig parser depends on exactly this name order. Weights are RAW (pre-σ-mask). The Zig loader returns float pointers aliasing the caller's buffer without copying. **Caveat: the only `.s4ln` on disk is the regenerable GOLDEN fixture `trainer/out/look_net.s4ln`, not a trained artifact** — the trained blob was deleted today. `SixFourNative.loadLookNet` has zero production callers and no real weights to load.

**σ-equivariant forward.** Masks applied at call time, not baked: L3 φ (64×10) free `iff sigma64Mask[o]==gmmTokenSigmaMask[i]`; L4 refine `x + tanh(W2·tanh(W1·x))` with 64×64 block-diagonal W1/W2 (22×22 achromatic + 42×42 chromatic, ~45% pruned); halt head reads σ-invariant features only (squared norms); L5's 8 heads each block-diagonal into the 64-D context. Output 384 coeffs → `SigmaPairHead.reconstructPaired` → 256-leaf σ-pair palette. (Spec-complete; production-unwired; no weights.)

**CPU-SIMD vs Metal split.** Zig owns integer math (CPU/SIMD); Swift owns UI; Metal owns the GPU field/render kernels. Nearest-centroid uses SIMD8 on CPU (`NearestCentroidTests.swift` gates GPU↔CPU within tolerance). The integer cube-lift kernel exists in Zig (`s4_cube_lift_level`); its Metal counterpart is NOT implemented.

**Current consumers.** Shipped rendering uses **deterministic Zig collapse** (`s4_global_collapse`, maximin), NOT learned selection. The Look-NN forward path is spec-complete but production-unwired (oracle `LookNetEval.hs`), with no trained weights. The Atlas value net trains on-device but is isolated fp32 telemetry that never selects a palette.

## 5. SIMT bit-agreement

**Core principle:** Zig does NOT compile to Metal. The two tiers are separately ported and unified ONLY through golden vectors — the parity gate is the agreement mechanism, not a shared IR (a Zig→Metal/SPIR-V bridge would violate Tier-2 zero-dep).

**Two regimes.** (1) **Integer Q16 — exact, byte-for-byte:** Haar lifting, collapse maximin, OKLab transforms. (2) **Float32 — ordinal-only:** policy logits, value estimates, histograms agree on the *decision* via Q16 comparison keys, tolerating sub-key float wobble.

**Named hazards.** (1) **`@divFloor` vs Metal truncation** — Haskell `div` / Zig `@divFloor` floor toward −∞; Metal `/` and `>>` truncate toward zero. On negatives they differ by 1 LSB, breaking the lifting's floor-cancellation inverse; every signed Metal division mirroring a Zig floor-div MUST use an explicit `floorDiv` helper. (2) **`simd_sum` reassociation** — unspecified lane order makes float reductions non-reproducible; require a fixed-order linear fold (no atomics) and quantize before comparing. (3) **Float histogram accumulation** — `AtlasBoard.histogram` sums in input order (permutation-dependent); a 1-ULP nudge can flip a bin boundary.

**Q16 argmax-key antidote.** `q16Key(v) = round(v · 65536)` (`GumbelSearch.hs:50`): equal keys ⇒ same 2^-16 bucket; combined with a fixed-order reduction, GPU and CPU emit the same key, and `lawArgmaxKeyDependsOnlyOnKeys` (`GumbelSearch.hs:31`) guarantees a seeded tie-break picks the same survivor. The histogram fix is `BoardQ16` (`countsQ16`, integer add, `lawCountsOrderIndependent`) — spec'd but with **zero Zig/Swift port** (no `countsQ16`/`s4_board_q16` in `Native/` or `SixFour/`), so the live device histogram path (`AtlasBoard.histogram`) stays float. This is THE open float-determinism hole gating any policy-net input determinism.

**Golden gates that enforce it (proven on real hardware):** Q16 Haar lifting (`rgbt4d_fixture_test.zig`, `RGBT4DGoldenTests.swift`, `lawLiftUnliftExact`), collapse maximin (`CollapseGoldenTests.swift`), Q16 OKLab transforms (`ColorFixed.hs` ↔ Zig), genome projections (`GenomeFixedGoldenTests.swift`), and the field shader within float tolerance.

**Honest gap — does any Metal kernel gate vs a Zig byte-exact golden today? No.** The only gated Metal is `field.metal`, and it gates against a Haskell/Swift CPU reference within float tolerance, not a Zig byte-exact golden. The integer cube-lift kernel exists in Zig but has no Metal port; the Gumbel-search GPU value oracle does not exist. So the GPU side of the cross-tier determinism contract is currently **aspirational** — every proven byte-exact gate is CPU-tier (Zig/Swift/Haskell).

## 6. The A/B nudge

One tap (`AtlasState.choose`) fans out into TWO paths, both logging the same BT Compare.

**Path 1 — training-weight update (θ).** Extract winner/loser leaves (SIMD3 Int32 Q16 OKLab) → FNV-1a32 hashes → `CurationMove.compare` → log to `DecisionLog` DECN chunk. `btUpdate` folds the Compare into the 770-D θ by exact BT-logloss + L2 SGD: `g = 1 − σ(θ·(w−l)); θ ← θ + η·g·(w−l) − η·λ·θ` (η=0.05, λ=1e-3). `personalBeta = n/(n+50)` ramps monotonically; every 10th Compare a candidate θ is replay-gated (strict majority over recent 8) before promotion. θ stays a pure memoized fold over the ordered local log → deterministic replay.

**Path 2 — inference-time genome displacement (no retraining).** The picked candidate is a 384-D Q16 OKLab δ in genome (Haar-coefficient) space. `applySigmaOverride(δ, g0)` reconstructs the palette exactly: even leaves = generator+δ, odd leaves = σ(generator+δ), σ-locked by construction so validity is free. Served to render immediately. (`Spec.LeafOverride` — built, Zig+Swift byte-exact.)

**"Nudge which way" control.** `sampleOrthogonalPair(g0, ranking)` proposes the next A/B pair, ranking by `personalBeta·θ·embedding + (1−beta)·colorEnergy` (warm) or `colorEnergy` alone (cold, n<8). The two candidates use DISJOINT generator bands (parity-interleave of top-2·pairBudget), giving EXACT 0 inner product by support-disjointness — in 384-D Haar space, NOT reconstructed-leaf space (Gram-Schmidt on leaves would destroy exactness).

**Spec'd vs wired (~30% on device).** BUILT: `applySigmaOverride` (Zig+Swift, exact Q16), DECN replay storage, hash-based Compare records, the on-device value-net training spike. SPEC-ONLY: `sampleOrthogonalPair` (today's device path uses a `perturb()` stub — fixed 0.04 chroma on the a-axis, placeholder, not real `GenomePair`), the `btUpdate` loop + `PersonalGenomeStore`, the 10-Compare promotion gate, `GenomeBlend` federated adoption, `GenomeCarrier` S4GN block, three-rung `ExportFamily`. Also: the spec wants full 770-D embeddings per Compare record, but `AtlasState.swift` stores hash-only — extending DECN to embed (w,l) is a prerequisite.

## 7. The build order this implies

Given the goal — own the tensor math in Zig with SIMT agreement, several trainable NNs, on-device — re-derived against current repo state:

1. **Wire the existing GLRM gate (`Spec.GLRM`) into the preference-training path.** It is BUILT (Gauss-Jordan OLS, `shouldTrain`, `r2Floor`) but not called by any live trainer. Port to Zig/Swift and gate Path-1 θ training on it, so preference learning can't fire on noise. (Cheap; the module no longer needs *building*.)
2. **Port `BoardQ16` to Zig + Swift and replace `AtlasBoard.histogram`.** Closes the live float-accumulation hole so the policy net's first matmul input is cross-device exact. Gate with a `lawCountsOrderIndependent` golden. This is the determinism prerequisite for any on-device policy/value selection.
3. **Decide the genome source, then wire it.** `loadLookNet` has no trained weights (look-net abandoned; only the golden fixture on disk). EITHER retrain a converging look-NN (full-colour, not grayscale-L) and re-export a real `.s4ln`, OR commit to the AlphaZero collapse path as the genome generator. Until one lands, "turn the trained base net into a palette source" has nothing to load — sequence this honestly.
4. **Replace the `perturb()` stub with `sampleOrthogonalPair` + wire `btUpdate`.** Extend DECN to store full 770-D embeddings, fold real θ on device, ship the disjoint-band orthogonal A/B proposer. Both nudge paths then live off one tap.
5. **Stand up the first byte-exact Zig→Metal golden gate.** Add a Metal port of `s4_cube_lift_level` (the Zig kernel already exists) using `floorDiv` + fixed-order reductions; gate it against the existing Zig golden fixtures. This is the missing proof that the GPU tier byte-agrees — the precedent every later kernel follows.
6. **Build the Gumbel-search GPU value oracle on that gate.** Batched frontier evaluation emitting Q16 keys via fixed-order reduction; gate `lawArgmaxKeyDependsOnlyOnKeys` on real hardware. Connects the on-device value net to actual genome selection.
7. **Close the AlphaZero loop on device.** Wire policy (node+delta) inference + the proven value oracle + MCTS over `DeltaCodebook`, fed by A/B Compares as reward; promote candidate θ/genomes via the 10-Compare replay gate. (Note: Atlas nets first need spec-pinned `NetIOSpec`s — they have none today.)
8. **Add `GenomeBlend` + `GenomeCarrier`/`ExportFamily`.** Foreign looks enter as one BT Compare (replay-deterministic); genomes ship in the S4GN carrier; export the three cube-ladder rungs. Federation (secure-agg + DP) layers on last.

## Confidence & caveats

**Source-verified (checked against repo / STATUS.md this pass):**
- `Spec.GLRM.hs` EXISTS (OLS kill-switch; its own header notes it was written because COLOR-ATLAS wrongly cited it as shipped). The earlier "GLRM missing / must be built" claim is false.
- Look-NN supervised MLX training is **ABANDONED** (STATUS.md, 2026-06-17); `look_net_trained.s4ln` / `atlas_net_trained.npz` / `synth_looknet_grayscale.gif` were DELETED. The only `.s4ln` on disk is the regenerable golden `trainer/out/look_net.s4ln`.
- Device value-net spike = **29,249 params** (STATUS.md + `AtlasTrainingSession`), 12.4 ms/step, Mac↔iPhone bit-identical loss. ("~24K" was wrong.)
- `GumbelSearch.hs`: `q16Key` at :50–51, `lawArgmaxKeyDependsOnlyOnKeys` at :31 (not :111).
- `s4_cube_lift_level` is IMPLEMENTED in Zig (`kernels.zig:684`, inverse :711); only its Metal port is absent.
- `NetContract`/`net_shape.py` pins ONLY `METRIC` (in=6,out=0) and `LOOK` (in=10,out=384); Atlas nets are NOT spec-pinned (`ATLAS_TOKEN_DIM=13`, `N_VOCAB=1524` live only in trainer Python).
- `.s4ln` `tensor_count = 13` with `TENSOR_ORDER = phi, w1, w2, halt_w, halt_b, head0..head7`.
- `BoardQ16` has zero Zig/Swift port (grep clean) — the live float-determinism hole on `AtlasBoard.histogram`.
- Maximin IS the collapse canon (the "maximin ≠ Wu" bug is disproven, per STATUS).
- Stable structural facts: σ-pair 384 vs 768 leaves, θ=770, DeltaCodebook 127×12=1524, 6-channel board, 13-D Atlas tokens.

**Design-doc claims (NOT independently verified here — treat as design, not fact):**
- Roster param counts **~115K (Look-NN), ~6K (Atlas policy), ~1K (Atlas value-Mac)** are ESTIMATES. No param-count literal exists in `atlas_net_mlx.py` / `look_net_mlx.py` / `net_shape.py`; the only repo figure is COLOR-ATLAS's loose "~16K–115K" range. Only METRIC (6), θ (770), and the device spike (29,249) are pinned.
- The Stage-1 loss recipe (Bures-W2 / Ou-Luo / Sinkhorn / PonderNet KL, ε schedule, λ weights) is read from `regimen.py`/design docs and describes a now-abandoned trainer. The **GAN framing is internally contested**: trainer code references an ε-annealed GAN, but `Map.hs` lists `Spec.Loss` as "GAN dropped."
- Federation thresholds, `personalBeta` dominance, and the on-device build feasibility are from `fed_sim`/research docs, not live device measurement beyond the value spike.
- The σ-equivariant forward internals (block dims 22+42, ~45% pruning, halt head, 8 heads) are spec/design; there is no shipped Swift/Metal forward pass exercising them and no trained weights.