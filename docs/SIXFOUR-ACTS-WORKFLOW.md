# SixFour — The Five Acts: One Surface, No Screens (UI/UX workflow)

> Keywords: one-surface law, SurfacePhase, cell-grid configuration, reverse cursor,
> browse-and-pick-four, deterministic render reveal, empty-cell data fill, DiversityRing,
> Spec.Display FSM, CellMechanics, GRID v3.0 4 pt atom.

**Status:** design + spec-first build plan (2026-06-08). Companion to
`SIXFOUR-DISPLAY-FSM.md` (the FSM `M=(Σ,ι,δ,λ,Π,κ)`) and `SIXFOUR-FOUR-GIF-UIUX-WORKFLOW.md`.
Per-act SVG mockups: `docs/acts/act{1..5}-*.svg` (canvas 400×872 pt, rounded corners,
faint 4 pt cell grid). SixFour owns all code; Haskell spec (`Spec.Display`) is the source
of truth, codegen-pinned to `Generated/DisplayContract.swift` → `SixFour/UI/Surface/`.

---

## 0. The one-surface principle (restated, law-cited)

There are **NO screen swaps**. The whole app is ONE persistent cell field — `SurfacePhase`
is a *phase of one Σ*, not a view. Every "act" is a **cell-grid CONFIGURATION** of that one
surface; every transition is a cell update, never a `present`/`push`.

This is a **theorem**, not a convention:

- `Spec.Display.lawPhaseIsCellGrid` (PHASE-T3): `∀ p. |phaseField p s| == |allPlaces|` —
  *every* phase observes as a full-lattice cell-field configuration, so a phase is a grid of
  cells, never a screen. (`Display.hs:504`.)
- `lawPhaseTotal` (PHASE-T1): `step` is total over every `(phase, event)` — the catch-all
  self-loop means an out-of-band event never derails the surface. (`Display.hs:487`.)
- `lawNoOrphanPhase` (PHASE-T2): every phase is BFS-reachable from `Bootstrap`. (`Display.hs:492`.)
- `lawReviewExplicit` (PHASE-T4): `Review` is entered ONLY by `Committed` — a single-edge
  transition, no implicit `primaryOutput != nil` predicate. (`Display.hs:512`.)
- `lawDeltaTotal` (T5): `δ_capture` writes EVERY cell each tick (`touched == fullLattice`).
- `lawOneClock` (T2): exactly one κ (one 20 fps `CADisplayLink`); both capture ingest and
  review playback are fired by it. `logicRateHz == captureRateHz == 20` (`lawCapturePhase`, T7).

**The gauge.** Σ = `(palette, indexCube, cursor)` carried as integers, observed up to the
`S_K` gauge (`lawGaugeInvariant`, T6). Out-of-band data — progress fraction, picks set, error
text — lives in Σ's fields / `CaptureViewModel`, **never in the event alphabet**, so `step`
stays a small total function. **Any new act-data MUST follow this discipline.**

### Ground geometry (verified, not asserted)

- **Atom** `gifPx = 4 pt` (`Spec.Lattice:107`, GRID v3.0). One pitch. `View.place(GridRegion)`
  is the ONLY placement API (`SixFour/UI/ScreenLattice.swift`).
- **Lattice** `cols = 100` (=400 pt) × `rows = 218` (=872 pt) (`Lattice.hs:128/132`).
- **Widgets** (`Spec.MovableLayout`, `ColorIdentity = Field64 | Palette16 | DiversityRing`,
  `MovableLayout.hs:91`):
  - `Field64` 64×64 cells = **256×256 pt**, dock (col 18, row 22). col 18 = (100−64)/2 ⇒
    horizontally centred. `cwInteractive = False`.
  - `Palette16` 16×16 cells = **64×64 pt**, dock (col 42, row 145). col 42 = (100−16)/2 ⇒
    centred. `cwInteractive = True` — **IS the shutter** (64 pt > 44 pt touch floor).
  - `DiversityRing` 20×20 cells = **80×80 pt**, dock (col 40, row 170). `cwInteractive = False`,
    **renders NOTHING today**.
- **Render files** (the Π per phase): `SixFour/UI/Surface/{LivePhaseField,CapturingPhaseField,
  RenderingPhaseField,ReviewPhaseField,SurfaceView,PhaseField}.swift`; Σ in `Surface.swift`.
