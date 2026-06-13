> **⚠ SUPERSEDED (2026-05-30) by [`L-NN-MASTER-DESIGN.md`](../L-NN-MASTER-DESIGN.md), the design of record.**
> The σ-eigenspace cascade and the decoder-factoring plan (§5: `D_L ⊕ D_A ⊕ D_B` + grounding laws)
> are KEEP. Corrected by the master: the "256-distinct-L via depth-8" claim (§3.2) is RETIRED (a §8
> fork), "A/B never re-index" is now Thm 18 *stability*, and the `[4,2,1]` metric is dropped (PairTree
> landed plain Euclidean). See the master §6 + §7.

# L-NN as the grounding atom of `B(A(L(·)))`

**Purpose of this doc.** Design the L-NN not as a standalone grayscale model but as
the **innermost atom** of a compositional color network `B(A(L(·)))` that grounds the
mapping **64 per-frame 256-palettes → 1 global 256-palette + index map**. Each of
`L`, `A`, `B` is a *layer-atom of the others*: structurally the same combinator,
composed by nesting. This supersedes the standalone-L framing in
`L-NN-RESEARCH-AND-WORKFLOW.md` (whose research verdicts still hold) and the
"separate depth-8 hack" in memory.

Source-of-truth alignment: `Spec/SigmaDecomp.hs` (the eigenspace split),
`Spec/AxisNet.hs` (the per-axis projection algebra), `Spec/LookNet{E,R,D}.hs` (the
E→R→D shape), `Spec/SigmaPairHead.hs` (the 384-DOF σ-pair tree this factors).

---

## 1. The compositional thesis

### 1.1 The eigenspace decomposition IS the composition
The chroma involution `σ(L,a,b) = (L,−a,−b)` splits OKLab orthogonally
(`SigmaDecomp.hs`, Parseval-exact):

```
   colour  =  grey-midpoint      ⊕   chroma-deviation
              (σ-SYMMETRIC)            (σ-ANTISYMMETRIC)
              a = b = 0                L = 0
              ── the L atom ──         ── the A,B atoms ──
```

A σ-pair palette leaf and its mirror `{c, σc}` decompose as
`c = m + d`, `σc = m − d` with `m = (c+σc)/2 = (L,0,0)` (pure grey) and
`d = (c−σc)/2 = (0,a,b)` (pure chroma). **So the 256-leaf σ-pair palette already in
the spec is literally `B(A(L))`:** the 128 midpoints `m_i` are the L-atom's output;
the 128 deviations `d_i = (0,a_i,b_i)` are the A- and B-atoms' output. The current
decoder emits `m` and `d` fused in one 384-DOF blob; this design **factors them**.

### 1.2 What "atom of each other" means precisely
`L`, `A`, `B` are the **same parameterized combinator** `Atom axis`, instantiated on
the three OKLab axes and composed by **residual nesting in orthogonal eigenspaces**:

```
   L : Tokens            → Palette          -- σ-symmetric base (grey skeleton)
   A : Palette           → Palette          -- + red-green deviation  (σ-antisym, ⊥ L)
   B : Palette           → Palette          -- + blue-yellow deviation (σ-antisym, ⊥ L, ⊥? A)
   look = B ∘ A ∘ L      : Tokens → Palette
```

Because A and B write **only** into the σ-antisymmetric eigenspace and L writes
**only** into the σ-symmetric one, the wrap is non-destructive by construction:
`A` and `B` cannot move the lightness `L` chose (orthogonality), so `L` **grounds**
the cascade — it is the stable base the chroma atoms refine around. This is the
algebraic content of `AxisNet`'s `axisSigmaSign` (+1 for L, −1 for A,B) and of
`SigmaDecomp`'s orthogonal `symPart`/`asymPart`.

### 1.3 Why this is the right shape (not three independent nets)
- **One involution, three eigen-components.** A single symmetry generates the whole
  factorization, so the atoms share structure and proofs (the σ-equivariance
  theorem in `LookNetCompose.hs` extends per-atom).
