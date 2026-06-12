# SixFour — App Widget Gap Report (the cell grid as medium; 256 = 16² = 4⁴ = 2⁸)

> **Scope.** The *app only* — not the website. This is a holistic gap report on the
> product idea ("spatio-temporal dithering + memories, picked on a cell grid, that
> trains the user's iPhone model"), focused on **planning the widgets**. Where the
> detail already exists it is *cited, not duplicated* — especially
> [`SIXFOUR-RADIX-CONTROLS.md`](SIXFOUR-RADIX-CONTROLS.md) (the file:line-grounded
> radix map), [`SIXFOUR-COLLAPSE-LEVER-UIUX.md`](SIXFOUR-COLLAPSE-LEVER-UIUX.md),
> [`SIXFOUR-HIGHDIM-UIUX.md`](SIXFOUR-HIGHDIM-UIUX.md), and
> [`SIXFOUR-PALETTE-IS-MOTION-WORKFLOW.md`](SIXFOUR-PALETTE-IS-MOTION-WORKFLOW.md).
> Written 2026-06-12.

---

## 0. The idea, restated as an app contract

Five pillars, in the user's own framing, each turned into a thing the app must own:

| # | Pillar | What it forces the app to provide |
|---|--------|-----------------------------------|
| P1 | **20 fps is the comprehension rate** | one 20 fps clock; every cell is I/O at 20 fps (already law) |
| P2 | **LAB/OKLab is the color structure** | every palette layout places by OKLab rank, never faked distance |
| P3 | **64³ voxel cube** (64×64 px × 64 frames) | one index cube = the single source of truth; 2D GIF + palette + shutter are projections of it |
| P4 | **Per-frame palette → user picks 256 colors on a cell grid** | the cell grid is the *picking medium*, not a viewer — the user must be empowered to choose the palette |
| P5 | **Compression lever: 64³ per-frame → {16³ … 256³} global** | a single control that funnels per-frame diversity into one global palette at a chosen resolution |
| P6 | **Upload/download GIFs to train the iPhone model** | an on-device preference signal (the pick *is* the training label) + a model the picks update |

The throughline the user named: **256 = 2⁸ = 16² = 4⁴**, and the cell grid is the
medium. 16² is a literal 16×16 grid (trivial). 4⁴ "has 4 dimensions" and 2⁸ "has 8
dimensions" — *that* is the UI/UX challenge: representing 4- and 8-component
addressing on a flat 2D grid. §3 resolves it.

---

## 1. What is actually real today (one paragraph)

The **spine is built and honest.** The 64³ index cube, the per-frame palette
extraction, the deterministic Zig collapse, the one-atom cell grid (`CellSprite`/
`PixelGrid`/`GridScript`), the live/capture/render/review phase fields, the movable
ColorWidgets, and the 20 fps clock all ship. The **16² coordinate grid**
(`PaletteGridView` + `GridLayout`, golden-gated) is the *done bar*. An **8-wheel /
4-wheel address picker** (`AddressPickerView`, count = `branching.depth`) and a
**treemap** (`PaletteTreeView`) exist in Swift and are reachable in per-frame
Review. On-device training is **proven on hardware** (`AtlasTrainer`, MPSGraph, 12.4
ms/step, bit-identical Mac↔iPhone). What is **not** real: the controls do not yet
reach the collapse output or the cube (display branching ≠ genome branching), the
compression *lever* (P5) is design-only, the palette explorers (cloud/grid/tree) are
mostly off the default navigation path, and the train-the-model **loop has no app
seam** — picks are not yet a training signal. The detailed, file:line status of the
radix widgets is in [`SIXFOUR-RADIX-CONTROLS.md`](SIXFOUR-RADIX-CONTROLS.md) §1–§4;
do not re-survey it.

---

## 2. The reframe that unlocks the widget plan

Two corrections to the mental model. Both are load-bearing.

**(a) 16² / 4⁴ / 2⁸ are ONE tree at three branching factors — not three pickers.**
There is exactly one 256-leaf median-cut `SplitTree`; `tree.view(branching)`
collapses *k* binary levels into one display level, and `factor^depth = 256` always
(`SplitTree.swift`, RADIX-CONTROLS §1). So:

| Radix | digits | what one "digit" is | depth |
|-------|--------|---------------------|-------|
| 16² | 2 base-16 | a hex column/row on the 16×16 grid | 2 |
| 4⁴ | 4 base-4 | a quadrant choice (a 2×2 opponent cross) | 4 |
| 2⁸ | 8 base-2 | one binary split (one median cut) | 8 |

The "4 dimensions" of 4⁴ and "8 dimensions" of 2⁸ are **tree depth / number of
split-decisions**, *not* 4 or 8 data axes. The data is always OKLab-3D + time.
(The honest-labeling rule from HIGHDIM-UIUX: never print "8-D" — print the address
as `(axis, position)` breadcrumbs.)

**(b) Radix is not how you pick ONE color — it is the granularity at which a gesture
grabs a whole SUBTREE.** This is the key to planning the widgets. A 16×16 grid
already lets you tap one of 256 colors directly; you do not *need* 4⁴ or 2⁸ to pick a
single swatch. You need them because **the verb is collective**: recolor / kill /
weight / nudge a *group* of related colors at once. The radix sets the bracket depth
of that group:

- **16²** — a brush grabs 1-of-16 columns → coarse 16-color groups.
- **4⁴** — a brush grabs a quadrant → 4-way opponent splits, mid granularity.
- **2⁸** — a brush grabs at any of 8 nested binary levels → fine, all the way to a single median cut and its σ-mirror partner.

> **Planning consequence:** the cell grid stays the *medium* in every radix; the
> radix is a **zoom of the verb**, exposed as one control (a depth slider or a
> branching segment), not three separate screens. This is exactly the
> collapse-lever's Axis A, and it is why the lever and the radix are the same widget.

---

## 3. The radix challenge — gap, with the answer per radix

How each radix lands *on a flat grid* (the UI/UX challenge), and the gap:

- **16² — SOLVED, it is the bar.** `PaletteGridView`: x = one OKLab axis rank, y =
  another; golden-gated; flat opaque cells, no alpha; shared `brushedIndex`.
  *Gap:* per-cell `accessibilityValue` and frame-to-frame slot stability
  (RADIX-CONTROLS §2 "Ship-gate gaps even on 16²").

- **4⁴ — the nesting answer is a quadtree-of-quadtrees.** A 16×16 grid *is* 4⁴ when
  read as a 4×4 macro-grid of 4×4 micro-blocks (outer 2 base-4 digits = block, inner
  2 = position). On screen: a **2×2 opponent-quadrant drill-down** (`Quad4DrillView`,
  TO BUILD) — show all four siblings `parent ± δ₁ ± δ₂` at once, tap to descend,
  breadcrumb the quadrant signs. The forward analyser (`quad4Analyze`) already exists
  in spec, so this is a Swift-port + view, not new math (RADIX-CONTROLS §2, §4 Step 3).

- **2⁸ — the answer is drill-down, NOT 8 literal wheels of toggles.** Eight binary
  wheels render today (`AddressPickerView`, depth = 8) but a binary wheel is a glorified
  toggle and 8 taps-to-a-color is poor UX. The *good* 2⁸ interaction is: (i) treat the
  8 levels as a **median-cut breadcrumb** the user descends, and (ii) exploit the
  σ-pair structure — selecting leaf `2i+1` should also light its σ-mirror `2i`
  (`σ(L,a,b) = (L,−a,−b)`), and a Δa/Δb nudge on one applies −Δa/−Δb to its partner.
  That halves the perceived dimensionality (128 generators, not 256 leaves) and makes
  8 levels navigable. None of the σ-pair partner-highlight / mirror-nudge is wired yet
  (RADIX-CONTROLS §2 "2⁸", §4 Step 4).

**The single biggest radix gap (all three share it):** *display branching is wired,
genome/collapse branching is not.* `PaletteCollapse.collapse(...)` takes no branching
parameter and returns flat leaves; the cube reconstructs from raw per-frame palettes.
So **today no control choice reaches the collapse output or the voxel cube** — picking
4⁴ vs 2⁸ only re-skins the display. Branch-parameterizing the collapse (RADIX-CONTROLS
§4 Step 1) is the prerequisite that makes every radix widget *mean* something.

---

## 4. The compression-mapping gap (P5): the residual pipeline that SEEDS 256³

The user's "funnel" is **not** a one-shot collapse to a chosen resolution — it is a
**round-trip whose residual seeds the high-definition final product**, and it yields
**TWO 256³ GIF products** (per-frame and global). The corrected, authoritative
pipeline (user, 2026-06-12):

```
  64³ per-frame palette        (capture; max LAB diversity per frame — ground truth)
        ├──────────────────────────────────────────────→  256³ PER-FRAME  ◀ PRODUCT A
        │                                  (direct super-res, keeps per-frame palettes;
        │                                   the diversity-max HD output = HD GIFA)
        │  collapse / compress (W₂ barycenter; cut-level = motion-bandwidth dial)
        ▼
  16³ global                   (aggressive global compression — the coarse rest pose)
        │  reconstruct at hero resolution using the GLOBAL palette
        ▼
  64³ global                   (the compressed base, re-expanded to 64³)
        │
        ▼
  COMPARE  64³ per-frame  ⟷  64³ global     ← the residual = what collapse LOST
        │                                      (= the per-frame ↔ global displacement
        │                                         = the motion/detail signal)
        ▼
  256³ GLOBAL                  ← super-res SEEDED by the two-64³ comparison  ◀ PRODUCT B
                                 (the compressed-but-recovered HD output = HD GIFB)
```

So there are **two 256³ GIFs, not one:**

- **Product A — 256³ per-frame (HD GIFA):** a *direct* super-res of the per-frame cube,
  preserving each frame's own max-LAB-diversity palette. No global bottleneck — the
  honest, diversity-max upper reference.
- **Product B — 256³ global (HD GIFB):** the *comparison-seeded* output. The per-frame
  and global 64³ are differenced; that residual seeds the super-res. Compressed through
  one global palette, then detail recovered from the residual.

This maps exactly onto the repo's existing **GIFA (per-frame) vs GIFB (global collapse)**
distinction — A and B are simply the **256³ HD versions** of that pair. Having both lets
the user (and the trainer) compare diversity-max vs coherent-global at full resolution.
The richer the per-frame↔global gap, the more detail Product B has to recover toward
Product A.

This is exactly the repo's settled math, now made concrete:

- Collapse = a **Wasserstein (W₂) barycenter** of the 64 per-frame measures; the
  barycenter is the "rest pose" and **motion is the residual displacement** from it
  (`SIXFOUR-PALETTE-IS-MOTION-WORKFLOW.md`). The **per-frame ↔ global comparison above
  IS that displacement field**, measured rather than assumed. The cut-level is the
  **motion-bandwidth dial**: a low cut folds more color-motion *into* the global rest
  pose (bigger residual to recover at 256³); a high cut keeps motion explicit.
- The residual-seeded expansion is the **RQ-VAE / VAR residual** super-res path
  (`SIXFOUR-JEPA-256-SUPERRES-WORKFLOW.md`): a deterministic base (the 64³ global) plus
  a thin additive residual decoded to 256³.
- The lever feeds **three live resolutions off one collapsed palette** — 16³ preview,
  64³ hero, 64³ global base — and the **256³ is the export-time product of comparing
  the two 64³** (`SIXFOUR-COLLAPSE-LEVER-UIUX.md`).

**Gap:** the lever's *Axis A* (radix branching) renders; **Axis B (the cut-level
slider) does not exist**, the 16³ live preview does not exist, **the per-frame↔global
64³ comparison/residual is not computed**, and **neither 256³ product exists** — the
direct per-frame super-res (A) and the residual-seeded global super-res (B) are both
replication-only today (the RQ-VAE/OT residual super-res is design-only,
`SIXFOUR-JEPA-256-SUPERRES-WORKFLOW.md`). This is the widget chain that most directly
realizes P5 and it is **the highest-leverage missing control**, because the cut-level
is the one knob that sets how much residual Product B has to recover toward Product A —
a *thing the user does*, not a backend default.

