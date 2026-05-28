# NOTES — design decisions, session log

Running notes on architectural pivots and their tensor evidence. Entries are
newest first.

---

## 2026-05-28 — σ-pair decoder pivot (Quad4 rejected → SigmaPairHead adopted)

**Session goal.** Unify three new spec primitives — the 16³ OKLab histogram
bottleneck (`Spec.Bottleneck16`), the σ-eigenspace split (`Spec.SigmaDecomp`),
and a 4-ary opponent-quadrant decoder (`Spec.Quad4`) — into one coherent
look-NN pipeline, and decide between binary PairTree and 4-ary Quad4 for the
L6 reconstruction stage.

**What the session committed.** Seven commits on top of `80b9843`:

| Commit | Lines | What |
|---|---|---|
| `3cb1be5` | +1198 | Substrate: GMM + Bures (W₂ on Gaussians) |
| `e09c791` | +3376 | Look-NN spec: 9-layer pipeline (L1…L9), 768-coeff PairTree |
| `c4f8e8e` | +2361 | Tooling: spec-tui, spec-gif, spec-gen |
| `a96d1c5` | +848  | Bottleneck16 + SigmaDecomp + Quad4 (the redesign primitives) |
| `ab27a16` | +548  | Spec.Pipeline (Stage / SigmaEquivariant type-class framework) |
| `06f8746` | +519  | LinAlg + Quad4Fit (tensor measurement on Quad4) |
| `f7667b8` | +341  | SigmaPairHead (σ-pair-symmetric decoder, tensor-verified) |

Net **+10,497 / -701** across 100 files. **191 spec tests pass.**

### The pivot in one paragraph

`ab27a16` encoded the σ-equivariance claim of the plan addendum (§A) as a
Haskell type-class framework. The composition theorem `option4Theorem`
typechecks — proving that *if* every stage is `SigmaEquivariant`, the whole
pipeline is. The user noted this proof is **structural only**: it certifies
shapes commute, not that the architecture has the right representational
power. The follow-up commit `06f8746` built the Quad4 design matrix
`B ∈ ℝ^{768 × 511}` explicitly and measured its image via Modified
Gram-Schmidt. **Finding:** Quad4's residual on σ-symmetric synthetic palettes
was *indistinguishable* from its residual on random palettes (median ≈ 6 %
both, contrast ratio ≈ 1). Quad4's image cuts ℝ⁷⁶⁸ at some generic angle
that captures concentrated palette content equally well regardless of σ
structure — it is **not** preferentially σ-aligned. The plan's claim "Option
4's Quad4 decoder yields σ-symmetric output by construction" was false at
the tensor level.

`f7667b8` introduced **`Spec.SigmaPairHead`** to fix this: instead of
freely-parameterised 256 leaves, emit only **128 σ-pair GENERATORS** via a
depth-7 binary Haar pyramid, and define the 256-leaf palette as
`[c_0, σ(c_0), c_1, σ(c_1), …]`. The σ-pair structure is now algebraic; every
odd leaf is the σ-reflection of its even predecessor for *any* genome. The
design matrix `B ∈ ℝ^{768 × 384}` is full rank (384) — exactly the dimension
of the σ-symmetric palette subspace — and the empirical residuals are:

| | SigmaPairHead | Quad4 |
|---|---|---|
| Rank | 384 (full) | 511 (full) |
| σ-symmetric residual (median) | **0.0** (≈ 1e-15) | 0.06 |
| Random palette residual (median) | 0.09 | 0.06 |
| **Contrast (random / σ-symmetric)** | **≈ 10²⁸** | ≈ 1 |

The contrast ratio is the architectural signature. SigmaPairHead is **10²⁸×
better** at fitting σ-symmetric content than random palettes; Quad4 has no
σ-preference at all.

### Why this matters

The "128 σ-balanced pairs" headline of `LOOK_NN.md` was always aspirational.
A free-parameter tree (binary or 4-ary) achieves σ-symmetric output only via
a learning signal — the architecture itself provides no guarantee.
SigmaPairHead is the structural inhabitant the headline required. Its DOF
(384) is exactly the σ-symmetric subspace dimension — **zero wasted DOF on
σ-antisymmetric content the constraint forbids**.

### Open questions left for the next session

