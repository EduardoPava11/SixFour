# SixFour NN Value-Head Research + Design (informs nn-6)

> STATUS: RESEARCH + RECOMMENDATION. **No decision in this document is final.**
> Every choice below is queued for the user's explicit sign-off (see §7). This
> report gathers web-cited options and *recommends* a design; it does not adopt one.
>
> Companion to: `docs/SIXFOUR-NN-STACK-RESEARCH.md` (§1.5 locked design),
> `docs/SIXFOUR-NN-WORK-PLAN.md`. Subject: the **nn-6** training law for the
> Bradley-Terry (BT) MLP value head.

---

## 1. Purpose

The forward value head already exists: `AtlasNetEval.atlasValue`, a small MLP of
shape **24 -> 32 -> 1** (tanh hidden layer) that emits a scalar taste score per
candidate look. What does **not** yet exist is a *proven on-device training law*
for it. nn-6 must supply that law and prove it the same way the **linear**
`SixFour.Spec.PreferenceUpdate` is proven:

1. a preference **loss** (Bradley-Terry over an ordered A/B pick);
2. an **analytic gradient**, pinned by **central finite differences**
   (the existing `lawGradientFiniteDiff`, h=1e-5, tol ~1e-6);
3. an **SGD step** that provably decreases the loss (restated for the nonlinear
   case as a small-eta / first-order law) and stays **bounded**.

nn-6 is the MLP counterpart of the already-proven LINEAR step. The decision
boundary stays deterministic across CPU/GPU via the existing **q16Key**
quantization of the value.

This report answers four design questions, each grounded in the attached
research and stress-tested by the attached adversarial critic:

- §2 What honestly transfers from DeepSeek to a *tiny* head (and what is scale-only)?
- §3 Which training **objective** (plain BT vs DPO vs GRPO-style group-relative)?
- §4 Which **head architecture** (linear vs the 24->32->1 MLP; activation; regularization)?
- §5 What keeps the result **verifiable + deterministic** (finite-diff-checkable, bit-exact ranking)?
- §6 The recommended nn-6 design (NOT decided).
- §7 The explicit DECISIONS FOR SIGN-OFF.

## 2. What transfers from DeepSeek (and what does not)

**Lead with the honest separation.** The four headline DeepSeek-V3 techniques are
**scale-only** and do not help a ~1K-100K-param dense, non-attention, non-MoE BT
value head. The adversarial critic returned a flat **DOES-NOT-TRANSFER** on the
whole architecture claim, and the reasoning is structural, not merely "low value":

| DeepSeek-V3 technique | Why it exists | Transfer to the tiny BT head |
|---|---|---|
| **MLA** (Multi-head Latent Attention) | Compress the **KV cache** during long-context **autoregressive decoding** (V3 uses KV-compression dim d_c=512) | **Inapplicable.** No attention, no KV cache, no sequence. The head is a one-shot scalar scorer over a fixed feature vector. The cost MLA attacks does not exist. |
| **DeepSeekMoE** | Grow total capacity while keeping active compute small via expert routing | **Contraindicated at this scale.** A dense head smaller than a single DeepSeek expert has no capacity problem to solve; the router adds latency and routing-collapse risk for nothing. |
| **Auxiliary-loss-free load balancing** | A learnable per-expert routing **bias** (sign-nudged by gamma=0.001) keeps MoE experts evenly loaded without an interference-laden auxiliary loss | **No experts to balance** -> literal mechanism is moot. |
| **FP8 mixed-precision** | Halve compute/memory of a 671B-param training run via per-tile/block FP8 GEMMs | **Scale-only AND anti-goal.** A 10^4-param head trains in <1s; FP8's hardware-dependent rounding *breaks* SixFour's bit-exact q16 decision boundary. The cross-device determinism requirement excludes FP8 independent of the scale argument. |

