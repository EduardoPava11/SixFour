# SixFour — Holistic Form Follows Function

> Status: **design only**. This workflow implemented nothing. It records the
> holistic UI/UX target, the adversarial review that found where the headline
> claim is currently false, and the resolved, buildable shape. Treat the
> "Adversarial review + resolutions" section as the contract any implementation
> must honour.

---

## Thesis

The cell grid **is** the 64×64 GIF-pixel field, and both product functions are
one gesture on that same field at two granularities — **SEARCH** the palette
(navigate projections of the one cube) and **MODIFY** the palette (write the one
global table) — so the GIF is the form and form follows function because each
function is literally one control over the one cube.

---

## Prior art (the principle and the patterns)

Three lineages justify the move from an eight-button toolbar to two axes:

- **Form follows function (Sullivan; Rams "as little design as possible").**
  "Good design is as little design as possible" and "good design makes a product
  understandable" (Dieter Rams' ten principles). A control that names no live
  function should not exist; a control that serves the *same* engine as another
  should be one control. This is the merge/defer rule below.
- **One primary action per step (progressive disclosure; Nielsen Norman Group).**
  Reduce co-equal options on a screen to a single obvious next action and defer
  the rest behind disclosure. The "co-equal toolbar" is the documented
  anti-pattern; each act here gets exactly one primary action that answers "what
  completes this step?".
- **Search/modify on the same surface (Coolors / Adobe Color "lock + tweak").**
  Palette tools let you *shuffle/explore* (search) and *lock + locally adjust*
  (modify) on the **same swatch strip** — the strip is both the result and the
  control. SixFour's MODIFY borrows the lock gesture directly; the strip is the
  16²-addressed palette living on the same field.
- **Sequence as wizard (one decision per screen).**
  Multi-step flows that surface one decision at a time, each with its own
  progress, reduce error and cognitive load. Review's Refine is this wizard:
  SEARCH screen, then MODIFY screen, each with its own progress, then back to
  Ship.

(Citations are to the well-known public sources above — Sullivan, Rams,
Nielsen Norman Group's progressive-disclosure guidance, and the Coolors/Adobe
Color lock-and-tweak interaction. No proprietary claim depends on a specific
URL.)

---

## The function

### GIF sizes (the ladder)

The deterministic producer (`SixFour/Encoder/LadderExport.swift`) emits two
shippable rungs today — these are the literal output forms:

- **`working16` — 16³ working copy.** A cheap, any-time snapshot (16×16, 16
  frames), global palette.
- **`global64` — 64³-B (GIFB).** The hero global GIF. `global = projectQ16(maximin
  leaves over selected groups, branching, override)`.

(64³-A per-frame is already the committed `Surface.gifURL`; the two 256³ tiled
rungs are deferred decode — see Open decisions.)

### Axis 1 — SEARCH the palette (navigate)

ONE control: a vertical depth-lever dragging `k = 0…8`, the collapse depth of the
single median-cut `SplitTree`, driving `SplitTree.collapse(k)` / `descendants(at:)`.
The 64×64 hero re-quantizes live as you drag — every move shows its consequence
(the scent). Radix is **not** a separate selector in the *target*: the bands
{16² SEE / 4⁴ CONTROL / 2⁸ LEARN} are labels on the same lever.

> **Honest caveat (see Adversarial review):** today SEARCH is **preview-only with
> no write path**, and the radix↔depth merge hides a real reconstructor
> discontinuity. The resolved design keeps the lever but reframes it truthfully.

### Axis 2 — MODIFY the palette (write the table)

ONE gesture borrowed from Coolors/Adobe: **lock + local tweak** on the
16²-addressed palette strip.

- **Groups (the real, byte-exact MODIFY today).** Tapping a group-cell toggles
  whether that RGBT group's leaves are pooled into the one global maximin table.
  This reaches `LadderExport.makeURL` byte-exact: `selectedGroups` →
  `GroupRGBT.selectedFrames` → `FarthestPointCollapse().collapse(...).leaves` →
  `BranchedPalette.projectQ16(...)` (LadderExport.swift:50–57). **This is the
  only control that writes the shipped table today.**
- **Look (whole-palette scope, same axis).** The OKLab grade
  (`off/soft/medium/strong/inverted`); a swipe recolours every leaf and, when
  `≠ .off`, **is** the export delta (the `.cube`).
- **Leaf-override (local rung, engine-wired, UI-dark).**
  `BranchedPalette.projectQ16(override:)` exists and reaches `makeURL`
  (LadderExport.swift:42,57) but nothing in chrome writes it. Keep it dark per
  Rams until a concrete local-tweak need appears.

MODIFY is the axis that writes the global table. SEARCH (when correctly wired)
projects; MODIFY commits.

