# GRAM → SixFour look-net: a research-to-program mapping

> **Design note, 2026-05-27. No spec or code change.** This is a literature survey of
> GRAM (Generative Recursive Reasoning Models) and a mapping onto the look-net contract
> of `LOOK_NN.md`. It commits nothing: the Haskell `Spec.*` modules and the studio build
> are untouched. Its purpose is to record *how the math dictates the program* so a future
> stochastic-core pivot can execute against a fixed reference, in the project's
> research-driven order (survey → map → let the math choose; never a design menu).
>
> Read `LOOK_NN.md` first — this note resumes its vocabulary (Def 21–38, Laws L1–L10).

---

## 0. Why this note exists

The look-net core is specified **deterministically**. `L4 Core R` (`LOOK_NN.md` Def 34)
is PonderNet (Banino et al. 2021) over a Mixture-of-Recursions shared block (Bae et al.
2025); its shape contract `coreIO : dM → dM` lives at
`spec/src/SixFour/Spec/LookNet.hs:119`. Given the same input and initialisation it
follows **one** latent trajectory and emits **one** palette.

But the SixFour product is *per-user personalized looks* — a **distribution** over
palettes, not a single canonical collapse — and the collapse target itself
(in-gamut **L3**, σ-balanced **L6**, globally surjective **L7**, diverse Def 32,
beautiful Def 31) is a **multi-solution constraint-satisfaction** problem: many distinct
palettes satisfy the contract, and the right one depends on the user.

That is precisely GRAM's regime. GRAM keeps the recursive core and its adaptive-compute
halting but turns the single deterministic trajectory into a **stochastic latent
generative process**, trained by amortized variational inference, with inference-time
scaling by sampling *many* trajectories and selecting among them. It is, almost
line-for-line, the stochastic generalization of Def 34 — and its selection stage is the
object SixFour already specified as the gallery (`Spec.Preference`).

Crucially, this lands inside the project's standing principle that look-net output
variance is **engineered and allowed**, with the burden on hardening the *quality
envelope that holds for all variance* (`feedback_variance_engineered_quality_hardened`).
GRAM's stochasticity is bounded and learnable; the decoder already clamps every output
(Def 35). So the engineered variance lives **inside** the proven envelope.

---

## 1. GRAM in one page

> Baek, J., Jo, M., Kim, M., Ren, M., Bengio, Y. & Ahn, S. (2026). *Generative
> Recursive Reasoning Models.* arXiv:2605.19376. ICLR 2026 Workshop on AI with
> Recursive Self-Improvement. (Code "coming soon" — **not released** as of this note.)

**Latent structure.** GRAM models `p_θ(y | x)` by marginalising over stochastic latent
reasoning trajectories `τ = (z₀ → … → z_T)`. The state is hierarchical, `z = (h, l)`:
`h` carries abstract reasoning state, `l` does fine-grained computation.

**One transition (the only stochastic part).** Within a step: (i) `l` is refined by `K`
deterministic inner updates `f_L` holding `h` fixed; (ii) a deterministic proposal
`u_t = f_H(h_{t−1}, l_t)` is formed; (iii) **learnable stochastic guidance** is sampled,
`ε_t ~ p_θ(ε_t | u_t) := N(μ_θ(u_t), σ²_θ(u_t) I)`; (iv) `h_t = u_t + ε_t`. The mean
`μ_θ` steers direction; the variance `σ²_θ` sets exploration magnitude.

**Training (amortized variational inference).**
```
log p_θ(y|x) ≥ E_{q_φ(τ|x,y)} [ log p_θ(y | τ, x) ] − KL( q_φ(τ|x,y) ‖ p_θ(τ|x) )
```
with Markov prior `p_θ(τ|x) = p(z₀) ∏_t p_θ(z_t | z_{t−1}, x)` and posterior
`q_φ(τ|x,y) = p(z₀) ∏_t q_φ(z_t | z_{t−1}, x, y)` — the posterior **sees the target `y`**
during training. For memory, GRAM uses **truncated gradient propagation** (backprop only
through the final transition of each supervision step — the same 1-step trick as
TRM/HRM), a biased but cheap ELBO surrogate `L_GRAM^(n)`.

**Inference-time scaling, two axes.**
- *Depth*: an ACT halt head `q_ψ : ℝ^D → ℝ²` decides continue/halt per step → variable
  recursion depth.
- *Width* (the headline): sample `N` independent trajectories `{τ^(i)}` in parallel;
  decode each terminal `z_T^(i)` to a candidate `ŷ^(i)`; **select** by majority vote or
  a learned **Latent Process Reward Model** `v_ψ(z_t)` predicting trajectory correctness.

**Capabilities & results.** Supports conditional reasoning `p(y|x)` and unconditional
generation `p(x)`. At ~10.9M params it beats HRM (27M) and TRM (7M): Sudoku-Extreme 97%,
ARC-AGI-1 52%, ARC-AGI-2 11.1%; and on **multi-solution** constraint satisfaction
N-Queens 99.7% accuracy with **90.3% coverage of valid solutions** — i.e. it does not
collapse to one answer, it spreads mass across the valid set.

