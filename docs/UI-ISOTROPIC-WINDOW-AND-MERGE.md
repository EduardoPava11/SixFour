# THE ISOTROPIC WINDOW + THE MERGE — open-scene reorg & the decision game

Status: **PROPOSAL** (Daniel's remote brief, 2026-07-09). Extends
`docs/UI-FORM-FOLLOWS-FUNCTION.md` (the charter); same rule of law — name FUNCTIONS
first, derive FORM, every visualization names its spec quantity. Iterative over the
landed POUR/SCROLL/independent-rungs arc, not a replacement.

Interactive mockups (isotropic window demo, playable MERGE prototype, glyph family):
published as the "SixFour — The Open Scene & The Merge" artifact.

---

## §0 The brief (decoded)

1. Open scene: organize by symmetry and the grid; expand and categorize what the user
   sees; the preview is camera information that *alludes to* the capture.
2. The three rung views must be **the same size** — 16³ has 4× the color-time per
   frame of 64³, 32³ has 2×; equal squares, not a size-graded pyramid.
3. Explore **flat square views with an isotropic window** the user scrolls through —
   the user chooses which view to see.
4. Post-capture, the user trains the model **by making decisions**, inspired by
   **2048**: start at the 16³ view, decide 16³↔32³ until a threshold, then 32³↔64³.
   Tiles represent SKI sequences; the user tiles the plane with square GIFs; the goal
   is 64³ but intermediate boards mix granularities — decomposing large colors into
   smaller ones, spending signal.
5. The **y-hexagonal look** (the cube seen down its diagonal) as the visual language
   for the 3D pixel color space.

## §1 The open scene — one isotropic window

### The law that justifies equal size

`Spec.WeaveOrder`'s energy equality: dither pressure × 4^k color-time is
rung-invariant — one 16² frame banks the full energy of four 64² frames, one 32²
frame two. The size-graded `InvertedPyramidField` stack contradicts the instrument
framing (bigger tile reads as "more"); **equal display area = equal integrated
color-time per frame** states it. What genuinely differs between rungs is the
**heartbeat** (20/10/5 Hz realize cadence) and that difference stays visible — the
window repaints at the visible rung's honest cadence (`realize32`/`realize16`
already exist in `InvertedPyramidField.swift`).

### Function inventory → form

| Function | Spec quantity | Form |
|---|---|---|
| SEE the signal | realized rung tiles 64/32/16 | ONE 64×64-cell square window at the `field64` anchor (18,49) — the eye never moves (same law that pins `scrollScene.hero` there) |
| CHOOSE the view | rung index k | paged scroll through the window + three dimetric-cube glyphs as selector/position indicator |
| METER the energy | EV stops, √N significance, arrival cadence | the existing `rung64/32/16` flank rows; the **visible** rung's row expands, the others compress to one-cell summaries |
| CAPTURE | collapse → the 64³ cube | a **standalone fixed shutter control** (filled dimetric cube, FRAME face + BEAT); never scrolls, never freezes; inherits the 16²-vertex's banked-frame **ledger fill** (`updateLedger`, lawLedgerConserves) as its fill animation |
| TRUST the instrument | tick-CPU, buffer, thermal | `system` strip unchanged |