---

## The form (cell-grid vocabulary)

Everything is whole-cell at the **4pt atom**, sized from `Spec.Lattice`, placed
via `View.place()` / `GridLayoutContract`. The cell-field law: the whole screen
is one data-coloured cell field; a cell→colour by render mode at 20fps.

| Role | Primitive | Footprint / notes |
|---|---|---|
| FIELD (hero) | `CellSprite` 64×64 | `gif(64) = 256pt`, one GIF pixel per cell — the literal `.global64` form |
| SHIP | `CellActionButton`, `prominent: true`, full-width | ≥11×11 touch floor; long-press discloses a rung row of small `CellActionButton(fillWidth:false, shortTitle:)` `16³`/`64³` |
| REFINE | `CellActionButton` 11×N, secondary (non-prominent) | opens the wizard |
| SEARCH lever | `CellSlider` M×11, knob = 1 lit cell | routed through `.cellDetent(tick:every:position:)`; one level crossed = one 20fps frame = one `CellTick` haptic = one hero repaint at the same frame index; bands labelled via `CellText` at sub-pt |
| MODIFY strip | 16×16 grid of group-cells (`CellSprite`/`CellToggle`) | each ≥ touch floor via an 11×11 hit region; lock = lit-cell state; Look = horizontal swipe-detent over the strip (same `.cellDetent`) |

The movable triad keeps its persisted position across acts.

---

## The holistic design (act-by-act)

One Surface, five acts; each act is a cell-grid reconfiguration with exactly ONE
primary action answering "what completes this step?".

1. **LIVE** — completes on **SHUTTER** (the 16×16 square). Swipe pre-sets
   `captureLook`, but the act ends only at the burst trigger.
2. **CAPTURE** — the 64-frame burst; completes **automatically** when the ring
   fills (`locking → capturing → .committed`). No button — the progress *is* the
   completion.
3. **BROWSE / pick-four** — *intended* to complete on **PICK-FOUR** (the quartet
   anchors). **Today this act does not exist as an FSM phase** (see review);
   anchors are hard-coded `[0,21,42,63]`. Ship-or-fold is an Open decision.
4. **RENDER** — the 5 Zig stages (quantize → dither → significance → palette →
   encode); completes **automatically** on encode. Progress = completion.
   Internal; not a surfaced act.
5. **REVIEW** — completes on **SHIP** (the one GIF export).

Each act surfaces only its primary action plus the field; deeper controls are
progressively disclosed.

### The Review reshape (form → function in cell primitives)

From an 8-button flat HStack (Share / Save / LUT / Motion / Cut / Retake / Atlas
/ Groups — the co-equal-toolbar anti-pattern) to:

- **64×64 GIF hero** filling the field (`CellSprite`, the `.global64` form).
- **ONE primary SHIP** below it (merges Share + Save; rung `16³`/`64³` is a
  long-press disclosure on Ship, not a peer button).