---

## 2. Research → program mapping

The deterministic core is the *one* thing GRAM replaces; everything around it in the
look-net contract already has the shape GRAM needs.

| GRAM construct | SixFour construct | Anchor |
|---|---|---|
| Deterministic recursive core (what GRAM generalizes) | `L4 Core R`: PonderNet over MoR | `LOOK_NN.md` Def 34; `coreIO` `LookNet.hs:119` |
| Two-level latent `z=(h,l)`, abstract↔fine | Haar pair-tree coarse→fine + MoR shared block iterated per level | `Spec.PairTree`; `maxPonderDepth = paletteDepth` `LookNet.hs:101` |
| `K` inner `f_L` refinements | barycenter fixed-point inner iterations (Bures) | Def 30, Thm 9; `Spec.Bures` |
| Stochastic guidance `ε_t ~ N(μ_θ,σ²_θ)` | the **engineered per-user variance**, bounded by `σ(aᵢ)+s·tanh(δ)`, `s=0.1` | Def 35; `feedback_variance_engineered_quality_hardened` |
| ACT halt head `q_ψ` | existing PonderNet halting dial, `Σ pₙ = 1` | Def 34; Law **L8** ("new `Spec.Halting`") |
| Width: `N` parallel trajectories | `N` candidate `HaarPalette`s (a gallery slate) | `LookOutput` `LookNet.hs:172` |
| Reward model `v_ψ(z_t)` + selection | `linearUtility` (Bradley–Terry) + DPP `greedyGallery` | `Preference.hs:59,137` |
| Selection signal / trajectory correctness | the **swipe / pin / keep** signal | `btProbability` `Preference.hs:64` |
| Multi-solution constraint satisfaction | palette constraints: gamut **L3**, σ-balance **L6**, surjectivity **L7**, beauty/diversity Def 31–32 | `LOOK_NN.md` §8 |
| Conditional `p(y \| x)` | `p(look \| pooled-GMM, LookCode)` | substrate `Spec.GMM`; control `LookCode ∈ [−1,1]⁴` Def 35 |
| Unconditional `p(x)` | a generative palette prior (sample looks with no scene) | future |

**The one substitution.** Deterministic `coreIO : dM → dM` becomes a stochastic kernel:
the same `dM → dM` block plus a noise head `(μ_θ, σ_θ) : dM → (dM, dM)` and the
reparameterized update `h_t = u_t + σ_θ ⊙ ε`, `ε ~ N(0, I)`. Nothing downstream of the
core changes shape — `L5 Decoder D` still consumes a `dM` context (Def 35) and still
clamps. That is why the variance is *contained*: every sampled `h_t` flows through the
same bounded decoder, so every realised palette is in-gamut and σ-balanced **by
construction**, exactly as the existing "∀ weights" proofs guarantee (§8 preamble).

---

## 3. The gallery is GRAM's width axis (unification)

SixFour already specified, independently, the machinery GRAM uses to scale at inference —
they are the same object viewed from two literatures:

- **A gallery of `N` looks _is_ `N` parallel GRAM trajectories.** Sampling `N` noise
  draws `{ε^(i)}` from the stochastic core yields `N` terminal contexts `{z_T^(i)}`,
  decoded to `N` distinct `HaarPalette`s — GRAM's parallel trajectory set, and SixFour's
  candidate slate, are identical.
- **GRAM's reward model `v_ψ` _is_ the SixFour preference utility.** `v_ψ(z_t)` scores
  trajectory quality; `Preference.linearUtility` (`Preference.hs:59`) scores a palette
  embedding under the Bradley–Terry link (`btProbability`, `:64`). Both are a learned
  real-valued utility over candidates. The `Embedding` for `v_ψ` is the natural one
  SixFour already names: the **768 Haar coefficients** (`Spec.Preference` doc; the
  decoder output of Def 35).
- **Selection is `greedyGallery`, not majority vote.** GRAM offers majority vote *or*
  `v_ψ`; SixFour's choice is strictly richer — the **quality-weighted DPP**
  `greedyGallery` (`Preference.hs:137`, L-ensemble `L = diag(√q) K diag(√q)`,
  `q = exp(α·u)`). This selects a *diverse, high-utility* subset, so the shown gallery
  both ranks by the reward and spreads across the valid-solution set — the SixFour analogue
  of GRAM's 90.3% N-Queens **coverage** (§1).
- **The swipe is the reward signal.** GRAM trains `v_ψ` to predict correctness;
  SixFour's pin/swipe/keep are pairwise preference observations under the same
  Bradley–Terry link. No new selection or reward machinery is invented — the swipe
  *is* the training signal for `v_ψ`.

Net: generate `N` palettes by sampling the stochastic core, select/show with the
existing DPP gallery, learn the utility from swipes. One coherent generate-then-select
loop, assembled entirely from constructs already in the contract.

---

