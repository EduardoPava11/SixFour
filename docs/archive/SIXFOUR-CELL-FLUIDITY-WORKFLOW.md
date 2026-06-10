# SixFour — Cell-Grid Graphical Fluidity (workflow)

> Keywords: fluidity at 20 fps, per-tick delta, one-grid-per-tick, coherent breathing drift,
> eased act1→act2 transition, lift-dim ramp, GIFA build reveal, snap-on-drop ease, smoothstep,
> tick-driven animation, cell-field law, no-blend hero, ProMotion-free.

**Status:** UI/UX + build plan (2026-06-09, v2 — REPLACES the v1 render-rate proposal). Companion
to `SIXFOUR-INFLUENCE-FIELD-WORKFLOW.md` (the ground), `SIXFOUR-ACTS-WORKFLOW.md`,
`SIXFOUR-DISPLAY-FSM.md` (`lawOneClock`). Branch `feat/influence-field-stage`.

## 0. The rate model — what is FIXED, what is the lever

Three distinct rates; only the third is touched:

1. **Compute rate** — how often a *new* cell grid is calculated. **FIXED at 20 fps** (`logicRateHz`):
   it matches the Zig GIF's true 20 fps cadence (the preview must not look smoother than the GIF is)
   and is the per-frame compute budget the phone is given. **Not changed.**
2. **Present rate** — how often pixels hit the screen. **FIXED at 20 fps** (one κ tick = one present).
   No native-refresh interpolation, no cross-fade presentation. **Not changed.** (v1's F1/F2 wrongly
   proposed raising this — retired.)
3. **Per-tick delta** — *how much the grid changes between two 20 fps ticks*. **THIS is the lever.**

The choppiness is per-tick delta: today each tick is a HARD CUT — instant phase swap, *random*
noise re-roll (strobe), 1-tick lift-dim snap, frames popping. Fluidity = make each 20 fps tick a
**small, coherent, eased step**. Same 20 grids/sec; no jumps between them.

> Honest limit: at 20 fps there is always a 50 ms step — the chosen GIF cadence. We remove the
> JARRING (pops/strobe/instant swaps), we do not add frames. Cells are discrete (4 pt, indexed,
> no AA — the cell-field law); "smooth" = eased *timing of content*, never sub-cell motion.

## 1. F0 — Foundation: ONE fresh grid per tick (everything else rides this)

Make the influence field recompute **every** κ tick, parameterized by the monotonic `clock.tick`.
Concretely: include `tick` in `InfluenceField`'s `StageField` `bakeKey` → the field re-bakes once
per tick (the "next cell grid" the 20 fps budget exists for). Retire the pre-baked N-frame noise
ring + `FieldTuning.phases` (the swap-a-random-frame strobe); the static B/W checker
(`GridRefreshFieldView`) keeps its constant `bakeKey` (single bake, no waste).

This is the whole architectural move: **one grid per tick, as a function of `tick` and the
animation state.** No new clock, no rate change. Every item below is then a pure function of
`tick`, recomputed inside that one per-tick bake.

## 2. The shared easing primitive + animation state

- **Easing** (pure, UI-only — off the verified GIF path): `smoothstep(p) = p*p*(3 - 2p)` on
  `p = clamp((tick − startTick) / durationTicks, 0, 1)`. Integer in, Double out. One helper
  `Ease.progress(tick, start:, ticks:) -> Double`.
- **Animation state = a few out-of-band σ fields** (Ints; NOT FSM events — mirrors the Display
  out-of-band discipline). Each is "the tick an animation began":
  - `phaseEnteredTick: Int` — set in `SurfaceView.onChange(of: surface.phase)` (already a seam).
  - `liftChangedTick: Int` — set when `liftedWidget` changes (already set in `MovableColorWidget`).
  - `capturedFrames: Int` + per-frame `frameLandedTick` — the burst-progress source (Act II).
  All derive `elapsed = tick − startTick`; no float state on the spine.

## 3. The fluidity items (each = a small eased per-tick delta at 20 fps)

