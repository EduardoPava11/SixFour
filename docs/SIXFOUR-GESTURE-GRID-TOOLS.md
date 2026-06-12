# SixFour — Gesture-Grid Tools: the palette IS the widget, not a form

> Keywords: gesture-grid, the-grid-is-the-control, paletteControlField is wrong,
> 16×16 palette tool, 64×64 swipe-pick-four, 2⁸ σ-pair flex, compose-by-acts,
> honest global, Act III browse, scrub / tap / flex, no slider no selector.

**Status:** design + spec-first replacement plan (2026-06-12). Companion to
`SIXFOUR-ACTS-WORKFLOW.md` (the five-act one-surface flow — the home of every tool
here) and `SIXFOUR-WIDGETS.md` (Family 1 = the ladder/output, Family 2 = the
delta control/input, Family 3 = uncertainty). This doc does NOT duplicate those;
it states the interaction LAW the user taught, specifies the three tools + their
composition as gesture-grids, and sequences the replacement of the form that was
built wrong. Every claim about an existing function/spec below was read from the
tree on 2026-06-12 and is marked HONEST (exists) or GAP (does not exist yet).

---

## 0. THE CORE PRINCIPLE (what the user taught)

**The cell grid is the widget. You operate it by gesture ON the grid — swipe, tap,
drag, flex — never by a form control beside it.** A widget is an X/Y-sized region
of the 4 pt lattice whose own cells are the affordance. To choose, you touch the
thing; to adjust, you drag the thing; to navigate, you push the thing past your
thumb. There is no control that "operates" the grid from outside it. This is the
direct extension of the one-surface law (`Spec.Display.lawPhaseIsCellGrid`,
`ACTS-WORKFLOW §0`): a phase is a full-lattice cell-field, so its controls must
also be cells, not chrome laid over cells.

### What was built WRONG, and why

`ReviewPhaseField.paletteControlField` (`SixFour/UI/Surface/ReviewPhaseField.swift:308–368`)
is a **`VStack`** stacking, top to bottom:

1. a `CellText` title,
2. a **`CellSelector`** for the radix (16²/4⁴/2⁸) — a dropdown,
3. the 16×16 `paletteSurface` (DISPLAY-ONLY — its only gesture is tap-to-brush),
4. an `HStack` of two axis-cycle **`Button`s** (X / Y),
5. a `CellText` readout,
6. a **`CellSelector`** (ΔL/Δa/Δb channel) + a **`CellSlider`** (δ value),
7. an `HStack` of export **`Button`s**.

This is **traditional UI rendered in cells**: six form controls arranged in a
column *beside* a grid that merely shows the result. To edit one generator the
user taps the grid to brush it, then looks DOWN to a channel selector, then drags
a SEPARATE slider — three disjoint controls operating on the grid from outside.
The grid is a readout; every decision happens on a knob next to it. That is the
exact inversion of the principle. **It must be deleted, not refactored.**

The cure is not "make the form prettier." It is: **fold every one of those six
control-functions into a gesture on a grid surface that already exists in the act
flow.** Radix-choice → a swipe ON the 16×16 grid. Axis → a swipe ON the grid. The
δ → a drag of the brushed cell itself. Frame-selection → a tap on the 64×64 frame
you are looking at. Export → the one sanctioned non-grid surface (the OS share
sheet), reached by a single gated cell button. Nothing sits beside the grid.

---

## 1. THE THREE TOOLS (+ composition)

All three reuse the two docked `ColorIdentity` widgets — **`Field64` 64×64 cells
@ col 18,row 22** and **`Palette16` 16×16 cells @ col 42,row 145** (verified
`MovableLayout.hs:91`, cited in `ACTS-WORKFLOW §0`) — reconfigured per phase. No
new footprint, no new movable identity. Placement is `View.place(GridRegion)`
only (the lint-enforced sole API).

### Tool A — 16×16 PALETTE (inspect + σ-flex the global colour table)

