> **⚠ SUPERSEDED (2026-05-30) by [`L-NN-MASTER-DESIGN.md`](../L-NN-MASTER-DESIGN.md), the design of record.**
> The **construct↔user-meaning traceability table (§3) survives** (re-cut to three steps + the funnel).
> RETIRED: the passive slider/chip UI (Layers 1–2) and the single-slider "Maya" story — replaced by the
> active three-step L→A→B authoring. See the master §6 supersession map.

# B(A(L)): A Palette-Authoring Instrument — Design Abstraction

*SixFour look-NN · authoritative user-meaning ↔ construct mapping · 2026-05-30*

> Produced by the `lnn-abstraction-to-userstory` workflow (5 facets decomposed →
> adversarially verified → 3 personas → synthesis). All 5 affordances survived
> verification (verdict REVISE, none CUT). Honors the 2026-05-30 "leaf structure is
> a feature" decision (128 σ-pairs / depth-7). Sister docs: `L-NN-ATOM-DESIGN.md`
> (the cascade), `L-NN-RESEARCH-AND-WORKFLOW.md` (research constraints),
> `HANDOFF-LNN-app-io-and-ui.md` (the UI seams).

---

## 1. The product thesis

`B(A(L(·)))` is not a quantizer — it is a **palette-authoring instrument**. The
64-frame burst is the raw material; the network's job is to hand the creator a
single, coherent **global color palette they author and own**, not one a quantizer
picked. The instrument is built from one idea: the chroma involution
`σ(L,a,b)=(L,−a,−b)` splits OKLab into orthogonal eigenspaces, so a color and its
complement `{c, σc}` decompose as `c=m+d`, `σc=m−d` with `m=(L,0,0)` a pure-grey
**tonal anchor** and `d=(0,a,b)` a pure **chroma deviation**. The L atom is the
σ-symmetric nucleus that emits the **128 tonal anchors**; the A and B atoms are the
σ-antisymmetric wrappers that emit each anchor's complementary spread. The leaf
structure is therefore **128 complementary harmonies — a color and its exact
opposite balanced around a shared tone — and this is a FEATURE, the authoring
grammar itself** (ATOM §6.1, user decision 2026-05-30). The creator does not paint
256 independent cells; they compose a *chord* of complementary pairs across a tonal
skeleton. The honest division of labor makes this safe: L owns the one thing with a
single right answer (fidelity — the Lloyd-Max ceiling, deterministic argmin index
map), which frees every *creative* degree of freedom — tonal richness, temperament,
harmonic spread — to be the user's to author.

---

## 2. The abstraction layers

Ordered by **authoring sequence** — tone is the ground everything else stands on, so
the creator authors L first.

### Layer 1 — Tonal Foundation *(the L atom · σ-symmetric, +1)*

- **What the user thinks:** "This is the *mood and grey bones* of my look. How
  low-key or luminous, how wide the tonal range breathes from black to white, where
  the grey midpoint sits. Everything else hangs off this."
- **What they do:** Flip the **before/after toggle** to watch the 64-frame burst
  collapse into ONE coherent tonal grade — the look the *whole burst* chose, not 64
  frames each grading themselves. Read the look's tonal identity off the chips:
  dynamic-range span `[Lmin,Lmax]` and grey midpoint. Confirm the collapse is the
  tonality they wanted.
- **Control surface:** `before/after` segmented control over `GIFCanvas`;
  `PaletteStripView` (static mode = the one grey skeleton) beside animated mode (the
  64 it replaced); the `dynamicRangeOf` / `greyOf` chips. *(HANDOFF §2a — no new
  widgets.)*
- **Construct underneath:** The L atom reads the 22 achromatic hidden dims, grounds
  the 64→1 pool (σ-symmetric projection of the population-weighted token pool), emits
  the **128 tonal anchors** `m_i=(L_i,0,0)` via a depth-7 scalar Haar, and owns the
  deterministic per-pixel **argmin index map** under the `L≻a≻b [4,2,1]` hierarchy.
  The user reads tonal identity and never touches the index map (it has a single
  right answer — grounded by L).