- **Σ accessors** (`Surface.swift`): `palette` (256 sRGB8), `palettesPerFrame` (64×256),
  `indexCube` (64·64·64, row-major t,y,x), `previewTile`/`previewPalette` (live 64×64 cells),
  `cursor` (Z₆₄), `gifCell(x,y,t)` / `cellGlobal(x,y,t)`. `advanceCursor()` = the κ frame step.

---

## 1. The five acts (in order)

Each act names its **phase token**, the **centred widget composition** (cells + pt), the
**interactions → FSM events**, the **CellMechanics feedback**, its **SVG**, and the **FSM
additions** it requires.

### ACT I — OPEN / LIVE  →  `live`
**SVG:** `docs/acts/act1-live.svg`

The resting state and the only entry to capture. The whole 400×872 pt surface is the living
checker ground (`TintedCheckerField`, palette-tinted, 20 fps parity invert), with two centred
heroes stacked on it.

**Composition (centred by construction):**
- **Field64** live preview — 64×64 cells = 256×256 pt, col 18, row 22 (or PROPOSED row 30 to
  balance the stack below the Dynamic Island; an open Q). Each cell =
  `previewTile[r·64+c]` resolved through `previewPalette`; ghost ink `(20,20,24)` before frame 0.
- **Palette16** = SHUTTER — 16×16 = 64×64 pt, col 42, row 145 (thumb zone). 256 colours as a
  16×16 swatch via `GridScript.capture(side:16)`.
- **DiversityRing** — 20×20 = 80×80 pt; today dock (40,170), PROPOSED moved to row 110 (mid
  gap) to host its live `effectiveDim/3` arc (`Spec.Diversity`).
- **Data bands** fill the gap: coverage ribbon (Headroom A, 64×10 cells = 256×40 pt, rows
  96–105) + readiness status line (Headroom B, 40×7 cells, rows 168–174).

**Interactions → events:**
- TAP Palette16 (clean tap, no movement) → `Surface.step(.shutterTap)` → `δ(.live,.shutterTap)
  = .locking`. Gated `phase == .live`; a composed gesture, **no Button wrapper**.
- LONG-PRESS + DRAG Palette16 → CellMechanics lift FSM (Resting→Pressed→Lifted), drag detents
  to the 4 pt lattice, release tests `MoveContract.dropAccepts` (disjointness). Tap and
  long-press composed `.exclusively` so a clean tap never lifts.

**Feedback:** living ground inverts parity every κ (the liveness pulse). Palette16 press-down
= Q16 pulse brightening the swatch; shutterTap = a `cellTick`-feel transition. Move path =
`liftPop`/`cellTick`/`edgeStop`/`dropAccept`(green)/`dropReject`(red).

**FSM additions:** **NONE required** — `.live`, `.shutterTap`, the move FSM and κ all exist.
RECOMMENDED additive enrichments: (1) activate the DiversityRing render (a Π read of
`Spec.Diversity`, no FSM change); (2) add Headroom/ring `GridRegions` to
`Spec.GridLayout.captureScene` (re-prove disjointness); (3) IF Field64 moves to row 30, update
`MoveContract.defaultRow(.field64)` and re-fold the move golden.

### ACT II — CAPTURE (no freeze, plays backwards)  →  `capturing`
**SVG:** `docs/acts/act2-capture.svg`

On `shutterTap` the preview **MUST NOT FREEZE**. `.live --shutterTap--> .locking --lockComplete
--> .capturing`. The reverse playback is a **Σ behaviour inside `.capturing`**, not a new phase
(one-surface law). `.locking` = dressed pre-roll (all-ghost progress); `.capturing` turns the
reverse cursor + ring fill on.

**Composition:**
- **Field64** (256×256 pt) renders `indexCube` at the **reverse cursor** `t_rev` (newest→oldest
  scan over the captured prefix). Not-yet-landed tail = ghost ink → a visible growing front.
- **Palette16** (64×64 pt) = burst PROGRESS: the rank-order `paletteProgress` fill (captured
  slots solid, rest ghost) + a concentric sweep arc, fraction = `capturedFrames/64`.