- **Grid:** 16×16 cells = 64×64 pt = the **`Palette16`** footprint. 256 = 16²
  exactly — one cell = one leaf, zero waste; the ONE size that shows all 256
  legibly. Same surface in three faces (16²/4⁴/2⁸).
- **Headline gesture:** **horizontal swipe = cycle face** (16²→4⁴→2⁸); the grid
  re-lays its own 256 leaves. (This single graft deletes the radix `CellSelector`,
  line 314.)
- **Full vocabulary:**
  - TAP a leaf → SELECT it; σ-partner `slot^1` lights too on the 2⁸ face; all
    others opaque-darken 35 % (Law #2). Tap-again = release. (Reuses the EXISTING
    hit math + partner-light, `ReviewPhaseField:388,392–398`.) Honest framing: tap
    picks the edit target and reveals the σ-pair; it does NOT yet change a colour.
  - HORIZONTAL SWIPE → cycle FACE (replaces the radix dropdown).
  - VERTICAL SWIPE (16² face only) → cycle the LAB axis (replaces the two X/Y
    `Button`s, lines 322–329).
  - **FLEX** (long-press 0.3 to arm — `lawDragRequiresHold` — then drag the
    selected leaf): drag-to-coordinate is the δ. The cell's own (a,b) opponent
    direction is the chroma AXIS; the drag supplies magnitude+sign; a clearly
    separated vertical component is ΔL. Writes `paletteOverride[gen]`; the
    σ-partner gets exactly −Δa/−Δb (ΔL free) by construction — **you cannot author
    an asymmetric palette.** Replaces the δ `CellSelector`+`CellSlider`
    (lines 338–347).

```
TAP-SELECT (.b2 face)              FLEX (drag the lit leaf; partner mirrors)
┌────────────────┐                 t0 armed @ slot  t1 drag→ +Δa   t2 release
│░░░░░░░░░░░░░░░░│ others darken    [ ◆ ]            [ ··◆]        dropAccept
│░░░░◆◇░░░░░░░░░░│ ◆=slot ◇=slot^1   ◇                ◇··           override[g]=δ
│░░░░░░░░░░░░░░░░│ (σ-partner)      partner ◇ swings −Δa  (σ-locked, can't break)
└────────────────┘ cellTick        whole grid re-projects live via projectQ16
horizontal swipe ▶ cycles 16²→4⁴→2⁸   vertical swipe ▶ cycles LAB axis (16² only)
```

- **Honest data path (HONEST — every fn verified):**
  `palettesPerFrame` → `LadderExport.flatGlobalLeaves` (maximin
  `FarthestPointCollapse`, off-main, ~seconds) → `globalLeaves` [256 OKLabQ16,
  cached] → `BranchedPalette.projectQ16(globalLeaves, branching, paletteOverride)`
  → `LadderGIF.paletteToSRGB8` → the 16×16 cell fills **AND** the exported bytes
  (preview ≡ ship; the override threads into both, `Spec.LeafOverride`). This tool
  is the OUTPUT inspector + fine-tuner, NOT the collapser.
- **VERIFIED CAVEATS (do not paper over):**
  - `projectQ16` **ignores `override` for `.b16`/`.b4`** — the FLEX δ only bites
    on the **2⁸ face** today (`BranchedPalette.swift:37,43`). FLEX is a 2⁸-only
    verb until 4⁴/16² overrides are specced.
  - the `.b2` projection routes through **`SixFourNative.haarAnalyze/Reconstruct`
    (Zig FFI)** (`BranchedPalette.swift:88–124`) — NOT pure Swift. Re-projecting
    on the main thread per FLEX detent must be **measured at 20 fps or cached**
    (the `globalLeaves` are cached once; only the cheap reconstruct re-fires) —
    this is a `lawDeltaTotal` 20 fps risk flagged in
    `SIXFOUR-CAPTURE-FLUIDITY-SYSTEMS.md`, not a free operation.

### Tool B — 64×64 SWIPE → PICK-FOUR (Act III browse, the temporal tool)