### Layer 2 — Broad-to-Fine Richness *(the Haar pyramid + PonderNet halting)*

- **What the user thinks:** "A *zoom level* for my look. Coarse = a few bold
  posterized tonal bands; fine = the full set of tonal anchors. The network can
  suggest how rich this scene wants to be, but the call is mine."
- **What they do:** Drag the **Complexity Budget / "Look Richness"** slider from
  POSTERIZED toward RICH. The L atom's Haar/halting depth truncates at inference
  (`~2^d` anchors, no retrain) and the palette strip **re-quantizes live**. The
  slider defaults to the network's own `E[d]` ("look complexity") readout — the depth
  it actually sized this scene to — which the creator can pull coarser or push
  fuller. Purely aesthetic: at full depth L already sits at the Lloyd-Max ceiling, so
  coarsening only changes the *look*, never the fidelity.
- **Control surface:** `LookConfig.complexityBudget` slider in the SettingsView
  "Look" section; the `E[d]` readout in `GIFReviewView` as the default anchor;
  live-re-quantizing static `PaletteStripView`. *(HANDOFF §2a/§2b verbatim.)*
- **Construct underneath:** Each retained Haar level adds finer L midpoints;
  truncating to depth `d` yields fewer tonal anchors — i.e. fewer, coarser
  complementary-harmony anchors *below* the full 128-anchor set. Halting is a
  decoupled **complexity readout, not a quality lever** (RESEARCH §1.4). The
  full-richness endpoint is **128 anchors / depth-7**, not 256.

### Layer 3 — Complementary Harmonies *(the 128 σ-pair leaf structure)*

- **What the user thinks:** "My palette is not 256 loose swatches — it is up to **128
  complementary harmonies**, each a color paired with its exact opposite around a
  shared tone. One harmonic decision, not two."
- **What they do (Phase L, today):** See the global palette rendered as **paired
  swatches** — each leaf above its σ-mirror — so the harmony structure is visible,
  not 256 cells. The tonal skeleton (the 128 anchors = pair midpoints) is what's
  authored today; the complement spread is grounded at zero until chroma lands.
- **What they do (Phase A/B, *future — not built*):** Once chroma deploys, each
  anchor becomes the midpoint `m` of a σ-pair `{m+d, m−d}` — a color and its **exact
  OKLab complement** (a guaranteed mirror by construction, not a soft prior). Pin a
  tonal anchor, then steer its spread on an a/b disc; the mirror moves
  equal-and-opposite automatically.
- **Control surface:** `PaletteStripView` static-global mode rendered as paired
  swatches; `LookConfig` threaded through `AppSettings` (mirroring `DitherConfig`),
  built so the chroma disc is later a *palette swap, not a redesign*.
- **Construct underneath:** The 256 leaves are **128 σ-pairs** `{c, σc}`, `c=m+d` /
  `σc=m−d` (ATOM §1.1, §6.1 — DECIDED). They are *not* independent: `c` and `σc` are
  bound by the involution, so authoring a pair's deviation `d` authors *both*
  members. The complement is a consequence, not a separate swatch.

### Layer 4 — Color Temperament *(the A and B atoms · σ-antisymmetric, −1) — FUTURE, not yet built*

- **What the user thinks:** "The *attitude* of my look — how warm or cool it runs (B
  blue-yellow), which way its accents lean (A red-green). Because every color is
  locked to its complement, warming a color cools its partner. One chromatic mood
  across the whole burst."
- **What they do:** *(Requires the M-A/M-B chroma atoms — HANDOFF §3 Q4, ATOM §5;
  SigmaPairHead 384-DOF still un-wired.)* Steer a warm/cool (B) and red-green (A) lean
  that biases the chroma the A/B atoms attach to each L level — never touching
  tonality, the index map, or fidelity (orthogonality guarantees L is untouched).
  Optionally adjust harmonic spread as **one** prior, not the sole chroma freedom
  (`A⊥B` vs `B|A` is deliberately open — ATOM §6 Q2).