1. **`spec-measure` exe on real captures.** The σ-symmetric / random
   distinction was measured on synthetic palettes drawn from a [0.2, 0.8] ×
   [-0.2, 0.2]² box. The decision-relevant question — what does the
   `sigmaSymFraction` distribution look like on on-device captures from
   `~/Library/Application Support/SixFour/sessions/` — is still pending
   (Tasks #3, #4 in the TaskList).

2. **Re-instantiate `option4Theorem` at `SigmaPairHead`.** The Pipeline
   composition theorem in `Spec.Pipeline` is currently parameterised over
   `Quad4ReconAchroma`. Should be straightforward to add a
   `SigmaPairHead`-instance and prove the conditional σ-equivariance for the
   updated pipeline.

3. **The L5 decoder.** The encoder L3 → L4 → L5 → L6 chain needs to emit a
   384-coefficient `SigmaPairTree` instead of a 768-coefficient
   `HaarPalette`. Cheap: drop the lowest Haar level.

4. **Codegen pin for the new dimensions.** `Spec.Codegen.Burn` should emit
   `SIGMA_PAIR_DOF = 384`, `SIGMA_PAIR_DEPTH = 7`, `SIGMA_PAIR_LEAVES = 256`
   into `studio/look-nn/src/generated/contract.rs`. One commit (Task #2).

5. **Stochastic core (GRAM-style, `spec/GRAM_MAPPING.md`).** Still design-
   only, still deferred. The VI target `y` open question is unresolved.

### Architectural diagram (post-session)

```
L1 Pool      :  CyclicStack → samples                                (Det)
L2 GMM       :  samples → tokens (μ, Σ, w)                           (Det)
L3 Encoder E :  10 → dM = 64                                         (Learn)
L4 Core R    :  dM → dM   (PonderNet over Mixture-of-Recursions)     (Learn)
L5 Decoder D :  dM → 384  (SigmaPairTree genome — was 768 PairTree)  (Learn)
L6 Reconstruct: SigmaPairTree → 256-leaf σ-pair palette              (Det,  NEW)
L7 Remap     :  per-frame K → K                                      (Det)
L8 GlobalIdx :  T·H·W + remap → T·H·W ∈ [0, K)                       (Det)
L9 Dither    :  index field + STBN3D → GIF index field               (Learn/Det)
```

Genome budget: **dM = 64** (encoder bottleneck) → **384** (decoder output) →
256 σ-pair-structured leaves. Both PairTree (768) and Quad4 (511) are
retained in the spec library as documented alternatives — they're not wired
into the pipeline, but their spec modules and tensor measurements are kept
as evidence of why SigmaPairHead won.

---

## Review summary (this session)

**Code added (Haskell):** 9 new modules in `spec/src/SixFour/Spec/`:
`Bottleneck16`, `SigmaDecomp`, `Quad4`, `Pipeline`, `LinAlg`, `Quad4Fit`,
`SigmaPairHead`, plus extensions to `Indices` (`GlobalSurjective` brand),
`Cyclic` (constant-trajectory AC-power fix), `Codegen.Burn` (Rust contract
emit). Total ~2.6 k LoC of spec, ~1.3 k LoC of property tests.

**Code added (Rust):** `studio/look-nn/` crate (272 LoC), `analysis-core`
extensions for Bures + GMM (~480 LoC). Golden-checked against Haskell spec.

**Tooling added:** Three executables (`spec-tui`, `spec-gif`, `spec-gen`)
with their own gen/viz/gen-test source dirs (~1.7 k LoC), plus a `gen-tests`
test-suite (9 tests green).

**Tests added:** 191 spec tests total (was 79 before commit `3cb1be5`).
Highlights: 16-law layer report at production 64³ × 3 seeds; Bures iteration
convergence; σ-eigenspace orthogonality / Parseval; PairTree round-trip;
Quad4 σ-equivariance; SigmaPairHead structural σ-pair guarantee; tensor
residual reports printed live with `§A.4` verdicts.

**Risks / things to watch.**
- Modified Gram-Schmidt is not the most numerically stable QR; if matrix
  conditioning degrades in a future variant, may need to upgrade to
  Householder QR or pull in a BLAS-backed LA library (license-gated).
- The `option4Theorem` proof in `Spec.Pipeline` is currently dead-end at
  Quad4ReconAchroma — needs the SigmaPairHead update before the
  type-class framework actually points at the new decoder.
- `spec/dist-newstyle/` is sometimes 300 MB; `.gitignore` covers it but
  watch out for `spec/analysis/dist-newstyle/` (covered by the
  `spec/**/dist-newstyle/` rule added in commit `3cb1be5`).
- The branch name `feat/significance-settings-instrument` is stale —
  significantly outscoped its original purpose.

**Verification performed.**
- `cabal test spec-tests` → 191 / 191 green.
- `cargo build -p analysis-core -p look-nn` in `studio/` → clean.
- `cabal run spec-codegen` → 8 files + 1 resource, no diffs against the
  shipped Swift / Python / Rust contracts.
- Manual review of every commit's diff against the plan's named files
  (`~/.claude/plans/flickering-dazzling-dewdrop.md`).