- **Grid:** 64×64 cells = 256×256 pt = the **`Field64`** footprint. One cell per
  GIF pixel (cube law `gifCell(x,y,t)`), so the whole frame shows 1:1, and one
  column of horizontal travel ≈ one of the 64 frames — a real geometry/gesture
  coincidence.
- **Headline gesture:** **horizontal swipe = scrub the 64-frame burst; clean tap =
  pick/unpick the frame you are looking at** (cap 4, ordered).
- **Full vocabulary** (verbatim from `ACTS-WORKFLOW` Act III, already specced):
  - HORIZONTAL SWIPE (non-lift drag, so disjoint from long-press-MOVE by
    `lawDragRequiresHold`) → `scrubCursor(by: cellsCrossed)`; one `CellTick` per
    frame boundary; `EdgeStop` at 0/63, no wrap.
  - CLEAN TAP → `selectFrame`: toggle cursor frame in/out of `σ.picks` (green
    breath add / red flit remove / 5th rejected `DropReject`). Green corner ticks
    mark a picked frame on the cells.
  - LONG-PRESS-DRAG a filmstrip thumbnail → reorder the 4 (the picks are ORDERED;
    filmstrip order = quad order per User Decision C). The ONE lift gesture here.
  - TAP CONTINUE GATE (lit only at `picks==4`) → `Picked4` → `.rendering`.

```
SWIPE = scrub            TAP = pick (green ticks)     filmstrip (ordered)
┌──────────┐ swipe ┌──────────┐ tap   ⌜▓▓◍▓⌝         [f08][f23][ + ][ + ]
│ frame 23 │ ───▶  │ frame 24 │ ───▶  ⌞────⌟ picked   long-press-drag = reorder
└──────────┘       └──────────┘       2/4 → 3/4       [ CONTINUE → RENDER ] lit@4
scrub rail: |·····▲··|·····●··●··|   ▲=cursor head  ●=pick markers
```

- **Honest data path — THE 4 PICKS MUST ACTUALLY DO SOMETHING (this is the crux).**
  The captured cube is already in Σ at `BurstComplete` (`indexCube` 64³ +
  `palettesPerFrame` 64×256); browsing is a pure projection. The **load-bearing
  failure** to avoid: the adversarial review verified that **`projectQ16` takes NO
  picks, takes no sub-tree index** (`BranchedPalette.swift:38`), and
  **`flatGlobalLeaves`/`makeURL` pool ALL 64 frames with no `picks` argument**
  (`LadderExport.swift:38,77`). And **`Spec.PairTreeFixed` is a Haar
  analyze/reconstruct/move pyramid over the 256-leaf palette — it has NO
  pick/anchor/pivot input** (read 2026-06-12). Therefore the cited "picks select
  which 4⁴ sub-tree the collapse pivots on" story is a **GAP, not a wired path**:
  as the code stands today picks would change *nothing* downstream and the pick
  would be cosmetic.
  - **The honest one-line graft (option A-lite, recommended):** make picks select
    the **collapse input set** — `flatGlobalLeaves(palettesPerFrame[picks])`
    instead of all 64. That is a real, existing-function change, matches the
    vision's "the 4 frames define the structure," and makes the global genuinely
    built FROM the 4. It needs no invented `projectQ16` hook.
  - **The User-Decision-C path (in-grammar quad pivot)** requires a NEW spec —
    `Spec.QuadPivot` (GAP) — defining how 4 ordered frame indices choose a
    `PairTreeFixed` sub-tree, plus a Swift `projectQ16` pick argument and a golden.
    Until that exists, do NOT advertise it as wired (§5 open decision).

### Tool C — 2⁸ "DIFFERENT": the σ-PAIR LEARN grid (motion-cored, not a fold)

The user asked for "2⁸ = something different — the σ-pair / LEARN structure as a
gesture-grid." The honest different-ness is **the σ-pair physics made the gesture
and the quartet's motion made the readout**, NOT a new geometry:

- **Grid:** the SAME 16×16 `Palette16`, **row-major** (the shipped `.b2` layout,
  `ReviewPhaseField:426`, which already adjacents σ-pairs at `2i,2i+1`).