- **Lightness-first is empirically standard.** Color models cascade L-then-chroma
  (PaletteNet alters only `ab`, keeps `L` fixed; PalGAN estimates chroma conditioned
  on a gray image). The cascade here is the *equivariant, residual* version of that.
- **It tells each atom what it is FOR** (§4): L is MSE-bounded and deterministic-
  ceilinged; A,B are relational and have no single right answer — which is exactly
  where learning (and a justified GAN) live.

---

## 2. The atom

A single combinator, axis-parameterized. Shape = the existing E→R→D, but each atom
reads **its own σ-eigenspace slice** of the shared hidden state and writes **its own
axis**.

```
Atom (axis : ColorAxis) =
  Encoder  E_axis : Tokens          → h ∈ ℝ⁶⁴      -- perm-invariant weighted pool (shared)
  Recursion R     : h               → [ctx₀..ctx₈]  -- ONE shared MoR block, 8 Haar levels (shared)
  Decoder  D_axis : [ctx]           → coeffs_axis   -- reads the axis's eigenspace slice
  Lift     ℓ_axis : coeffs_axis     → Δ_axis         -- inverse-Haar → per-leaf axis values
```

**The σ-classified hidden state is the eigenspace router.** `Tensor.sigma64Mask`
partitions the 64-d state into **22 achromatic ⊕ 21 red-green ⊕ 21 blue-yellow**
(Hurvich–Jameson). Each atom's decoder reads only its block:

| Atom | reads hidden dims | σ-class | writes | resolution |
|---|---|---|---|---|
| **L** | 22 achromatic | σ-fixed (+1) | `L_i` (128 tonal anchors) | **128 distinct L** (depth-7 *scalar* Haar) |
| **A** | 21 red-green | σ-negated (−1) | `a_i` (deviation) | 128 σ-antisym coeffs |
| **B** | 21 blue-yellow | σ-negated (−1) | `b_i` (deviation) | 128 σ-antisym coeffs |

- **L emits the 128 pair-midpoint anchors** in the σ-symmetric eigenspace
  (`SigmaDecomp.dimSigmaSym = 2048`, so 128 distinct levels is comfortably within it).
  The depth-7 scalar Haar is the *principled* L-atom: the symmetric-eigenspace
  generator at the σ-pair cardinality. (Per the user's "leaf structure is a feature"
  decision, the palette unit is the 128-harmony σ-pair, not 256 independent leaves —
  so L's 128 anchors is the design, not a resolution loss.)
- **A,B write the σ-antisymmetric deviations.** Together they reconstruct the 128
  `d_i = (0,a_i,b_i)`, one per σ-pair. **Decision (user, 2026-05-30 — "the leaf
  structure is a feature not a bug"):** the palette **IS 128 σ-pairs** `{c_i, σc_i}`
  = **128 complementary harmonies**, the authoring grammar (a colour *and its
  complement*), NOT 256 independent colours. So:
  - **L emits the 128 tonal anchors** `m_i = (L_i,0,0)` (the pair midpoints) — a
    depth-7 *scalar* Haar in the σ-symmetric eigenspace → **128 distinct lightness
    levels**. (The depth-8 "256 distinct L" idea is **retired**: 128 anchors is the
    feature, not a resolution loss to engineer around.)
  - **A,B emit the per-anchor complementary spread** `d_i = (0,a_i,b_i)`; the σ-pair
    `{m_i+d_i, m_i−d_i}` is the harmony around anchor `i`.
  - The grayscale milestone therefore targets the **128-level** ceiling (128-level
    Lloyd-Max), not 256 — consistent with the σ-pair being the unit of the palette.

**Sharing.** `E` (the pooled encoder) and `R` (the one MoR recursion block) are
**shared across atoms** — they compute the common σ-classified context once. Only the
per-axis decoders `D_axis` + lifts `ℓ_axis` differ. This is what makes them "atoms of
each other": identical machinery, different eigenspace read/write. (Equivalent to
three thin heads on one trunk — cheap, and it keeps the ~58K param budget.)

---

## 3. How L grounds the `64 → 256` mapping

The L-atom is responsible for the two things that define the global palette, *before*
any chroma exists:

### 3.1 The collapse (64 per-frame palettes → 1 global)
- Input: 64×256 weighted OKLab tokens (per-frame palettes), pooled permutation-
  invariantly (`L3Encoder` sum-pool weighted by population) → one 64-d context. The
  collapse is the **pool**, and it is L's job because the *grey marginal* is the
  σ-symmetric projection of the pooled histogram (`SigmaDecomp.symPart` of the pool).
- L is the only atom that must see the **whole burst's lightness distribution** to
  size the dynamic range; A,B operate on the already-collapsed context.

### 3.2 The cardinality + index map (the grounding)
- L emits **256 distinct lightness levels** (the global grey palette) and, by
  deterministic **argmin on L** (research-decided, `global_palette.global_reindex`),
  the **per-pixel index map**. This index map is the grounding object: every pixel is
  assigned to a lightness level *first*.
- A,B do **not** re-index. They attach `(a_i,b_i)` to the level `i` a pixel already
  has. Under the LAB hierarchy `L ≻ a ≻ b` (weights `[4,2,1]`, `OKLabMetric`), L
  dominates assignment, so chroma deviations perturb only pixels at L-level
  boundaries. **The index map is thus grounded by L and only refined by A,B** — the
  compositional analogue of the palette cascade.
- Consequence: the global palette's *structure* (how many levels, which pixel goes
  where) is fixed by L; A,B decorate it. This is exactly "L grounds the per-frame →
  global mapping."

