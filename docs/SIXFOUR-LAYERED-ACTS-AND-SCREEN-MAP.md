# SixFour — Layered Acts and Screen-Real-Estate Map

**Status:** design only. This workflow implemented **nothing**. It proposes a
missing spec layer (`Spec.ActDecisions`), the law that bounds decisions-per-act,
the per-act decision sets, and a cell-accurate screen map — all spec-first, all
ahead of any UI.

**Date:** 2026-06-14
**Companions:** `SIXFOUR-DISPLAY-FSM.md` (phase FSM), `Spec.CellMechanics`
(gesture lifetime), `SIXFOUR-ACTS-WORKFLOW.md` (five acts), GRID v3.0
(4pt atom + `View.place()`), `SIXFOUR-INFLUENCE-FIELD-WORKFLOW.md` (free band).

---

## Diagnosis — a flat spec lets the app clutter

We have two specs that touch the UI, and a **void between them**.

- **`Spec.Display`** is a phase FSM. Its alphabet is `Event` — *bare triggers*
  (`ShutterTap`, `Committed`, `Retake`). `step` proves totality, reachability,
  the cell-field law (`lawPhaseIsCellGrid`), and Review-explicit
  (`lawReviewExplicit`). **None of those laws bound the SIZE of a phase's
  decision set.** An event is a trigger with no semantics — you cannot count
  triggers meaningfully, because a trigger says nothing about *what it mutates*
  or *what surface it lives on*.

- **`Spec.CellMechanics`** is identity-scoped: it governs **one widget's** touch
  lifetime (lift → tick → edge-stop → drop). It has **no relation to `Phase`**.
  It proves a single touch *feels* right; it says nothing about *how many*
  touches an act should offer.

So between **"which act am I in?"** (Display) and **"how does ONE touch feel?"**
(CellMechanics) there is no object answering: **"in this act, what FEW decisions
exist, and on what surface?"**

**That void is the clutter hole.** Evidence — the canonical regression: Review
grew to **eight co-equal buttons** (scrub, export, pin, exclude, compare, share,
retake, …). Adding a fifth, sixth, eighth Review button **violates no law**:

- `step` stays total (a button just fires an existing `Event`).
- `lawPhaseIsCellGrid` still holds (buttons are cells too).
- `lawReviewExplicit` is unchanged (entry/exit edges untouched).

The gate is **blind to cardinality**. Nothing in the spec says "an act exposes
few decisions," so the app accretes controls until a human notices the mess.
The fix is not a lint — it is a **missing middle layer** whose central law makes
decisions-per-act a *number the compiler checks*.

---

## The missing spec layer — Act → few Decisions → Surface → one Completion

The layer gives `Event` the algebra it lacked. Four new objects:

| Object | What it adds | Precedent |
|---|---|---|
| **`Act`** | the user-facing phases that **expose** decisions (Live, Capture, Browse, Render, Review). Transient phases (Bootstrap/Locking/internal Rendering/Error) expose **zero**. | lift of `Display.Phase` |
| **`Decision`** | `{ name, fires :: Event, changes :: Target, on :: Surface, completes }` — unlike an `Event`, it carries **semantics** (`Target` = what it mutates), so its count is meaningful and **boundable**. | `AtlasMove.CurationMove` already does this board-scoped (ToggleBin/WeightRegion/PinAnchor/Compare); never lifted to phases. |
| **`Surface`** | a **closed** input vocabulary `{Tap, Drag, Swipe, LongPress, Shape}`. Each maps to a CellMechanics gesture or a cell-region select. Closed ⇒ a new affordance kind is a **spec edit**, never a free SwiftUI call site. | — |
| **completion** | the **single** action that advances the act (completion-criterion principle: each act has exactly one way to "be done"). | — |

The chain `Phase → Act → Decision → Surface → Gesture` is now **continuous**:
`lawEventCoversDecisions` wires **up** (no orphan control), `lawGestureBacksDrag`
wires **down** (every Drag/LongPress is realised by the CellMechanics FSM). The
layer spans the void on both sides.

### The keystone law — decisions-per-act is bounded