- **Headline gesture:** **PINCH-A-PAIR (tap) → FLEX (drag-to-δ) with the adjacent
  partner moving equal-and-opposite IN PLACE.** Tap a generator; its `slot^1`
  neighbour lights (existing law); FLEX drags its colour and the partner mirrors
  −Δa/−Δb. This is Tool A's FLEX on the 2⁸ face — the "asymmetry is
  unrepresentable" property IS the different-ness.
- **The genuinely DIFFERENT readout (HONEST — spec exists):** overlay the
  **`Spec.QuartetDelta`** field on the grid. `QuartetDelta` (read 2026-06-12)
  already turns the **4 picked frames** into a per-slot OKLab trajectory: `core`
  (slot mean) + `displacement` (path length over the 3 transitions). Render
  displacement as cell intensity → the user SEES which colours are the moving
  motion-outline vs the stable core that the 2⁸ Haar ribbon should protect. This
  is the honest, golden-gated way to "see the 4," and it directly links Tool B's
  picks to Tool C's surface — **NOT a fabricated R/G/B channel split.**
- **REJECTED idea (recorded so it is not re-attempted):** the "mirror-fold across
  col 8" (left half = generators, right half = σ-mirrors). It contradicts the
  shipped row-major adjacency (`slot^1` is the NEIGHBOUR, not a col-8 mirror), its
  signature "fold opens" animation is dead on ΔL (σ shares L), and it needs a new
  unspecced layout. **Keep the FLEX, kill the fold.**

```
2⁸ LEARN face (row-major, σ-pairs adjacent):
 tap generator g → g and g^1 light → FLEX g → g^1 mirrors −Δa/−Δb in place
 QuartetDelta overlay: dim cell = stable core (protect)   bright cell = high motion
 (the "see the 4" readout = displacement of the 4 PICKED frames, golden-gated)
```

### Tool D — COMPOSITION: the act SEQUENCE is the wiring, not a 4th panel

The tools compose by the **act FSM edges**, not by stacking:

```
Act III .browsing   →  Act IV .rendering:*       →  Act V .review
Tool B: Field64        the collapse runs            Tool A: Palette16 16² inspect + cut
 swipe-pick 4          (consumes σ.picks via         + Tool C: Palette16 2⁸ flex/QuartetDelta
                        the §5 honest graft)
edge: (Capturing,BurstComplete)→Browsing ; (Browsing,Picked4)→Rendering(.quantize) ;
      (Rendering(encode),Committed)→Review ; (Review,applyGenome)→Rendering(encode)→Review
```

- 16³ GLOBAL = `projectQ16(globalLeaves, branching, override)` **as shown live in
  Tool A** = the working/preview rung (HONEST: preview ≡ ship).
- 64³ GLOBAL = `LadderGIF.reindexCubeToGlobal(indexCube, paletteToSRGB8(that same
  projection))` + `GIFEncoder.encodeGlobal` on Save/Apply (HONEST: existing spine).
- One palette object, two sampling rates — that is the honesty law. The 4 picks
  enter this only via the §5 graft; until then they bias nothing.

---

## 2. WHERE EACH TOOL LIVES IN THE ACTS (cite, don't duplicate)

Per `SIXFOUR-ACTS-WORKFLOW.md`:

- **Tool B (pick-four) lives in ACT III `.browsing`** (the PROPOSED-NEW phase,
  `ACTS-WORKFLOW §1 Act III`, mockup `docs/acts/act3-browse.svg`). This is where
  global-building gestures belong — NOT bolted into Review. The new edge
  `(Capturing,BurstComplete)→Browsing` REPLACES the current direct
  `→Rendering(.quantize)` (`Surface.swift` FSM ~line 105; `ACTS-WORKFLOW §2`
  rows 1–7).
- **Act IV `.rendering:*`** is the non-interactive collapse where the picks are
  consumed (serpentine reveal, `ACTS-WORKFLOW §1 Act IV`).