### 3.3 The MSE ceiling lives entirely in L
Per the research, the L-axis MSE ceiling is **Lloyd-Max** (1-D k-means on the pooled
lightness); the full-OKLab MSE ceiling is **3-D k-means** (= per-capture `StageA`).
Both are deterministic. So **fidelity (MSE) is a property of the grounding (L + the
deterministic argmin), not of the learned chroma.** The atoms above L are not there to
cut MSE — they are there for the σ-antisymmetric, relational, per-user structure that
no deterministic quantizer expresses (§4). This is the honest division of labor:
*L grounds fidelity; A,B add the look.*

---

## 4. Objectives per scale — where the GAN fits

The cascade tells us which objective each atom should carry, and resolves the GAN
question by **scale** (the user's "if GAN fits in the scales, fine"):

| Atom / scale | Has a closed-form optimum? | Objective | GAN? |
|---|---|---|---|
| **L** (σ-symmetric, MSE) | **Yes** — Lloyd-Max | OT/reconstruction (sliced-W is exact in 1-D) + Bures anchor + halting-as-readout | **No.** GAN is inert here (single right answer; D parks at the uninformative fixed point). |
| **A, B** (σ-antisymmetric, relational) | **No** — chroma harmony is relational, many valid | reconstruction (coverage of `H_asym`) + **Ou–Luo beauty** (`Preference.hs`) + symmetry prior | **Optional/justified.** Adversary on the *rendered colour image* (à la PalGAN), never on the palette tensor. |
| **unify / per-user gallery** (QD over chroma) | **No** — taste-dependent | MAP-Elites diversity + on-device user reward | **Yes** — diversity/adversarial objectives are the point. |

So: **drop the GAN at L; (re)introduce an image-space adversary at A/B and a
diversity critic at the gallery scale.** This matches the research (GAN inert/risky on
tiny structured MSE outputs; legitimate when targeting image-space colour with no
single correct answer) and the user's per-scale framing.

Two scale-axes coexist and both are legitimate places for an adversary on chroma:
the **axis scale** (L→A→B above) and the **Haar/pyramid scale** (depth ℓ within an
atom). Coarse Haar levels carry global relational structure (where Ou–Luo/adversarial
signal helps); fine levels carry per-leaf detail (reconstruction). The halting head
already indexes the pyramid scale.

---

## 5. The concrete refactor (spec + trainer)

What changes from today's monolithic σ-pair decoder, smallest-diff first. None of
this touches the σ-equivariance *theorem*; it factors the decoder along the
eigenspaces the theorem already names.

1. **`Spec/AxisNet.hs` — promote `AxisNet` from a post-hoc projection to a generative
   atom.** Today `step = map (projectAxis axis)` (deterministic projection of a
   finished palette). Add the atom signature `AtomNet (axis)` carrying a decoder head
   + lift, with `In = [ctx]`, `Out = AxisDeviation`. Keep `projectAxis` as the
   read-back law (`D_axis` then `projectAxis axis` round-trips).
2. **Factor the decoder.** `LookNetD` currently emits one 384 = `m ⊕ d` blob.
   Re-express as `D_L` (→ 256 scalar L-Haar coeffs, σ-symmetric eigenspace) ⊕ `D_A`
   (→ red-green antisym coeffs) ⊕ `D_B` (→ blue-yellow antisym coeffs). Law: the
   concatenation reconstructs the existing 384 σ-pair coeffs (golden-vector
   no-drift), so the codegen and goldens move continuously.
3. **`look = B ∘ A ∘ L` composition + residual law.** A new compose combinator
   (extends `LookNetCompose`): `A` and `B` add into the σ-antisymmetric eigenspace
   only ⇒ prove `symPart (look x) == L x` (chroma cannot move the grey skeleton) and
   `asymPart (L x) == 0` (L is pure grey). These two laws ARE "L grounds the cascade."
4. **Trainer (`trainer/`): stage the cascade.**
   - **Phase L:** train the L-atom alone (frozen A,B = 0). Objective = OT/recon (no
     GAN). Gate vs **Lloyd-Max** (the real ceiling). This is the current
     `train_look_net_mlx.py` minus the discriminator, plus `lloyd_max_l()`.
   - **Phase A, Phase B:** freeze L, train the chroma atoms as residual deviations.
     Objective = recon(`H_asym`) + Ou–Luo + optional image-space GAN.
   - **Phase unify/QD:** the gallery (later).
   Two-phase "pretrain base, then add adversary" is exactly the stabilization
   PaletteNet found necessary — here it falls out of the cascade for free.
5. **Index map stays deterministic argmin (LAB-hierarchy weighted), grounded by L.**

---

## 6. Open design questions (flagged, not yet decided)
1. **Leaf count vs σ-pairing — DECIDED (user, 2026-05-30): 128 σ-pairs (the leaf
   structure is a FEATURE).** The palette is 128 complementary harmonies; L provides
   128 tonal anchors, A/B the complementary spread (§2 table, §3.2). The "256
   independent leaves" alternative is rejected. This makes the depth-7 symmetric-
   eigenspace L head principled *and* makes the σ-pair the user-facing authoring unit
   (a pinnable colour + its complement). No longer open.
2. **A ⊥ B?** L⊥{A,B} is exact (sym vs asym). Whether A (red-green) and B
   (blue-yellow) should be mutually orthogonal residuals (independent atoms) or B
   should condition on A (`B(A(·))` truly nested, chroma-chroma coupling) is a real
   choice — the WCS opponent structure suggests they're *separate* opponent channels
   (independent), but Ou–Luo harmony couples them. Resolve with the chroma research
   when M-A/M-B start.
3. **Shared vs per-axis recursion `R`.** This doc shares one MoR block across atoms
   (cheap, unified). If chroma needs deeper per-axis compute, `R` could fork per atom
   at a param cost. Measure when chroma lands.
4. **Halting target.** Still the rate-distortion knee (research doc §3.4); per-atom or
   global? Likely global (one complexity budget for the look), per-atom truncation as
   a steering dial.
```
