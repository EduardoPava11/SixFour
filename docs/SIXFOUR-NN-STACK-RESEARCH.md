# SixFour NN Stack, Research & Design Options

> **Status: RESEARCH + PROPOSAL.** UPDATE 2026-06-19: the 4 architecture-gating decisions are now **SIGNED OFF** (see §1.5); the other 9 (§8) default to the §7 recommendation unless revisited.
> This is the cited-research companion to [`docs/SIXFOUR-NN-STACK.md`](./SIXFOUR-NN-STACK.md).
> For **as-built status** (what actually compiles, what is a stub, what is dormant), defer to
> `SIXFOUR-NN-STACK.md`, that file is canonical for "what exists"; this file is "what the
> literature says we could build, and what I'd recommend." Where the two disagree about
> as-built reality, the NN-STACK doc wins.

---

## 1. What this is

This report gathers **cited research options** behind the three forks the user has **aligned on**
(but not yet finalized in detail):

- **Fork A, MLX demoted to OPTIONAL warm-start.** Every net must be trainable on-device from a
  cold seed; a Mac/MLX base may only ever be a non-required prior.
- **Fork B, fully-LEARNED on-device 256-cube super-res**, per-frame, that preserves the
  hard contract **zero-genome == deterministic floor, bit-for-bit**.
- **Fork C, value-guided Gumbel-AlphaZero proposer** that learns from the user's A/B picks and
  surfaces ≥2 candidate looks per shutter press.

For each fork it lays out the candidate architectures with real citations, maps them onto the
**dormant repo assets** they would reuse, and folds in an honest set of adversarial feasibility
verdicts (Section 6). Section 7 is a single **RECOMMENDATION** (clearly marked, not decided), and
Section 8 returns the specific open choices to the user.

---

## 1.5 LOCKED DECISIONS (signed off 2026-06-19)

The four architecture-gating choices are decided. The remaining 9 (§8) default to the §7
recommendation unless revisited.

| Decision | Choice |
|---|---|
| **SR delivery** | **Pure from-scratch on-device** — no Mac/MLX warm-start of SR weights; the residual is zero-gated to the deterministic floor so export == floor bit-exact until it learns. |
| **Value head** | **Tiny ~50–100K-param Bradley-Terry MLP** on the MPSGraph `AtlasTrainer` spine; CPU-linear θ kept as fallback. |
| **Proposer search** | **Shallow MCTS tree, depth 2–3** over policy-sampled genomes (`GenomePair` seed) ranked by the value head (a real tree, not depth-1 afterstate). |
| **Cold-start** | **Optional frozen Reptile/federated prior** via `personalBeta = n/(n+50)`, never required; applies to the value/policy + genome path, NOT the SR head. |

**Consistency note (SR from-scratch vs. warm-start prior).** These do not conflict. The SR head
trains from scratch on-device, but its *output quality* is never cold because the zero-gated
**floor is its warm-start** (export == deterministic floor until the residual trains). The optional
prior applies only to the **value/policy + genome** path, where there is no floor to fall back on.
So: SR cold-starts on the floor; taste/proposer cold-start on the optional prior.

**Open feasibility risk carried forward.** On-device *training* of the SR head at interactive
latency is UNPROVEN (not refuted) and thermally throttled — mitigated by amortized burst-training
plus the floor gate, but it is the piece to spike first.

**Every claim below is grounded in the research/feasibility JSON gathered for this pass.** Where a
claim is a synthesis rather than a citable result, it is flagged as such. Uncertainty is called out
honestly rather than smoothed over: in particular the "AND a super-res head at interactive latency"
half of on-device training is the weakest-supported part of the whole plan, and is treated that way.

**Nothing here is a decision.** The forks are *aligned*; the *design choices within them* (which
SR body, which value-head link, which sim budget, which cold-start policy, whether to keep a
federated prior) are queued for sign-off. Treat Section 7 as a proposal to react to, not a plan
to execute.

---

## 2. The unified on-device loop

The three forks are **not three separate systems**, they are one closed loop driven by a single
signal: the **Bradley-Terry pick**. One A/B tap is, simultaneously, a label that trains the *value
head* (which look is better), a target that improves the *policy/proposer* (make winners more
likely), and a supervision signal that the *learned super-res* learns detail against. The
deterministic floor sits underneath all of it as the cold-start safety net and the anti-collapse
anchor.

