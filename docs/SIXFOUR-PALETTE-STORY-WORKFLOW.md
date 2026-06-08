# SixFour — The Palette Story: 16²→4⁴→2⁸ Progressive Authoring (+ the 2⁸ Haar-abstraction discovery)

> Status: workflow (2026-06-08). The authoring narrative the user drives from GIFA to the global palette,
> and the discovery of what `2⁸` means as UI/UX. Engine verdict folded in: **statistical base, NO JEPA
> core, gated σ-pair residual** (confirms `SIXFOUR-256-SUPERRES`). SixFour owns all code.

---

## 0. The story (the user's model)

The three factorizations are not three views of one thing — they are **three acts of one authoring story**,
and each act **widens the temporal scope and lengthens the scroll**:

| Act | Lens | Temporal scope | Scroll | Meaning |
|---|---|---|---|---|
| **I** | **16²** | **1 frame** | step through 64 frames | a per-frame palette (the atom) |
| **II** | **4⁴** | **4 frames** | through 16 quartets | deltas outline the *core* colors |
| **III** | **2⁸** | **all 64, abstracted** | down the 8 Haar levels (longest) | abstract → organize the **global 256** |
| **IV** | **EXPORT** | the committed global | result view | the **GLOBAL PACK** — GIFC 16³ + GIFB 64³ + GIFD 256³ |

→ Acts I–III author the global 256 palette → **Act IV exports the global pack** {16³, 64³, 256³} via the
custom Zig. The scroll grows act to act (64 → 16 → deep), so the interaction *feels like a story* climaxing
in the abstraction, then resolving in the export.

---

## 1. Act I — `16²` is ONE frame's palette (the atom)

Capture GIFA (64³, per-frame palettes). **Pick a frame → its 256-colour palette IS a 16×16 grid.** This is
exactly `Spec.StageA` (each frame extracts a 256-colour palette). The square is the per-frame palette — the
honest atom, the thing the user already understands. Scroll = step through the 64 frames, one palette at a
time. Owns the **square** shape.

---

## 2. Act II — `4⁴` is FOUR frames; the deltas outline the CORE

Pick **4 frames** → the quartet (`R,G,B,T`, T = 4 frames). Compute the **W₂ barycenter** of the four (the
"core of the whole"), then for each colour show its **displacement from the core**:

```
core colour   :  small |v| = stable across the 4 frames   → OUTLINED / bright   (the "core of the whole")
moving colour :  large |v| = high inter-frame delta        → dim / flagged motion
```

So **the inter-frame deltas literally outline the colours closest to the barycenter core** — the user *sees*
which colours are structural vs which are motion/edge. This is the OT motion field (`v_t = T_{μ̄→μ_t} − x`,
`SIXFOUR-PALETTE-IS-MOTION`) turned into a visible cue. Shape = a **1×4 panel strip** of the quartet (not a
square). Scroll = through the 16 quartets. The core colours found here are carried into Act III as the
*protected* set.

---

## 3. Act III — `2⁸` DISCOVERED: the Haar abstraction ladder

**The discovery.** `4⁴` and `16²` have concrete meanings (a quartet, a frame). `2⁸`'s meaning is different
by design: it is the **abstraction** — where the per-frame and quartet observations are *abstracted into the
one global 256-palette the user commits*. Its structure is the depth-8 σ-pair Haar tree: `256 → 128 pairs →
64 → … → 1`. Each level up **merges a σ-pair `(cᵢ, σ(cᵢ))` into its Haar parent** (mean; detail set aside).

**The UI/UX (the answer):** a **scrollable σ-pair ribbon** (the `128×2` "P" shape — distinct from the square)
where **scroll position = Haar abstraction level (the collapse cut)**:

```
top of scroll   →  256 distinct leaves          (no abstraction; = GIFA's richness)
scroll down …   →  128 σ-pairs merge → 128       (first Haar level)
                →  64 … 32 … 16                   (deeper abstraction)
bottom          →  the global core               (maximum abstraction)
```

- **Scroll = abstract.** Pulling down the ribbon collapses Haar levels — the user *watches* 256 simplify
  toward the global palette. This is the cut-level lever (`Spec.CollapseLever`) as a *gesture*, not a slider.
- **Tap = protect.** Tapping a pair locks it (it survives deeper collapse) — this is where Act II's **core
  colours** get pinned, so the user's sense of "important" shapes the abstraction.
- **Output = the organized global 256.** Where the user stops scrolling (+ what they protected) *is* the
  global palette they approximate → handed to the Zig engine.

Why a ribbon, not a grid: the **shape is the meaning** — square = "all colours at once" (Act I), 4-panel =
"across the quartet" (Act II), **long scrolling ribbon = "the deep hierarchy you travel through to abstract"**
(Act III). The longest scroll is the story's climax. (`2⁸` is the abstraction lens precisely *because* it is
the Haar binary cascade — the one structure that expresses progressive merge.)

---

## Act IV — Export the GLOBAL PACK {16³, 64³, 256³}

GIFD is its **own act**, and it does not stand alone — it ships as part of the **global pack**: the three
resolutions of the one committed global palette, bundled as a single export.

