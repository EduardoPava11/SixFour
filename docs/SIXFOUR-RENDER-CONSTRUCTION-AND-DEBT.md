# SixFour — Capture→Render→Review flow notes, debt cleanup, and the render-construction fix

> Keywords: as-built pipeline notes, deterministic render partials, RenderingPhaseField black hero,
> clock-sweep vs real progress, loadingProgress dead, frame-0 palette mispaint, reverse-cursor dead
> chain, CellSprite un-cached, CPU/GPU field duplication, show-the-GIF-being-constructed.

**Status:** flow documentation + debt + fix plan (2026-06-09). Written now that capture works without
the palette-jump glitch (`225db7f`). Companion to `SIXFOUR-DIMENSIONAL-FIELD-ARCHITECTURE.md` (the
unification plan) and `SIXFOUR-CAPTURE-FLUIDITY-SYSTEMS.md`. Branch `feat/metal-field-render`.

---

## 1. How it works now (the as-built one-surface pipeline)

`SurfaceView` mounts ONE `Surface` (σ), ONE `SurfaceClock` (κ, 20 fps), ONE `CaptureViewModel`
(engine). `PhaseField.field(for: σ.phase,…)` projects σ.phase → a per-phase field view. The ONE
persistent influence-field ground is hoisted in `SurfaceView` behind every phase; each phase field
renders its widgets + chrome on a clear background over it.

**The lifecycle (σ.phase) + the engine seam:**
- **`.live`** — `LivePhaseField`: the 64×64 live preview hero (`surface.previewTile`/`previewPalette`)
  + the 16×16 palette-as-shutter, both at the MOVABLE placement (`region(for:_, at: placement)`). Tap
  the palette → `surface.step(.shutterTap)`.
- **`.locking` / `.capturing`** — `CapturingPhaseField`: on `(.live,.locking)` `SurfaceView` kicks
  `engine.capture()` (AE/AWB lock → `captureBurst`). The hero shows the LATEST landed frame forward
  (the burst's preview renderer COALESCES — keeps only the newest, drops the rest — so individual
  frames are NOT surfaced; a frame-by-frame build here is not available without an engine change).
  The palette becomes the burst-progress fill (at the SAME movable placement — no jump, fixed in
  `225db7f`).
- **`.rendering(stage)`** — `RenderingPhaseField`: the deterministic Zig core runs 5 stages
  (quantize→dither→significance→palette→encode). The per-frame path STREAMS a true-colour partial
  cube after each of stages 1-4 (`DeterministicRenderer.emitPartial` → `surfaceRenderPartial` →
  `SurfaceView` `.onChange(of: engine.renderPartialCube)` → `surface.indexCube`/`palette`). The hero
  is meant to reveal the GIFA-in-progress under a serpentine sweep.
- **`.review`** — `ReviewPhaseField`: at `commit(out)` (after render) σ gets the full `indexCube` +
  `palettesPerFrame`; the hero plays the GIFA loop via `gifCell` through the true per-frame palette.

**The clocks/cursor:** κ ticks 20 fps; `advanceCursor()` (forward) in most phases,
`advanceCursorReverse()` in `.capturing`/`.rendering`.

---

## 2. THE SINGULAR PROBLEM — the 64×64 goes black during GIF computation

**Root cause (audit-confirmed, NOT missing data):** the render DOES stream the real partial cube into
`surface.indexCube`. But `RenderingPhaseField` paints a **clock-timed ghost sweep that ignores it**:
1. `RenderingPhaseField.progress` = `(stageIndex + within)/5` where `within =
   CellEase.progress(clock.tick, since: surface.phaseEnteredTick, ticks: 8)` — a TIMER, not real
   stage progress. `surface.phaseEnteredTick` is re-stamped on EVERY phase change (`SurfaceView:98`),
   so each stage RESETS the ease to 0 → the sweep keeps snapping back. Real Zig stages finish faster
   than 8 ticks → the front never opens → almost the whole 64×64 stays `ghost = (12,12,14)` ≈ black.
2. Resolved cells use `cellGlobal(c,r,cursor)` through `surface.palette` = **frame-0's** partial
   palette, while `cursor` sweeps BACKWARD through all frames → wrong colours even when revealed.