```
                         ┌──────────────────────────────────────────────┐
                         │   DETERMINISTIC FLOOR (no training, integer)   │
                         │   RGBT4DLift / synthBeyond256 replicate        │
                         │   zero-genome  ==  floor, bit-for-bit          │
                         └───────────────────────┬──────────────────────┘
                                                 │ (additive base, always present)
   per-frame OKLab                               │
   palettes (16 / 64)                            ▼
        │                  ┌────────────────────────────────────────┐
        │   sample k       │  FORK C: Gumbel proposer                │
        │   genomes        │  • policy head  → sample ≥2 genomes     │
        ├─────────────────►│  • value head (Bradley-Terry) ranks     │
        │  GenomePair      │    via Sequential Halving (n=1..16 sims) │
        │  .sampleOrth.    └───────────────┬────────────────────────┘
        │                                  │ survivors = gallery (≥2 looks)
        │                                  ▼
        │                  ┌────────────────────────────────────────┐
        │   genome cond.   │  FORK B: learned 256-cube super-res    │
        └─────────────────►│  detail = floor  +  gate(genome)·resid │
                           │  zero genome ⇒ zero residual ⇒ floor   │
                           └───────────────┬────────────────────────┘
                                           │ rendered candidates (per-frame)
                                           ▼
                              ┌──────────────────────────┐
                              │   USER A/B PICK (winner)  │   ← the ONE signal
                              └────────────┬─────────────┘
                                           │  Bradley-Terry pair (w ≻ l)
            ┌──────────────────────────────┼──────────────────────────────┐
            ▼                              ▼                              ▼
   trains VALUE head            improves POLICY/proposer        supervises SR RESIDUAL
   (rank next gallery)          (DPO-style toward winner)       (detail the pick rewarded)
            │                              │                              │
            └──────────────► personalBeta = n/(n+50) shrinkage ◄──────────┘
                       (optional federated / MLX warm-start prior, Fork A)
```