- **GIFC 16³** (16×16 × 16f) — the coarse preview, the abstraction made motion.
- **GIFB 64³** (64×64 × 64f) — the native render under the global palette.
- **GIFD 256³** (256×256 × 256f) — the super-res, the deep render.

All three are the **same committed global 256 palette** at the three rungs of the cube ladder. The custom
**Zig runs here**: sliced-W₂ collapse → SplitTree → argmin (GIFB); box-downsample (GIFC); Haar-RQ + OT/McCann
advection in OKLab, re-quantised once (GIFD). The pack is one bundle (`.quad`-style container + share sheet).
**GIFD's zoomed display (the D-pick) is the Act IV result view** — the user never authors in GIFD, they
*review the pack* there. Story shape: **author (Acts I–III) → export the pack (Act IV).**

## 4. The scroll IS the story

`more scrolling per act` is not decoration — it is the temporal scope widening:
`Act I` scrolls 64 frames · `Act II` scrolls 16 quartets · `Act III` scrolls 8 Haar levels (× 128 pairs).
The user travels from a single instant, to a 4-frame motion, to the abstraction of the whole — a narrative
arc from *concrete* to *abstract*, ending at the global palette.

---

## 5. The engine behind the story (research verdict — folded in)

The UI organizes the global palette; the **engine is statistical, not a JEPA core.** The cell grid is the
killer constraint: every cell must emit an exact 1-byte index into the 256-leaf codebook (byte-faithful GIF).
JEPA predicts in embedding space and never emits indices — exactly backwards. So:

- **Base (no net):** sliced-**W₂ barycenter** collapse → **256-leaf `SplitTree`** → **deterministic argmin**.
  The **Haar pyramid is the RQ residual stack**. **OT/McCann advection for 64→256 is done in OKLab,
  re-quantised once at the end — never warp indices directly** (index-warping is ill-posed).
- **Residual head (gated, gap-only):** the existing **384-DOF σ-pair look-NN** predicts a *continuous OKLab
  residual* and **snaps to the nearest leaf at write time** — only for disocclusion holes + HF/MF chroma
  subbands, behind a **gradient-cosine gate that provably can't degrade the base**.
- Orbis [2507.13162] (controlled same-backbone bake-off): continuous latent prediction beats discrete
  masked-token "by a large margin" on FVD → **continuous OKLab/OT for fidelity, discrete 256-index for
  drift-free stability**. The story's `2⁸` Haar ribbon is the user-facing face of that RQ/SplitTree stack.

Every act maps to an engine artifact the UI already proves: `16²`→`StageA`, `4⁴`→`Collapse` barycenter +
displacement field, `2⁸`→`SplitTree`/`CollapseLever` Haar cut. The user *authors the inputs* to a
deterministic pipeline; the gated net only fills gaps.

---

## 6. Discovery / validation plan for the `2⁸` ribbon

Spec-first; treat the ribbon as a hypothesis to validate, not a given:
1. **Prototype** the σ-pair ribbon (scroll=cut, tap=protect) as a `#Preview` over synthetic GIFA — does
   scrolling-to-abstract *read* as a story? (the "feels like a story" acceptance test).
2. **Spec** `Spec.HaarRibbon`: scroll-offset → Haar level → surviving pairs (refines `CollapseLever`); laws:
   monotone abstraction, protected pairs never merge, bottom = global core. Golden-pin.
3. **Measure** core-colour outlining (Act II) on real bursts: does barycenter-displacement actually separate
   structural from moving colours? (if not, the "outline the core" cue is hollow).
4. **Wire** the protect-set from Act II into the Act III cut (protected = locked leaves in `CollapseLever`).

---

## 7. Spec-first phases
1. `Spec.QuartetDelta` — 4-frame barycenter + per-colour displacement (the Act II "core" outline). SIMD 4-lane.
2. `Spec.HaarRibbon` — scroll→Haar-level→surviving pairs + protect-set (refines `CollapseLever`).
3. `Spec.PreviewProxy` / `Spec.Export` — GIFC 16³ preview + GIFD 256³ (per the four-GIF workflow).
4. Swift: Act I frame-picker (16² square) → Act II quartet strip → Act III σ-pair ribbon; tap-to-inspect.
5. Engine: confirm base path (sliced-W₂ → SplitTree → argmin → Haar-RQ → OT advection) before the gated head.

---

## 8. Resolved + remaining
- **RESOLVED — `16²` per-frame vs global:** distinguished by the **ACT** (context), no label. Act I = a
  per-frame `16²` (frame N); Act III = the global `16²` (the abstraction). The square means "per-frame
  palette" in Act I and "the global palette you're abstracting toward" in Act III; the surrounding act tells
  the user which. Same shape, two acts, never on screen together.
- **RESOLVED — GIFD:** its **own act (Act IV)**, bundled into the **global-pack export {16³, 64³, 256³}**.
  GIFD's zoomed D-pick display is the Act IV result view, not an authoring surface.
- *Remaining:* the protect-gesture's exact collapse semantics (lock vs weight) — pin in `Spec.HaarRibbon`.
- *Remaining:* which GIFD D-pick (pan / tiles / loupe / zoom-ladder) renders the Act IV pack review.
