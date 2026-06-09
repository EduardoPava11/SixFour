# SixFour — Cell-Grid Graphical Fluidity (workflow)

> Keywords: fluidity, render-rate vs logic-rate, fixed timestep + interpolated render, one-clock
> law, ProMotion, field breathing cross-fade, act1→act2 transition, lift dims radiation, preview
> frame-build reveal, snap easing, cell-field law, no-blend hero.

**Status:** UI/UX + build plan (2026-06-09). Companion to `SIXFOUR-INFLUENCE-FIELD-WORKFLOW.md`
(the ground), `SIXFOUR-ACTS-WORKFLOW.md` (the acts), `SIXFOUR-DISPLAY-FSM.md` (κ / `lawOneClock`).
Branch `feat/influence-field-stage`. SixFour owns all code; spec is the source of truth.

The influence field looks right but **not smooth**. This maps how to make the cell grid fluid:
act1→act2 must be smooth, radiation and tap+hold+drag must work together (radiation recedes while
lifting), and tapping the 16×16 palette to capture must build the GIFA in the preview smoothly.

## 0. Why it isn't smooth (root cause, `file:line`)

1. **ONE 20 Hz clock drives every visual.** `SurfaceClock` is a single `CADisplayLink` pinned to
   `SixFourDisplay.logicRateHz = 20` (`SurfaceClock.swift:52`). The field breathing, the cursor,
   and phase transitions ALL update 20×/s. On a 60/120 Hz display that reads as a **strobe** — the
   dominant cause.
2. **Discrete bakes, no interpolation.** `StageField` hard-SWAPS between pre-baked noise frames each
   tick (`StageField.swift`); widget moves re-bake discretely; nothing tweens.
3. **Hard phase swaps.** `live → locking → capturing` swaps the whole phase field instantly — the
   palette content (shutter→progress fill) and banner pop in.
4. **Preview frame cadence.** During capture the hero shows the reverse cursor over the captured
   prefix at 20 fps with hard cuts — "frames building" looks steppy.
5. **No eased lift feedback** (now: lift dims the field, but as a hard step — see F5).

> **The honest frame:** cells are DISCRETE (4 pt, indexed, no AA — the cell-field law). "Fluid"
> here = smooth **cadence + easing + cross-faded ground**, NOT sub-cell motion. We make the
> *timing* continuous, not the geometry.

## 1. The plan (F1 is the crux)

### F1 — Decouple RENDER rate from LOGIC rate  ⚠️ needs go-ahead (spec-touching)
Keep ONE clock (honor `lawOneClock`) but run the `CADisplayLink` at the **native refresh** (up to
120 Hz via `preferredFrameRateRange.maximum`) and DERIVE the 20 Hz logic from a **time
accumulator**: step δ / `advanceCursor` only once ≥ 1/`logicRateHz` s has elapsed; EVERY native
frame, advance CONTINUOUS visual params — `renderPhase: Double` (breathing), `transitionProgress`,
`liftAmount`, `snapEase`. The canonical *fixed-timestep + interpolated-render* loop.
- **Spec impact:** `logicRateHz` stays 20 (the LOGIC rate); add a `renderRateHz`/native concept and
  reword `lawOneClock` to "one display link; logic subdivided to 20 Hz." Edit `Spec.Display` →
  `DisplayContract` → `SurfaceClock`; re-fold parity. THIS is the change that makes everything else
  feel smooth, so do it first — but it is behavioral + spec, hence the go-ahead gate.

### F2 — Smooth field breathing (cross-fade, not strobe)
With F1's continuous `renderPhase`, `StageField` CROSS-FADES between ring frame ⌊p⌋ and ⌈p⌉ by
frac(p) — a cheap GPU opacity blend of two pre-baked images, no re-bake. For the cross-fade to read
as *flow* (chaos radiating) and not blur, make the ring a **coherent outward drift** (the noise
pattern advances radially away from each source per frame) instead of independent random frames.