> **Planning consequence (per Decision 1):** Axis A (radix) is now *three dedicated
> screens*, and Axis B (the cut-depth slider) is a **separate control hosted on each
> radix screen** — sharing one backing `SplitTree` and one `brushedIndex`, with a live
> 16³ preview reacting at 20 fps. The cut slider is the same physical knob on every
> screen; only the *radix view above it* changes. (This is the one place I'd still
> flag the tradeoff: three screens means the user changes zoom by navigating, not by a
> segment — more taps, but each screen can be tuned to its radix's ideal interaction.)

---

## 5. The ecosystem seam (P6): the one app widget the loop requires

The north-star is **on-device personalized look-learning** (STATUS.md): the user
trains a tiny net on the iPhone so it learns *their* taste. The hardware path is
proven (`AtlasTrainer`, MPSGraph). The **missing app seam is the preference signal**:
in the current app, when the user picks a palette/look there is *no place the pick
becomes a training label.*

**The gap is one conceptual widget: the pick IS the label.** Every collective edit on
the cell grid (keep/kill a subtree, nudge a σ-pair, choose a cut-level, select 1-of-N
proposed looks) is a **preference event**. The ecosystem loop the user described —
upload GIFs you made, download GIFs you like, and those train your model — is, *on
device*, exactly: the looks you keep vs discard are Bradley–Terry comparisons feeding
`AtlasTrainer`. The web upload/download (out of scope here) is the same signal at
population scale.

**What is missing in the app:**
1. A **proposal surface** — the net proposes N candidate global palettes/looks; the
   user picks; the comparison is logged. (`SIXFOUR-SEARCH-AS-DECISION.md` frames
   search-as-decision; `COLOR-ATLAS.md` is the curation/policy/value design this
   trains.) The `AtlasBoardView` (16³ curation board) is the closest shipped surface,
   but it is flag-gated and not yet wired to emit training comparisons.
2. A **look-category taxonomy** — the user's "looks in categories" has *zero spec
   footprint* (STATUS.md open debt). Without categories the picks are unstructured.
3. The **delta-head spec** — the per-user adapter the picks update (STATUS open debt).

> **Planning consequence:** do not build a separate "training UI." Make the existing
> cell-grid edits *emit* comparison events, and add **one proposal/curation surface**
> where a pick is a vote. The training is invisible; the widget is the choice.

---

## 6. Cross-cutting gaps (apply to every widget above)

| Gap | What it is | Why it blocks the vision | Source |
|-----|-----------|--------------------------|--------|
| **No voxel cube at all + brushing not unified** | *(corrected 2026-06-12)* `VoxelCubeView` **does not exist**; `brushedIndex` lights grid/tree/cloud/picker but there is no cube to illuminate, and `.voxel3D` is an orphaned representation case | The cube is the "single source of truth" (P3) but it isn't rendered → the medium feels disjoint; building it is a §7 Step 2 feature, not a wiring task | scout wf_c777dd6f; RADIX-CONTROLS §3 |
| **Explorers are off the default path** | `PaletteGridView`/`PaletteTreeView`/`PaletteCloudView` are reachable only via sub-states or not at all | P4 says "the user is *empowered* to pick" — but the picking widgets aren't where the user lands | inventory; HIGHDIM-UIUX §8 |
| **Honesty labeling** | no per-cell a11y value; "8-D" temptation | OKLab/LAB integrity (P2) requires address breadcrumbs `(axis,pos)`, not dimension theater | HIGHDIM-UIUX §3 |
| **Atom-size doc drift** | *(corrected 2026-06-12)* the real atom is **4 pt** — `Generated/LatticeContract.swift:24` `gifPx = 4` (GRID v3.0), surfaced via `ScreenLattice.swift`. My earlier "DESIGN-LANGUAGE v2.0 = 6 pt authoritative" was **wrong**: that doc was deleted; 6 pt is stale GRID-v2.0 lineage | a widget built to 6 pt violates the grid law | **`LatticeContract.swift` is the source of truth (4 pt)**; stale 6 pt refs (e.g. DISPLAY-FSM.md:48, GlobalLattice comments) still need a sweep |

---

## 7. The widget plan (sequenced)

Each widget must clear the **16² done-bar** (RADIX-CONTROLS §2): golden-gated, honest
rank not faked distance, in-order NN adjacency, flat opaque cells (no alpha), 20 fps +
shared `brushedIndex`. Sequence chosen so each step *unlocks* the next.

1. **Branch-parameterize the collapse (no NN).** The unblocker. Make
   `PaletteCollapse` carry `branching` + genome so a radix choice reaches the collapse
   output, not just display. **CORRECTED 2026-06-12 (scout-verified):** the spec
   groundwork is *already done* — `analyzePaired` (σ-pair forward analyser) exists and
   is exported in `SigmaPairHead.hs:122-138` with its round-trip + σ-fixed laws
   (`:216-228`), `quad4Analyze` exists in `Quad4.hs:149-175` with `lawQuad4AnalyzeRoundTrip`,
   and `BranchedPalette.swift` already routes all three branchings. So this step is
   **pure integration, not new spec**: extend `CollapsedPalette` (today only
   `{leaves, chosenIndices}`) to carry `branching` + genome, add a branching param to
   the `PaletteCollapse` protocol, and wire every consumer (cube, GIF re-index, Review
   editor, Atlas) in concert. That breadth is exactly why it stays MANUAL/human-gated —
   it's a breaking protocol+struct change, not an additive feature. *(RADIX-CONTROLS
   §4 Step 1.)*