- **ONE secondary REFINE** affordance. Tapping Refine enters a wizard (one
  decision per screen):
  - **Step A = SEARCH** — drag the collapse-depth lever; hero re-quantizes live
    with scent. Motion is a **brightness overlay toggle** on this field, not its
    own destination.
  - **Step B = MODIFY** — lock/pool groups + Look swipe. **The only step that
    changes what ships.** LUT auto-appears here when `Look ≠ .off` (it is this
    axis's export form, not a 7th button).
- **Retake** — low-priority secondary, styled down (not hidden).
- **Atlas** — flag-gated sub-mode behind Refine, never on the main row.

---

## What merges / goes away (and why function says so)

| Control today | Fate | Function-following reason |
|---|---|---|
| Cut depth-slider + BranchingSelector | **MERGE** → one SEARCH depth-lever* | both drive `SplitTree.collapse(k)`; *but see review — the merge is conditional* |
| Share + Save | **MERGE** → one Ship | the GIF is the product; rung size = long-press disclosure |
| Motion button | **DEMOTE** → overlay toggle on SEARCH | it reads the displacement of the current collapse; not a destination |
| LUT button | **FOLD** → auto-surfaced inside MODIFY when `Look ≠ .off` | it is the export form of the Look axis |
| Leaf-override | **STAY DARK** (engine-wired, un-charted) | no UI writes it; surface only when local-tweak earns its place (Rams) |
| Atlas | **DEMOTE** behind Refine | flag-gated sub-mode, never main row |

Result target: 8 co-equal buttons → **1 Ship + 1 Refine** on the main row;
Refine opens 2 wizard steps. Every cut control either served the same engine as
another (merge) or named no live function (defer).

`*` The Cut/Branching merge is the contested claim. See next section.

---

## Adversarial review + resolutions

The review verdict was **needs-rework**: form-follows-function is *not yet* true
because the headline SEARCH control writes nothing, and the "one lever" merge
papers over a real discontinuity. The findings are accepted. Resolutions below
are what make the design honest and buildable.

### R1 — SEARCH ships nothing (CRITICAL)

**Finding.** `LadderExport.makeURL` (LadderExport.swift:38–45) takes
`branching` / `override` / `selectedGroups` but **no `cutDepth`/`k`**.
ReviewPhaseField's cut writes only `@State cutDepth` + a preview array
(`recomputeCutGlobal`). The design itself admits "pulling the lever NEVER
exports." So the headline SEARCH function does not exist in the engine.

**Resolution.** Reframe SEARCH honestly as **navigation, not commit** — and make
that the *designed* contract, not an accident:

- SEARCH is a **lens** that re-projects the preview. It is explicitly
  preview-only and byte-identical to the committed hero at `k = off`. This is a
  feature (risk-free navigation), stated as the contract.
- The thing a user "keeps" from SEARCH is **not** a cut depth — it is the
  *radix/branching choice* they land on, which **already** flows to `makeURL` via
  `branching`. SEARCH's job is to let the user *feel* the radix bands and pick
  one; the picked branching is what commits.
- **If and only if** a future need to commit an arbitrary `k` appears, add a
  `cutDepth: Int` parameter to `makeURL` and a `collapse(k)`-keyed global table.
  Until then, SEARCH does not pretend to commit. (This kills the "wants it both
  ways" problem in R6.)

### R2 — "radix = coarse notches, cut-depth = fine notches" merge is false

**Finding.** `PaletteBranching` (SplitTree.swift:38–46) is a 3-value **persisted
setting** {b16 depth2 / b4 depth4 / b2 depth8} that **re-roots the depth ceiling**.
Worse, each radix projects leaves through a **different reconstructor**
(`BranchedPalette`: b16 = identity, b4 = Quad4 opponent-quadrant, b2 = σ-pair),
so a notch on b4 ≠ the same notch on b2 in **output structure**, not just
granularity. Folding them onto one 0…8 axis hides a semantic discontinuity.

**Resolution.** **Do not** collapse branching and cut onto one continuous 0…8
lever. Keep the honest two-level shape:

- The lever has **three labelled bands = three branchings** (16²/4⁴/2⁸), and
  crossing a band boundary is an *explicit notch* that switches reconstructor.
  Within a band, finer detents (if any) are *the same* reconstructor.
- This preserves the documented honesty note (SplitTree.swift:51–59,
  docs/SIXFOUR-HIGHDIM-UIUX.md): these are radix factorizations, not a coordinate
  continuum. The lever is *one widget*, but it carries a real discontinuity at
  band edges and the UI must show it (a heavier detent / a band-change haptic),
  not smooth it away.
- Net: the merge is "two controls → one widget," **not** "two controls → one
  continuous axis." That is still a chrome reduction and still function-following,
  without the false abstraction.

### R3 — actFlow over-claims five acts

**Finding.** `Surface.swift` FSM (lines 19–122) has **no `browsing` phase** and
**no pick-four event**; `SurfaceEvent` has no anchor-pick token. `[0,21,42,63]`
is hard-coded (ReviewPhaseField:220) and used **only** by the Motion overlay,
never as export anchors. Render is internal.

**Resolution.** State the truth: **4 surfaced acts** (LIVE, CAPTURE, REVIEW +
internal RENDER). BROWSE/pick-four is a **proposed** act that requires new FSM
tokens, a new δ case, and Display-spec regen — it is *not* a pass-through and is
*not* shipped. It is listed as an Open decision, and the doc no longer counts it
among delivered acts.

### R4 — the Refine "wizard" is net-new navigation state

**Finding.** Today every Review tool (Groups/Cut/Atlas) is an in-place `@State`
boolean field swap (`groupPickField` / `atlasCurationField`), not a stepped flow
with per-step progress. The wizard is a new sub-FSM.

**Resolution.** Scope it as such. The Refine wizard is **explicitly a new
sub-FSM** (two states A/B + done), to be spec'd in `Spec.Display` and regenerated,
not a "reshape of the existing row." The first implementation slice does **not**
build the wizard; it only does the row reshape (Ship + Refine), with Refine
initially toggling the *existing* in-place fields. The wizard is a later slice.

### R5 — "MODIFY is the ONLY axis that touches what ships" is accidental

**Finding.** That is true today **only because SEARCH is broken.** Groups
(`selectedGroups`) and Look (`≠ .off` → `.cube`) reach the table; Cut does not.

**Resolution.** Reframe honestly: **today only Groups + Look write the table.**
The SEARCH/MODIFY split is the *target* architecture; the current truth is "one
working write axis (Groups+Look) and one preview-only lens (Cut)." The doc states
this as the as-built reality, with the clean split as the goal once R1's commit
path (if ever) lands.

### R6 — merging Cut into SEARCH risks wanting it both ways

**Finding.** Either Cut gains a real commit (then it is *not* pure projection and
"never exports" is wrong), or it stays preview-only (then it is a function-less
control that should be cut per Rams, like leaf-override).

**Resolution.** Pick the Rams branch **now**: Cut/SEARCH is **preview-only,
permanently, until a commit need is proven**. As preview-only it is *not*
function-less — its function is **navigation/scent** (helping the user pick a
branching that *does* commit). That is a real, named function, so it survives the
Rams test. It is sold as exactly that and nothing more. No "both ways."

---

## Open decisions

1. **BROWSE/pick-four:** ship the planned `browsing` FSM phase with user-pickable
   quartet anchors (new tokens + δ case + Display-spec regen), or keep
   `[0,21,42,63]` fixed and fold Browse into Capture? Memory leans keyframes; the
   act has **no completion criterion** until anchors are user-set.
2. **SEARCH lever band labels:** radix names (16²/4⁴/2⁸ — honest to the engine but
   jargon) or plain semantics (SEE/CONTROL/LEARN — scented but lossy)?
3. **Leaf-override:** keep dark (engine-only) until a concrete local-tweak need
   appears, or wire a minimal single-σ-pair nudge now? **Recommend dark** per
   Rams until frequency data justifies it.
4. **Save rungs:** is the deferred 256³ tiled export ever a Ship rung, or is 64³
   the permanent ceiling? Affects whether the long-press disclosure scales beyond
   2 rungs.
5. **Instrument MODIFY frequency:** log group-pick vs Look-swipe touches behind
   the existing Atlas flag to confirm which becomes the default-surfaced MODIFY
   gesture and which defers.
6. **Look on capture vs review:** the grade is set live (`LivePhaseField` swipe)
   **and** re-modifiable in Review's MODIFY step — confirm the Review swipe
   **overrides** the captured look rather than composing, so MODIFY has one
   unambiguous source of truth.

---

## First implementation slice

The smallest honest step that moves toward the target without shipping a
false control:

1. **Row reshape only.** Replace the 8-button HStack with **Ship** (merges
   Share + Save; long-press discloses `16³`/`64³` rungs via the existing
   `LadderExport.Rung`) + **Refine** (secondary). Retake demoted; Atlas behind
   Refine. No wizard yet — Refine toggles the *existing* in-place Groups/Cut
   fields.
2. **Make Cut honest.** Label the Cut control as **preview/navigation** and
   ensure it does not imply commit (no "save this cut" affordance). Keep
   BranchingSelector as a *band* control beside it (R2) — do **not** fold onto a
   continuous axis.
3. **Confirm the one write axis.** Verify Groups + Look (`≠ .off`) are the only
   paths to `makeURL`'s table, and that the Review Look swipe **overrides** the
   captured look (Open decision 6) — a one-line source-of-truth check, not new
   UI.

Deferred to later slices: the Refine sub-FSM/wizard (R4), the BROWSE/pick-four
FSM phase (R3/Open 1), any `cutDepth` commit path (R1), leaf-override UI (Open 3).

---

## Executive summary

SixFour's UI/UX target is **one cube, two gestures**: SEARCH (navigate
projections of the one median-cut SplitTree) and MODIFY (write the one global
maximin table). The GIF field *is* the form, and form follows function because
each function is one control over that field — collapsing an 8-button toolbar to
**Ship + Refine**.

The adversarial review is accepted and the headline claim is corrected to be
true rather than aspirational:

- **SEARCH ships nothing today** → reframed as preview-only **navigation/scent**
  (a real function under Rams), with branching — not cut depth — as the thing
  that actually commits. A `cutDepth` commit path is added *only if* proven
  needed.
- **The "one 0…8 lever" merge is false** (each radix uses a different
  reconstructor) → keep one *widget* with three explicit **bands**, not one
  continuous axis; show the discontinuity, don't smooth it.
- **Five acts → four surfaced acts** (LIVE/CAPTURE/REVIEW + internal RENDER);
  BROWSE/pick-four is proposed, not delivered.
- **The clean SEARCH/MODIFY split is the goal**; the as-built truth is "Groups +
  Look write the table, Cut is a lens."

First slice: **row reshape only** (Ship + Refine), Cut labelled honestly as
navigation, one write axis confirmed. Everything riskier (the Refine wizard
sub-FSM, the BROWSE FSM phase, any cut-commit path, leaf-override UI) is deferred
behind proven need. **This workflow implemented nothing.**