- **Tool A (16² inspect + cut) and Tool C (2⁸ flex) live in ACT V `.review`** as
  faces of the ONE `Palette16` widget (`ACTS-WORKFLOW §1 Act V`). They map to
  **`SIXFOUR-WIDGETS` Family 2** (the delta control: 4⁴ RGBT face + cut-lever +
  σ-mirror nudge — status there: "exist in spec; UI not wired"). Family 1 (the
  ladder/output) is the Save/Apply target; Family 3 (uncertainty) supplies the
  QuartetDelta/coverage intensity the cells render.
- **ACTS-WORKFLOW Act V must be AMENDED:** its current §1 text still prescribes a
  "CUT slider (272×8 pt track)", a "3-way tree selector (≈40×18 pt segments)" and a
  "scope toggle" — the exact form pattern the user rejects. Replace with: face =
  horizontal swipe on the grid; cut = vertical gesture that FUSES cells; scope =
  corner-tap. (Open: cut-gesture/face-swipe/tap disjointness, §5.)

---

## 3. BUILD PLAN — replace `paletteControlField` with the gesture tools

Sequenced; each step is spec-first where it touches the source of truth, then the
Swift port is verified against the golden. Bar per `CLAUDE.md` = `cabal test` green
+ `spec-codegen` + iOS BUILD SUCCEEDED (compile-only; the user runs on device).

**Step 1 — DELETE the form, keep the renderer.** Remove `paletteControlField`
(`ReviewPhaseField.swift:308–368`) and its `CellSelector`/`CellSlider`/axis-`Button`/
export-`Button` rows. KEEP `paletteSurface` (the `CellSprite` + hit math + `darken`)
and the data path (`projectQ16`/`paletteToSRGB8`/`globalLeaves`/`paletteOverride`).
Re-home `paletteSurface` as the docked `Palette16` (`.place(region(for:.palette16))`),
not a centered VStack child. (No spec change; lint-grid clean.)

**Step 2 — Build Act III `.browsing` (Tool B).** This is the biggest, already-specced
piece. SPEC-FIRST: add the `Browsing` phase + `SelectFrame`/`Picked4` events + the
`BurstComplete→Browsing` rewire to `Spec.Display`; `σ.picks:[Int]` (cap 4) +
`scrubCursor(by:)`; extend `goldenHappyPath` (`ACTS-WORKFLOW §2` table, all 7 rows).
THEN port `BrowsingPhaseField.swift`: scrub gesture (NEW — generalize `lookSwipe`
from `.onEnded` to `.onChanged` + `cellsCrossed` detents; it is a NEW gesture, NOT a
verbatim reuse), tap-select, filmstrip reorder (existing move FSM, constrained),
continue gate. Prerequisite: Act II reverse cursor (`captureReverseCursor` golden).

**Step 3 — Make the picks HONEST (the §1-Tool-B graft).** Either (A-lite) thread
`palettesPerFrame[picks]` into `flatGlobalLeaves` (existing fn, one real change,
add a golden that the 4-frame collapse differs from the 64-frame one), OR write
`Spec.QuadPivot` + a `projectQ16` pick argument + golden for User-Decision-C.
**Do not ship Tool B claiming picks matter until this step lands** (else the pick
is cosmetic — the exact fake-data-path failure to avoid).

**Step 4 — Tool A gesture set on `Palette16` in `.review`.** SPEC-FIRST: add
`Spec.PaletteGesture` proving the recognizers PARTITION the input space (tap-select
vs long-press-FLEX vs horizontal-face-swipe vs vertical-axis-swipe) — mirrors how
`Spec.CellMechanics` proves move-vs-tap; pin the drag→δ decode (2-D drag → 3-D OKLab
δ, the lossy axis) with a golden. THEN port the gestures onto `paletteSurface`.
MEASURE the `.b2` re-projection (Zig FFI) at 20 fps; cache or move off-thread if it
stalls.