### F3 — Smooth act1→act2 transition
Already 80% solved: the universal field + persistent widgets keep the GROUND and POSITIONS
continuous across the swap (shipped). Remaining discontinuities to ease (via `transitionProgress`
or `withAnimation`): the palette **shutter→progress fill grows smoothly** as frames land; the
banner fades/slides in; a `shutterTap` fires a Q16 **press ripple** from the palette
(`Spec.CellMechanics` pulse already exists). Low risk once F1 lands.

### F4 — Preview builds the GIFA smoothly during capture
The hero is indexed cells (no-blend law) — do NOT cross-fade frames (that blends indices). Instead:
as each of the 64 frames lands, REVEAL it with a cell-progressive wipe (`Spec.Order.serpentine`,
the same reveal `RenderingPhaseField` uses) + one `CellTick`; F1's native cadence makes the
per-frame arrival smooth, not a pop. The no-freeze reverse-cursor (Act II design) keeps it alive;
F4 makes each landing fluid. Net: you watch the GIFA assemble frame-by-frame, smoothly.

### F5 — Lift dims radiation  ✅ SHIPPED (this turn), ease pending
While a widget is lifted, the field energy is scaled by `FieldTuning.liftDim` (σ carries
`liftedWidget`; `MovableColorWidget` sets it on lift/drop; `InfluenceField` reads it). Currently a
HARD step — F1's `liftAmount` (eased 0→1 over ~150 ms) makes the radiation recede/return smoothly.

### F6 — Eased widget snap-on-drop
Animate the snap when a drop commits (today the `.offset` auto-resets instantly). `withAnimation`
on the `widgetPlacement` change → the widget glides to its cell. Independent of F1, low risk.

## 2. Sequencing

| Phase | Items | Risk | Gate |
|------|-------|------|------|
| **now** | F5 lift-dim (hard step) | shipped | builds |
| **A** ⚠️ | F1 render/logic split + F2 smooth breathing | spec-touching | `Spec.Display` go-ahead, `cabal test`, on-device |
| **B** | F3 transition ease + F5 ease + F6 snap ease | low (SwiftUI anim) | on-device |
| **C** | F4 preview frame-build reveal | low–med | on-device |

## 3. Files

- **F1:** `spec/src/SixFour/Spec/Display.hs` (logic vs render rate, `lawOneClock` reword) →
  `Generated/DisplayContract.swift`; `SixFour/UI/Surface/SurfaceClock.swift` (native link +
  accumulator + continuous params); `SurfaceView.swift` (`onTick` → onLogicTick / onRenderFrame).
- **F2:** `SixFour/UI/Components/StageField.swift` (cross-fade overlay) +
  `InfluenceField.swift`/`FieldModel` (coherent outward-drift ring).
- **F3:** `LivePhaseField` / `CapturingPhaseField` (palette fill + banner + press ripple).
- **F4:** `CapturingPhaseField` (serpentine per-frame reveal, reuse `Order.serpentine`).
- **F5 (done):** `Surface.swift` (`liftedWidget`), `MovableColorWidget.swift`, `InfluenceField.swift`
  (`FieldTuning.liftDim`). Ease = F1 `liftAmount`.
- **F6:** `MovableColorWidget.swift` (animate the commit).
- Never hand-edit `Generated/*`.

## 4. Open questions

- F1: cap render at 120 Hz, or honor `maximumFramesPerSecond`? Battery vs smoothness — the field is
  a full-screen bitmap swap, cheap, but a 120 Hz cross-fade is more GPU than a 20 Hz swap.
- F2: does the outward-drift breathing read as "chaos radiating," or is a gentle in-place shimmer
  calmer? (on-device judgment.)
- F4: serpentine reveal per landed frame vs a simple top-down wipe vs just the higher cadence alone?
- Should reduce-motion pin the breathing (accessibility) even though the field "never pauses"? (Lean:
  reduce amplitude, keep a minimal pulse.)
