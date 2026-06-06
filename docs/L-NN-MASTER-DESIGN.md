> **Status/built-state:** see [docs/STATUS.md](STATUS.md) (canonical, gated by `scripts/verify-doc-claims.sh`). This document is design rationale, not a status ledger.

# The L→A→B Look-NN — Authoritative Master Design

**Status of record: 2026-05-30. This document supersedes and reconciles**
`docs/archive/L-NN-RESEARCH-AND-WORKFLOW.md`, `docs/archive/L-NN-ATOM-DESIGN.md`,
`docs/archive/L-NN-PRODUCT-ABSTRACTION.md`, and `docs/archive/PALETTE-LOOM-INTERACTION.md`
(all archived 2026-06-05). The forward direction is `docs/GIFA-GIFB-COLLAPSE-REDESIGN.md`. It is
built on the landed keystone `spec/src/SixFour/Spec/Obfuscation.hs`
(BLEED_LOOP Def 45–47, Thm 14) and the BLEED_LOOP module map. Where the older docs
disagree, **this doc is the record**; the supersession map in §6 is the cleanup.

> **Reading discipline.** Five independent formalizations of this reconfiguration were
> adversarially verified; all five returned REVISE on the *same* three over-claims.
> Those corrections are baked in here and called out where they bite:
> 1. L/A/B are an **orthogonal eigenspace sum**, not a forced composition — the L→A→B
>    order is a *default authoring discipline*, mathematically reversible, **not** a
>    "you cannot evaluate B before A" necessity.
> 2. The **256-vs-128** question is a genuine deployed-head **fork the user must
>    decide** (§8), not a resolution that the three-step frame closes by fiat.
> 3. The real resolution funnel is **palette ↔ histogram ↔ voxel**, NOT
>    `2⁸ ↔ 4⁴ ↔ 16²` (those are three re-groupings of one 256-set, all the same
>    cardinality). The cross-resolution claim (`Bottleneck16` ↔ palette) is an
>    **unproven lemma that must be pinned** before the funnel leans on it
>    (`BLEED_LOOP.md` line 212).

---

## 1. Form follows function (the thesis)

There is **one algebraic object**, read four ways. The chroma involution
`σ(L,a,b)=(L,−a,−b)` splits OKLab orthogonally into `V₊` — the grey `L` axis
(`axisSigmaSign AxisL = +1`) — and `V₋` — the `(a,b)` chroma plane (sign `−1`). The
look-net `B(A(L))` writes **L into `V₊` only** and **A, B into `V₋` only**: `L`
emits the 128 tonal anchors `mᵢ=(Lᵢ,0,0)`, `A` emits the red-green component of the
spread `δᵢ`, `B` the blue-yellow component, so each colour leaf is
`cᵢ = mᵢ ± βᵢδᵢ` with `δᵢ=(0,aᵢ,bᵢ)`. Because `V₊ ⊥ V₋` and chroma provably never
moves tone (`Thm 16`), these three writes **commute and are independently reversible**
— which is exactly why the *authoring* is three ordered steps L→A→B, each surfacing a
256-cell (16×16) palette + a GIF: the net layer that writes an eigenspace **is** the
step that authors it **is** the reveal `βₜ` that un-hides it (`BLEED_LOOP` Def 48).
The "256 shapes" (`16²=4⁴=2⁸`) are three navigation **lenses on that one 256-set
palette**, not three resolutions; the genuine **resolution funnel** (`64³ ↔ 16³ ↔
256³`) is an orthogonal *render-pitch* dial over the OKLab **distribution**
(`Bottleneck16.Histogram4096`), under which the 256-leaf palette is invariant. Net
structure = authoring flow = eigenspace decomposition = reveal family: **one
structure, four readings** — the surfacing (palette + GIF per step) and the funnel
(where you render it) are the *honest second and third dimensions* of that object, not
three more things bolted on.

---

## 2. The steps

