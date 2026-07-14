# The NN's dimensional space — recursive σ-balanced pairing tree

> **STILL CURRENT after the 2026-05-27 pivot.** This doc describes the *output* palette
> structure (the Haar σ-balanced pair-tree, `Spec.PairTree`) — which was always
> category-free and **survives the pivot unchanged**. Only the *input* side changed:
> the substrate is now the continuous OKLab Gaussian mixture (`Spec.GMM`) collapsed by
> the Wasserstein-2/Bures barycenter (`Spec.Bures`), not the 11-category code. The
> §1 note that the leaf pairs coincide with σ on the neutral axis now points at
> `PairTree.sigmaReflect` (the continuous complement; the category complement map is deleted).

Working notes (2026-05-26), hardening the design conversation. Companion to the
formal `LOOK_NN.md`; this fixes the *shape of the space the look-NN lives in*
before the regimen (Phase C) is designed. The Haskell that mirrors these notes is
`SixFour.Spec.PairTree` and `SixFour.Spec.Dither` (contract-first, real reference
functions, no stubs).

## 1. The palette is a Haar pyramid of balanced pairs

The output primitive is not "256 colours" but a **perfect binary tree of σ-balanced
pairs**, written `[(1:1):(1:1)]:[(1:1):(1:1)]…`. Because `256 = 2⁸`, the tree has
exactly **8 levels of pairing**:

```
level 0:   1 root      = the palette mean (DC)
level 1:   1 split  → 128 pairs are the σ-balanced dither AXES
level ℓ:   2^(ℓ-1) offsets → 2^ℓ nodes
level 8: 256 leaves     = the global palette
```

Each node splits into two children that are **mirror images about the parent**:
`childₗ = parent + δ`, `childᵣ = parent − δ`. This is precisely the **Haar
multiresolution**: the parent is the average, the offset `δ` is the detail. So the
palette is the *inverse Haar transform* of a tree of 255 offset vectors, and:

- **symmetry holds at every scale** (each node is balanced) — fractal/self-similar
  symmetry, a stronger beauty claim than Phase A's single-scale complement;
- **"pairs that are themselves paired"** = the tree of offsets;
- the **distance within a pair** = `2‖δ‖` (the "range of distances" knob);
- the **aggregate is balanced**: the offsets cancel, so `mean(leaves) = root`.

> Relation to Phase A's σ: the tree uses *mirror balance about the local parent*
> (additive complement, general at every level). The leaf pairs coincide with the
> chroma complement σ(L,a,b)=(L,−a,−b) of `Spec.Pair` when the parent sits on the
> neutral axis; in general the tree balance is the multiresolution generalisation.

## 2. Degrees of freedom — reorganised, not added

The tree does **not** change the count of free numbers — it *restructures* them:

```
DOF = 3 (root) + 3·(2⁸ − 1) offsets = 3·256 = 768
levelDof = [3, 6, 12, 24, 48, 96, 192, 384]   (3·2^(ℓ-1) per level)
```

768 reals = the same as 256 colours × 3 channels, but now addressed as **8 levels
of detail**.

> **Shipped genome is 384-DOF, not 768 (2026-06-05).** The 768 above is the *free*
> Haar tree = the reconstructed **leaf space**. The shipped decoder emits the
> σ-constrained **384-DOF σ-pair genome** (`SIGMA_PAIR_DOF = 3·128`,
> `Spec/SigmaPairHead.hs`); L6 reconstructs that into these 768 leaf reals. Per
> `CLAUDE.md`: *the NN emits 384, the leaf space is 768.* Read every "768-DOF" below
> as the leaf/tree space, with the learnable genome σ-halved to 384. That is the whole point: the NN can have **layers specialised per
level** — a *distance head* that sets offset magnitudes `‖δ‖` (variety / axis
length), a *pairing head* that sets how subtrees couple (unity / nested balance),
and a recursive core whose **recursion depth = tree level** (this is *why* the
recursive architecture from the design review fits — it walks the 8 levels).

## 3. φ as the coefficient-decay law (self-similarity)