2. **Build the voxel cube, then wire `brushedIndex` into it.** **CORRECTED 2026-06-12
   (scout-verified):** `VoxelCubeView.swift` **does not exist** today (the RADIX-CONTROLS
   §3 file:line citations were design-intent, not real), `.voxel3D` is an orphaned
   `PaletteRepresentation` case no path renders, and there is no `GIFReviewView.swift` —
   review lives in `ReviewPhaseField.swift`. So this is a **feature BUILD** (build the
   cube view + add `paletteRepresentation` routing in the review surface), *then* the
   brush wiring: tap a cell → light every voxel of that color (opaque step, `!flat`
   gated); tap a voxel → set `brushedIndex`. Depends on Step 1. *(RADIX-CONTROLS §4 Step 2.)*
3. **Cut-depth slider + 16³ live preview (P5), shared across screens.** The Axis-B
   control + a live 16³ preview reacting at 20 fps, with one backing `SplitTree`/
   `brushedIndex`. Built once, hosted on each radix screen (Decision 1). Highest-
   leverage missing control. *(COLLAPSE-LEVER §B.)*
4. **16² screen** is the done-bar (`PaletteGridView`); close its ship-gate gaps
   (per-cell a11y value, slot stability). **4⁴ screen** = `Quad4DrillView`, a 2×2
   opponent-quadrant staircase; `quad4Analyze` port. **2⁸ screen** = the wheel/tree
   drill with σ-pair mirror: partner-highlight `2i↔2i+1`, mirror-locked nudge, DOF
   readout 384/128 generators. *(RADIX-CONTROLS §4 Steps 3–4.)*