The 16²-tile-as-shutter dies naturally here: once views scroll, a control that is
sometimes off-screen is not a control (charter debt #1). The shutter becomes its own
region with the ControlFace algebra it already speaks (BRACKETS→FRAME, PRESSED,
BUSY, DISABLED, BEAT = `lawBeatIsPoolCadence`).

### Layout options

- **A · THE PAGER (recommended)** — horizontal paged scroll; neighbor rungs peek
  ~3 cells at the window edges (the scroll affordance); selector glyphs + expanded
  telemetry below; shutter fixed at the thumb line. Symmetric about the center
  column. BOOT RESOLVE maps to the selector: glyphs crystallize coarse→fine as
  `revealAt` crossings land.
- **B · THE LADDER RAIL** — vertical scroll, ladder order as the scroll axis.
  Honest to the rung order but the shutter competes with the scroll gesture and only
  ~1.4 views fit above the fold.
- **C · THE DECK** — three stacked with cell offsets, tap to cycle. Densest, but
  hidden rungs show only edges and the cadence difference (the information) is
  invisible.

### GridLayout impact (spec-first)

`liveScene` v2: replace the three `field*` bands with `window` 64×64 @(18,49) +
`selector` (3 glyph cells) + `shutter` (≥11×11 cells for the 44pt floor) + keep
`rung64/32/16` flanks, `intake` rails (per-visible-rung), `evRail`, `lookStrip`,
`fluxBar`, `system`. `lawSceneDisjoint` re-proves the scene; THE POUR overlays
re-anchor to the window. Pyramid code path stays behind a feature flag during
bring-up (`Feature.isotropicWindow`), per the compile-only device discipline.

### Categorizing what the user sees (the brief's "expand and categorize")

Five information families, each visually distinct and each naming its quantity:
**SIGNAL** (the window), **ENERGY** (EV/√N per rung), **TIME** (arrival pulse, pour
tallies, BOOT RESOLVE), **SYSTEM** (thermal/buffer/CPU), **ACTION** (selector,
shutter, LOOK/EV rails). Anything on Live that can't claim a family is a deletion
candidate — same knife as charter E10.

## §2 THE MERGE — the post-capture decision game

2048's loop (simple move → merge → new tile arrives → threshold unlocks) inverted:
instead of merging numbers upward, the player **decomposes coarse color into fine**,
spending banked signal. Every capture opens as the 16³ board; the goal is the fully
constructed 64³.

### The mapping

| 2048 | THE MERGE | Existing machinery |
|---|---|---|
| 4×4 board | the 64² plane as a **quadtree of regions**, each at depth 16/32/64 | `renderSelect` semantics — per-region chosen scale is already the render model |
| merge two equal tiles | **S** = split a region one rung finer · **K** = pool back coarser · **I** = hold | the 11 axis-graded SKI ops ({I}∪{K_x,K_y,K_t}∪{S_x,S_y,S_t}∪{S_xy,S_xt,S_yt}∪{S_xyt}); v1 ships S_xy/K/I via tap + long-press, axis-swipes are v2 (a swipe IS S_x/S_y; a time gesture IS S_t — AxisSKI's depth vector) |
| new tile appears each turn | each **POUR** (4-frame slice replayed) deposits signal | `ColorTimeDisplay` pour boundaries; intake-tally idiom already crosses scenes |
| score | **signal used** — banked color-time spent on decisions | √N significance, paletteW1 flux |
| reach 2048 | whole board at 64³ | the honest ceiling; never exceeded |
| your move order | the **decision word**, recorded at ACCEPT | `.s4cr` v3 key (`dw`), same argument as the weave word: `lawOrderIsInvisibleToTheMeasure` — order is real information no marginal keeps, so the record must |

### Why the decisions are training signal

Where the player chooses to spend fine evidence IS the taste section:
`Spec.ChoiceTraining` (accept/again on what wasn't painted), `Spec.MixSKI` (the
user's section over color — "these colors I like"), `Spec.CubeBrush` (the stroke
algebra: where + which scale, finest-wins — exactly the move algebra of the board),
`Spec.HaltDepth`/gene-compute-economy (SKI ops as the priced currency). None of
these have UI today (verified 2026-07-09) — THE MERGE is their front door, and it
replaces "painting as the everyone-mechanic" with **deciding**, which is the
ordering-is-natural thesis WeaveOrder already committed to.

### Rules (v1)

1. Board opens all-16 (4×4 regions; region = 16×16 GIF px). Signal starts small.
2. **Tap = S** (split to next depth, −1 signal). **Long-press = K** (pool back,
   mass kept, no refund — K keeps, it doesn't pay). **Doing nothing = I.**
3. Phase 1 allows 16↔32 only. Crossing the threshold unlocks phase 2 (32↔64).
   Threshold options: **(a) count** (12/16 regions at 32) — legible; **(b) energy**
   (banked √N at 32 crosses significance) — instrument-true. Recommend (b) surfaced
   as a fill bar.
4. **POUR** replays the next 4-frame slice of the burst and deposits signal
   (bounded session: 16 pours = the whole burst). Option: price ops from the SKI
   budget instead (HaltDepth) — can layer under (a) later.
5. A mixed board is a **legal render** (renderSelect field) — the mosaic is honest,
   never a failure state.
6. **ACCEPT** seals: board depth-field + decision word → `.s4cr`; training pairs →
   ChoiceTraining corpus. **AGAIN** recaptures. The game lives *between* the two
   verbs — it replaces the dead space in Decide, not the verbs (D3 stands; the
   advanced W1 paint bench stays behind the fold).

### GridLayout impact

`decisionScene` v2: `hero` becomes the board (64×64, BRACKETS face per region under
touch), add `signalBar` + `phaseGlyph` + reuse `tally` for pours; `again`/`accept`
verbs unchanged. Cell interactions ride `Spec.CellMechanics` verbatim: tap-vs-hold
is `lawDragRequiresHold`'s gate, CellTick detents on region boundaries, drop-verdict
pulse on illegal moves (locked phase / no signal).

### Spec-first build order

1. `Spec.MergeBoard` — quadtree depth-field + move legality (phase gate, signal
   ledger) + `lawMixedBoardRenders` (every board state is a renderSelect field) +
   `lawDecisionWordRecordsOrder` + golden traces. Codegen the Swift contract.
2. `.s4cr` v3: `dw` key (decision word, zigzag ints), v2 bytes pinned unchanged.
3. `Scenes/Decide/MergeBoardWidget.swift` (renders via existing sprite/cell vocab,
   per-region cadence honesty: a 16-region updates at 5 Hz).
4. ChoiceTraining wiring: sealed boards → training pairs (the corpus problem is the
   real problem — real bursts, per the standing lesson).

## §3 The y-hex language

The hexagon-with-a-Y is the cube seen down its body diagonal — three visible faces =
the three axes (x, y, t) of the color volume. One glyph family: **rung selector**
(subdivision 1/2/4 cells per face, hollow/inked), **shutter** (largest, face-filled;
pressing it fills the cube = collapse), **board badges** (per-region depth).

**Ruling already on file:** a true 60° hexagon anti-aliases on the cell grid —
`Spec.VoxelFit` proved the only AA-free form is the **2:1 dimetric cube**
(pixel-art isometric), sliders snapping to discrete rungs. Revive VoxelFit for the
glyph family; the retired `Surface.bakeCube` x/y shear rasterizer (git history,
noted at `Surface.swift:352`) is the reference implementation. This also re-lands
the "3D pixel color space" reveal the brief asks for, without re-opening the
retired live cube path.

## §4 Decisions to lock

| Decision | Recommendation | Why |
|---|---|---|
| Window layout | A · pager | shutter fixed + thumb-reachable; peek edges teach the scroll; symmetric |
| Shutter form | standalone dimetric cube, FRAME+BEAT, ledger fill | a control must read as a control; ledger behavior preserved |
| Threshold rule | energy (√N) | the instrument framing demands the real quantity |
| Signal economy | pours (v1), SKI pricing under it (v2) | bounded, teaches the burst's rhythm |
| Split verb | tap/long-press (v1), axis-swipes (v2) | ships fast; swipes unlock S_x/S_y/S_t literally |
| Where MERGE lives | inside Decide, between ACCEPT/AGAIN | the verbs are the exits; the game replaces dead space, not D3 |

## §5 What this does not touch

The capture path, GIF bytes, weave record v1/v2 compatibility, the pour schedule,
THE SCROLL, and the independent-rungs telemetry all stand. The pyramid view remains
compilable behind its flag until the window is device-verified (compile-only rule).