Sources: DeepSeek-V3 Technical Report (arXiv:2412.19437,
<https://arxiv.org/abs/2412.19437>); MLA explainer (DeepWiki,
<https://deepwiki.com/deepseek-ai/DeepSeek-V3/3.2-multi-head-latent-attention-(mla)>);
Auxiliary-Loss-Free Load Balancing (arXiv:2408.15664,
<https://arxiv.org/abs/2408.15664>); Multi-Token Prediction (DeepWiki,
<https://deepwiki.com/deepseek-ai/DeepSeek-V3/3.4-multi-token-prediction-(mtp)>);
FP8 stability (arXiv:2405.18710, <https://arxiv.org/abs/2405.18710>).

### What survives as a *pattern* (kept on the table, not adopted)

Two DeepSeek ideas are honestly portable **in spirit only** and are flagged for
later evaluation, NOT default adoption:

- **Bias-controller-outside-the-loss** (from aux-loss-free balancing): a
  sign-based, bounded, **non-gradient** controller updated outside the loss is a
  clean, provable primitive that resonates with nn-6's "prove the step" goal. It
  would matter only if SixFour ever ensembles taste sub-heads. (arXiv:2408.15664.)
- **Shared-trunk auxiliary head as a regularizer** (the generic pattern behind
  Multi-Token Prediction): attach a cheap head off the shared 24-dim features
  (e.g. predict the orthogonal A/B margin, or reconstruct the feature vector),
  train it jointly, **discard it at inference**. The multi-task literature shows
  this can help exactly SixFour's regime (tiny model, few + noisy labels) -- with
  the real caveats that mis-weighted auxiliaries can *hurt* and that extra loss
  terms complicate the finite-difference gradient proof. (MTP DeepWiki;
  Auxiliary Tasks in Multi-task Learning, arXiv:1805.06334,
  <https://arxiv.org/abs/1805.06334>.)

**Net for §2:** do NOT import MLA, MoE, FP8, or MTP-as-token-prediction. The
genuinely transferable DeepSeek *research-line* ideas (GRPO-style group-relative
objective; explicit scalar reward head; the R1 "distillation beats RL on small
models" lesson) are **objective-level**, covered in §3 -- not the architecture
techniques refuted here. The critic's caveat is explicit: there is no
peer-reviewed <1M-param ablation of these four techniques; the refutation rests
on first-principles structural argument plus the primary sources' own stated
rationale.

## 3. The training objective

The objective fork is: **plain pairwise Bradley-Terry** vs **DPO** vs a
**GRPO-style group-relative** update over the shown candidate set.

### 3a. Plain pairwise Bradley-Terry (the as-built linear law, lifted to the MLP)

The BT loss for an ordered pick (winner `w`, loser `l`) is

```
L = -log sigma(r_w - r_l)   =   softplus(r_l - r_w)
```

with `r = atlasValue(x)` now an MLP instead of `theta . x`. This is the standard
reward-modeling recipe (RLHFlow, Skywork-Reward, InternLM2-Reward all do exactly
this). Two structural facts the spec must encode:

- **Only differences matter** -- absolute scale is unidentified, so the head needs
  an explicit anchor (L2) and the decision is made on the *difference*, which
  SixFour already does at the q16Key. (Nathan Lambert, RLHF book Ch.5,
  <https://rlhfbook.com/c/05-reward-models>.)
- It is a **shared-weight, two-forward / one-backward** (Siamese) step; the
  gradient flows through the *difference* of the two candidates' forward passes.

The loss is C-infinity in the network outputs, so the linear `PreferenceUpdate`
gradient lifts through the MLP Jacobian cleanly for the finite-difference law.
**Caveat the spec must honor:** the linear "step-decreases-loss" law does NOT
survive verbatim. The linear proof used the closed-form gap increase
`eta * g * ||d||^2`, which only holds locally for a nonlinear `r()`. State nn-6's
decrease law as a **small-eta / first-order Taylor** statement; keep the
finite-difference gradient law as the unconditional one. (Neural BT precedent:
arXiv:2307.13709, <https://arxiv.org/pdf/2307.13709>.)

### 3b. DPO -- the wrong direction for SixFour

DPO (Rafailov et al. 2023, <https://arxiv.org/abs/2305.18290>) reparameterizes the
reward as a log-ratio between a target **policy** and a frozen **reference**
policy, so you can skip an explicit reward model. **Structurally inapplicable
here:** SixFour's proposer generates candidates by deterministic/search operators,
not a sampling policy with tractable log-probs, so there is no implicit reward to
ride on, and there is no reference policy for a freshly-initialized per-user head
to anchor to. At a standalone scorer, DPO just collapses back to BT (which
`PreferenceUpdate` already is). Worse, **Apple's own research** shows the DPO
*implicit* reward generalizes **worse OOD** than an explicit BT reward model
(mean accuracy drop ~3%, max ~7% across five out-of-domain settings) and
recommends integrating an explicit reward model -- and SixFour's regime is OOD by
construction (the proposer keeps emitting new orthogonal looks).
(<https://machinelearning.apple.com/research/reward-generalization>.) **Keep the
explicit value head.**

### 3c. GRPO-style group-relative -- only relevant for n>2, and even then prefer Plackett-Luce

GRPO (DeepSeekMath, arXiv:2402.03300, <https://arxiv.org/abs/2402.03300>) drops
PPO's critic and computes each candidate's advantage by normalizing rewards
within a sampled **group** (`A_i = (r_i - mean)/(std+eps)`). Three findings
collapse the "GRPO is a better fit" claim (critic verdict: **DOES-NOT-TRANSFER**):

1. **Category mismatch.** GRPO trains a generative *policy* by reweighting
   log-probs of sampled actions. The value head has no sampling distribution; in
   the RLHF stack the BT reward model is the thing GRPO *consumes*, not the thing
   it trains. "Train the value head with GRPO" is a type error unless reframed.
2. **At G=2 (the A/B pick), GRPO provably IS Bradley-Terry / DPO.** "It Takes Two:
   Your GRPO Is Secretly DPO" (arXiv:2510.00977,
   <https://arxiv.org/abs/2510.00977>) shows the group-normalized advantage at
   group size 2 collapses to a binary contrastive winner-vs-loser signal -- the
   same contrast SixFour already proves. For a strict A/B pick a "GRPO update" and
   the existing BT step are the **same object**.
3. **Std-normalization is a liability at tiny groups.** Dr. GRPO removes the std
   denominator (`A = r - mean(r)`) because dividing by a noisy per-group std
   over-weights low-variance groups; at G=2 the std estimate is degenerate (df=1).
   It is also a **determinism hazard** (a noisy per-group statistic in the
   update). (Dr. GRPO writeup,
   <https://medium.com/@jenwei0312/the-evolution-of-policy-optimization-understanding-grpo-dapo-and-dr-3e758c54b2c6>.)

**Where group-relative thinking IS legitimate:** if SixFour ever shows **n>2**
candidates and the user picks one, the principled, group-relative-by-construction
upgrade is the **listwise softmax / Plackett-Luce** generalization of BT:

```
L = -log( exp(r_winner) / sum_j exp(r_j) )
```

This normalizes across all candidates with one shared partition function, giving a
lower-variance, mutually-calibrated update from a single pick -- and it needs
**no** RL/sampling machinery and carries **none** of the std-normalization
pathology. (LiPO, arXiv:2402.01878, <https://arxiv.org/abs/2402.01878>; DPO paper
§B uses the same PL extension for K>2; Plackett-Luce is the decades-old listwise
generalization of BT.) DeepSeek-GRM's **pointwise-score-then-contrast** skeleton
(arXiv:2504.02495, <https://arxiv.org/abs/2504.02495>) further validates scoring
each candidate independently (matches `atlasValue`), which makes the n-way
extension free.

### 3d. The R1 lesson that actually matters for a tiny head

DeepSeek-R1 (arXiv:2501.12948, <https://arxiv.org/abs/2501.12948>; Nature 645:633,
<https://www.nature.com/articles/s41586-025-09422-z>) reports that
**distillation beats large-scale RL on small models**. Translated: do NOT train
the tiny head tabula-rasa as a full RL learner. Seed / regularize it from a
distilled **population prior** (`theta_0`) and let the per-pick step do only
bounded local adaptation -- which is exactly SixFour's as-built "one SGD step, L2
to prior." R1 also **abandoned learned process-reward models** for reward-hacking
reasons: keep the **human pick as the only un-gameable reward** and never
bootstrap the head off its own predictions.

### 3e. Objective recommendation

**Recommend plain pairwise BT as the canonical nn-6 step at the A/B shape**,
with the **listwise softmax (Plackett-Luce)** form named as the n>2 generalization
that *subsumes* BT at N=2 (so one law can cover both if the loop ever surfaces
>2). **Reject DPO** (no policy/reference; worse OOD) and **reject GRPO machinery**
(type-mismatch; at G=2 it is just BT; std-norm is a determinism hazard). The
contrastive-loss insight from the GRPO line is a *confirmation* of the existing BT
design, not a replacement.

## 4. The head architecture

### 4a. Linear vs the 24->32->1 MLP -- a real but small, conditional gain

The critic returned **CONDITIONAL** on "the MLP is justified over linear," and the
skeptical default holds at the stated data scale (a few dozen noisy picks). The
fork turns on **one** question: *does the taste signal contain genuine feature
INTERACTIONS that a linear-in-features BT cannot represent?*

**Why linear is the default winner at low N+noise:**

- **Bias-variance.** With a few dozen labels, variance dominates the error
  budget; lower-complexity models match or beat higher-capacity ones when samples
  are scarce (Brigato & Iocchi, "A Close Look at Deep Learning with Small Data,"
  arXiv:2003.12843, <https://arxiv.org/abs/2003.12843>).
- **Noise favors simpler models provably.** Semenova/Chen et al., "A Path to
  Simpler Models Starts With Noise" (NeurIPS 2023,
  <https://proceedings.neurips.cc/paper_files/paper/2023/file/0a49935d2b3d3342ca08d6db0adcfa34-Paper-Conference.pdf>):
  lower-capacity models are favored as label noise rises. A ~800-900-param MLP on
  tens of labels is squarely in memorization-risk territory (params >> labels by
  ~10-30x).
- **Practitioner precedent is a linear head.** In RLHF the reward head on top of a
  feature extractor is typically a single linear layer (rlhfbook.com/c/05);
  linear probes beat MLP probes when the representation is already good.

**Why the MLP can earn its capacity (the steelman):**

- **Real non-linearity in aesthetic preference.** Linear-in-features BT cannot
  model interactions or non-monotonic taste. Knox et al., "Models of human
  preference for learning reward functions" (arXiv:2206.02231,
  <https://arxiv.org/pdf/2206.02231>) give the canonical XOR counterexample (likes
  A and B alone, dislikes A-AND-B). Color/aesthetic taste is non-additive: harmony
  depends on color *combinations* (arXiv:2508.15777, arXiv:2308.15397). SixFour's
  orthogonal A/B candidates are color-genome combinations, so interaction
  structure is plausibly present.
- **BaseReward** (arXiv:2509.16127, <https://arxiv.org/abs/2509.16127>) ablated
  the reward head directly: **2 layers is the sweet spot, single linear layer was
  the WORST**, and depth beyond 2 brings no significant gain. The deployed
  24->32->1 IS that 2-layer shape.

**Middle option (the false binary).** If the goal is just to capture pairwise
interactions cheaply, a **Factorization Machine / low-rank bilinear utility** adds
2nd-order interactions without a full MLP's variance (Rendle FM; RaFM
arXiv:1905.07570). This sits between linear BT and the MLP and belongs on the fork.

**Verdict:** MLP justified **only if** (i) the taste signal demonstrably contains
interactions a linear-in-770D head cannot fit (test: does linear BT plateau in
offline replay accuracy on held-out picks?), **and** (ii) it is heavily
regularized. Absent evidence of (i), linear wins on bias-variance **and** on the
determinism budget (§5). **The honest empirical fact:** whether the MLP beats
linear at a single user's label volume is unsettled and must be measured on
SixFour's own replay data, not assumed -- the embedding may already encode the
harmony/combination structure, collapsing the case for the MLP.

### 4b. Activation -- smooth (tanh/SiLU), NOT a foregone SiLU, and NOT ReLU

- The deployed `atlasValue` already uses **tanh**, which is the correct choice for
  the proof technique (see §5): C-infinity, so the analytic gradient matches
  central finite differences tightly.
- **Do not blindly import the LLM-scale SiLU/SwiGLU default.** At width 32, an
  empirical activation study reports **tanh often outperforms ReLU/sigmoid for
  small MLPs**, that ReLU needs higher L2 while smooth activations need minimal
  weight decay, and that activation interacts with the regularizer (grokking
  study arXiv:2603.25009, <https://arxiv.org/pdf/2603.25009>;
  <https://mbrenndoerfer.com/writing/ffn-activation-functions>). tanh's bounded
  output also keeps the BT score scale in check and shrinks the float dynamic
  range feeding q16 (§5).
- **Do NOT switch to ReLU/LeakyReLU/maxout for this head.** The kink at 0 forces
  the finite-difference law's tolerance from ~1e-7 to ~1e-4 and makes the gradient
  pin honest only away from the kink (CS231n gradient-check note,
  <https://cs231n.github.io/neural-networks-3/>).

**Recommendation:** keep the proof **activation-agnostic**, pin **tanh** as the
default (already deployed), name **SiLU** as the one alternative to sweep.

### 4c. Normalization -- avoid it

BatchNorm/LayerNorm are determinism hazards (batch-dependent / variance
reductions are exactly the non-associative float ops that diverge CPU vs GPU,
arXiv:2408.05148) and earn nothing at 1-hidden-layer scale. **Keep the head
normalization-free** (plain Linear -> tanh -> Linear). If any stabilization is
needed, prefer a **fixed input standardization** baked into the weights offline,
not a runtime normalization layer.

### 4d. Init + regularization for few + noisy picks

- **L2 weight decay** is the right primary regularizer (already in the linear
  law). With Adam, apply it as **decoupled weight decay (AdamW)** so the adaptive
  LR does not de-regularize large-second-moment params (AdamW,
  <https://optimization.cbe.cornell.edu/index.php?title=AdamW>). MPSGraph's Adam op
  takes a `gradient` input, so weight decay must be an explicit post-update
  scaling.
- **Prior/parameter anchor (L2-toward-`theta_0`).** One mechanism serves **three**
  needs: cold-start (anchor to a distilled population default), anti-forgetting
  (anchor to last-good weights), and regularization. Highest-leverage single
  addition for this regime; trivial to spec and prove.
- **Label smoothing / cDPO-style epsilon target** for noisy picks: set the BT
  target to `1-eps` (eps ~0.05-0.1) so a single mis-click cannot slam the head; it
  stays C-infinity, so the finite-difference law is intact (Provably Robust DPO,
  arXiv:2403.00409, <https://arxiv.org/html/2403.00409v2>; TRL cDPO docs).
- **IPO-style bounded (MSE-margin) loss** named as a fork: plain BT drives the
  score gap to +/-infinity on near-deterministic picks, defeating regularization
  (Azar et al. IPO, arXiv:2310.12036, <https://arxiv.org/abs/2310.12036>). At
  minimum add a target margin `m`: `sigma(r_w - r_l - m)`.
- **Bounded-step / early-stopping-equivalent.** No held-out split exists from a
  few noisy picks, so substitute **step-count / step-size bounds** (the existing
  "bounded" + "step-decreases-loss" laws are already the right rail).
- **Frozen feature backbone** is the single most important anti-overfit lever, and
  SixFour already does it (the head sits on a fixed 24-d feature map).
- **Small experience-replay buffer** for the online loop: pure per-pick SGD
  *will* drift; a tiny ring buffer of recent/diverse past pairs is essentially
  free at this scale (Online Continual Learning, arXiv:2501.04897,
  <https://arxiv.org/pdf/2501.04897>).

## 5. Verifiability + determinism

This is the section where SixFour's hard constraints, not the general ML
literature, decide the design.

### 5a. Smooth activation so the analytic gradient is finite-diff-checkable

The `PreferenceUpdate` proof method is `lawGradientFiniteDiff`: analytic gradient
vs central difference (h=1e-5, tol ~1e-6). CS231n's canonical gradient-check note
says smooth objectives (tanh/softmax) hit relative error <=1e-7 ("you should be
happy"), while kinked objectives (ReLU/maxout/hinge) only reach ~1e-4 because at
the kink the analytic gradient is a *subgradient* (any value in [0,1] for ReLU at
0) while the finite difference picks one side, so the two disagree and the law
fails *spuriously* (<https://cs231n.github.io/neural-networks-3/>). **tanh
(already deployed) is the right choice;** softplus/GELU/SiLU also qualify (all
C-infinity with bounded, Lipschitz first derivatives). The proof obligation is
identical at 1K and 100B params -- this is tiny-head-relevant, not scale-only.

### 5b. The float non-associativity problem, and why q16 at the boundary is correct

IEEE-754 arithmetic is non-associative, and GPU kernels legitimately reorder/fuse
reductions, use dynamic tiling, and schedule threads non-deterministically, so the
same network on CPU vs GPU yields slightly different float outputs
(arXiv:2408.05148, <https://arxiv.org/abs/2408.05148>). On **Apple Silicon
specifically**, MLX/Metal is documented as non-reproducible even at temperature 0
because "Metal kernels optimize through dynamic tiling, adaptive reduction orders,
and variable parallelization" (Karnam,
<https://adityakarnam.com/mlx-non-determinism-apple-silicon/>). This bites
**harder** on a tiny head: a 32-wide tanh layer has so few summation terms that a
single reordered add can dominate a near-tie and flip `sign(V_w - V_l)`.

SixFour's existing choice -- **quantize the value to an integer q16Key and compare
integers** -- is exactly the path the same sources endorse ("quantization provides
a practical path to determinism"). The minimal, correct contract (Jacob et al.
integer-arithmetic-only inference, arXiv:1712.05877,
<https://arxiv.org/abs/1712.05877>): compute V in float, then quantize at the
boundary so **ranking/comparison is on integers and CPU==GPU by construction**.

**The determinism law must be stated CONDITIONALLY.** Quantization only removes
ambiguity *outside* the rounding band: two candidates whose true values fall
within one q16 ULP can still flip. So nn-6's law is:

> q16Key agrees on the winner **whenever** `|V_w - V_l|` exceeds the quantization
> granularity (one q16 ULP).

Not unconditionally. Quantize the **difference** of the two candidates (what BT
decides on), which cancels common-mode error; a bounded activation (tanh) shrinks
the dynamic range feeding q16, reducing boundary-flip risk.

### 5c. What keeps the ranking bit-exact across CPU/GPU

- **Normalization-free head** (§4c) -- the only reductions are the two small dot
  products, which can be pinned to a fixed summation order (strict left fold, as
  `PreferenceUpdate` already uses) in the Metal/Swift port.
- **fp32 ORDINAL-only contract:** the cross-device invariant is the **argmax and
  `sign(V_w - V_l)`**, not the float value. The spec already declares this.
- **Prefer the hand-derived-gradient-pinned-by-finite-differences proof** over
  trusting MPSGraph autodiff for the determinism guarantee. MPSGraph fuses/reorders
  float reductions; its autodiff is not a determinism oracle. (MPSGraph *does*
  support the loop: `gradients(of:with:)` + fused `adam(...)` ops exist, so
  training the deployed head on-device is feasible with zero third-party deps --
  it is the *guarantee*, not the feasibility, that must live at the q16 boundary.)
- **Open, needs device confirmation:** no MPSGraph-specific bit-exact guarantee
  was found in web search. The LINEAR BT head already reproduced the Mac-MLX loss
  trajectory bit-for-bit on the iPhone 17 Pro (CLAUDE.md, 12.4 ms/step), but the
  nonlinear tanh path adds a **transcendental** whose Metal-vs-Accelerate
  implementation may differ in low bits -- this needs the same on-device
  verification before the determinism law is signed off.

### 5d. Quantization as a bonus regularizer (named, not adopted)

Fixed-point can both improve robustness to noisy labels and deliver determinism
(arXiv:2303.11803, <https://arxiv.org/pdf/2303.11803>). But **full integer-only
TRAINING** is a riskier branch: straight-through estimators are non-smooth and
break the tight finite-difference pin, and MPSGraph is float-native. The
defensible stance: **train in float with the smooth BT law, quantize ONLY the
final value to q16 for the deterministic comparison.**

## 6. Recommendation (NOT decided)

Pending sign-off (§7), the recommended nn-6 design is:

- **Objective:** plain pairwise **Bradley-Terry** `-log sigma(r_w - r_l)` as the
  canonical step, with **label smoothing** (eps target) and an optional **target
  margin `m`** to stop infinite-confidence blow-up. Name the **listwise softmax /
  Plackett-Luce** form as the n>2 generalization that subsumes BT at N=2, to be
  proven only if the loop surfaces >2 candidates. Reject DPO and GRPO machinery.
- **Architecture:** keep the deployed **24 -> tanh(32) -> 1** MLP, but treat the
  linear-vs-MLP choice as **empirically gated** -- ship the proof at the deployed
  shape, and only keep the MLP if offline replay shows linear BT plateauing
  (interaction structure present). **Normalization-free.**
- **Activation:** **tanh** (deployed, smooth -> finite-diff-provable,
  bounded -> determinism-friendly); SiLU named as the one sweep alternative.
- **Regularization:** **L2 decoupled weight decay (AdamW)** + **L2-toward-`theta_0`
  prior anchor** (one mechanism for cold-start + anti-forgetting + regularization)
  + **label smoothing** + **bounded step count/size** + **frozen backbone** +
  **small experience-replay buffer**.
- **Determinism:** float forward, **quantize the candidate DIFFERENCE to q16** at
  the decision boundary; pin the two dot-product summation orders; state the
  determinism law **conditionally** (holds when `|V_w - V_l|` > one q16 ULP).

### 6a. The coupling fork (recommended: self-contained-at-shape)

Three ways to couple the proof to the deployed forward:

1. **self-contained-at-shape** *(recommended)* -- prove the law over a
   self-contained 24->32->1 MLP whose shape **matches** the deployed `atlasValue`,
   with golden vectors pinning the forward. Cleanest finite-difference check (over
   24 inputs / the head's ~1.6K weights), least coupling to upstream.
2. **train-atlasValue** -- thread the proof through the backbone's sigma-masked
   forward (via `invProj`) so the law is deployment-faithful end-to-end. Most
   faithful, but the finite-difference check now ranges over upstream weights and
   the proof couples to the masked backbone.
3. **generic** -- prove a generic tiny MLP, accept drift risk vs the shipped shape.
   Rejected: the R1/BaseReward findings argue the law should be a bounded update on
   a *specific* distilled prior, not an abstract learner.

**Recommend (1):** it keeps the law tight and finite-diff-clean while pinning the
exact deployed shape via golden vectors, with (2) as a follow-on if
deployment-faithfulness gaps appear.

### 6b. Rough spec-first plan

- New `SixFour.Spec.ValuePreferenceUpdate` (MLP counterpart of
  `Spec.PreferenceUpdate`), wired into `spec.cabal` + one `Spec.Map` line.
- **`lawGradientFiniteDiff`** for the MLP BT loss: analytic gradient vs central
  difference (h=1e-5, tol ~1e-6) over the 24->32->1 weights -- the unconditional
  law (tanh makes it tight).
- **`lawStepDecreasesLoss`** restated as a **small-eta / first-order Taylor**
  statement (the linear closed-form does not survive nonlinearity).
- **`lawBoundedStep`** lifted from the linear case (the early-stopping rail).
- **`lawQ16RankingAgrees`** conditional determinism law: q16 of the difference
  agrees with the float sign whenever the gap exceeds one ULP.
- Golden vectors pinning the forward + one BT step, gating the Swift/MPSGraph and
  Metal ports bit-for-bit (the `cabal test` gate).
- Codegen the contract to `Generated/` for the on-device trainer.

## 7. DECISIONS FOR SIGN-OFF

The user requires alignment on web-research-driven choices. The following are the
specific decisions queued; **none is adopted until confirmed.**

1. **Objective.** Confirm **plain pairwise Bradley-Terry** as the canonical nn-6
   step (recommended), vs DPO (recommended *reject*) vs GRPO-style group-relative
   (recommended *reject* the machinery; at G=2 it is just BT). Sub-decision: is
   **label smoothing** and/or an **IPO-style bounded / target-margin** loss part of
   the canonical step, or named-only?

2. **Linear vs MLP, and the MLP shape/activation.** Confirm whether to prove the
   **24->32->1 MLP** (deployed) or fall back to the **linear** head pending offline
   replay evidence of interaction structure -- and whether a **low-rank
   Factorization-Machine** middle option is in scope. Confirm activation: **tanh**
   default (recommended) with **SiLU** as the sweep alternative; confirm the head
   stays **normalization-free**.

3. **Regularization.** Confirm the set: **AdamW decoupled weight decay** +
   **L2-toward-`theta_0` prior anchor** + **label smoothing** + **bounded
   step-count/size** + **frozen backbone** + **experience-replay buffer**. Confirm
   whether a **distilled population prior `theta_0`** will be shipped (the anchor's
   target) or every user starts from scratch.

4. **The coupling fork.** Confirm **self-contained-at-shape** (recommended) vs
   **train-the-exact-`atlasValue`-through-the-masked-backbone** vs **generic** --
   i.e. whether the finite-difference check ranges over the head's 24 inputs only,
   or threads through the backbone's `invProj`.

5. **Does the group-relative idea change the Proposal's visit-target?** If SixFour
   commits to **n>2** candidate groups, the objective should become **listwise
   Plackett-Luce** (subsumes BT at N=2), and the Proposal/proposer's candidate-set
   construction (and any visit-target) must reflect that the *whole shown set* is
   the training signal, not one pair. Confirm: **strictly A/B**, or **n-way
   tournaments**? This single fork decides whether the listwise law is built at all.

### Open items needing measurement before/at sign-off

- The **q16 granularity vs typical `|V_w - V_l|` gaps** on real candidate values
  (the determinism law only holds outside one ULP; the head's output scale / init
  should place real gaps above the quantization band).
- **On-device bit-exactness of the tanh (transcendental) path** -- the linear head
  reproduced Mac-MLX bit-for-bit on the iPhone 17 Pro; the nonlinear path needs the
  same verification.
- **Empirical:** how many picks before the MLP's taste signal beats the linear
  baseline on held-out replay -- i.e. is the MLP capacity premature at one user's
  label volume?