5. **Capture-side read-mostly pick (Decision 2).** A lightweight live brush/preview on
   the Capture screen that defers heavy collapse re-projection to Review, to protect
   the shutter + camera budget. *(CAPTURE-FLUIDITY.)*
6. **Proposal/curation seam (P6), logging now (Decision 3).** Make cell-grid edits emit
   Bradley–Terry comparison events into `AtlasTrainer` *immediately*, behind the Atlas
   flag; surface N proposed looks to pick from. Look-category taxonomy spec follows.
   *(COLOR-ATLAS.md; STATUS open debt.)*
7. **Two 256³ super-res exports (Decision 4).** Last and downstream. (7a) **Product A —
   256³ per-frame:** direct tiled/streamed super-res of the per-frame cube (no global
   bottleneck). (7b) compute the **per-frame↔global 64³ residual** (reconstruct `64³
   global` from the collapsed palette, difference against `64³ per-frame` — the seed);
   (7c) **Product B — 256³ global:** decode that residual to a literal 256×256×256 cube,
   tiled/streamed, never held whole. replicate4x is the Phase-0 stand-in for both.
   *(JEPA-256-SUPERRES — design-only.)*

Steps 1–2 are pure plumbing (zero NN) and make every later widget *mean* something.
Steps 3–5 raise 4⁴/2⁸ to the 16² bar. Step 6 closes the train-your-iphone loop.