φ enters as the **falloff of offset magnitude across levels**: `‖δ‖` at level ℓ
scales like `(1/φ)^ℓ ≈ 0.618^ℓ`. Big balanced splits up top, golden-smaller splits
below → a **self-similar / fractal** palette. This is the testable φ hypothesis
(does golden decay raise Birkhoff M and lower flicker vs free per-level scale?).
The golden *angle* (137.5°) is the companion tool for spreading anchors in the
chroma plane (maximally even coverage). `Spec.PairTree.goldenDecay` is the reference.

## 4. The dither space — a binary (Bernoulli) distribution

Each pixel, over the 64-frame loop, is a **Bernoulli(p)** process on a pair:
show anchor (0) or partner (1). The eye averages → perceived colour
`(1−p)·anchor + p·partner`, so **p ∈ [0,1] is the continuous position on the dither
axis**. Over the loop the partner-count is **Binomial(T, p)**:

- **mean `T·p` = the colour** (correctness),
- **variance `T·p(1−p)` = the flicker** (the dirty-window effect; maximal at p=0.5).

i.i.d. sampling gives the right mean but high variance. The fix is a **low-discrepancy
ordering** — `frac(n·φ)` in time, STBN3D in space-time (tileable ⇒ cyclically closed,
matching the existing cyclic-closedness law) — so the running average converges
immediately: **binary distribution sets the mean, blue-noise ordering kills the
variance.** Realised as a threshold: partner ⟺ `p > M(x,y,t)`. See `Spec.Dither`.

Note: φ's natural 0.382/0.618 split is *off-centre*, so φ-positioned tones are
**lower-variance (less flicker)** than a 50/50 blend — beauty and stability align.

## 5. "Not all 256 per frame" is forced, not imposed

At any single frame a pixel shows *one* end of its pair → a frame is a **sparse slice**
of the tree; the **union over the 64-frame loop covers all 256** (global surjectivity).
This **replaces L7** of `LOOK_NN.md` (currently per-frame "every frame uses all 256"):

> **L7′ (global surjectivity):** ⋃ₜ usedₜ = 256, with each frame using a *significant
> subset*. Per-frame `CompleteVoxelVolume` from Stage A (local extraction) is a
> different stage and is unchanged.

## 6. Pairs move and interact (the dynamic layer)

Pairs are **not** fixed per pixel. The leaf-assignment and p-field evolve over the
64 frames; pairs migrate, merge, repel. Coupling is structural — **siblings/cousins
in the tree** + **spatial neighbours** under the dither — i.e. an NCA-/organism-style
interaction (the SATOR72/ROTAS lineage). Motion reintroduces *variety*; the binary
distribution + blue-noise ordering keep *flicker* bounded.

## 7. What is fixed vs free (the division of labour)

| Fixed by construction (cannot be wrong) | Free — the NN chooses |
|---|---|
| σ/mirror balance at every node | root colour (DC) |
| dyadic topology (8 levels, 256 leaves) | the 255 offset vectors `δ` (distances + directions) |
| STBN3D cyclic dither ordering | the moving (T,H,W) leaf-assignment + p-field |
| gamut clamp; cyclic closure | the subtree coupling ("pairs of pairs") |

**Global structure (768-real tree) vs local realisation ((T,H,W) p-field)** — this is
likely the §9 CPU/GPU split re-derived from the math: the tree is small/global (CPU),
the p-field is large/local (GPU).

## 8. Open questions (still in discussion, not committed)

1. **Coefficient decay**: golden falloff per level, or free? (measurable)
2. **Interaction rule**: NCA update on the p-field, attention over leaves, or both?
3. **Tone-resolution shape**: how does perceived depth split across temporal (≤T+1
   levels) × spatial neighbourhood × tree level? (a measurement study, like Phase A)
4. **Anchor placement**: golden-angle (137.5°) spread vs learned — measure on M.

## Mirrors

- `SixFour.Spec.PairTree` — the Haar pairing pyramid + DOF (this doc §§1–3, 5, 7).
- `SixFour.Spec.Dither`   — the binary distribution + ordering (this doc §4).
- `Properties.{PairTree,Dither}` — the laws as QuickCheck properties.