> **UPDATE 2026-05-30 (§8 #1 RESOLVED → COUPLED 2-D):** the chroma research collapsed
> Steps 2–3 (A red-green, B blue-yellow) into **ONE 2-D chroma step** (a single a-b disc)
> — chroma is not separable for authoring/generation, and `V₋` is one 2-D eigenspace. The
> honest flow is **TWO steps: L (1-D tone) → a 2-D chroma disc**, matching the two OKLab
> eigenspaces. The Step-2 / Step-3 text below is kept as the *internal* `a`/`b` structure
> of the joint chroma head, **not** two separate user acts. Read "the user authors the
> a-b spread `δᵢ=(0,aᵢ,bᵢ)` as one disc act," with `A` and `B` as the two coordinates of
> that one act (jointly generated, non-diagonal covariance). See §8 #1.

The instrument is **one loom**: **Step 1 = L (tone)**, then **Step 2 = the 2-D chroma
disc** (the `(a,b)` spread authored jointly). Each step = author into
one OKLab eigenspace = evaluate one atom of `look = B ∘ A ∘ L` = surface a 256-cell
(16×16) palette + a 64³ GIF. **The net layer IS the step.** The ordering is the
default discipline (tone first, grounded by `L52.8` tonal separability); back-navigation
is *safe and free* because `V₊ ⊥ V₋` — editing `L` re-grounds the anchors, and the
banked `A,B` deviations `δᵢ` (in the retained store `𝔡`) re-attach at each anchor's own
`Lᵢ` via the **residual write `R`** (`cᵢ = mᵢ + βᵢδᵢ`), **never** `projectAxis AxisA/B`
(which resets `L→0.5`; see the trap in §7). This is *not* a "you cannot evaluate B
before A" claim — the anti-automation guarantee comes from the loom's hand-fold verb
and `L52.10` (the scaffold returns only a dismissible suggestion + an admissibility
predicate), not from a false irreversibility.

### Step 1 — L (grayscale base) · `σ`-symmetric, `+1` · **ships today**
- **NN layer generates:** the L-atom pools the 64 per-frame palettes
  (permutation-invariant `64→1`) into the global grey skeleton and emits the tonal
  anchors `mᵢ=(Lᵢ,0,0) ∈ V₊` (`SigmaDecomp.symPart` of the pool). Rendered at `β=0`,
  i.e. `shown = projectAxis AxisL` leafwise (`Obfuscation.shown`, `Thm 14` / `L45.1`).
- **User CHOOSES:** the tonal posterization — climbs the L Haar / Lloyd-Max merge
  tree by taste (MERGE = `Ω` at `β=0`: `m=(c₀+c₁)/2`, retain `d`; SPLIT = `Ω⁻¹`).
  The deterministic argmin index map is walled off (single right answer).
- **Surfaced:** a 16×16=256 grid + a **grayscale 64³ GIF**. *Honest cardinality:* at
  `β=0` the 256 leaf slots carry only the **distinct grey anchors** (each grey is its
  own σ-mirror, `L45.6` / `Thm 18` collapse). Whether the grid shows N distinct greys
  with duplicated slots (depth-7/128 head) or 256 distinct L tones (depth-8/256 head)
  is the **§8 deployed-head fork** — surface it, do not hide it behind a fake "anchor +
  mirror = 2 cells."
- **Control:** the active hand-merge loom (Tonal Loom). The `E[d]` complexity readout
  is a **dismissible hint only**, never an auto-fold.
- **Commit:** skeleton `{mᵢ}` frozen; chroma reservoir `𝔡` banked (retained, not
  deleted — `Thm 14`).

### Step 2 — A (red-green) · `σ`-antisymmetric, `−1` · gated
- **NN layer generates:** the A-atom emits `aᵢ` into `V₋` via the residual write `R`:
  `cᵢ = mᵢ + βᵢ(0,aᵢ,0)`. By `L53.2` it cannot move `mᵢ`.
- **User CHOOSES:** steers the red-green spread on an `a`-disc as the bleed `βₜ`
  (Def 48) opens the a-axis from `β=0`. The σ-mirror is a **free fixed operator**
  (`sigmaSwapAndReflect`), never authored by the net. Waterfilling (Def 52) =
  dismissible suggestion.
- **Surfaced:** the *same* 16×16 grid, anchors now flanking to `mᵢ ± βᵢδᵢ`, + a
  `+A` GIF (grey base with red-green bled in).
- **Control:** the a-spread loom (the Sigma-Pair Loom's a-axis).

### Step 3 — B (blue-yellow) · `σ`-antisymmetric, `−1` · gated
- **NN layer generates:** the B-atom emits `bᵢ`, completing `δᵢ=(0,aᵢ,bᵢ)`; same
  residual write, still tone-invariant.
- **User CHOOSES:** steers the blue-yellow spread; `β` opens the b-axis to full colour.
- **Surfaced:** the same grid as **full-colour σ-pairs** + the **final 256-cell
  palette and final 64³ GIF**.
- **Control:** the b-spread loom.
- **Open (carry):** whether B nests on A (`B(A(·))`, Ou–Luo coupling ⇒ Step-3's disc
  shows A as fixed context) or A⊥B (WCS opponent ⇒ steps commute) is **undecided**
  (`BLEED_LOOP` G3 / ATOM Q2) — resolve from chroma research, not by fiat
  (`feedback_categories_from_research`). See §8.

---

## 3. The 256 shapes

`256 = 16² = 4⁴ = 2⁸ = 256 SIMD lanes = the 64³ global-palette voxel target`. **These
are NOT a resolution funnel** — all four factorizations have exactly 256 leaves; they
are three re-groupings (navigation lenses) of the *one* 256-cell palette, available in
**any** step (they are not per-step exclusive shapes). The resolved meaning of each:

| Shape | Reading | Role in the loom |
|---|---|---|
| **`16²` flat** | 256 loose cells, sorted dark→light | the **mat** — the raw 16×16 authoring face the user reads before folding; the literal grid surfaced at every step. |
| **`2⁸` binary spine** | balanced Haar cascade, parent nested above its two children | the **gesture grammar** — one `2→1` fold at a time (`m=½(c₀+c₁)`, retain `d`); the merge/split verb's math (Haar synthesis), shared by all three steps. `256→128` is the **first rung UP** this tree, not a terminal. |
| **`4⁴` quadtree** | 2×2 super-cells coarsen in powers of 4 (256→64→16→4→1) | the **zoom/posterization lens** — how chunky the current fold depth reads; a navigation regroup of the binary tree, **no new DOF** (a `quadView` law, not a step-shape and not a resolution level). |

**128 σ-pairs** is the σ-reflection structure *imposed within* the 256-grid once
chroma is present (each pair = anchor `mᵢ` + complementary spread, `reconstructPaired`).
It is one binary rung up from the 256 leaves — **not** a competitor to 256 and **not**
a quadtree level (`128 ∉ {4ᵏ}`). The 256-grid is the authoring surface; the 128-pair
structure is the σ-geometry on it (§8 keeps both via the funnel, does not reject 256).

---

## 4. The resolution funnel

The funnel is a single axis: **render/measurement PITCH over the OKLab distribution**,
orthogonal to the L/A/B eigenspace axis. It is `64³ ↔ 16³ ↔ 256³` over the
**distribution**, *not* a walk among the §3 256-faces.

- **`16³` = `Bottleneck16.Histogram4096`** (16 bins/axis, 4096 bins): the funnel floor
  = the scene-input distribution the NN already funnels to (`SigmaDecomp` operates here;
  `histogramFromOKLabs` builds it). Authoring can *steer* at this pitch.
- **`64³` = the live GIF** (Coverage isotropic): the create-resolution, what ships.
- **`256³` = optional deep export** (16.7M voxels = 64× the 64³ count): **aspirational**
  — pending an on-device memory/time measurement on iPhone 17 Pro. Not a free re-render.

**Down/up maps** are exact dyadic bit-shifts on the `okLabBin` grid (verified: `okLabBin`
is `floor(v·n)` for L and `floor((v+½)·n)` for a,b, with `n` a power of two, so
`coarsenBin (iL,ia,ib) = (iL≫1, ia≫1, ib≫1)` and refine compose to identity on the coarse
representative). This is a pure resolution pyramid of the *distribution*.

**Palette invariance — scoped to PITCH, not to bleed.** The 256-leaf palette is an
argmin over a fixed codebook; it is invariant across render pitch `p ∈ {64,256}` — the
GIF voxel count changes, the palette does not. **It is NOT β-invariant**: per `Thm 18`,
revealing chroma re-indexes pixels at Voronoi near-ties (`2·maxᵢ βᵢ‖δᵢ‖ < γ_pix` is the
stability condition; strict invariance is provably false). State invariance over pitch,
stability-up-to-`γ_pix` over `β`.

**The numerology, honestly.** `256` colours = the palette leaf count (a `16×16`
authoring face). `4096` bins = `16³` = the histogram, a *different object* (a probability
simplex over the gamut), NOT a "face of the palette." `64³ / 256³` = voxel render counts.
The "palette-128-split ↔ histogram-4096-split are the same σ-eigenspaces at different
resolution" claim (`BLEED_LOOP §5`, line 212) is the **commuting-square LEMMA that must
be PINNED** (a golden + QuickCheck law) before the funnel may reuse `Bottleneck16` as an
*authoring* substrate. **Until pinned, the funnel is purely a GIF render-pitch control
over the fixed 256-leaf palette** — which is sound and needs no new representation.

```
              RESOLUTION FUNNEL  (render/measurement pitch over the DISTRIBUTION)
              ──────────────────────────────────────────────────────────────────
                          ↑ refine (bit-shift, dyadic-exact)
                          │
     256³  deep export ───┤   16.7M voxels · ASPIRATIONAL (device measure first)
                          │
      64³  live GIF    ───┤   the create-resolution · SHIPS · Coverage isotropic
                          │
      16³  Bottleneck16 ──┘   4096-bin histogram · the funnel floor / scene substrate
                          ↓ coarsen (bit-shift)        (authoring reuse GATED on the
                                                        §5 commuting-square lemma)

   INVARIANT across pitch:  the 256-leaf PALETTE  (argmin over a fixed codebook)
   NOT invariant across β:  the index map  (Thm 18 stability, margin γ_pix)

   ┌─────────────────────────────────────────────────────────────────────────┐
   │  ORTHOGONAL to the funnel — the L→A→B EIGENSPACE axis (the three steps):  │
   │     L (V₊, grey)  ──►  A (V₋, red-green)  ──►  B (V₋, blue-yellow)        │
   │  each step renders its 256-cell palette + GIF at whatever funnel pitch    │
   │  is selected.  256 = 16² = 4⁴ = 2⁸  are LENSES on the 256-set, not pitch. │
   └─────────────────────────────────────────────────────────────────────────┘
```

---

## 5. GIF at every step

Each step emits a GIF — `L` (grey base) → `+A` (red-green bled in) → `+B` (full
colour). These are **three evaluations of one bleed field `βₜ`** (Def 48), never three
pipelines: `β=0` renders Step-L's pure grey (`L45.1`); raising `β` on the a-channel
renders `+A`; full `β` renders `+B`. Because `A,B` write only `V₋` and `L` lives in `V₊`
(`Thm 16`, tone-invariance `L48.2`), **the grey skeleton the user authored at Step L is
visibly unchanged across Steps 2–3** — the user *feels* the orthogonality as "my tone is
safe."

Each step is therefore a **rewarding, complete artifact**: a shareable grayscale GIF
after Step L, a richer `+A` GIF after Step A, the final full-colour GIF after Step B.
Progress is monotone and non-destructive — every commit adds colour without risking the
work already done — which is what *inclines* the user to keep folding (the
"seductive loop" of `Thm 17`: each iterate invites the next; the only fixed point is
degenerate full-reveal + the user has stopped). The bleed `βₜ` is the across-step
progression; the loom merge/split is the within-step verb; the emitted GIF is the
conditioning channel into the next atom's scaffold (Def 54).

*(Open product decision: are all three GIFs first-class exports, or are `L`/`+A`
previews and only `+B` the product? See §8.)*

---

## 6. Supersession map

The cleanup of record. KEEP = unchanged and load-bearing; REVISE = survives in a
restated form; RETIRE = dropped.

| OLD relationship (source) | Status | Replaced by |
|---|---|---|
| **L is a standalone grayscale model** ("separate depth-8 hack"; RESEARCH §0/§2) | REVISE | `L` is the innermost atom `B(A(L))` and **Step 1 of 3** — the first authored step, not a product. RESEARCH's verdicts (deterministic argmin, Lloyd-Max ceiling, OT-not-GAN) are KEEP. |
| **Deployed L head emits PURE GREY** (a=b=0, chroma discarded) | REVISE | Chroma-**retaining** L: still SHOWS grey at `β=0` (`Ω`), but BANKS `R c=(0,a,b)` so Steps A/B reveal it (`Thm 14`, `Ω⁻¹∘Ω=id`). The discard contradicts the keystone; the head must carry the retained chroma. (BLEED_LOOP G5/G7.) |
| **Authoring = a single 16×16 hand-merge loom** (PALETTE-LOOM §1–6) | REVISE | One loom, **three steps** (L tonal / A red-green / B blue-yellow), each a 256-palette + GIF. The MERGE-as-Haar verb (`m=½(c₀+c₁)`, retain `d`) is KEEP as the *within-step* verb. |
| **Passive 5-layer slider/chip UI** (before/after toggle, "Look Richness" slider, DR/grey chips, `E[d]` readout; PRODUCT §2/§4) | RETIRE | Active per-step authoring (the loom). KEEP only PRODUCT's **construct↔user-meaning traceability table** (re-cut to 3 steps + the funnel dial). |
| **Maya user story** (one before/after toggle + one richness slider, chroma "coming later"; PRODUCT §4) | RETIRE | A three-step narrative: the user CHOOSES a grey base (Step L, 256-palette+GIF), then red-green (Step A), then blue-yellow (Step B). The old single-slider story is contradicted, not restated. |
| **Phase gate: A/B chroma is FUTURE / deferred** (only L shippable) | REVISE | A/B are **Steps 2 and 3 of the core flow** (form-follows-function), designed in now. Build-order may still ship L's surface first (an implementation lag), but the *design* treats A/B as present steps. |
| **"Merge toward grey reveals the complement" is VACUOUS** (Phase L) | REVISE | Vacuous *only* under pure-grey L. With chroma retained (`R c=(0,a,b)` banked), the complement is present from Step 1, merely HIDDEN, revealed at A/B (`βₜ`). Survives only as the narrow law `L45.6` (a=b=0 ⇒ R c=0), not as a product statement. |
| **depth-8/256 vs depth-7/128 "reconciled by phase"** (256=Phase-L, 128=Phase-A/B) | REVISE | A genuine **deployed-head fork the user must decide** (§8). 256 = the grid/leaf cardinality (the flat authoring face, every step); 128 = the σ-pair authoring unit; both are real. **Do NOT claim it is decisively resolved.** |
| **Index map: "L grounds, A/B never re-index"** (strict invariance; ATOM §3.2/§5.5) | REVISE | `Thm 18` **tonal-grounding STABILITY** (not invariance): A,B re-index only at quantified near-ties (`2·maxᵢ βᵢ‖δᵢ‖ < γ_pix`). The argmin + Lloyd-Max ceiling are KEEP. |
| **`[4,2,1]` L≻a≻b weighted metric** (ATOM §3.2 / PRODUCT §1) | RETIRE | `PairTree` landed plain Euclidean (`okLabDistanceSquared`); the `[4,2,1]` weighting is gone. The index claim weakens to `Thm 18` β-stability. |
| **Two scale-axes: axis (L→A→B) + Haar "Look Richness" slider** (ATOM §4; PRODUCT Layer 2) | REVISE | The **L→A→B axis** is the primary three-step spine. The Haar/quadtree "richness" survives as a *within-step* posterization lens (the `4⁴` face), authored by hand-folds, **not** a passive slider; `E[d]` stays a dismissible hint. |
| **"128 σ-pairs is a FEATURE, 256 leaves REJECTED"** (ATOM §2/§6.1) | REVISE | 256-grid (`16²`, the authored surface) and 128 σ-pairs (the σ-structure on it) are **both kept** — different readings, not one rejected for the other. The three-step vision *requires* a 256-cell grid per step. |
| **"L emits 256 DISTINCT L levels via depth-8"** (ATOM §3.2 — contradicts §2/§6.1) | RETIRE | The internal `256-distinct-L` claim is dropped as a *design claim*; whether the deployed head is depth-8/256 or depth-7/128 is the §8 fork, framed by the funnel (256-cell grid, σ-pair structure within). |
| **`2⁸ → 4⁴ → 16²` is a resolution funnel** (proposed) | RETIRE | False — all three are 256-cardinality re-groupings of one set (§3). The genuine funnel is **palette ↔ histogram(16³) ↔ voxel(64³/256³)** (§4). |
| **Obfuscation `Thm 14` / `L45.1` (shown = `projectAxis AxisL`)** | KEEP | The keystone. Step-L's renderer; untouched. `symPart` stays the scene ceiling (Def 55) only, never the obfuscation operator. |
| **Deterministic argmin index map; "user does the work / NN scaffolds"** | KEEP | Across all three steps. Index map walled off; `L52.10` scaffold-not-automator; `Thm 16` only the user's fold moves the skeleton. |

---

## 7. What the spec/atoms must become

Smallest-diff, contract-first, **extends the keystone, never contradicts it**.

**1 — Chroma-retaining L head (the single biggest break, BLEED_LOOP G5/G7).** Today's
deployed head emits `(Lᵢ,0,0)` and discards chroma; the spec's `Ω` *banks* it. The head
must SHOW grey at `β=0` but carry the retained `δᵢ` so Steps A/B can reveal them.
Concretely: deploy the **factored decoder with β-gating**, not a grey-only blob.
`Obfuscation.shown` is unchanged (`Thm 14`/`L45.1` intact); the chroma simply stops being
thrown away.

**2 — Factor `LookNetD`'s 384-DOF σ-pair blob into `D_L ⊕ D_AB`** (ATOM §5.2, revised by
§8 #1): `D_L` (`V₊`, the 128 L-anchors `mᵢ`) and `D_AB` — **one JOINT 2-D chroma head**
emitting the `V₋` spread `δᵢ=(0,aᵢ,bᵢ)` with a **non-diagonal (block-triangular or
full-2-D) covariance**, **not** two independent `D_A`, `D_B` heads (chroma research
RESOLVED: the cardinal a,b axes are correlated and hue is the joint variable). Three
laws to pin:
- **no-drift golden:** `concat(D_L, D_A, D_B) == existing 384 coeffs`;
- **grounding:** `symPart (look x) == L x` (chroma cannot move the grey skeleton);
- **purity:** `asymPart (L x) == 0` (L is pure grey).
These three make "three-step authoring = net layering" true. **Wire the
`SigmaPairHead` 384-DOF pivot** (un-wired per `NOTES.md`) — the blocking dependency for
Steps 2–3.

**3 — Promote `AxisNet` from post-hoc projection to generative atom (`AtomNet`)**
(ATOM §5.1), so `D_A/D_B` are atoms, not projections. **KEEP `projectAxis AxisL`** as the
Step-1 / `β=0` renderer. **Critical trap:** the A/B heads MUST write via the residual `R`
(`cᵢ = mᵢ + βᵢδᵢ`), **NOT** `projectAxis AxisA/B` — verified in `AxisNet.hs:108–109`,
those reset `L→0.5`. Pin a regression law: head output preserves each anchor's `Lᵢ`.

**4 — Land the BLEED_LOOP reveal modules** (the A/B step operators; currently only the
`Obfuscation` keystone exists on disk):
- `Spec/ColorBleed.hs` — `βₜ` (Def 48) + the bleed field `B_β` (Def 49) + `L48.*`. The
  three steps reveal a then b; extend the per-leaf scalar field to a **per-(leaf,channel)**
  field `β: Index×{A,B}→[0,1]` so Step A = `(t_A,0)`, Step B = `(1,1)`. This is a typed
  extension with re-proven laws (`L48.4` semigroup → product monoid; `L48.6` σ-equivariance
  holds; `L52.9` σ-mirror survives), **not** "no new numerics."
- `Spec/Reference.hs` — Def 54–55 (`asymPart(H_ref)` conditioning + scene ceiling).
- `Spec/ChromaAllocation.hs`, `Spec/Bleed.hs`, `Spec/BleedLoop.hs`, `Spec/Incitement.hs`
  stay contract-first/heuristic until real telemetry exists (`feedback_dither_abstraction`:
  capture before theorizing the conditioning functional).

**5 — `Bottleneck16` as the funnel hinge.** Re-role from "scene-affordance diagnostic"
to the funnel's `16³` floor. Add `coarsenBin`/`refineBin` dyadic maps + the law
`binsPerAxisAtPitch Author16 == numBinsPerAxis`. **Pin the §5 commuting-square lemma**
(`Π_grey ∘ leaves == leaves ∘ perPairAnchor`, BLEED_LOOP line 212) as a golden +
QuickCheck law **before** authoring reuses the histogram. Until pinned, the funnel is a
render-pitch control only (§4). Keep `Histogram4096` (the simplex) and the 256-leaf
palette as **distinct objects** — do NOT add a "grid = histogram face" map.

**6 — Golden vectors ADD, never replace.** Keep the existing scalar `β∈{0,½,1}` goldens
(they pin `L48.3` monotone + `L48.5` affine-in-t). ADD per-channel goldens at the three
checkpoints `β∈{(0,0),(t_A,0),(1,1)}` + a b-only cut to pin channel independence. Exclude
the `T_t` bookkeeping path (Def 50b) from rendered-GIF goldens.

**What retires from the spec/UI:** the passive slider/chip surfaces (segmented toggle,
"Look Richness" slider as the primary verb); the `[4,2,1]` weighted metric; any kernel
that maps `256 → final palette in one call` (anti-automation is a build constraint —
`n→1` lasso compiles to a replayable sequence of `2→1` synthesis calls).

---

## 8. Open decisions for the user

Genuine forks — carry them, do not pretend resolved.

1. **A ⊥ B vs A-coupled-B — RESOLVED 2026-05-30 (chroma-research workflow): COUPLED 2-D.**
   The chroma channels are **not** separable for generation/authoring → the honest flow is
   **TWO steps (L → one 2-D a-b chroma disc), not three (L→A→B)**, and the decoder models
   chroma **jointly** (block-triangular `B(A(·))` or full-2-D, **non-diagonal `V₋`
   covariance** — *not* a `D_A ⊕ D_B` direct sum). Evidence (medium confidence):
   - **The cardinal a,b axes are NOT decorrelated in natural images** — red-green (L-M) and
     blue-yellow (S) are *negatively correlated*; decorrelation needs a rotation *off* the
     cardinal axes, so a chroma prior in the a,b basis has off-diagonal covariance and a
     block-diagonal `D_A ⊕ D_B` mis-specifies it (Lee-Wachtler-Sejnowski 2002; Ruderman-
     Cronin-Chiao 1998; CIELAB a*/b* replication PMC9418166).
   - **The aesthetic/categorical variable is HUE = the joint a-b angle**, not a and b
     separately (colour harmony, WCS hue-circle categories) → two independent 1-D channels
     are perceptually unnatural.
   - **Cardinal independence is real but narrowly scoped** — Krauskopf-Williams-Heeley 1982
     habituation separability holds only at the *threshold* stage and on a *tritanopic
     S-cone* axis that does **not** coincide with the Hurvich-Jameson colour-*appearance*
     axes the model authors in; it does not govern generation or aesthetics.
   - **σ-consistency:** σ already negates the `(a,b)` plane *as one unit*; `V₋` is a 2-D
     eigenspace. Two steps = two eigenspaces (`V₊` 1-D tone, `V₋` 2-D chroma) is *more*
     form-follows-function than the three-step cut, which split `V₋` artificially.
   - **Confidence caveat (medium):** the vision-science (cardinal-axis correlation + scoped
     independence) is high-confidence; the **hue/harmony + neural-generator-practice legs
     were reasoned, not citation-confirmed** in this batch, and the **magnitude** (full-2-D
     vs merely block-triangular) + the **OKLab-specific rotation angle** are still open. If
     you want this firmed to high confidence before wiring the decoder, run a focused
     harmony/WCS + generator-practice verification (see the open sub-questions).

   **Program impact:** §2 collapses to two steps; §7 item 2 changes `D_L ⊕ D_A ⊕ D_B` →
   `D_L ⊕ D_AB` (one joint chroma head); the per-channel bleed field (§7 item 4) becomes a
   2-D `β: Index → [0,1]²` (or scalar over the disc radius), authored as one act.

2. **Deployed-head fork: depth-8/256 vs depth-7/128.** EITHER ship the depth-8 256-distinct-L
   head as Step 1 (richer tone, 256 distinct greys, σ-pairing deferred to a re-pairing
   pass) OR adopt the depth-7 128-anchor head (128 distinct greys, σ-structure native,
   Steps 2–3 plug in directly). These are two different **grey resolutions**, not orthogonal
   axes — one of them is the Step-1 palette. A documented fork, not a fake reconciliation.

3. **Funnel up-target: 64³ vs 256³.** `64³` is the create-resolution and ships. Is `256³`
   a real deep-export path or aspirational? The 256-leaf palette is pitch-invariant (cheap),
   but the `256³` GIF render is 64× the voxel count — **measure on iPhone 17 Pro** before
   promising it.

4. **Step-back semantics.** Does committing a step lock it, or can the user pop back
   (Step 3 → re-edit Step 1)? Orthogonality makes free 3-axis editing *safe* (A,B never
   touch L), so free editing is admissible — but it weakens the "ordered nesting = forced
   work" story. Pick: free-order safe editing, or default-ordered with explicit re-grounding.

5. **`β` semantics.** Single scalar the user crosses, per-pair waterfilling, or auto-full at
   step entry? Needs real loop telemetry before fixing the functional
   (`feedback_dither_abstraction`: capture first, do not theorize `β_{k+1}` from the
   reference).

6. **Three shareable GIFs, or final-only.** Are L / +A / +B all first-class exports (three
   artifacts per session), or are L/+A previews and only +B the product? The "each step is
   a rewarding artifact" vision implies three real exports; confirm.

7. **Per-step funnel pitch.** Author all three steps at `16³`, or finer for chroma (16 a/b
   bins may be too coarse for Ou–Luo spread while 16 L levels suffice)? Tied to (3) and (5);
   capture telemetry first.