- **Control surface:** An OKLab a/b pad + optional spread slider added to `LookConfig`
  alongside `complexityBudget`; results render through the *same* static
  `PaletteStripView` and before/after toggle, with the L chips shown **unchanged** to
  prove tone is untouched. *(Design-ahead-of-implementation — must be labeled as
  such.)*
- **Construct underneath:** A reads 21 red-green dims, B reads 21 blue-yellow dims
  (Hurvich–Jameson 22+21+21). They write only the σ-antisymmetric `d_i=(0,a_i,b_i)`.
  `symPart(look x)==L x` (chroma cannot move the grey skeleton) is the algebraic
  guarantee. Objective = reconstruction + **Ou–Luo relational beauty** + optional
  **image-space adversary** (never on the palette tensor).

### Layer 5 — One Look + Signature Gallery *(L-collapse + per-user MAP-Elites QD)*

- **What the user thinks:** "*One look, locked across the whole burst* — not 64 frames
  each grading themselves. And over time my keepers stack into a personal library of
  looks that are mine."
- **What they do (today):** Confirm the burst reads as one authored grade
  (before/after toggle + static palette strip), then enable the persisted **Look
  on/off** toggle. Keep the grade.
- **What they do (future, *design-only, deferred*):** Kept looks accumulate into a
  per-user MAP-Elites **gallery** the creator swipes / keeps / exports; their pick is
  the refinement signal. Explicitly *not shipped* as a present affordance.
- **Control surface:** `useLookNetPalette` persisted toggle; before/after over
  `GIFCanvas`; static-vs-animated `PaletteStripView`; (future) a keep/swipe/export
  shelf.
- **Construct underneath:** The L collapse + deterministic argmin hand the creator ONE
  grade over the whole burst (a coherence/authoring win, never higher fidelity — the
  L-MSE ceiling is Lloyd-Max, RESEARCH §0/§2). The gallery is QD diversity over the
  σ-antisymmetric A/B spread around **fixed** L-grounded anchors: each saved look is a
  different authoring of the 128 harmonies over one shared tonal skeleton.

---

## 3. Traceability table

| NN construct | σ-role | User meaning | User action | Control surface | Objective / GAN-scale |
|---|---|---|---|---|---|
| **L atom** — 22 achromatic dims → 128 tonal anchors `m_i=(L_i,0,0)` via depth-7 scalar Haar; grounds 64→1 collapse + argmin index map | σ-symmetric (+1) | Tonal foundation: mood, grey bones, dynamic range, key | Read tonal identity (`[Lmin,Lmax]`, grey midpoint); flip before/after to see the collapse | before/after toggle; static `PaletteStripView`; `dynamicRangeOf`/`greyOf` chips | OT/reconstruction + Bures anchor; **NO GAN** (Lloyd-Max = single right answer) |
| **Haar pyramid + PonderNet halting** — `[ctx₀..ctx₈]`, depth indexes pyramid scale | scale axis (within L) | Broad-to-fine richness: posterized ↔ rich "zoom level" | Drag Look Richness slider; override the `E[d]` default | `LookConfig.complexityBudget` slider; `E[d]` readout; live re-quantizing strip | Halting = decoupled **complexity readout**, not a quality lever |
| **128 σ-pair leaf structure** — `{c,σc}`, `c=m+d`, `σc=m−d`, complement exact by involution | sym ⊕ antisym decomposition | Complementary harmonies: a color *and its opposite*, one decision | (today) see paired swatches; (future) pin anchor + steer pair | paired-swatch `PaletteStripView`; `LookConfig` in `AppSettings` | symmetry prior on chroma deviations; harmony = the authoring unit |
| **A atom** — 21 red-green dims → `a_i` deviation *(future)* | σ-antisymmetric (−1) | Temperament: red-green accent lean | Steer A lean on a/b pad *(not built)* | OKLab a/b pad in `LookConfig`; L chips shown unchanged | reconstruction + **Ou–Luo beauty** + optional image-space adversary |
| **B atom** — 21 blue-yellow dims → `b_i` deviation *(future)* | σ-antisymmetric (−1) | Temperament: warm/cool lean | Steer B lean / harmonic spread on a/b pad *(not built)* | OKLab a/b pad + spread slider; before/after toggle | reconstruction + **Ou–Luo beauty** + optional image-space adversary |
| **L-collapse + per-user MAP-Elites gallery** — argmin index map + QD archive over A/B spread | grounding ⊕ QD over antisym | One look locked across the burst; a signature library | Enable persisted Look toggle, keep; (future) swipe/keep/export gallery | `useLookNetPalette` toggle; before/after; (future) keep/swipe shelf | **diversity / QD GAN** at the gallery scale (per-user reward) |