- **DiversityRing** begins a running LAB-coverage gauge (today nothing).
- **Empty regions get data:** TOP "t/64 captured" readout + 64-tick burst timeline (256 pt × 6
  pt = 4 pt/tick); MID 8×8 filmstrip of landed/ghost thumbnails; LEFT per-frame coverage
  sparkline; RIGHT the LOCKED capture params (ISO/EV/WB frozen at `lockComplete`).

**Interactions → events:** deliberately **INERT** for movement/selection (pick-four is Act III).
The only advancing events are engine-driven: `.lockComplete` → `.capturing`; per landed frame
the engine appends to Σ (one `CellTick` haptic each); `.burstComplete` → `.rendering(.quantize)`.
NEW κ behaviour: each tick advances a **reverse cursor**, not `advanceCursor()` (forward).

**Feedback:** reuse `CellTick` as the per-frame-landed pulse — exactly 64 ticks across the burst
(mirrors `lawTickConservation`). Progress arc + 256-cell fill use the calm Accept-family tint
(no red — capture cannot "reject"). At `.burstComplete` a single success notification ("all 64
caught").

**FSM additions:**
- **(A) REVERSE-CURSOR during `.capturing`** — add a pure spec fn beside
  `PlaybackClock.frameAfter`, e.g. `captureReverseCursor :: capturedCount -> tick -> Int`,
  pin a golden, and have `SurfaceClock` call it (not `advanceCursor`) while `phase == .capturing`.
  This is the ONE FSM-data addition the act requires; it closes the named flow gap.
- **(B)** a `capturedFrames` count in Σ (or derive from `palettesPerFrame.count`) so the arc
  fraction and the reverse-cursor bound read ONE source.
- **(C)** NO new event — the engine appends to Σ; the renderer/haptic react to `capturedFrames`
  changing. Only existing `.lockComplete` / `.burstComplete` are FSM events. **No new SurfacePhase.**

### ACT III — BROWSE & PICK FOUR  →  `browsing` (PROPOSED-NEW phase)
**SVG:** `docs/acts/act3-browse.svg`

After the burst, let the user inspect EACH of the 64 frames and curate exactly FOUR. The cube
already lives in Σ the moment `burstComplete` fires, so browsing is a **pure projection of Σ at
a finger-driven cursor** — no new data engine. Field64 becomes `interactive = True` for the
first time. New edge: `capturing --burstComplete--> browsing --picked4--> rendering(.quantize)`.
`lawPhaseIsCellGrid` holds (`|phaseField browsing s| == |allPlaces|`). New Π:
`BrowsingPhaseField.swift`.

**Composition:**
- TOP STATUS STRIP (rows 14–21): "BROWSE | frame 23/64 | picked 2/4" — fills the dead band.
- **Field64** the scrubber (256×256 pt, col 18, row 22): shows `gifCell(x,y,cursor)`; green
  corner ticks when the current frame is a pick.
- SCRUB RAIL (64×3 cells = 256×12 pt, col 18, row 89): 64 ticks, cyan cursor head, 4 green pick
  markers.
- PICK-FOUR FILMSTRIP (rows 99–115): 4 thumbnails each 16×16 cells = 64×64 pt (centred:
  4·64 + 3·8 = 280 < 400).
- OPEN-Q CALLOUT (rows 119–136): amber strip stating the unresolved "what are the four?".
- **Palette16** (col 42, row 145) MIRRORS the cursor frame's per-frame palette (inert here).
- **DiversityRing** (col 40, row 170) finally renders: a 64-tick coverage gauge of the 4 picks.
- CONTINUE GATE (72×11 cells = 288×44 pt = exact HIG floor, col 14, row 200): dim until
  `picks==4`.

**Interactions → events:**
- HORIZONTAL SWIPE on Field64 = SCRUB: a Pressed→Lifted drag whose `cellsCrossed` advances
  `cursor` (`deltaReview` Z₆₄ successor/predecessor). ONE `CellTick` per frame boundary
  (`lawTickConservation`); `EdgeStop` at 0/63 (no wrap during curation). The long-press-to-MOVE
  binding on Field64 is suppressed (`enabled:false`) so the lift gesture is repurposed for
  scrubbing — widget stays docked.
- CLEAN TAP on Field64 = `selectFrame` (NEW): toggles the cursor frame in/out of the 4-pick set
  (a self-loop on `.browsing` mutating `σ.picks`). Add = green pulse + filmstrip slot fills;
  re-tap = remove (red flit); 5th pick rejected (`DropReject`).
- TAP filled FILMSTRIP thumbnail = jump cursor / remove.
- TAP CONTINUE GATE (enabled only `|picks|==4`) = `picked4` (NEW) → `.rendering(.quantize)`.
- κ does NOT auto-advance the cursor in `.browsing` (finger-driven); κ only drives the ground.

**Feedback:** `CellTick` per frame boundary; `EdgeStop` at 0/63; on add `LiftPop`-confirm +
green breath (`verdictInk Accept (70,200,90)`); on remove/reject red flit (`verdictInk Reject
(220,60,60)`). Continue gate breathes slow green the instant `picks==4`. All via the existing
`tintLerpQ16` + `pulseSampleQ16` integer path (ports byte-exact).

**FSM additions:** NEW phase `Browsing`; NEW events `SelectFrame` (toggle; index + pick-set live
in σ, NOT the alphabet) and `Picked4`; NEW δ edges — `(Capturing,BurstComplete)→Browsing`
(REPLACES the current direct `→Rendering minBound`), `(Browsing,SelectFrame)→Browsing` (self-
loop), `(Browsing,Picked4)→Rendering Quantize`, `(Browsing,Retake)→Live` (escape), `(Browsing,
Fault)→Error` (covered by the catch-all); σ adds `var picks:[Int]` (cap 4) + `scrubCursor(by:)`
distinct from `advanceCursor`; guard `Picked4` accepted only when `picks.count==4`; extend
`goldenHappyPath` with `SelectFrame×4 + Picked4` between `BurstComplete` and `StageDone Quantize`
and regen `goldenPhaseTrace`. **Prerequisite:** Act II reverse-cursor (so capture flows into
browse without a freeze).

### ACT IV — RENDER  →  `rendering:{quantize,dither,significance,palette,encode}`
**SVG:** `docs/acts/act4-render.svg`

Make the deterministic fixed-point Zig pipeline VISIBLE as a sequence of cell transforms — never
a spinner. The GIFA resolves into existence under a serpentine sweep across the centred Field64.
**No new phase** — reuses the existing `rendering(*)` family.

**Composition:**
- **Field64** resolve hero (col 18, row 22): `cellGlobal(x,y,cursor)`; cells whose serpentine
  rank < `progress·4096` show resolved, the rest are opaque ghost — image REVEALED in
  `Spec.Order.serpentine` order over 5 stages (each owns a 1/5 band). The front edge row = a
  bright accent line.
- LEFT GUTTER STAGE LADDER (cols 0–17): five cells (quant/dither/signif/palet/encod). Done =
  green `(47,107,58)`; current = amber `(200,162,58)` + pulse + 1.5 pt outline (9×9 cells = 36
  pt, one atom larger); pending = ghost.
- MID DATA REGION (rows 86–144): per-stage LIVE METRIC — a big counter (e.g. "slots backed
  214/256"), a 16×16 (128 pt) slot-map (significant=green, donating=amber), a 5-segment
  progress bar (256×8 pt).
- **Palette16** (col 42, row 145) INERT — draws the CURRENT-STAGE collapsing palette.
- **DiversityRing** (col 40, row 170) — `Spec.Coverage` LAB-volume arc.
- RIGHT GUTTER byte-meter (cols 82–99) — ghost until encode, then fills as LZW output grows.

**Interactions → events:** **INTENTIONALLY non-interactive** (a render state is a cell
transform, never a button — matches `CapturingPhaseField.allowsHitTesting(false)`). Only
FSM events from the Zig driver advance: `stageDone:quantize→dither→significance→palette→encode`
(encode self-loops, `lawReviewExplicit`); `committed → review`; `fault → error`. CellMechanics
gesture FSM is NOT engaged.

**Feedback:** the current-stage ladder cell PULSES (`pulseSampleQ16`/`tintLerpQ16` on κ) as a
"kernel is live" heartbeat. Each `stageDone:*` snaps the cell amber→green-done + fires `CellTick`
("stage advanced"). `committed` → `DropAccept` (the GIFA "landed"); `fault` → `DropReject`. The
serpentine front edge is itself moving visual progress.

**FSM additions:** NONE required for the happy path. OPTIONAL (spec-first if adopted): (1) a
stage-local `stageProgress: Int 0..256` field in Σ backed by the Zig kernel's real counter, so
the reveal is continuous within a stage (today `RenderingPhaseField` fakes it from stage index)
— Spec home `Spec.Display.phaseField` or a new `Spec.RenderProgress`, pin a golden; (2)
`hapticOnRenderTransition` dispatch reusing existing `CellTick`/`DropAccept`/`DropReject` tokens
(no new tokens) in `Spec.CellMechanics`; (3) deferred `abort` event for a long-press cancel.

### ACT V — REVIEW  →  `review`
**SVG:** `docs/acts/act5-review.svg`

The committed GIFA is the verdict. Reachable ONLY via `.committed` (`lawReviewExplicit`). The
user (a) WATCHES the 64-frame loop at 20 fps through its true per-frame palette, (b) READS
capture quality (coverage / eff-dim / diversity), (c) STEERS the collapse via the lever
(tree 16²/4⁴/2⁸ × cut-level → ONE palette), (d) SHIPS one cube rung {16³,64³,256³} or retakes.
No new lifecycle phase; the collapse-lever Apply proposes ONE re-entry edge.

**Composition:**
- TOP identity line + determinism badge + 3 cube-ladder rung badges (64³ highlighted).
- **Field64** hero (col 18, row 22): the GIFA loop; "t 37/64" overlay (Z₆₄ cursor from κ).
- Quality row (rows 92–104): two cell-bars — COVERAGE (`Spec.Coverage`) + EFF·DIM
  (`Spec.Diversity.effectiveDim` 0..3), 45×2 cells ≈ 180×8 pt each.
- COLLAPSE LEVER (rows 100–138): a 16×16 radix grid FUSED at the cut level (collapse made
  visible); 3-way tree selector left (≈40×18 pt segments); per-frame|global scope toggle right
  (≈44×18 pt). CUT slider (272×8 pt track, 44 pt hit-pad) with detents.
- **Palette16** (col 42, row 145) — the per-frame palette cycling with the cursor.
- **DiversityRing** (col 40, row 170) — 64-tick gauge.
- ACTION ROW (rows 198–210): [Apply 64³] [Share] [Export 256³], each 108×48 pt (≥44 pt floor).
  Retake = swipe-down on the hero.

**Interactions → events:**
- HERO horizontal drag = manual cursor scrub (sets `σ.cursor`, pausing κ while touched;
  release resumes). A NON-lift gesture (no long-press) so it stays disjoint from widget-move.
- HERO swipe-DOWN → `SurfaceEvent.retake` → `.live` (the one modelled review exit).
- Tree selector / scope toggle TAP → `producesTap` → writes `AppSettings.paletteBranching` /
  `paletteScope` → re-projects the radix grid + 16³ proxy live (pure projection, no re-encode).
- CUT slider drag → `AppSettings.collapseCut`, snapped to detents (one `CellTick` per detent)
  → live 16³ proxy re-render only (NO 64³ re-encode).
- Apply 64³ TAP → NEW `.applyGenome` (re-enter `rendering(.encode)` with the collapsed palette,
  then `.committed` back to review). Share → system share over `gifURL` (impure leaf, off σ).
- Long-press+drag any ColorWidget = the EXISTING move FSM, unchanged.

**Feedback:** hero scrub fires `CellTick` per frame crossed (time-axis detent); "t N/64" tints
toward green at the loop seam. Cut slider = `CellTick` per detent + `EdgeStop` at 0/depth.
Selector taps = light `CellTick` confirm + blue accent `(#9ec3f0)`. Collapse FUSION: cut↑ visibly
merges radix cells into fewer larger blocks — the visual IS the feedback. All via shipped
`tintLerpQ16` + `pulseSampleQ16`.

**FSM additions:** NEW event/edge `.applyGenome` — `(Review,.applyGenome)→Rendering(.encode)`,
closed by the existing `(Rendering(.encode),.committed)→Review`; pin a SEPARATE golden trace (or
extend `goldenHappyPath`) so the cross-language step gate stays green. NO new event for
scrub/scope/cut/tree (out-of-band σ writes per the Display discipline). NEW Field64 scrub
interactivity — a NON-lift gesture (mirrors `lawDragRequiresHold`'s tap/drag split) so scrub and
move stay disjoint; law-safe because Field64 at 64×64 already clears the touch floor. NEW Σ:
`AppSettings.collapseCut` (Int 0..depth), cached collapsed global palette + 16³ proxy. NEW spec:
`Spec.CollapseLever` (monotone/idempotent laws), `Spec.PreviewProxy` (64³→16³, palette-exact);
`Spec.Export.downsample2D`/`replicate2D` already exist for the rungs.

---

## 2. FSM EXTENSIONS (consolidated)

All additions are **additive** and preserve `lawPhaseTotal`, `lawNoOrphanPhase`,
`lawReviewExplicit`, and the golden trace. Edit `Spec.Display` → `cabal test` → `spec-codegen`
→ `Surface.swift` re-fold parity (`Surface.assertSpecParity`).

| # | Addition | Kind | Keeps honest by |
|---|----------|------|-----------------|
| 1 | **Reverse cursor in `.capturing`** | Σ behaviour + pure fn `captureReverseCursor` | Golden vector beside `PlaybackClock.frameAfter`; no new phase/event |
| 2 | **`Browsing` phase** | NEW phase | BFS-reachable via `BurstComplete` (preserves `lawNoOrphanPhase`); `phaseField Browsing = projGif` (preserves `lawPhaseIsCellGrid`) |
| 3 | **`SelectFrame` / `Picked4` events** | NEW events | `step` total by catch-all; pick-set lives in σ not the alphabet; `Picked4` guarded by `picks.count==4` |
| 4 | **Edge `(Capturing,BurstComplete)→Browsing`** | REWIRE (was `→Rendering minBound`) | Render now entered from browse via `Picked4`; only-into-Review-by-Committed unchanged |
| 5 | **Field64 `interactive=True` (scrub)** | MoveContract / gesture | Scrub is a NON-lift gesture (no `HoldElapsed`) ⇒ disjoint from long-press-move (`lawDragRequiresHold`); Field64 already clears the floor |
| 6 | **`.applyGenome` edge (Review→Rendering(.encode)→Review)** | NEW event/edge | Separate or extended golden trace; closed by existing commit edge |
| 7 | **Golden trace update** | regen | `goldenHappyPath` gains `SelectFrame×4 + Picked4`; `Surface.assertSpecParity` re-folds bit-for-bit |

**Discipline reminder:** scrub position, picks, collapse cut, scope, branching are **out-of-band
Σ fields**, never events (mirrors how `Display.hs` keeps `step` small). Only genuine lifecycle
triggers (`SelectFrame`, `Picked4`, `applyGenome`) join the alphabet.

---

## 3. PICK FOUR — OPEN DECISION

The narrative demands "browse each frame and PICK FOUR" but leaves **what the four ARE** open.
The choice changes the render contract and MUST be resolved before `BrowsingPhaseField` is built
(it dictates what `σ.picks` feeds into `rendering(.quantize)`). Three mutually-exclusive
candidates:

- **(A) KEYFRAMES** — the 4 are anchors the render interpolates/blends between (McCann geodesic
  temporal super-res, per `SIXFOUR-PALETTE-IS-MOTION-WORKFLOW.md`); the GIF is reconstructed from
  4 chosen poses. Keeps all 64 frames' information; richest, most novel; heaviest render contract.
- **(B) 4-FRAME CURATION** — the committed GIFA literally IS just these 4 frames looped. Drastic,
  punchy, tiny output; discards the other 60. Simplest contract; least uses the cube's depth.
- **(C) 4⁴ QUAD ANCHORS** — the 4 map onto the `Spec.PairTreeFixed` / collapse-lever 4⁴ quad
  level, choosing which sub-tree the collapse pivots on. Ties pick-four to the existing collapse
  machinery; most "in-grammar".

> **USER DECISION 2026-06-08 → (C) 4⁴ QUAD ANCHORS, ORDERED, FIXED 4.** The four picks
> map onto the `Spec.PairTreeFixed` / collapse-lever 4⁴ quad level and select which sub-tree
> the palette collapse pivots on; they are an ORDERED list of exactly 4 (filmstrip order =
> quad order, needs a drag-reorder gesture). `σ.picks :: [Int]` (length 4, ordered). This
> ties pick-four to the existing collapse machinery rather than the interpolation stage —
> Act III feeds the collapse lever, not a McCann reconstruction. (Workflow had recommended
> (A) keyframes; the user chose the in-grammar collapse-pivot reading.)

**(Superseded recommendation) → (A) KEYFRAMES.** It (1) honours the cube's whole premise — 64 frames of
per-frame palette diversity collapsing into ONE GIF — by letting the user choose the *poses* the
motion is reconstructed from, rather than throwing 60 frames away (B) or overloading the address
radix (C); (2) reuses the already-spec'd McCann geodesic / displacement-interpolation math
(`SIXFOUR-PALETTE-IS-MOTION-WORKFLOW.md` §1.3) so the four feed a *known* deterministic stage;
(3) keeps `σ.picks` an ORDERED list (filmstrip order = interpolation order), which the filmstrip
UI already implies. **Sub-decisions to confirm with the user:** is 4 a hard constant (4 = 2×2
filmstrip / 4⁴ quad) or a user-settable N? do picks PRUNE the cube or merely TAG within the
64-frame GIFA? are the four ordered (needs a drag-reorder gesture) or a set?

---

## 4. FILL THE EMPTY CELLS (ranked data plan)

The big empty regions around the centred widgets become a **palette/telemetry skin** — every
fill is a data-coloured 4 pt cell field (no glass, no Text), reading a real Σ field / spec module.
Ranked by `value ÷ effort`; **(S)/(M)/(L)** = effort.

| Rank | Fill | Act(s) | Region (cells) | Source | Eff |
|------|------|--------|----------------|--------|-----|
| 1 | **DiversityRing → `effectiveDim/3` gauge** (the QUICK WIN — widget docked, draws NOTHING) | I/II/III/V | dock (40,170) 20×20 | `Spec.Diversity.effectiveDim` over `previewPalette`/`palettesPerFrame[cursor]` | **S** |
| 2 | **Gamut-Coverage bar** (the headline yardstick, monotone-growing) | II/V | below Field64 rows 96–105, 64×10 | `Spec.Coverage.gamutCoverageFraction`/`occupiedBins` (16³) over `palettesPerFrame` union | **S** |
| 3 | **Live frame counter** (NN/64 LED, exact not palette-derived) | II/IV | top gutter rows 0–21 | `CellDigits` (`SevenSegContract`) backed by NEW `capturedFrameCount: Int` on Surface | **S** |
| 4 | **Per-frame coverage scrubber track + pick-4 markers** (the literal Act III selection surface — answers "which four") | III/V | below Palette16 rows 161–176, 64×3 | `Spec.Coverage` per frame + NEW `picks:[Int]` σ field | **M** |
| 5 | **Frame-palette ribbon** (per-frame colour drift, 64 columns) | II/V | mid-band rows 128–143, 64×16 | `palettesPerFrame` (64×256) collapsed 256→16 via `Spec.GridAxis AxisL` rank | **M** |
| 6 | Significance population strip (per-slot pixel backing; makes the `significance` stage visible) | IV/V | right margin cols 82–99, 16×64 | `Spec.Significance` per-slot population over `indexCube`; NEW per-slot counts on Σ | **M** |
| 7 | Temporal motion heatmap (per-pixel frame-to-frame change — biggest empty band, most diagnostic) | V | mid rows 90–121, 64×32 | `indexCube` reduce; NEW `Spec.Motion.changeMap` (index-domain, Zig-portable) | **M** |
| 8 | Reverse-playback trail ticker (the no-freeze contract made visible) | II | left rail cols 2–9, 1×64 | reverse `cursor` + capture fraction; needs FSM addition #1 | **M** |
| 9 | Locked capture triplet (ISO / shutter / WB, frozen at `lockComplete`) | I/V | left gutter cols 0–17, rows 22–86 | `CaptureSession.device` (iso/exposureDuration/WB gains); NEW `CaptureTelemetry` on Σ | **M** |
| 10 | OKLab a–b vectorscope / RGB parade (broadcast colour scopes) | I/V | mid band 32×32 / 96×26 | `previewPalette`→OKLab via `Spec.Color` + `Spec.GridAxis` projections | **M** |
| 11 | Collapse-lever spectrum (4⁴/2⁸ cut as a coloured cell slider) | V | below Palette16 rows 161–167, 64×6 | `Spec.Collapse` 4⁴/2⁸ + `Spec.AddressPicker`; NEW `cutLevel` σ field | **L** |
| 12 | GIFC 16³ mini-loop contact sheet (the shipped-size reality) | V | bottom rows 181–193, 4×(16×16) | `Spec.Export.downsample2D` over `indexCube` at 4 sampled t | **L** |

**Note on #1:** `DiversityRing` is the single most wasteful real estate — docked, named for the
metric, drawing nothing. Filling its own dock with its namesake `effectiveDim` (participation
ratio of the OKLab covariance, 0..3) is the lowest-effort, highest-justification win and unlocks
its presence across Acts I/II/III/V.

---

## 5. Build plan (spec-first, gated by `scripts/s4.sh`)

Each phase ends green on `scripts/s4.sh all` (codegen → verify → native → lint → gen → build).
Spec-first: edit `Spec.Display` (+ siblings), `cabal test` the new laws/goldens, `spec-codegen`
to regen `Generated/DisplayContract.swift`, then port to `Surface.swift` and re-fold
`assertSpecParity`.

**Phase 1 — CENTRED LAYOUT + DiversityRing quick win (see-able).**
Confirm Field64/Palette16 docks render centred on the one surface; activate the DiversityRing
Π (`Spec.Diversity.effectiveDim` arc — fill #1) with NO FSM change; add the Coverage bar (#2)
and frame counter (#3). Gate: `s4 verify` (Diversity/Coverage goldens) + `s4 lint` (GRID) +
`s4 build`.

**Phase 2 — BACKWARDS PREVIEW (feel-able, no freeze).** Add FSM addition #1: pure
`captureReverseCursor` + golden, `capturedFrames` in Σ, `SurfaceClock` calls it while
`.capturing`; wire the reverse-playback trail (#8) + progress arc. Gate: `s4 verify`
(reverse-cursor golden) + `s4 build`; manual on-device check that the preview does NOT freeze.

**Phase 3 — SWIPE-BROWSE + PICK FOUR (the new act).** RESOLVE §3 first. Add the `Browsing`
phase + `SelectFrame`/`Picked4` events + the rewired `BurstComplete→Browsing` edge + `picks:[Int]`
σ + `scrubCursor(by:)`; build `BrowsingPhaseField.swift` (scrub rail + filmstrip + coverage track
#4); extend `goldenHappyPath` and re-fold `assertSpecParity`. Gate: `s4 verify` (new golden
trace) + `s4 lint` + `s4 build`.

**Phase 4+ — DATA FILLS + REVIEW LEVER.** Land fills #5–#12 by region/act; add Act V scrub +
`Spec.CollapseLever` / `.applyGenome` + the collapse-lever UI. Each fill is its own spec
golden + Π, gated by `s4 all`.

---

## 6. Open questions (carried, for the user)

- **Field64 dock:** keep row 22 or adopt the balanced-stack row 30 (forces `MoveContract.defaultRow`
  + move-golden regen)?
- **Pick-four meaning:** §3 recommends KEYFRAMES (A) — confirm vs CURATION (B) / QUAD (C); is 4
  fixed or settable; ordered or set; prune or tag?
- **Reverse-cursor wrap:** bounded prefix `[0,capturedFrames)` (honest) vs full Z₆₄ wrap — pin one
  golden.
- **`capturedFrames` source:** derive from `palettesPerFrame.count` vs explicit counter (requires
  `CaptureViewModel` to fold per-frame EARLY, not only at commit).
- **Per-stage render progress:** real Zig integer counter (continuous reveal) vs stage-granular (5
  discrete reveals) — decides FSM addition Act-IV #1.
- **`.applyGenome`:** an FSM micro-loop (Review→Rendering(.encode)→Review, golden amendment) vs a
  pure σ-recompute that never leaves `.review`?
- **Export 256³ container:** true 256-colour GIF is impractical — APNG/HEVC or down-sample to 64³?
  (The "256³" label may over-promise.)
- **DiversityRing scalar:** `effectiveDim` (chosen) vs per-frame `coverage` (would duplicate the
  COVERAGE bar)?