| # | What | Driver | Duration | Per-tick delta (recomputed in the F0 bake) |
|---|------|--------|----------|---------------------------------------------|
| **F1** | **Coherent breathing drift** (chaos radiates, not strobes) | `tick` | continuous | The dither threshold samples noise at a position DRIFTING outward from the dominant source: `n = noise(c − dir.x·tick·drift, r − dir.y·tick·drift)`, `dir = unit(p − domCenter)`. Each tick the speckle marches ~`drift` cell outward (tunable `driftPerTick`, e.g. 0.2). Adjacent ticks differ slightly → flow, not re-roll. |
| **F2** | **Eased act1→act2** | `phaseEnteredTick` | ~8 ticks (0.4 s) | `p = smoothstep(elapsed/8)`. The palette's shutter→progress fill grows by `p` (and tracks `capturedFrames`); the banner eases in (cell rows fill by `p`); a `shutterTap` press ripple (Spec.CellMechanics pulse) plays over the first ~3 ticks. Ground + widget positions already persist (universal field) → no jump. |
| **F3** | **Lift-dim RAMP** (not a snap) | `liftChangedTick` + target | ~4 ticks (0.2 s) | `a = smoothstep(elapsed/4)` toward `target = lifted ? 1 : 0`; `E *= 1 − a·(1 − liftDim)`. Radiation recedes/returns over 4 ticks instead of one. (Replaces the hard step shipped in F5/`3ae2cf0`.) |
| **F4** | **GIFA build reveal** (watch frames assemble) | `frameLandedTick[t]` | ~3 ticks/frame | Hero is no-blend indexed cells ⇒ REVEAL, not cross-fade: as each landed frame shows, its cells appear in `Spec.Order.serpentine` rank order, fraction `= smoothstep(elapsed/3)`; un-revealed cells = the prior frame / ghost. One `CellTick` per landed frame. The no-freeze reverse cursor keeps it alive; this makes each landing fluid. |
| **F5** | **Snap-on-drop ease** | drop event | ~4 ticks | The widget glides from its lifted offset to the snapped cell (a residual offset eased to 0). This is the placed widget VIEW (not the cell field) → a `withAnimation(.easeOut)` on the committed `widgetPlacement`/offset; reads fine at 20 fps. |

## 4. Performance budget (the reason 20 fps exists)

One full field bake/tick ≈ `100×218 = 21,800` cells × the N-source inner loop. The 20 fps budget is
50 ms/tick — ample. Watch items: precompute a **256-bucket angle LUT** per source once per bake
(kills per-cell `atan2`), and keep the static geometry (source rects, usage histogram) out of the
per-cell loop. If a device tick ever exceeds budget, drop `driftPerTick` resolution or coarsen the
far-field (low-energy cells are `farDark` regardless). Measure on device; never exceed 20 fps.

## 5. Sequencing

| Phase | Items | Risk | Status |
|------|-------|------|------|
| **A** | F0 one-grid-per-tick + F1 coherent drift | med (per-tick cost) | ✅ SHIPPED (`0804a8c`) — builds; verify perf ≤ 50 ms/tick + smoothness on-device |
| **B** | F2 act1→act2 ease + F3 lift ramp | low | ✅ SHIPPED (`691068c`) — verify on-device |
| **C** | F4 GIFA build reveal (eased serpentine) | low–med | ✅ SHIPPED — verify on-device. **F5 snap-ease DEFERRED** (drop lands ≈ where lifted ⇒ ≤4 pt snap; low value, finicky `@GestureState` reset) |

## 6. Files

- **F0/F1:** `SixFour/UI/Components/InfluenceField.swift` (tick in `bakeKey`; drift in the noise
  sample; retire `phases` ring), `StageField.swift` (per-tick bake path stays; ring no longer used
  by the field). New `Ease` helper (small, in `InfluenceField.swift` or a `CellEase.swift`).
- **F2:** `Surface.swift` (`phaseEnteredTick`), `SurfaceView.swift` (set it on phase change),
  `CapturingPhaseField.swift` / `LivePhaseField.swift` (progress-driven fill/banner/ripple).
- **F3:** `Surface.swift` (`liftChangedTick`), `MovableColorWidget.swift` (set it),
  `InfluenceField.swift` (ramp `E`).
- **F4:** `Surface.swift` (`capturedFrames` / `frameLandedTick`), `CapturingPhaseField.swift`
  (serpentine reveal, reuse `Order.serpentine`).
- **F5:** `MovableColorWidget.swift` (`withAnimation` on commit).
- Never hand-edit `Generated/*`. No `Spec.Display` change (rates unchanged) — F0–F5 are Swift-only
  presentation easing; the field math formalizes later in `Spec.InfluenceField` (incl. the drift +
  ease as pinned functions).

## 7. Open questions

- `driftPerTick` magnitude + whether drift is purely radial (outward) or has a slight tangential
  swirl (more organic). On-device.
- F2 duration (8 ticks) and whether the banner slides or fills.
- F4: serpentine reveal per frame vs a simpler row wipe vs cadence alone.
- Reduce-motion: pin the drift (no breathing) but keep the field present? (Lean yes — accessibility.)