---

## 4. The user story

**Maya authors her global palette.**

Maya has a look in her head: low-key, smoky shadows with a recognizable cool-amber
split. She catches her roommate spinning a sparkler on the fire escape at dusk — the
warm-gold-against-blue moment her followers eat up. She opens SixFour, frames the
rain-lit alley, and holds the **shutter** — the app fires its **64-frame burst** in
one press. No menus; capture is the one decisive act.

She lands on the **Review screen**. The GIF loops, but the 64 per-frame grades flicker
and crawl — every frame negotiating its own colors. Beneath it she flips the
**before/after segmented control** over the `GIFCanvas`. *Snap:* the burst collapses
into ONE coherent grade, held to a single tonal skeleton — the **L atom's 64→1
collapse** made visible. In **`PaletteStripView` (static mode)** that one grey
skeleton sits beside the 64 animated per-frame palettes: "one look vs 64 frames."

She reads its bones off the **dynamic-range and grey-anchor chips** (`[Lmin,Lmax]` +
grey midpoint, `dynamicRangeOf`/`greyOf`) — confirming the burst collapsed into the
deep, narrow tonality *she* wanted, not one a quantizer guessed. The **`E[d]` "look
complexity" readout** tells her how many tonal anchors the scene actually asked for,
and the **Complexity Budget / "Look Richness" slider** (`LookConfig.complexityBudget`)
defaults right there. The sparkler scene reads moody, so she drags it **coarser**
toward posterized — and the palette strip **re-quantizes live** as the L atom's
Haar/halting depth truncates. No retrain, no fidelity loss: at full depth L already
sits at the **Lloyd-Max ceiling**, so coarsening is purely the graphic-vs-rich feel of
her grade. She settles two notches below the knee — bold, but breathing.

She flips the **Look on/off toggle** (`useLookNetPalette`) once more to confirm the
global look reads as one authored grade, then leaves it on — persisted. In the Look
panel, the σ-pair **temperament** and **harmony-spread** chroma controls (warming a
color while its complement cools, on an a/b disc) are flagged as **coming with the A/B
chroma phase** — not yet built; today's surface is L-only, and that's a palette swap
away. Satisfied, she keeps this grade; over time her keepers will stack into her
**per-user gallery of signature looks** (deferred, design-only). Export. Posted.

She has authored a tonal signature — not accepted a quantizer's.

**Job-to-be-done:** *Collapse my 64-frame burst into ONE coherent tonal look that I
authored and can make my signature — not a grade a quantizer picked for me.*

---

## 5. What the user NEVER sees

The instrument exposes **creator verbs** (set the tone, dial richness, pin a harmony,
lean warm/cool) and **read-only identity** (dynamic range, grey midpoint, look
complexity). Everything below the verb line stays hidden, on purpose:

- **The σ-eigenspace decomposition.** The user never sees "symmetric vs antisymmetric
  eigenspaces," `axisSigmaSign`, or `symPart`/`asymPart`. They experience its
  *consequence*: chroma edits can't wreck tone (orthogonality), so temperament feels
  safe.
- **Haar coefficients & the inverse-Haar lift.** The user sees a "Look Richness"
  slider, never `[ctx₀..ctx₈]`, the depth-7 scalar Haar, or coefficient vectors.
  Pyramid depth is surfaced only as posterized↔rich.
- **σ-masks / the σ-block-diagonal router.** `_PHI_MASK`, `_SIGMA_MASK`,
  `_HEAD_MASKS`, the 22+21+21 Hurvich–Jameson partition — invisible. The user thinks
  "grey bones / red-green / warm-cool," not "hidden-dim blocks."