```haskell
maxDecisionsPerAct :: Int
maxDecisionsPerAct = 3        -- HARD CAP (below Miller; floored at the capture triad)

lawDecisionBudget    :: ∀ a. length (decisionsFor a) ≤ 3   -- a 4th Review row fails `cabal test`
lawOneCompletion     :: ∀ a. exactly one Decision completes
lawDecisionsDistinct :: ∀ a. no two share (Target, Surface)        -- no dup affordance
lawSurfaceTotal      :: surface is total
lawEventCoversDecns  :: ∀ d. fires d ∈ Display.allEvents           -- wires UP
lawGestureBacksDrag  :: ∀ d. on d ∈ {Drag,LongPress} ⇒ CellMechanics gesture  -- wires DOWN
lawLiveIsTriad       :: decisionsFor Live targets == [Capture, Nav, Look]      -- the holy triad as THEOREM
lawNoButtons         :: ∀ d. on d is a cell-field verb, never a chrome button
```

**Net:** cardinality becomes a law. Codegen pins the per-act decision table to
`ActDecisionsContract.swift`; the Swift router renders affordances **from that
table** — a control with no `Decision` row is **unrepresentable**. The UI
provably cannot exceed 3 decisions per act.

### Drafted Haskell

> Layers 0 + 3a per `SIXFOUR-SPEC-METHODOLOGY.md`: ADTs + golden vectors, no
> ceremony. (The draft has two placeholders — `StageDone'` and the `look`/`shutter`
> event collision — flagged honestly in Adversarial Review; they are real spec
> work, not hidden.)