3. The global-palette path + the GPU float fallback stream NO partials → `indexCube` empty → fully
   black the whole render.
4. `engine.loadingProgress` — the REAL monotonic 0→1 progress — is computed but **read nowhere**
   (`RenderingPhaseField` recomputes from the clock instead). Dead signal.

**The fix — show the GIF being constructed (honest, uses the real data):**
- **Drive the reveal by REAL progress, not the clock.** Bridge `engine.loadingProgress` →
  `surface.renderProgress`; `RenderingPhaseField.progress` reads that. Monotonic across the whole
  render, never resets per stage → the serpentine front advances steadily as stages complete.
- **Paint resolved cells with the RIGHT colours.** During render, reveal **frame 0** of the partial
  cube (`cellGlobal(c,r,0)`) through `surface.palette` (which IS frame-0's partial palette) — correct
  colours; one coherent frame resolving, not a backward mis-paletted sweep. (Stop the
  `advanceCursorReverse` during `.rendering`, or pin the render hero to frame 0.)
- **Under-construction base = the last frame, not black.** Unresolved cells show the FROZEN
  `surface.previewTile` (the last captured frame, still populated through render) instead of near-black
  ghost — so the user watches the last preview RESOLVE into the true GIFA along the serpentine front.
  That reads as construction, never a black hole.
- **(deferred) global/GPU paths:** give `renderGlobalPalette` an `onPartial` too, or fall back to the
  previewTile base so they're never fully black.

Net: the last preview frame is visible, a bright serpentine front sweeps across it at the real render
pace, revealing the true GIFA underneath — "the GIF showing itself being constructed."

---

## 3. Technical debt to clean (catalogued, file:line)

**(A) The reverse-cursor chain is DEAD** — its only consumer (the capturing reverse-cursor hero) was
removed in `3f46581`. Remove the whole orphaned chain:
- `Surface.capturedFrames` / `capturedPalettes` (`Surface.swift:180-181`) + `captureReverseCursor`
  (`:186-189`) — no callers.
- `CaptureViewModel.capturedFrames` / `capturedPalettes` (`:205-206`) + the per-burst-frame
  accumulation in the renderer `onFrame` (`:443-446`) + the reset (`:412-413`).
- `SurfaceView` `.onChange(of: engine.capturedFrames.count)` bridge (`:136-139`).
- The `CoalescingFrameRenderer` now only needs the `image` (the live hero); the `PreviewFrame.indices`
  /`.palette` accumulation is dead — simplify back toward an image-only renderer.

**(B) `loadingProgress` orphaned** (`CaptureViewModel.swift:153`) — written 4×, read nowhere. The
render fix (§2) gives it a consumer (`surface.renderProgress`); wire it instead of deleting.

**(C) `CellSprite` un-cached** (`CellSprite.swift:42-58`) — re-bakes the bitmap every body eval (no
input-keyed cache like `StageField`). The render/review heroes re-bake every tick. Add a `bakeKey`
cache (or fold into the GPU surface per the dimensional-field plan).

**(D) CPU/GPU field duplication** — `InfluenceField` (CPU) and `FieldMetalView` (GPU) maintain the
same field logic in parallel (`arrangement`/`sources`/usage). Converge once the GPU path is confirmed
(the dimensional-field unification, S7/S8), then retire the CPU `FieldModel` per-tick 21,800-cell bake.

**(E) Stale comments / waste:** `emitPartial` re-flattens all 64 frames every stage
(`DeterministicRenderer.swift:131-140`) though only frame 0 is shown — flatten one frame; `CellSprite`
doc overstates caching; `Surface.cellGlobal` exists mainly for the render hero (keep, now used right);
`syncPreviewDither`/`previewSamplerNote` reference a "future" SettingsView that exists.

---

## 4. Order of work
1. **Cleanup (A)** — delete the dead reverse-cursor chain (safe; no consumers). Smaller surface to fix.
2. **Render fix (§2)** — `surface.renderProgress` (wire B), frame-0 partial reveal, previewTile base.
3. **Verify on device** — the render should now show the last frame resolving into the GIFA, not black.
4. **(later)** (C) CellSprite cache + (D) field unification + (E) waste, per the dimensional-field plan.