**Step 5 — Tool C: 2⁸ FLEX + QuartetDelta overlay.** FLEX is the same
`Spec.PaletteGesture` δ-decode on the 2⁸ face (no new geometry — row-major,
existing `slot^1` law). Add a Swift port of `Spec.QuartetDelta`
(`slotDisplacement`/`coreColors`) verified against its existing golden, and render
displacement as cell intensity over the picked-4. (`QuartetDelta` exists in spec;
**no Swift twin yet** — that port is genuinely new.)

**Step 6 — Amend `SIXFOUR-ACTS-WORKFLOW.md` Act V** to retire the slider/selector
prose (§2 above), so the doc and the tools agree.

### What is REUSED vs genuinely NEW

- **REUSE (verified to exist):** `CellSprite`, `.place(GridRegion)`, the tap-vs-hold
  split + `lawDragRequiresHold` (`MovableColorWidget`), `cellsCrossed`/`snapToAtom`/
  Haptics 0–4, `paletteSurface` hit math + `slot^1` partner-light + `darken`,
  `projectQ16` / `paletteToSRGB8` / `flatGlobalLeaves` / `reindexCubeToGlobal` /
  `GIFEncoder.encodeGlobal`, `paletteOverride[128]`, the `Spec.QuartetDelta` &
  `Spec.PairTreeFixed` Haskell specs, the move FSM for filmstrip reorder.
- **GENUINELY NEW:** `BrowsingPhaseField.swift` + the `.browsing` FSM additions; the
  ongoing-scrub gesture (`lookSwipe` is `onEnded`-only — NOT a verbatim reuse); the
  picks→collapse honest link (Step 3); `Spec.PaletteGesture` (partition proof +
  drag→δ golden) — **does NOT exist**; a Swift `QuartetDelta` port.
- **MUST BE SPEC-FIRST (golden before Swift):** the `.browsing` phase/events/trace;
  the picks→collapse graft; `Spec.PaletteGesture`; (if Decision-C) `Spec.QuadPivot`.

### What does NOT exist despite being cited elsewhere (do not rely on)

- **`Spec.CollapseLever` is NOT in `spec/`** (only the UIUX doc
  `SIXFOUR-COLLAPSE-LEVER-UIUX.md`; the memory note's "COMPILES, 6 laws GREEN" is
  branch-only/stale). The cut-fuse mechanic must be specced before it is a law.
- The 4⁴/16² overrides in `projectQ16` (FLEX bites only on 2⁸ today).
- Any function mapping 4 frame indices → R/G/B/T channel panels (that "see as RGB"
  framing is a category error — the 4⁴ quadrants are LEAF-space tree nodes, not the
  4 chosen FRAMES). Use the QuartetDelta motion readout instead.

---

## 4. THE GRID-IS-THE-CONTROL LAW (for lint / future tools)

For any new palette/genome tool: **(1)** it occupies an existing widget footprint
(64×64 or 16×16), placed by `.place`; **(2)** every parameter the old form exposed
becomes a gesture ON that surface — choice = swipe, magnitude = drag-to-coordinate,
selection = tap; **(3)** zero `CellSelector`/`CellSlider`/`Button` BESIDE the grid
(the only sanctioned non-grid surface is the OS share sheet via one gated cell
button); **(4)** overlapping recognizers must be proven disjoint by a `Spec.*`
partition law before the Swift port. A tool that adds a control beside the grid is
the lint failure, exactly as `paletteControlField` was.

---

## 5. HONEST DEFERRALS & OPEN DECISIONS

1. **HOW the 4 picks map to R/G/B/T — UNRESOLVED and the most important gap.** The
   user's prose ("see those 4 as R, G, B") reads like channel DECOMPOSITION
   (option A); User Decision 2026-06-08 chose (C) in-grammar 4⁴ quad pivot. **Both
   are currently UNWIRED** (no `projectQ16` pick hook; `PairTreeFixed` has no pivot
   input; collapse pools all 64). Recommendation: ship the **honest A-lite graft**
   (`flatGlobalLeaves(palettesPerFrame[picks])` — picks select the collapse INPUT
   set, the global is genuinely built from the 4) and use **`QuartetDelta` as the
   "see the 4" readout** (core/motion, golden-gated), NOT a fabricated RGB split. If
   the user truly wants Decision-C's quad pivot, that needs a new `Spec.QuadPivot`
   first. **Decide before building `BrowsingPhaseField`'s reveal panel.**