**Why one signal trains both heads.** The pick is a *pairwise comparison*, which is exactly the
Bradley-Terry reward-model objective `P(w≻l)=σ(u(w)−u(l))` used across modern RLHF reward modeling
([Bradley-Terry reward models overview](https://www.emergentmind.com/topics/bradley-terry-reward-models)).
That same labeled pair (a) is the value-head training target the Gumbel search ranks by, and (b) can
*directly* shape the proposer via a DPO-style loss with the floor as the frozen reference
([DPO, arXiv:2305.18290](https://arxiv.org/abs/2305.18290)), and (c) tells the super-res residual
which high-frequency detail the user rewarded. The genome is the shared currency: it conditions the
SR residual (Fork B) and it is the action the proposer emits (Fork C), so improving the policy and
improving the detail are two projections of the same per-pick gradient.

**Why the floor unifies cold-start AND collapse-safety.** Round-0 ships the pure deterministic floor
(real, non-degenerate data). Self-consuming-models theory shows that retraining on curated
(=picked) self-output provably optimizes the user's preference **only if a positive fraction of real
data is mixed in every round, else the loop collapses**
([Ferbach et al., NeurIPS 2024, arXiv:2407.09499](https://arxiv.org/abs/2407.09499)). SixFour's
deterministic floor *is* that mandatory real fraction, so the same zero-genome==floor contract that
gives a safe cold start (Fork B) doubles as the anti-collapse anchor. Per-frame is preserved
throughout: genomes, palettes, residual quantization, and value scoring all run per-frame across the
64-frame burst.

---

## 3. Fork A, MLX as an OPTIONAL warm-start

**The contract:** train every net on-device from a cold seed; a Mac/MLX base is allowed only as a
*non-required* prior that improves day-one quality and decays as picks accumulate. The research says
this is **sound but partly semantic**, a truly zero-prior cold seed is weaker than the cited
warm-started results, and SixFour's `personalBeta = n/(n+50)` federated prior is *itself* doing soft
warm-start work.

### Cold-start-from-scratch: what's feasible

- **Tiny nets DO train on-device.** MIT's MCUNetV3 trains under 256 KB memory with quantization-aware
  scaling + sparse update ([On-Device Training Under 256KB](https://github.com/mit-han-lab/tiny-training)),
  and TinyPropv2 adds sparse backprop ([arXiv:2409.07109](https://arxiv.org/abs/2409.07109)). A
  ~100K-param value/policy head is in this regime. This is what distinguishes SixFour from the
  "full CNN from scratch on a phone is infeasible" warning
  ([machinethink, training-on-device](https://machinethink.net/blog/training-on-device/)).
- **The deterministic floor is the cold-start safety net.** The zero-genome==floor contract is the
  ZerO/ReZero residual-with-zero-init pattern: the network "effectively begins as an identity
  function and refines it during training"
  ([ZerO Initialization, ICLR 2022](https://openreview.net/forum?id=EYCm0AFjaSS)). First-use quality
  is therefore *the floor* (a real, shippable look), not random garbage, the load-bearing reason the
  cold-start premise survives at all.

### Warm-start options (all OPTIONAL)

1. **Reptile / first-order MAML meta-learned init.** Meta-train (offline, Mac/MLX) a single shared
   init so a handful of on-device SGD steps adapt to a user's taste; first-order, ≥4× cheaper than
   MAML ([Reptile, Nichol & Schulman](https://www.researchgate.net/publication/323654774_Reptile_a_Scalable_Metalearning_Algorithm)).
   `p-Meta` extends this to memory-efficient on-device adaptation by updating only the most
   adaptation-sensitive layers ([arXiv:2206.12705](https://arxiv.org/pdf/2206.12705)). The meta
   *training* is the optional heavy outer loop; the few-step *adaptation* is always on-device. The
   synthetic-task distribution needed for meta-training is exactly what the Zig synthetic-GIF data
   engine can generate.
2. **Frozen federated-average / shipped-weights prior (WarmFed-style).** A privacy-clean static prior
   gives a sensible day-one taste; influence decays as local data grows
   ([WarmFed, arXiv:2503.03110](https://arxiv.org/abs/2503.03110)). For SixFour this stays a
   *shipped frozen blob* (no live server aggregation, which the product explicitly does not want).
   Personalized-federated cold-start results confirm shrinkage-to-population-prior helps new users
   ([Personalized Federated Recommendation for Cold-Start Users, WWW 2025](https://openreview.net/forum?id=bhWngwuo74)).
3. **No prior at all.** Pure from-scratch is viable at 100K params; it only changes *how many picks*
   are needed before the net is useful, not *whether* on-device adaptation works.

### Map to repo assets

- **`AtlasTrainer`** (dormant MPSGraph Bradley-Terry value net, ~12.4 ms/step proven on iPhone 17
  Pro) is the on-device training spine all three options feed.
- **`PersonalGenome.personalBeta = n/(n+50)`** is the Bayesian analogue of "warm-start decays as data
  grows", it *is* the soft prior, so be honest that "cold seed, no base" is partly semantic.
- **`PersonalTaste theta`** (live CPU Bradley-Terry linear leaf) works from pick #1 with zero GPU,
  the always-available fallback while a GPU net warms up.
- **MLX** is therefore demotable to optional **per the literature**, but a population/federated prior
  is effectively a warm-start, so the honest framing is "MLX-base optional, *some* prior recommended."

---

## 4. Fork B, Learned 256-cube super-res

**The contract:** a per-frame, on-device-trainable 64-cube→256-cube super-res head where a
zero/near-zero genome reproduces the deterministic replicate floor **bit-for-bit**. The candidate
space splits into (i) a *wrapper* that guarantees identity-at-floor, (ii) a *tiny body* that
generates the residual, and (iii) a *conditioning path* for the genome.

### (i) The wrapper, how identity-at-floor is guaranteed

- **Global-residual-above-floor + zero-init gate (VDSR / ControlNet pattern).** Learn only the
  high-frequency residual above the floor, add the floor via a skip, and zero-init the last layer (or
  a ControlNet-style zero-conv gate) so the sum is *exactly* the floor at init and at zero-genome
  ([VDSR, arXiv:1511.04587](https://arxiv.org/pdf/1511.04587);
  [ControlNet zero-conv conditioning](https://www.emergentmind.com/topics/controlnet-style-conditioning-mechanism)).
  This is architecture-agnostic and is **the** mechanical answer to the bit-exact contract, it ships
  the exact floor at step 0 and degrades gracefully as the gate learns.
- **Honest caveat (from feasibility):** the bit-exact identity holds **by construction because the
  floor is the INTEGER INDEX domain**, not because a float net evaluates to the floor. `NetSynth256`
  already enforces this with a *guard* (`return floor` when weights absent OR genome all-zero), and
  `Spec.ExportFamily.lawZeroGenomeIsFloor` pins it as a golden law. The moment the net emits ANY
  nonzero detail, bit-exact **cross-device** reproducibility of *that detail* requires fixed-point
  integer treatment with overflow-safe accumulators, 16-bit gave literally zero cross-platform error
  ([Quantized Decoder for Deterministic Reconstruction, arXiv:2312.11209](https://arxiv.org/html/2312.11209v2)).
  ReZero/SkipInit give exact identity *only* at alpha literally 0; "near-zero genome" is **not**
  bit-exact in float ([ReZero, arXiv:2003.04887](https://arxiv.org/abs/2003.04887)). So the residual
  must run through SixFour's Zig integer core + golden vectors, or determinism that holds at the floor
  will *not* extend to trained outputs.

### (ii) The tiny body, residual generators (all sub-100K, MPSGraph-trainable)

| Body | Upscaler | Params | Notes |
|------|----------|--------|-------|
| **ESPCN** | weight-free pixel-shuffle (`depth_to_space`) | <100K (f16, 2 conv) | all compute at LR; shuffle is a pure reshape, trivially portable. Needs the floor as an additive skip (vanilla ESPCN zeros to black). ([arXiv:1609.05158](https://arxiv.org/pdf/1609.05158)) |
| **QuickSRNet** | folded identity-init conv stack | sub-50K (f16-m2) | **best-documented identity-at-floor recipe**; ReLU1 clamp aligns with gamut-closed laws; 1.14–2.2 ms/2× on a phone. ([arXiv:2303.04336](https://arxiv.org/abs/2303.04336)) |
| **FSRCNN** | learned transposed-conv | ~4K–16K | smallest credible learned SR; shrink/expand keeps it tiny; deconv risks checkerboard, heavier gradients than shuffle. ([arXiv:1608.00367](https://arxiv.org/pdf/1608.00367)) |
| **edge-SR (eSR)** | one-layer + pixel-shuffle | minimal | maximally interpretable; **identity-at-floor trivial** (seed the single filter at the replicate kernel); hard quality ceiling, best as floor-residual, not the whole engine. ([arXiv:2108.10335](https://arxiv.org/abs/2108.10335)) |
| **Coordinate-MLP (LIIF/SIREN)** | continuous coordinate query | small MLP | **one model for 4× SPACE *and* 4× TIME**; risk is INFERENCE cost (256²×256 queries/frame), not trainability. ([LIIF, arXiv:2012.09161](https://arxiv.org/abs/2012.09161); [INR for video+image SR, arXiv:2503.04665](https://arxiv.org/pdf/2503.04665)) |

A heavier residual-quantization route exists (**RQ-VAE** stacked additive codes,
[arXiv:2203.01941](https://arxiv.org/abs/2203.01941); **VAR** next-scale prediction maps cleanly onto
the {16,64,256} ladder but published artifacts are 300M–2B params, Mac/cloud-class,
[arXiv:2404.02905](https://arxiv.org/abs/2404.02905)). If any quantizer is used, **FSQ** (finite
scalar quantization) removes the single biggest on-device instability, codebook collapse, with no
codebook params and deterministic integer-friendly rounding that matches the byte-exact Zig ethos
([FSQ, arXiv:2309.15505](https://arxiv.org/abs/2309.15505)).

### (iii) Conditioning the residual on the genome

- **FiLM (γ,β) modulation**, cheapest known conditioning (2 params/feature-map); init the
  genome→(γ,β) projection so zero-genome ⇒ γ=1,β=0 = exact identity
  ([FiLM, arXiv:1709.07871](https://arxiv.org/abs/1709.07871)). Low-capacity, so it sits *on top of* a
  residual body rather than replacing it.
- **Zero-init gate** (above), genome multiplies the residual; zero genome ⇒ zero residual.
- **Hypernetwork** (genome generates adapter weights), amortizes personalization but is the
  least stable to train from cold-start; better as an optional Mac/MLX warm-start amortizer
  ([HyperTTS, arXiv:2404.04645](https://arxiv.org/pdf/2404.04645)).

### Map to repo assets

- **`NetSynth256.synthesize(floor:genome:)`**, the guard already returns floor byte-for-byte; slot a
  tiny body (ESPCN/QuickSRNet/eSR) as the gated residual above it.
- **`Spec.ExportFamily`**, `synthDetail`, `exportFamily`, `genomeToSynthSeed` are currently
  `error "TODO"`, so `lawZeroGenomeIsFloor` / `lawTier256FloorIsNearestNeighbour` are *vacuously*
  satisfied today. These are the laws the residual body must keep honoring.
- **`RGBT4DLift`**, the additive identity anchor (the floor the residual targets). Open question:
  whether the floor is nearest-neighbour replicate (`synthBeyond256`) or a bilinear/RGBT4D-derived
  upscale changes what high-frequency content the net must learn.
- Per-frame is preserved because every body quantizes/decodes per-frame OKLab palette latents. **Gap
  the literature does not address:** temporal consistency of learned 256-cube detail across the
  64-frame burst is unspecified by any cited source.

---

## 5. Fork C, Gumbel-AlphaZero value-guided proposer

**The contract:** a value-guided search that proposes and ranks ≥2 candidate looks per shutter,
learns from A/B picks, runs at a tiny on-device simulation budget, and reuses the half-ported
`GumbelSearch` machinery.

### The search core

- **Gumbel-top-k + Sequential Halving (canonical, already half-ported).** Replace AlphaZero's
  Dirichlet+PUCT with: sample k root actions without replacement via Gumbel-top-k on the policy
  logits, then distribute a fixed sim budget with Sequential Halving; the visit distribution + a
  completed-Q transform give a **provably policy-improving target even at ~2 simulations**
  ([Danihelka et al., ICLR 2022](https://davidstarsilver.wordpress.com/wp-content/uploads/2025/04/gumbel-alphazero.pdf);
  [ICLR spotlight](https://iclr.cc/virtual/2022/spotlight/6419)). Independently reproduced: LightZero
  reports Gumbel-MuZero "learns reliably even with n=2 simulations" while plain MuZero fails at ≤4
  ([LightZero, arXiv:2310.08348](https://arxiv.org/pdf/2310.08348);
  [MiniZero, arXiv:2310.11305](https://arxiv.org/pdf/2310.11305)).
- **Gumbel-SH as a generic candidate-ranker (ReSCALE).** Pulled out of board games to rank LLM
  reasoning branches; the ablation finds **Sequential Halving is the primary driver**, and it
  restores monotonic budget-scaling with no retraining
  ([ReSCALE, ICAPS 2026](https://arxiv.org/html/2603.21162)). This is the closest published evidence
  that Gumbel-SH works as a pure *propose-and-rank-options* procedure, justifying keeping SixFour's
  tree **shallow** (depth-1 over a sampled candidate set may be the whole search).

### Searching a CONTINUOUS 384-DOF genome space

- **Sampled-policy MuZero/AlphaZero.** You can't enumerate a continuous genome space, so sample k
  genomes from the policy and run improvement over only that subset, the principled bridge between
  fixed-arm Gumbel-SH and SixFour's 384-DOF sigma-pair action
  ([Hubert et al., ICML 2021](https://arxiv.org/abs/2104.06303)). Requires adding a *stochastic*
  head over the genome (current `ThetaToDelta` is a deterministic θ→384 map).
- **Progressive widening / kernel-regression candidate generation.** Limit children to k·Nᵅ and place
  new genomes where the value surface looks promising via kernel regression, reuses the existing
  `greedyGallery` RBF length-scale
  ([Bayesian-Optimized Progressive Widening, IFAC 2025](https://www.sciencedirect.com/science/article/pii/S2405896325020105)).
  Run it in the **low-D PersonalTaste θ space**, not raw 384-DOF, to dodge curse-of-dimensionality.

### Why a deep tree is probably unnecessary

SixFour's "environment step" is **one stochastic user pick = a chance/afterstate node**. A 1-ply
afterstate search with a Bradley-Terry value at the chance node subsumes most of MuZero's machinery
*without* a learned dynamics model (the genome→render state machine is already exact)
([Stochastic/afterstate framing via Gumbel-MuZero](https://davidstarsilver.wordpress.com/wp-content/uploads/2025/04/gumbel-alphazero.pdf)).
**Recommendation within the fork:** take the afterstate *framing* but NOT the learned dynamics net
(it would blow the ~100K budget and is the worst cold-start of all options).

### The value head and active A/B selection

- **Bradley-Terry value = the search reward** `P(i≻j)=σ(V_i−V_j)`, trained with `−log σ(V_w−V_l)` , 
  matches the pick signal exactly, convex, tiny, and **already proven on-device** by `AtlasTrainer`
  at ~12.4 ms/step ([BT reward models](https://www.emergentmind.com/topics/bradley-terry-reward-models)).
- **Active pair selection** (which 2 to show): optimal-design / info-gain picks the most informative
  duel ([Optimal Design for Human Preference Elicitation, NeurIPS 2024](https://arxiv.org/pdf/2404.13895)),
  or frame the loop as **neural contextual dueling bandits** with Thompson sampling for regret-bounded
  exploration ([Neural Dueling Bandits, ICLR 2025](https://arxiv.org/abs/2407.17112)). Tension: the
  *most informative* duel is not always the *most enjoyable* duel.

### Map to repo assets

- **`Spec.GumbelSearch`** already implements `sequentialHalving`, `visitPolicyTarget`,
  `policyWidthCap=8`, and the `q16Key` determinism boundary (CPU tree ↔ GPU value agree despite
  Metal `simd_sum` reassociation). Supersedes the PUCT path in `Spec.PaletteSearch`.
- **`GenomePair.sampleOrthogonalPair`**, the k-sample / ≥2-arm candidate generator (orthogonality is
  a built-in diversity guard against mode collapse).
- **`AtlasTrainer`**, the value oracle; **`ThetaToDelta`**, the policy mean (needs a sampling head
  added); **`PersonalGenome` federated prior**, the chance-outcome predictor and cold-start
  regularizer.
- **Cold-start:** `COLOR-ATLAS.md`'s flywheel gives a deterministic `referencePolicy` + `paletteReward`
  so Sequential Halving runs with **zero trained weights on day 1**, Gumbel-top-k degenerates toward
  the orthogonal-pair prior, which is still a valid ≥2-candidate gallery.

---

## 6. Feasibility & risks

These are the adversarial verdicts, reported honestly. Three of four claims are only *partially*
supported.

### 6.1 MPSGraph on-device training, value head YES, "AND a super-res head" WEAK

**Verdict: PARTIALLY-SUPPORTED.** MPSGraph genuinely trains (forward+backward) via
`gradients(of:with:name:)` + variable-assign optimizers
([Apple training guide](https://developer.apple.com/documentation/MetalPerformanceShadersGraph/training-a-neural-network-using-mps-graph);
[WWDC21](https://developer.apple.com/videos/play/wwdc2021/10152/)). The **~100K-param value head is
well-supported**: ResNet-34 (~21M params) trains at ~7.3 s/batch on iPhone 16
([arXiv:2512.22180](https://arxiv.org/html/2512.22180v1)); scaling ~200× down lands in low-tens-of-ms,
matching `AtlasTrainer`'s claimed ~12.4 ms/step.

**Blockers / weak link:**
- The **super-res head at interactive latency is UNPROVEN, not refuted.** No citation benchmarks
  training a small on-device SR head on iPhone; image-sized I/O makes it materially heavier than a
  scalar value MLP.
- **Thermal throttling is the hard ceiling for *sustained* training:** degradation by ~batch 13–17
  ([arXiv:2512.22180](https://arxiv.org/html/2512.22180v1)) and ~41.5% sustained-throughput drop at
  thermal equilibrium ([arXiv:2603.23640](https://arxiv.org/html/2603.23640)). "Interactive latency"
  is defensible **only for short amortized bursts** (a few steps per pick), not a continuous loop.
- **Static-graph rigidity** (no separable backward, no dynamic control flow) is an engineering tax
  that complicates variable-compute Gumbel training graphs, not a correctness blocker.

### 6.2 Identity-at-floor, SUPPORTED, by construction (with one hard condition)

**Verdict: SUPPORTED.** Bit-exact zero-genome==floor holds **because the floor is the integer index
domain** (`SixFourExport.replicate`, UInt8 index replication, zero float) and `NetSynth256` enforces
it with a **guard/short-circuit**, not by trusting float weights. The hard condition: identity must be
a **gate/mask**, not merely zero-init weights (ReZero gives exact identity only at alpha literally 0).
**The unproven half:** bit-exact *cross-device* reproducibility of the LEARNED DETAIL once genome≠0
requires fixed-point/integer decoding ([arXiv:2312.11209](https://arxiv.org/html/2312.11209v2)), i.e.
the detail must go through SixFour's Zig integer core, or determinism that holds at the floor will not
extend to trained outputs. No cited source validates a learned *index-cube* SR at 100K-param,
on-device, MPSGraph-trained scale end-to-end, it's a plausible synthesis, not a citable result.

### 6.3 Gumbel-AlphaZero at tiny sim budget, SUPPORTED, with caveats

**Verdict: SUPPORTED.** n=2 is the *designed* regime and independently reproduced. **Caveats:**
(a) the improvement guarantee is **conditional on value-estimate quality**, at n=0 picks the value
head is untrained, so early candidates are no better than the prior/floor (the cold-start risk);
(b) n=2 is demonstrated for *large* action spaces (362-action Go); with SixFour's m=2 candidates and
n=2, Sequential Halving degenerates to "visit both, pick the better", the *planning* contribution is
thin and most quality comes from the value/policy net; (c) no cited source validates the guarantee
under noisy *human* pairwise rewards specifically; (d) only the **model-free** Gumbel-AlphaZero / root-
bandit variant transfers (Gumbel-MuZero "has not been applied to stochastic environments").

### 6.4 Cold-start without a required base, PARTIALLY-SUPPORTED

**Verdict: PARTIALLY-SUPPORTED.** Bridgeable **only because of this architecture**: first-use quality
= the deterministic floor (a real look), and tiny nets do train on-device (MCUNetV3/TinyPropv2).
**Blockers:** (a) the whole support hinges on the floor look itself being *acceptable*, if disliked,
no learned model rescues first use; (b) AlphaZero/MuZero cold-start weakness is documented
([Warm-Start AlphaZero, PPSN 2020](https://arxiv.org/abs/2004.12357)), the proposer ranks candidates
poorly for the first several picks; (c) preference learning is sample-inefficient at low budgets,
needing ~9× less data with smarter selection ([arXiv:2511.12796](https://arxiv.org/abs/2511.12796)) , 
and that active-selection layer is **unbuilt** (Spec.PaletteSearch/GumbelSearch are spec-only);
(d) `personalBeta=n/(n+50)` is doing soft warm-start, so "fully cold seed, no base" is partly
semantic.

### 6.5 Cross-cutting risk: self-consuming collapse

Pick-driven retraining provably optimizes preference **only if a positive fraction of real data is
mixed in each round, else it collapses** ([Ferbach et al., NeurIPS 2024](https://arxiv.org/abs/2407.09499)).
Plus the standard RLHF failure modes, mode collapse, reward over-optimization, early-pick over-fit
([When RLHF Fails, arXiv:2606.03238](https://arxiv.org/html/2606.03238v1)). Mitigations are cheap and
on-device-friendly: KL-anchor the residual to the floor, enforce gallery diversity via the orthogonal
sigma-pair guarantee, cap per-pick updates via `personalBeta`. **Design rule: the deterministic floor
IS the mandatory real fraction.**

---

## 7. Recommended design path

> **RECOMMENDATION, NOT DECIDED. Queued for sign-off (see Section 8).**

A single end-to-end design that maximizes reuse of dormant assets, keeps the strongest-supported
options, and quarantines the weakest-supported one (the SR trainer) behind a safe floor.

### The recommended stack

- **Value head (Fork C core):** keep the **Bradley-Terry** link, upgrade `PersonalTaste theta` from a
  linear leaf to a **tiny MLP (~50–100K params)** trained by per-pick SGD on `AtlasTrainer`'s proven
  MPSGraph spine. This is the single strongest on-device evidence in the whole plan. Keep the
  CPU-linear θ leaf as the always-on fallback.
- **Search (Fork C):** **depth-1 Gumbel-top-k + Sequential Halving** over k genomes sampled from the
  policy, ranked by the value head. No real tree, no learned dynamics (afterstate framing only). Reuse
  `Spec.GumbelSearch` as-is. `GenomePair.sampleOrthogonalPair` seeds the ≥2 arms (built-in diversity).
- **Super-res (Fork B):** **VDSR-style global-residual-above-floor + ControlNet zero-init gate**,
  with a **QuickSRNet/ESPCN tiny body** (pixel-shuffle upscaler) as the residual, and **FiLM**
  conditioning from the genome (init γ=1,β=0). Floor = integer-index `synthBeyond256` replicate. The
  residual runs through the **Zig integer core** so cross-device determinism extends past the floor.
  Ship v1 with the residual **gated to zero**, the export is *exactly the deterministic floor* until
  enough picks accrue, which is the safe cold start the feasibility verdict relies on.
- **Cold-start (Fork A):** ship a **frozen meta-learned/federated prior blob** (Reptile-init over
  Zig-synthetic taste tasks) as an OPTIONAL warm-start, consumed via `personalBeta=n/(n+50)`. MLX
  required for nothing; on-device adaptation always works; floor guarantees a non-degenerate day-one
  render.
- **Safety rails:** KL-anchor the residual to the floor; mix the floor (real fraction) into every
  retraining round to prevent self-consuming collapse; enforce orthogonal-pair gallery diversity; cap
  per-pick updates via `personalBeta`. Train in **short amortized bursts per pick**, never a
  continuous loop (thermal).

### Rough phase order

1. **Phase 0, value head.** Upgrade `PersonalTaste`→tiny-MLP BT head on `AtlasTrainer`; wire it as
   the `GumbelSearch` value. Lowest risk, strongest evidence. Ships a working value-guided gallery
   with the residual still zeroed.
2. **Phase 1, proposer.** Add the stochastic head to `ThetaToDelta`; wire Gumbel-top-k sampling +
   Sequential Halving over `sampleOrthogonalPair`. Measure sim-budget vs A/B quality **on-device** (a
   measurement, not a paper number).
3. **Phase 2, SR residual.** Implement `Spec.ExportFamily.synthDetail` as VDSR+zero-gate+QuickSRNet
   body through the Zig integer core; keep `lawZeroGenomeIsFloor` green. Train the residual last, it
   is the weakest-supported, heaviest, and thermally riskiest component.
4. **Phase 3, cold-start prior + active selection.** Add the frozen Reptile/federated prior and an
   info-gain or dueling-bandit active-pair selector. Add self-consuming collapse guards.

---

## 8. DECISIONS FOR SIGN-OFF

These are the specific choices that must be made to finalize the design. They come back to the user.

1. **SR upscaler primitive.** Weight-free **pixel-shuffle** (ESPCN/eSR, easiest to port, easiest to
   keep floor-preserving) vs **learned transposed-conv** (FSRCNN) vs **coordinate-MLP** (LIIF/SIREN , 
   the *only* option giving one model for both 4× SPACE and 4× TIME, at higher inference cost). Which
   axis-handling does SixFour want?
2. **SR body + identity mechanism.** QuickSRNet identity-init vs ESPCN+skip vs eSR floor-residual , 
   and confirm identity-at-floor is enforced by the **zero-init gate/guard** (permanent algebraic
   invariant), with identity-init used only to speed convergence (if at all).
3. **Genome conditioning path.** FiLM (γ,β identity-at-zero) vs zero-init gate scalar vs hypernetwork
   adapters, or a composition (genome→FiLM→gated residual). Which stays in budget AND trains from
   cold-start?
4. **Value-head capacity & link.** Linear BT (max stability, replay-deterministic, fits `PersonalTaste
   theta`) vs **tiny non-linear BT MLP** (more expressive, but loses the clean 3KB-θ replay story and
   makes the KataGo-style gate mandatory). And: calibrated probabilities (BT/Thurstone, needed for
   info-gain/Thompson selection) vs order-consistent classifier/DPO (more robust to one noisy user)?
5. **Simulation budget.** What n actually beats deterministic argmax on the genome space, needs an
   **on-device A/B-vs-budget measurement**, not a paper number. And confirm depth-1 (Gumbel-top-k + SH
   over a sampled set) vs any real tree.
6. **Where preference learning binds.** Value-head **ranker only** (Fork C) vs **DPO-shaped proposer**
   (`ThetaToDelta`/`GenomePair` aligned directly) vs **both**. Decision C says value-*guided*, so do we
   want both?
7. **Cold-start policy (Fork A).** Reptile/MAML meta-learned **init** vs frozen federated-average
   **prior** vs **no prior** (pure from-scratch). Trades day-one quality vs build complexity. And:
   keep an optional federated prior at all, or ship a static blob / nothing?
8. **Param/compute budget split.** Does the ~100K budget cover the SR body **alone**, or is it shared
   with the value/policy head? This decides whether an f64-m11 QuickSRNet body or only a sub-20K
   FSRCNN/eSR body is affordable.
9. **Floor choice for the residual.** Nearest-neighbour replicate (`synthBeyond256`) vs
   bilinear/RGBT4D-derived upscale, changes what high-frequency content the net must learn.
10. **Quantizer (only if a residual-code stack is used).** Learned VQ codebook (higher fidelity,
    collapse-prone on-device) vs **FSQ** (no codebook, cold-start-safe, ~0.5–3% quality cost, matches
    the Zig byte-exact ethos).
11. **Active pair-selection vs UX.** Show the most-*informative* duel (info-gain/dueling-bandit) vs the
    two most-*enjoyable* candidates, and the policy for trading information gain against enjoyment
    once the genome is trusted.
12. **Self-consuming collapse guard.** Confirm the deterministic floor counts as the "positive
    fraction of real data" mixed into every retraining round, and at what cadence/mixing ratio (and
    whether retained real burst frames are added too).
13. **Training cadence.** Per-A/B-tap micro-update vs batched every-N-picks, bounded by thermal
    (interactive latency holds only for short bursts). The value head is affordable per-tap; the SR
    head's per-step cost is **unmeasured**.