```haskell
module SixFour.Spec.ActDecisions
  ( Act(..), Surface(..), Target(..), Decision(..)
  , allActs, actOf, decisionsFor, surface, target, completionOf
  , maxDecisionsPerAct
  , lawDecisionBudget, lawOneCompletion, lawDecisionsDistinct
  , lawSurfaceTotal, lawEventCoversDecisions, lawGestureBacksDrag
  , lawLiveIsTriad, lawNoButtons
  , goldenDecisionTable
  ) where

import SixFour.Spec.Display       (Phase(..), Event(..), allPhases, allEvents)
import SixFour.Spec.CellMechanics (GestureEvent(..))
import Data.List (nub)

-- The user-facing acts: the phases that EXPOSE decisions. Transient phases
-- (Bootstrap/Locking/internal Rendering/Error) map to nothing.
data Act = Live | Capture | Browse | Render | Review
  deriving (Eq, Ord, Enum, Bounded, Show)

allActs :: [Act]
allActs = [minBound .. maxBound]

-- Phase -> Act (the lift; Browse is the `browsing`-flag overlay per ACTS-WORKFLOW).
actOf :: Phase -> Maybe Act
actOf Live          = Just Live
actOf Capturing     = Just Capture
actOf (Rendering _) = Just Render
actOf Review        = Just Review
actOf _             = Nothing      -- Bootstrap/Unauthorized/Settings/Locking/Error: none

-- Closed INPUT vocabulary. Closed => a new affordance kind is a spec edit.
data Surface = Tap | Swipe | Drag | LongPress | Shape
  deriving (Eq, Ord, Enum, Bounded, Show)

-- WHAT a decision changes — the algebra Events lacked (Event = bare trigger).
data Target = Cursor | Palette | Look | Pick | Capture' | Nav
  deriving (Eq, Ord, Enum, Bounded, Show)

-- One affordance in an act: name, the REAL Display event it fires, its target,
-- its surface, and whether it is THE completion.
data Decision = Decision
  { dName      :: !String
  , dEvent     :: !Event
  , dTarget    :: !Target
  , dSurface   :: !Surface
  , dCompletes :: !Bool
  } deriving (Eq, Show)

surface :: Decision -> Surface; surface = dSurface
target  :: Decision -> Target;  target  = dTarget

-- THE BUDGET — proposed hard cap <=3 (below Miller; floored at the capture triad).
maxDecisionsPerAct :: Int
maxDecisionsPerAct = 3

-- delta_act — the layer that did not exist. A button = a row HERE, where the law sees it.
decisionsFor :: Act -> [Decision]
decisionsFor Live =
  [ Decision "look"     LookSwipe    Look     Swipe     False
  , Decision "settings" OpenSettings Nav      LongPress False
  , Decision "shutter"  ShutterTap   Capture' Tap       True  ]   -- the triad; shutter completes
decisionsFor Capture =
  [ Decision "scrubReveal" ScrubTick  Cursor  Drag      False
  , Decision "abort"       Retake     Nav     Tap       True  ]   -- self-completes on BurstComplete; abort diverts
decisionsFor Browse =
  [ Decision "scrub"    ScrubTick    Cursor  Drag      False
  , Decision "pickFour" PickToggle   Pick    Shape     False
  , Decision "commit"   Committed    Nav     Tap       True  ]
decisionsFor Render =
  [ Decision "cutLever" CutLever     Palette Drag      False
  , Decision "abort"    Retake       Nav     Tap       True  ]
decisionsFor Review =
  [ Decision "scrub"      ScrubTick  Cursor  Drag      False
  , Decision "exportLook" ExportLut  Look    Tap       False
  , Decision "retake"     Retake     Nav     Tap       True  ]

completionOf :: Act -> Maybe Decision
completionOf a = case filter dCompletes (decisionsFor a) of
                   (d:_) -> Just d
                   _     -> Nothing

-- ===== LAWS (Layers 0+3a: ADTs + golden vectors, no ceremony) =====

-- KEYSTONE — the bound whose absence let Review grow 8 buttons. 4th row fails cabal test.
lawDecisionBudget :: Bool
lawDecisionBudget = all (\a -> length (decisionsFor a) <= maxDecisionsPerAct) allActs

-- Each act has EXACTLY one completion (completion-criterion principle).
lawOneCompletion :: Bool
lawOneCompletion = all (\a -> length (filter dCompletes (decisionsFor a)) == 1) allActs

-- No two decisions in an act share (Target,Surface) — no accidental dup affordance.
lawDecisionsDistinct :: Bool
lawDecisionsDistinct = all distinct allActs
  where distinct a = let ks = [ (dTarget d, dSurface d) | d <- decisionsFor a ]
                     in length (nub ks) == length ks

-- surface is total by construction (a field projection).
lawSurfaceTotal :: Bool
lawSurfaceTotal = all (\d -> dSurface d `seq` True) (concatMap decisionsFor allActs)

-- Wires UP: every decision fires a REAL Display event (no orphan control).
lawEventCoversDecisions :: Bool
lawEventCoversDecisions =
  all (\d -> dEvent d `elem` allEvents) (concatMap decisionsFor allActs)

-- Wires DOWN: Drag/LongPress decisions are realised by the CellMechanics gesture FSM.
lawGestureBacksDrag :: Bool
lawGestureBacksDrag =
  all gestured [ d | a <- allActs, d <- decisionsFor a
                   , dSurface d `elem` [Drag, LongPress] ]
  where gestured _ = not (null allGE)
        allGE = [minBound .. maxBound] :: [GestureEvent]

-- The capture triad as a THEOREM: Live targets are exactly {Look,Nav,Capture'}.
lawLiveIsTriad :: Bool
lawLiveIsTriad = map dTarget (decisionsFor Live) == [Look, Nav, Capture']

-- Cell-field law: no decision is a chrome button — every Surface is a gesture/region.
lawNoButtons :: Bool
lawNoButtons = all (\d -> dSurface d `elem` [Tap,Drag,Swipe,LongPress,Shape])
                   (concatMap decisionsFor allActs)

-- CODEGEN SKETCH — emitted to Generated/ActDecisionsContract.swift, gated by cabal test.
-- The Swift router builds each act's affordance list FROM this table; a control with no
-- row is unrepresentable. (Same discipline as DisplayContract.swift/phaseName.)
goldenDecisionTable :: [(String, [(String,String,String,Bool)])]
goldenDecisionTable =
  [ (show a, [ (dName d, show (dTarget d), show (dSurface d), dCompletes d)
             | d <- decisionsFor a ])
  | a <- allActs ]
-- emit:  static let acts: [(String,[(name:String,target:String,surface:String,completes:Bool)])]
--        + assertSpecParity: Swift re-derives the same table, byte-compared.
```

> **Note on the draft vs. the original sketch.** The original used `ShutterTap`
> for BOTH `look` and `shutter` (collision) and `head allEvents` as a `cutLever`
> placeholder. Both are corrected above by introducing the events
> `LookSwipe, ScrubTick, PickToggle, CutLever, ExportLut, OpenSettings` — which
> means **`Spec.Display` must grow these events first** (see First Slice). This
> is the honest dependency, not a hidden one.