## 4. Contract deltas a future pivot would make (described, not committed)

If the stochastic core is later adopted, these are the contract touch-points — named
here so the pivot is mechanical, **not** written in this note:

1. **`coreIO` gains a stochastic form** (`LookNet.hs:119`): add prior noise-net IO
   shapes `μ_θ, σ_θ : dM → dM` and posterior `μ_φ, σ_φ : dM → dM` (the latter conditioned
   on the target during training), with reparameterized sampling `h = u + σ ⊙ ε`.
2. **New / extended laws:**
   - *Bounded-noise envelope* — **every** sampled trajectory still satisfies L1–L7. The
     existing decoder proof already holds "∀ weights"; this extends the quantifier to
     "∀ ε": since `ε` enters only through the clamped decoder (Def 35), gamut closure
     (L3), boundedness (L2), and σ-equivariance (L6) are noise-invariant. This is the
     formal statement of "harden the envelope ∀ variance."
   - *ELBO / KL well-formedness* — `σ_θ, σ_φ > 0`; `KL(q_φ ‖ p_θ) ≥ 0`; the truncated
     surrogate `L_GRAM^(n)` lower-bounds the step objective.
   - *Selection law* — tie §3: the gallery selected from `N` trajectories under
     `greedyGallery` is a sub-multiset of the sampled candidates, utility-monotone, and
     duplicate-free (already the content of `Preference` laws — restated over GRAM draws).
3. **Conceptual modules** (named only): `Spec.Halting` (already anticipated by Law L8)
   for the ACT head, and a stochastic-core extension of `Spec.Net` / `Spec.LookNet`.

Order of execution, per project convention: Haskell spec + laws first (contract-first,
codegen-pinned), then the Rust `burn` v2 core (the autodiff path needed for the VI
objective — currently deferred pending license vetting).

---

## 5. What GRAM does *not* hand us (honest gaps)

- **No code.** The repository is unreleased; the core must be reimplemented. The natural
  home is the deferred Rust `burn` v2 backend (reparameterization + KL need autodiff,
  which the v1 pure-Rust 1+1-ES path does not provide).
- **Domain mismatch.** GRAM's tasks are **discrete grids** (Sudoku, ARC, N-Queens);
  ours is **continuous OKLab with an optimal-transport barycenter** target (Def 30,
  `Spec.Bures`). The latent transition and decoder are continuous already, so this is
  favourable — but the transition must be *adapted*, not copied.
- **Biased estimator.** Truncated 1-step backprop makes `L_GRAM^(n)` a biased ELBO
  surrogate; acceptable in GRAM's results, but a known approximation.
- **The target `y` is undefined for a self-supervised palette task — the key open
  question.** The posterior `q_φ(τ|x,y)` needs a `y`; the v1 look-net loss (Def 37) is
  self-supervised with **no labels**. Two research-grounded candidates to resolve before
  any pivot:
  - *Pseudo-target = the barycenter floor.* Use `G⋆` (Thm 9, the free-support
    Wasserstein-2 barycenter / k-means floor) as `y`. The posterior then learns the
    bounded *deviation* from the floor — consistent with Def 37's "controlled deviation
    from this floor, not an escape of it."
  - *Posterior over preferred looks.* Treat user-kept palettes as samples from the
    target; `q_φ` becomes a taste-conditioned posterior, directly coupling §3's reward
    `v_ψ` to the VI target. This is the more ambitious, product-aligned option.

  This choice determines whether GRAM enters SixFour as a *fidelity* generative model
  (floor-anchored) or a *preference* generative model (taste-anchored), and should be
  decided from the literature + captured data, not assumed.

---

## 6. Bibliography (cross-referenced to `LOOK_NN.md` §10)

*This note.* Baek, J., Jo, M., Kim, M., Ren, M., Bengio, Y. & Ahn, S. (2026).
*Generative Recursive Reasoning Models.* arXiv:2605.19376. (Whole note.)

*Recursive-core lineage (already in `LOOK_NN.md` §10).* Banino, A., Balaguer, J. &
Blundell, C. (2021). *PonderNet.* arXiv:2107.05407. (Def 34, the deterministic core
GRAM generalizes; ACT head ↔ Graves 2016.) — Bae, S. et al. (2025).
*Mixture-of-Recursions.* arXiv:2507.10524. — Dehghani, M. et al. (2019).
*Universal Transformers.* ICLR. (the shared-block recurrence.)

*Variational inference / reparameterization (new for the stochastic core).* Kingma, D.
& Welling, M. (2014). *Auto-Encoding Variational Bayes.* ICLR. (the ELBO + reparam trick
GRAM's training rests on.)

*Selection / reward (already in `LOOK_NN.md` §10, via `Spec.Preference`).* Kulesza, A. &
Taskar, B. (2012). *Determinantal Point Processes for ML.* (DPP gallery = width-axis
selection.) — Chu, W. & Ghahramani, Z. (2005). *Preference Learning with Gaussian
Processes.* (Bradley–Terry utility = `v_ψ`.)