- **Halting math.** PonderNet logits, the rate-distortion knee `K*`, halting KL — all
  hidden. The user sees only `E[d]` as a *default anchor* the slider lands on, never
  `K*` presented as an authoritative number (its science is unsettled — RESEARCH
  §1.4, ATOM §6.4).
- **The deterministic argmin index map.** Per-pixel assignment under the `L≻a≻b
  [4,2,1]` hierarchy is research-fixed and pointwise-optimal — never exposed, never
  editable. No per-cell hand-tinting.

**The line:** *the user authors what has no single right answer; the machine grounds
what does.* Tonal richness, temperament, harmonic spread, which looks to keep —
relational, per-user, no closed-form optimum — are the creator's. Fidelity (the L-MSE
Lloyd-Max ceiling) and assignment (deterministic argmin) are automatic grounding,
walled off so the creator can steer freely without ever degrading the picture. No
invented "cinematic/noir/mood" presets — the docs sanction only halting-truncation +
read-only readouts; the Ou–Luo beauty term is a *training-side* objective, never a UI
verdict on what is beautiful.

---

## 6. Engineering implications

- **Build order is the cascade, deployable surface is L-only.** Ship Phase L first
  (HANDOFF §2b): `LookConfig { useLookNetPalette, complexityBudget }`, before/after
  toggle, static `PaletteStripView`, dynamic-range/grey chips, `E[d]` readout.
  Temperament / harmony-spread / a/b disc are **M-A/M-B work and must be labeled
  not-yet-built** — do not ship them as present affordances. Maps to ATOM §5
  Phase L → Phase A → Phase B staging.

- **Honor 128 / depth-7 as the authoring unit — and resolve the live doc conflict.**
  The σ-pair decision (ATOM §2, §6.1) retires "256 distinct L / depth-8." But the
  *currently-trained blob* and HANDOFF §1②/§37/§63 still describe a **256-level
  depth-8 grey head** (`haar_l_depth8`, "do NOT use `reconstruct_sigma_pair` for L; it
  caps L at 128"). The abstraction's authoring unit is **128 anchors**; surface the
  deployable look honestly as **tonal levels** until the L head is re-cut to depth-7,
  and don't promise 128 *locked pairs* until chroma lands. Refactor item: align the L
  head + forward kernel (HANDOFF §63) with ATOM §2.

- **`LookConfig` must be threaded as an extensible `AppSettings` field from day one**
  (mirroring `DitherConfig`, `AppSettings.swift:62`), so adding the chroma a/b pad
  later is a *palette swap, not a redesign* (HANDOFF §3.4). Spec implication:
  `LookConfig` carries `complexityBudget` now, reserves temperament/spread fields.

- **Factor the decoder along eigenspaces (ATOM §5.1–5.3).** Promote `AxisNet` from a
  post-hoc projection to a generative atom; split the 384-DOF blob into
  `D_L ⊕ D_A ⊕ D_B` with the golden law that concatenation reconstructs the existing
  σ-pair coeffs (no-drift). This is what makes Layer 1 (L) authorable independently of
  Layers 3–4 (A/B), and keeps codegen + goldens moving continuously.

- **Prove the grounding laws so the "safe to steer" promise holds.** The compose
  combinator must establish `symPart(look x)==L x` (chroma cannot move the grey
  skeleton) and `asymPart(L x)==0` (L is pure grey) — ATOM §5.3. These two laws *are*
  "L grounds the cascade," and they are what let the UI show L chips **unchanged**
  during temperament edits.

- **GAN by scale, wired stage by stage.** No GAN at L (Lloyd-Max ceiling — drop
  `Discriminator`/`lam_adv` from the L milestone, RESEARCH §1.3). Re-introduce an
  **image-space** adversary + Ou–Luo at Phase A/B; a **diversity** critic only at the
  gallery/QD scale. The trainer's two-phase "pretrain base, then add adversary" falls
  out of the cascade for free (ATOM §5.4). Keep the index map deterministic argmin,
  grounded by L (ATOM §5.5).