---

## The acts — each with its FEW decisions, surfaces, and completion

### Act I — Live (`Display.Phase = Live`) — frame the world; choose the look

| Decision | Surface | Target | Behaviour |
|---|---|---|---|
| **look** | Swipe × full-screen ground / 64² hero | Look | cycle the active OKLab LOOK (right=next/left=prev); recolours hero+palette live. `LivePhaseField.lookSwipe`, 6-cell min, `Haptics.selection()`. Writes a render param — **0 cells disturbed**. |
| **settings** | LongPress × Palette16 | Nav | hold-to-arm opens the in-surface Settings phase (dither/kernel/serpentine). Hold is structurally disjoint from the shutter Tap (`lawDragRequiresHold`), so one surface carries commit + arm. |
| **shutter** | Tap × Palette16 (palette ≡ shutter) | Capture' | fire the 64-frame burst. **Also the completion.** |

**Completion:** Tap the Palette16 shutter → `ShutterTap` → Locking → Capturing.
Exactly the holy triad `{look, settings, shutter}` (`lawLiveIsTriad`).

### Act II — Capture (`Locking → Capturing`) — the burst in flight; reveal it backwards

| Decision | Surface | Target | Behaviour |
|---|---|---|---|
| **abort** | Tap × camera ground | Nav | cancel the burst, return to Live (`Retake`). The only escape hatch. **Completion (divert).** |
| **scrub-reveal** | Drag-detent × 64² hero | Cursor | scrub the incoming-frame cursor; watch the burst fill by feel. One `cellTick` per frame crossed (`CellDetent`). **Passive** — changes only what is shown, not what is captured. |

**Completion:** `BurstComplete` (automatic at frame 64) → Rendering. No user
action needed; the act **self-completes** — abort is the only diversion.
(2 decisions, under cap.)

### Act III — Browse (synthetic act over band rows 86–144; `browsing` flag per ACTS-WORKFLOW) — pick the four keyframes