---

## 8. Decisions (resolved 2026-06-12)

1. **Three radix screens, not one unified lever.** Each radix gets a *dedicated*
   pick view (16² grid / 4⁴ quad-drill / 2⁸ wheel-tree), switched explicitly.
   **Clarified intent: "screens" = three *perspectives of the same widget*** — like
   rotating one object to see it from three angles, not three independent objects.
   → **Honest reconciliation with §2(b):** the three perspectives must read off one
   `SplitTree` via `tree.view(branching)` (one backing structure), and a pick on any
   perspective drives the same shared `brushedIndex` — otherwise a color brushed on
   the 4⁴ perspective won't light on the 2⁸ perspective or in the cube, and the
   "one cube projected honestly" invariant breaks. The "radix = zoom of the verb"
   principle is preserved *inside* each perspective (the verb is still collective
   subtree edit); the user changes zoom by switching perspective rather than by a
   segment control — the cost being more navigation, the benefit being each
   perspective tuned to its radix's natural gesture (grid tap / quadrant drill /
   median-cut descent). **Consequence:** the cut-level lever (P5, Axis B) is a
   **separate, shared control** hosted on each perspective, not fused into one panel —
   see revised §7 Step 3.
2. **Picking lives on BOTH Capture and Review.** Lightweight live palette shaping
   during Capture + the full radix screens in Review. → **Watch-item:** this contends
   with the clean-shutter law and the camera/main-thread budget
   (`SIXFOUR-CAPTURE-FLUIDITY-SYSTEMS.md`); keep the Capture-side pick *read-mostly*
   (brush/preview), defer heavy collapse re-projection to Review.
