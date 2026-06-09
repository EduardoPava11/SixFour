# SixFour — Testable Act I: a no-camera harness for the influence field

> Keywords: testable Act I, no-camera, Simulator, DemoScene synthetic sensor, -demoScene launch
> arg, LivePhaseField #Preview, influence field tuning, order-vs-chaos, SurfaceView demo gate.

**Status:** test harness (2026-06-09). Companion to `SIXFOUR-INFLUENCE-FIELD-WORKFLOW.md` (the
field this lets you see) and `SIXFOUR-ACTS-WORKFLOW.md` (Act I = `.live`). Branch
`feat/influence-field-stage`.

## 0. Why

Act I (`.live`) only renders the **influence field** when σ carries real `previewTile` + palette
data — and that comes from the camera. **The iOS Simulator has no camera**
(`FigCaptureSourceSimulator err=-12784`), so the field has nothing to radiate and Act I can't be
seen there. Claude **compile-checks only** (it cannot meaningfully run a camera app); the user runs
on a real device. This harness closes that gap: a synthetic sensor so Act I is **runnable in the
Simulator** (for the user) and **previewable in the Xcode canvas**, with the real surface, real
movability, and the real `StageField`/`InfluenceField` — only the camera is faked.

## 1. The lens: ORDER (widgets) vs CHAOS (cells)

The two widgets are **order** — crisp, structured, the field's two sources. The surrounding cells
are **chaos** — colour radiating out of the widgets, dense and faithful right at their edges,
dissolving into speckle, then into the dark void. The harness feeds a scene built to show exactly
this: a couple of moving "subjects" dominate the colour histogram (their colours throw long,
*ordered* spokes via the usage-weighted reach), while drifting interference bands keep the rest of
the field a live *chaos*. Dragging a widget re-authors where order meets chaos (the `balance=0`
ridge moves with it).

## 2. The harness (as-built, all DEBUG-only, stripped from release)

- **`SixFour/UI/Components/DemoScene.swift`** — the synthetic sensor. `DemoScene.palette` (a fixed
  256-colour hue/value ramp) + `DemoScene.tile(tick:)` (a 64×64 index tile that DRIFTS with the κ
  tick and has deliberately NON-UNIFORM usage: two moving dominant subjects + interference bands).
  Pure, dependency-free, `#if DEBUG`.
- **`SurfaceView` demo gate** (`SixFour/UI/Surface/SurfaceView.swift`) — `-demoScene` launch arg:
  - `.task`: when set, **skip `engine.bootstrap()`** and fire `surface.step(.sessionReady)` →
    straight to `.live` (no camera, no auth prompt path).
  - `clock.onTick`: while `.live`, write `DemoScene.tile(tick: clock.tick)` + palette into σ each
    tick (keyed off κ's monotonic `tick`), so the field animates at 20 fps. The engine never
    produces, so its `onChange` bridges stay silent — no conflict.
- **`LivePhaseField` #Preview** (`"Act I — influence field (demo scene)"`) — a mock `Surface`
  stepped to `.live` + seeded with one `DemoScene` frame; instant Xcode-canvas iteration of the
  `InfluenceField` `static` tunables (no app boot, no engine).

## 3. How to run / tune

- **Xcode canvas (fastest):** open `LivePhaseField.swift`, show the canvas, pick the
  "Act I — influence field (demo scene)" preview. Edit the `static let`s at the top of
  `InfluenceField.swift` (`reachField`, `reachPalette`, `usageReachMin`, `ridgeMute`, `phases`) and
  watch it update.
- **Simulator, full interactive app:** Scheme ▸ Edit Scheme ▸ Run ▸ Arguments ▸ add `-demoScene`,
  then Run on any Simulator. Act I comes up live and animated; **long-press-drag** Field64 /
  Palette16 to re-author the link (the ridge follows). *Note:* the shutter TAP isn't wired in demo
  (no engine) — testing here is by dragging, which is the point (authoring the field).
- **Real device:** no flag needed — the real camera feeds the real field. This is the only place
  the true scene-driven look is judged.

## 4. Scope / non-goals

- Demo is `.live` only (Act I). Tapping the shutter in demo leaves σ in `.locking` (the masked
  checker) — capture/render/review demo data is out of scope (a later harness could fake the burst).
- The scene is illustrative, not a real camera model; it exists to exercise usage-weighting, edge
  bleed, ridge muting, and breathing — not to look like a photo.
- DemoScene + the gate are `#if DEBUG`; release builds are byte-identical to pre-harness.