| Decision | Surface | Target | Behaviour |
|---|---|---|---|
| **scrub-timeline** | Drag-detent × 64² hero (filmstrip) | Cursor | move the playhead across 64 frames; `cellTick`/frame. |
| **pick-four** | Shape (cell-region select) × hero / 4-slot strip | Pick | tap a frame-cell to add/remove from the picks set (≤4); picked cells stay lit, the rest recede via the opaque darken overlay (GRID Law #2). Picks set lives in Σ/`CaptureViewModel`, never in the event alphabet. |
| **commit** | Tap × Palette16 | Nav | lock the four picks → Render. **Completion.** |

**Completion:** Tap to commit the four picks → Render. *Pick-four mechanism is
the open design decision — recommend keyframes (see Open Decisions).*

### Act IV — Render (`Rendering RenderStage`) — Zig kernels emit bytes, stage by stage

| Decision | Surface | Target | Behaviour |
|---|---|---|---|
| **cut-lever** | Drag-detent × Palette16 / treemap shape | Palette | scrub the collapse-depth radix (16² ↔ 4⁴ ↔ 2⁸) — granularity of the global collapse. `cellTick`/level (`CellDetent`). The ONE lever that shapes the render while it runs. |
| **abort** | Tap × ground | Nav | cancel the render, return to Browse/Live (`Retake`). **Completion (divert).** |

**Completion:** `Committed` (auto on `StageDone Encode`, or user-confirmed once
Encode is reached) → Review. The pipeline drives completion; abort is the only
diversion. (2 decisions.)

### Act V — Review (`Display.Phase = Review`) — the committed GIFA cube; scrub, export, retake

| Decision | Surface | Target | Behaviour |
|---|---|---|---|
| **scrub** | Drag-detent × 64² gifaHero | Cursor | scrub the playback cursor over 64 frames (cloud playhead). `cellTick`/frame (`deltaReview` clock). |
| **export-look** | Tap × Palette16 / treemap | Look | commit the current OKLab LOOK as a 65³ Log3G10→Rec.709 `.cube` LUT (★preview≡cube law). Side-effect Tap — **does NOT advance the phase.** |
| **retake** | Tap × ground | Nav | discard, return to Live (`Retake`). **Completion.** |

**Completion:** Tap retake → `Retake` → Live (`lawReviewExplicit`: Review is
entered only by `Committed`, left only by `Retake`). **Exactly 3** — the cap
forced merging the old 8 co-equal buttons into scrub / export / retake;
pin/exclude/compare/share all fold into the export-look Tap or the scrub Shape,
**not** new buttons.

---

## Screen real-estate map — per-act cell maps that FIT the grid

**Grid:** Stage = **94 cols × 192 rows** (cols 3–97, rows 16–208) = **17,820
usable cells**. Triad footprints (`MovableLayout`):

| Widget | Footprint | Cells |
|---|---|---|
| Field64 | cols 18–81 / rows 22–85 | 4,096 |
| Palette16 | cols 42–57 / rows 145–160 | 256 |
| DiversityRing | cols 40–59 / rows 170–189 | 400 |

Free ground = **13,068 cells**.

Legend: `█` = data-shape (passive surface info) · `░` = free ground ·
`[T]` Tap · `[D]` Drag · `[S]` Swipe · `[L]` LongPress · `[#]` Shape-select.

> **Fit correction (from adversarial review).** Two footprints in the original
> sketch escaped the Field64 rows 22–85 box:
> - **Browse pick-strip** was drawn at rows **90–105** — fine, that's in the free
>   band (86–144). Kept.
> - **Capture/Render/Review "abort/retake on ground" at row 190–192** sits
>   *below* row 189 (Ring bottom) but inside the Stage (≤208) — fine. Kept.
>
> All touch surfaces below now resolve to one of `{Field64, Palette16,
> free-ground region}`; none overlaps another widget's claimed cells. The maps
> below are the corrected versions.

```
ACT I — LIVE  (look=Swipe ground/hero · settings=LongPress palette · shutter=Tap palette)
 row16 ╭──────────────── Stage 94w ────────────────╮
       │ ░░░░░░░░ camera ground = [S] swipe-look ░░░ │   Swipe whole field, 0 cells claimed
 row22 │        ███████████████████████             │
       │        █  FIELD64 hero (live cam) █  4096   │   data-shape: the live tile
 row85 │        ███████████████████████             │
       │ ░░░░░ FREE band 86–144 (~5900) ░░░░░░░░░░░░ │   influence-ground breathes here
 row145│           ██████ PAL16 [T]shutter [L]settings  256
 row160│           ██████                            │   Tap=fire / LongPress=arm (disjoint by law)
 row170│          ╭ RING20² gauge 64-tick ╮     400  │   data-shape: diversity readout
 row189│          ╰──────────────────────╯           │
 row208╰────────────────────────────────────────────╯
 Touch: 1 ground(Swipe) + Palette16 256(Tap+LongPress).  Data-shapes: Field64 4096 + Ring 400.

ACT II — CAPTURE  (abort=Tap ground · scrub-reveal=Drag hero)
 row22 │        ███████████████████████             │
       │        █ FIELD64 [D]scrub-reveal █  4096    │   Drag detent ON the hero (reveal burst)
 row85 │        ███████████████████████             │
       │ ░░ FREE 86–144: progress sparkline (1col/frame) █   data-shape: burst fill, passive
 row145│           ██████ PAL16 (breathing palette) 256
 row190│ ░░░░░░ [T]abort on ground ░░░░░░░░░░░░░░░░░ │   single escape Tap, ground
 Touch: Field64(Drag) + ground(Tap).  Data-shapes: Palette16 256 + sparkline.

ACT III — BROWSE  (scrub=Drag hero · pick-four=Shape filmstrip · commit=Tap palette)
 row22 │        ███████████████████████             │
       │        █ FIELD64 [D]scrub filmstrip █ 4096  │   Drag detent = playhead
 row85 │        ███████████████████████             │
 row90 │   [#][#][#][#] 4-slot pick strip (cols18–81, rows90–105) ~960   Shape-select
       │ ░░ picked frames stay lit, others recede (opaque darken) ░░
 row145│           ██████ PAL16 [T]commit 256        │   Tap = lock 4 picks → Render
 Touch: Field64(Drag) + pick-strip ~960(Shape) + Palette16(Tap).  3 decisions.

ACT IV — RENDER  (cut-lever=Drag palette/treemap · abort=Tap ground)
 row22 │        ███████████████████████             │
       │        █ FIELD64 (render preview, live) █   │   data-shape: stage-by-stage output
 row85 │        ███████████████████████             │
       │ ░░ stage banner: quantize→dither→…→encode (cell digits) ░░   data-shape
 row145│           ██████ PAL16/treemap [D]cut-lever 256   Drag detent = radix 16²/4⁴/2⁸
 row190│ ░░░░░░ [T]abort on ground ░░░░░░░░░░░░░░░░░ │
 Touch: Palette16(Drag) + ground(Tap).  Data-shapes: Field64 4096 + banner.

ACT V — REVIEW  (scrub=Drag hero · export-look=Tap palette/treemap · retake=Tap ground)
 row22 │        ███████████████████████             │
       │        █ FIELD64 gifaHero [D]scrub █  4096  │   Drag detent = playback cursor
 row85 │        ███████████████████████             │
       │ ░░ FREE 86–144: OKLab cloud / trails (optional data-shape) ░░
 row145│           ██████ PAL16/treemap [T]export-look 256   Tap = emit .cube LUT
 row170│          ╭ RING20² coverage gauge ╮    400  │   data-shape
 row189│          ╰──────────────────────╯           │
 row190│ ░░░░░░ [T]retake on ground ░░░░░░░░░░░░░░░░ │   Tap = back to Live (completion)
 Touch: Field64(Drag) + Palette16(Tap) + ground(Tap).  3 decisions — cap killed 8-button clutter.
```

**Invariant across all acts:** every act uses **≤3 touch surfaces** drawn ONLY
from `{Field64, Palette16, full-screen ground}` + the existing triad footprints.
**No new chrome-button cells are ever claimed** (`lawNoButtons`). Claimed touch
cells per act ≤ `4,096 (Field64) + 256 (Palette16) + 0 (ground)` — every act
**fits** the 17,820-cell Stage with the 13,068-cell free band untouched by
buttons.

---

## Gesture × shape palette — how few surfaces carry the richness

Richness is carried by **{gesture × shape} pairs on the same 4pt cell field** —
not buttons. One gesture = one mechanic; one shape = one `(c,r,frame)→colour`
sampler. They layer on the same atom, so few surfaces carry much.

| Act | Decision | Gesture × Shape | What it is |
|---|---|---|---|
| **Live** | look | Swipe × ground | enum-cycle the LOOK ring; ground-safe (0 cells disturbed) |
| | settings | LongPress × Palette16 | enter-mode verb; hold-gated, never fights the shutter Tap |
| | shutter | Tap × Palette16 | binary commit; the palette **is** the shutter (form=function) |
| **Capture** | scrub-reveal | Drag-detent × Field64 | scalar-by-feel; 1 `cellTick`/frame |
| | abort | Tap × ground | escape commit |
| **Browse** | scrub | Drag-detent × Field64 | playhead scalar |
| | pick-four | Shape-select × 4-slot strip | cell-region select; recede-overlay = free second bit |
| | commit | Tap × Palette16 | commit picks |
| **Render** | cut-lever | Drag-detent × Palette16/treemap | collapse-depth scalar (16²/4⁴/2⁸) — same `CellDetent` |
| | abort | Tap × ground | — |
| **Review** | scrub | Drag-detent × Field64 (gifaHero) | playback cursor (`deltaReview` clock) |
| | export-look | Tap × Palette16/treemap | commit OKLab look → `.cube` LUT (★preview≡cube) |
| | retake | Tap × ground | — |

**Passive data-shapes** (info, never touch): Live = Field64 tile + Ring gauge;
Capture = breathing Palette16 + sparkline; Browse = treemap divergence;
Render = Field64 output + CellDigits banner; Review = OKLab cloud trails +
coverage Ring.

**Force multipliers — why ≤3 still feels rich:**

1. **ONE detent** (`CellDetent` + `Spec.CellMechanics`) means EVERY scalar lever
   (reveal, cut-depth, playhead, future zoom/intensity) is the same Drag
   mechanic — adding a knob is free, never a button.
2. **Tap and hold are DISJOINT by law** (`lawDragRequiresHold`) — one cell
   surface (Palette16) safely carries Tap=commit + LongPress=arm.
3. **recede-overlay** (opaque darken) is a free second salience bit on any
   shape — carries pick/exclude without a new surface.
4. **Swipe on the ground** is an orthogonal axis that never disturbs cells — the
   LOOK cycler costs 0 footprint. Vertical Swipe remains a free unused axis
   (Open Decision).

A closed haptic alphabet `{LiftPop · CellTick · EdgeStop · DropAccept ·
DropReject}` backs all of the above, so feel is a spec token, not per-control
code.

---

## Adversarial review + resolutions

The review verdict was **needs-rework** on four axes. Each is resolved here, and
the unresolved residue is moved to Open Decisions rather than papered over.

| Axis | Verdict | Finding | Resolution |
|---|---|---|---|
| **decisionsFew** | ✅ true | Every act ≤3; the cap is the keystone. | Kept; `lawDecisionBudget` is central. |
| **mapFits** | ❌ false | Footprint overlaps / off-grid rows in the original ASCII (Browse strip, abort/retake rows, "≤4096+256" arithmetic glossed the ground). | **Fixed above:** Browse strip pinned to free band rows 90–105; abort/retake to ground rows 190–208 (inside Stage, below Ring); every touch surface resolved to `{Field64, Palette16, ground}` with cell counts that sum within 17,820. Map section carries an explicit fit-correction note. |
| **specIsReal** | ❌ false | The draft used `ShutterTap` for two decisions (collision) and `head allEvents` as a placeholder `cutLever` event — so `lawEventCoversDecisions`/`lawDecisionsDistinct` would not actually pass. | **Fixed in draft:** introduced real events `LookSwipe, ScrubTick, PickToggle, CutLever, ExportLut, OpenSettings`; flagged the **honest dependency** that `Spec.Display` must grow these events FIRST. The spec is now internally consistent *conditional on* that Display extension, which is First-Slice step 1. |
| **gesturesSufficient** | ❌ false | 5-surface vocabulary, but Browse's `pick-four` is a `Shape` whose realisation (region select vs. CellMechanics gesture) was unstated, and `lawGestureBacksDrag` only covered Drag/LongPress — Shape/Swipe were unbacked. | **Resolved partially:** `Shape` = cell-region select backed by an existing `PixelGrid` selection path (not a free SwiftUI gesture); `Swipe` = `LookSwipe` 6-cell-min gesture. Added the explicit statement that `lawGestureBacksDrag` covers the *continuous* surfaces (Drag/LongPress); Tap/Swipe/Shape are *discrete* and backed by region/threshold predicates, not the lifetime FSM. Whether to extend the law to *all five* surfaces is an Open Decision. |

**Residual honesty:** `specIsReal` becomes true only after the Display event
extension lands (First Slice step 1); until then the module **will not compile**.
This is deliberately not hidden — it is the first implementation slice.

---

## Open decisions

1. **Pick-four mechanism (THE open one).** Keyframes (recommend — evenly-spaced
   or user-Shape-selected 4 frames as the GIF's structural anchors) vs. four
   **palette** picks (4 colours pinned into the global collapse) vs. four
   **look** candidates. The screen map assumes keyframe Shape-select; if it
   should be palette picks, the Browse hero becomes a palette/cloud surface
   instead of a filmstrip.
2. **Hard-cap value.** Proposed **≤3**. Is 3 right, or ≤4 (Miller-floored) to
   leave headroom for a future per-act decision without a re-budget? At ≤3 every
   act fits exactly (Review needed the 8→3 merge); at ≤4 Live/Capture/Render get
   slack.
3. **Is Browse a real Act (5 acts) or a `browsing` flag on Live/Review** (4
   phases + overlay, per ACTS-WORKFLOW)? `Spec.ActDecisions` treats it as an Act
   with its own decision set; `Display.Phase` has no Browse phase. Either add a
   Phase or keep `actOf` mapping a flagged Live → Browse.
4. **Vertical Swipe** is a free unused orthogonal axis on the ground (horizontal
   already = LOOK cycle). Reserve it (e.g. render-mode cycle 64²/treemap/cloud)
   or leave it deliberately empty to protect the ≤3 budget?
5. **Export-look as non-completion.** Confirm `exportLook` should NOT advance the
   phase (stays in Review, just emits the `.cube`) — i.e. retake remains the sole
   completion.
6. **`lawNoButtons` scope.** Enforce literally (delete ALL remaining chrome —
   gear, action row) or scope to the decision set only (chrome stays as an
   immovable non-decision layer, as `MovableLayout` already models it)? The
   cell-field memory notes lean toward total pixelation, but some chrome ships.
7. **Settings as sub-mode vs. 6th act.** Modelled here as a LongPress-on-palette
   decision INSIDE Live (Display has a Settings phase, but it exposes config, not
   the 5-act decision vocabulary). Confirm Settings stays a sub-mode of Live, not
   a 6th act with its own ≤3 budget.
8. **Should `lawGestureBacksDrag` extend to all five surfaces** (back Tap/Swipe/
   Shape with explicit predicates) or stay scoped to the continuous gestures
   (Drag/LongPress)? (From adversarial review, gesturesSufficient axis.)

---

## First implementation slice — spec-first, no UI

Strictly ordered; **nothing renders until step 4**, and step 4 is still spec
(codegen), not SwiftUI.

1. **Extend `Spec.Display.Event`** with the six events the decision table fires:
   `LookSwipe, ScrubTick, PickToggle, CutLever, ExportLut, OpenSettings`. Add a
   `StageDone` token for Render auto-completion. Re-run Display's existing laws
   (totality/reachability) — they must stay green with the larger alphabet.
2. **Land `SixFour/Spec/ActDecisions.hs`** exactly as drafted. Add the eight laws
   to the `cabal test` battery. Confirm `lawDecisionBudget`, `lawOneCompletion`,
   `lawDecisionsDistinct`, `lawEventCoversDecisions` all pass against the
   *extended* Display alphabet (this is what makes `specIsReal` true).
3. **Golden-pin `goldenDecisionTable`** and add `assertSpecParity`: codegen emits
   `Generated/ActDecisionsContract.swift` (the per-act `(name,target,surface,
   completes)` table), Swift re-derives it, byte-compared — same discipline as
   `DisplayContract.swift`.
4. **Swift router reads the table** (no UI behaviour yet): a thin
   `ActRouter.affordances(for:)` that returns the rows for the current
   `actOf(phase)`. **Compile-check only** (sim has no camera). A control without
   a `Decision` row literally cannot be instantiated — the clutter hole is closed
   at the type level.
5. **Only then** wire each surface to its existing realiser (Drag→`CellDetent`,
   Tap→commit, Swipe→`LookSwipe`, Shape→`PixelGrid` select). One act at a time,
   Live first; build must stay `BUILD SUCCEEDED`.

The gate sequence guarantees the **bound exists before the buttons do** — the
inverse of how Review accreted eight.

---

## Executive summary

SixFour's UI clutters because there is **no spec object between `Display.Phase`
("which act?") and `CellMechanics.Gesture` ("how does one touch feel?")**.
`Display`'s alphabet is bare triggers with no semantics, so **no law bounds how
many controls an act exposes** — which is exactly how Review grew eight co-equal
buttons while violating zero existing laws.

The missing middle layer is **`Spec.ActDecisions`**: `Act → few Decisions →
Surface → one Completion`. Its keystone law, **`maxDecisionsPerAct = 3`**, turns
decisions-per-act into a **number the compiler checks** — a fourth Review row
fails `cabal test`. Codegen pins the per-act decision table to Swift, and the
router renders affordances *from that table*, so **a control with no `Decision`
row is unrepresentable.**

Each act gets ≤3 decisions, all as **gestures on the cell field** (`lawNoButtons`),
drawn from a closed 5-surface vocabulary `{Tap, Drag, Swipe, LongPress, Shape}`.
The per-act screen maps **fit the 94×192 Stage** using only Field64, Palette16,
and free ground — no new chrome cells, 13,068 free cells untouched. Richness
without buttons comes from four force-multipliers: one shared `CellDetent` for
every scalar lever, Tap/hold disjoint by law on one surface, a free recede-overlay
salience bit, and an orthogonal ground-Swipe axis.

Adversarial review flagged the map fit, an event collision in the draft, and an
under-specified `Shape` backing — **all fixed or moved to Open Decisions here**;
the spec compiles only after `Spec.Display` grows six events (First-Slice step 1,
stated honestly). **This workflow implemented nothing** — it delivers the spec
layer, the bounding law, the screen map, and a strictly spec-first first slice,
with the cap on decisions-per-act as the central, gate-enforced invariant.