2. **`Spec.PaletteGesture` partition proof does not exist.** Four+ recognizers on a
   64×64 pt surface (tap / long-press-FLEX / horizontal-face / vertical-axis or
   -cut) overlap in input space; the FLEX-δ-drag and the cut-vertical-drag are both
   free drags and WILL collide. Cleanest axis split: horizontal = face, vertical =
   cut, clean-tap = brush, long-press = FLEX — but it must be a proven law, not an
   assertion.
3. **2-D drag → 3-D OKLab δ loses a DOF.** The cell's intrinsic (a,b) direction
   supplies the chroma axis; the drag supplies magnitude+sign; ΔL needs a clearly
   separated vertical channel. Pin with a golden or it drifts from the NN's 384-DOF
   σ-pair genome. (The old explicit ΔL/Δa/Δb selector was lossless; the gesture
   trades precision for directness — accept consciously.)
4. **`.b2` re-projection is Zig FFI on the main thread** — measure at 20 fps before
   claiming `lawDeltaTotal` holds; cache/offload if needed.
5. **σ-pair gamut rejection:** a δ valid for the generator may push the σ-partner
   out of sRGB — gamut-check the MAX over the pair each tick or `preview ≡ ship`
   silently breaks.
6. **Cut-fuse needs a spec.** `Spec.CollapseLever` is not in the tree; the
   vertical-drag-fuses-cells mechanic must be specced + goldened before it ships.
```

---

## RESOLVED — the pick→palette data path (user decision, 2026-06-12)

**64 = 16 groups × 4 frames; each group of 4 IS one RGBT unit (equal weight).** This is
the honest factorization the picks ride, replacing the cosmetic-pick problem:

- Partition the 64-frame burst into **16 groups of 4 consecutive frames** `g = 0..15`,
  `frames[4g .. 4g+3]`.
- Within a group the 4 frames are the **R, G, B, T** axes at equal weight — the **4⁴**
  structure, now grounded in real captured frames (not abstract leaf-quadtree).
- The **16 groups** are the **16²** palette axis (the "16" of the 16×16). So
  `64³ → 16³ global` = "collapse each of the 16 RGBT-quads to one palette entry."
- The user **chooses among the 16 groups** (and sees each group's 4 frames as R/G/B/T)
  to shape the global palette they like — **the UI must GIVE the user this knowledge**
  so the choice is informed, not blind.

**Consequence for the tools:** Act III's 64×64 swipe tool browses the burst *as 16 RGBT
groups* (not 64 anonymous frames); "pick 4" becomes "pick/weight groups, each seen as its
4 RGBT frames." The honest backend is a real spec — `Spec.GroupRGBT` (TO WRITE):
`64 frames → 16 RGBT-quads → per-group analysis → global`, golden-gated, threaded into
`flatGlobalLeaves` so the choice drives the shipped GIFB (`preview ≡ ship`).

## Build decision (user, 2026-06-12): DELETE the form, build Act III first

1. **Delete** `paletteControlField` + its sub-state/entry/δ-row (the VStack form) — the
   thing the user rejected. Backend kept (`projectQ16(override:)`, `Spec.LeafOverride`,
   `LadderExport`, the Save ladder).
2. **Act III `.browsing` spec-first**: new `.browsing` FSM phase + `SelectFrame`/`Picked4`
   events + scrub cursor, golden-trace gated (`SIXFOUR-ACTS-WORKFLOW.md` §3).
3. **64×64 swipe-scrub + group-pick widget** (`BrowsingPhaseField`), browsing the burst as
   16 RGBT groups; reuse `lookSwipe` scrub + tap-pick + `CellSprite` + `.place`.
4. **Then** the 16×16 palette + 2⁸ gesture tools (re-dock `paletteSurface`, kill the form).