3. **Log picks as comparisons NOW, behind the Atlas flag.** Cell-grid edits emit
   Bradley–Terry events into `AtlasTrainer` immediately (cheap, reversible) so data
   accrues before the look-category taxonomy lands.
4. **TWO 256³ GIF products** (see §4 pipeline), both literal 256×256×256 voxel cubes,
   neither a naive 4× upsample: **Product A = 256³ per-frame** (direct super-res of the
   per-frame cube, diversity-max, = HD GIFA) and **Product B = 256³ global** (seeded by
   comparing `64³ per-frame ⟷ 64³ global`, = HD GIFB). → **Hard implications:** (a) the
   **per-frame↔global 64³ comparison/residual must be computed** for Product B — it is
   the seed and does not exist today; (b) each 256³ = 16.7M voxels, so **neither can be
   held or rendered naively** — both export decodes must **tile/stream** the RQ-VAE
   residual (`SIXFOUR-JEPA-256-SUPERRES-WORKFLOW.md`), and 256³ is **export-only, never
   an interactive surface** (live preview stays at 16³/64³). The "replicate4x" path
   (`SIXFOUR-COLLAPSE-LEVER-UIUX.md`) is the Phase-0 stand-in for both. This redefines
   the export target away from the docs' earlier "256-color × 256-frame" reading, maps
   A/B onto the existing GIFA/GIFB pair, and establishes that Product B is *derived from
   the two-64³ gap*, not the global alone — update those docs.
5. **Both 256³ products are TRAINABLE and SHAREABLE** (Decision, 2026-06-12) — no
   archival-only / share-only split. Product A (per-frame, diversity-max) and Product B
   (global, comparison-seeded) are *both* exportable/shareable GIFs *and* both feed the
   on-device trainer as preference/comparison signal (P6). → **Consequence:** the A↔B
   pair is itself a natural training comparison (diversity-max vs coherent-global at full
   res), and the share/upload surface must offer **both**; the P6 seam (§5) logs picks
   over A and B alike, neither demoted to reference-only.
