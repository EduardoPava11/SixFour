# SixFour — Capture Fluidity: the systems & frameworks map

> Keywords: capture fluidity IS the product, disjointed root cause, CPU bake vs GPU shader,
> main-thread contention, Metal CAMetalLayer cell field, UIViewRepresentable host, one CADisplayLink,
> frame-ring decoupling, ingest cadence vs render cadence, 20 fps content, keep the cell-field law +
> spec, F0 per-tick bake regression.

**Status:** ARCHITECTURE / systems study (2026-06-09). The decision doc that should precede any more
fluidity code. Companion to `SIXFOUR-CELL-FLUIDITY-WORKFLOW.md` (the 20 fps per-tick easing — shipped
but insufficient) and `SIXFOUR-RADIATION-THEMES-AND-FLUIDITY-STUDY.md`. Branch
`feat/influence-field-stage`. CLAUDE.md permits hand-written **Metal** (zero deps) — so the GPU path
is on-contract.

## 0. The premise

**The fluidity of capture IS the product.** Tap → the GIFA building, smoothly, is the whole emotional
payload. It currently reads **disjointed on device** even after the reverse-cursor + eased
transitions. Patches have not fixed it because the cause is the **rendering system**, not the
easing. This doc maps the frameworks honestly and picks the one that can actually deliver smooth
full-screen motion at the chosen 20 fps, then plans the migration.

Non-negotiables (carried from the user): **20 fps content** (matches the Zig GIF; the phone's compute
budget), **discrete cells** (4 pt, indexed, the cell-field law), **one clock**, **zero third-party
deps**, **Haskell spec is the source of truth**.

## 1. Why it is disjointed (diagnosis, `file:line`)

| # | Cause | Evidence |
|---|-------|----------|
| **D1** | The full-screen field is **CPU-baked on the MAIN THREAD every tick**: 21,800 cells (100×218) × the N-source inner loop (`atan2`, `sqrt`, dist-to-rect, drift, dither) in Swift, synchronously inside SwiftUI `body`. | `StageField.swift:64` (`CellBitmap.image` over the whole lattice), F0 put `tick` in `bakeKey` ⇒ re-bake every tick (`InfluenceField.swift`). |
| **D2** | During capture, that main-thread bake **competes** with the burst's per-frame main-actor hops AND SwiftUI's tree re-evaluation — three main-thread consumers at 20 fps ⇒ late/dropped frames ⇒ judder. | `CaptureViewModel` `onFrame { Task { @MainActor … } }` per landed frame + the `capturedFrames` bridge + `body` re-eval. |
| **D3** | **Cadence mismatch:** the camera/burst delivers frames *unevenly*; the reverse-cursor consumes at the *steady* 20 fps κ ⇒ the "build" stutters as frames arrive in clumps. | burst `burstFrameCallback` cadence ≠ `SurfaceClock` 20 Hz. |
| **D4** | Each tick swaps a **full-screen `UIImage`** into SwiftUI + writes several `@Observable` fields ⇒ texture-upload churn + invalidation cascades. | `Image(uiImage:)` swap in `StageField`; `baked` @State async store; bridges. |
| **D5** | Per-frame **palette shimmer** in the reverse-cursor (each burst frame quantized to its own palette). | `CaptureViewModel.capturedPalettes` (per-frame). |

**Root cause:** SwiftUI + CPU `CellBitmap` baking is being used as a **per-frame full-screen
renderer**. SwiftUI/Core Animation composite *layers*; they were never meant to recompute a
21,800-cell procedural field on the CPU main thread 20×/s while the camera runs. (Note: F0 — "one
fresh grid per tick" — was the right *idea* but the wrong *engine*; it traded a cheap pre-baked swap
for a heavy main-thread bake. The idea survives; it must run on the GPU.)

## 2. The frameworks map (what each system is FOR)

| System | Strong at | Weak at | Verdict for the field |
|--------|-----------|---------|------------------------|
| **SwiftUI** | declarative structure, layout, gestures, chrome, small views | per-frame full-screen procedural pixels | **KEEP** for structure, the movable widgets, gestures — NOT the ground render |
| **Core Animation + `CADisplayLink`** | the frame clock; compositing pre-made layers | computing pixels | **KEEP** — the one κ stays the clock |
| **Metal — `CAMetalLayer` / `MTKView` + fragment shader** | full-screen per-pixel/per-cell fields at 60–120 fps on the GPU, off the main thread | one-off tiny chrome | **ADOPT** — the right system for the field + capture preview |
| **Metal compute** (already have `GPUContext`, `Pipeline`, `*.metal`) | parallel cell math, palette quant, frame textures | — | **REUSE** — the field math is embarrassingly parallel per cell |
| **AVFoundation capture** | the burst | even playback cadence | **DECOUPLE** via a frame ring (D3) |
| **SwiftUI `Canvas` / `TimelineView`** | medium 2D vector/immediate drawing | reliable heavy per-cell at 20 fps; still CPU-ish | weaker fit; not the answer |
| **Core Image** | filter graphs on images | bespoke per-cell field logic | not the fit |

The codebase **already ships Metal** for capture (`SixFour/Metal/*`), so adopting Metal for the UI
field is consistent, dependency-free, and reuses `GPUContext`.

## 3. Target architecture — the system that delivers smooth capture

**(T1) GPU cell-field render.** Port the influence-field math (dist-to-rect, falloff, usage-weighted
spokes, edge-bleed, seam mute, outward drift, dither) to a Metal **fragment shader**, rendered into a
**`CAMetalLayer`** hosted in SwiftUI via a thin `UIViewRepresentable` (`FieldMetalView`). The GPU
recomputes the field per presented frame *for free* (it's per-pixel parallel), off the main thread.
Cells stay discrete: the shader floors to the 4 pt grid and masks to the Stage (the same
`Boundary.inside` test, in-shader). Inputs become **uniforms / small buffers**: the two widget rects,
lift amount, theme params, the active palette (a 256-entry buffer), the usage histogram (256 floats),
the captured-frame texture (T2). **The CPU per-tick bake is deleted.**

**(T2) Even capture playback (kills D3).** Burst frames land — at the camera's jittery cadence — into
a **GPU texture ring** (triple-buffered `MTLTexture`s, indices written as they arrive). The renderer
reads the ring at the **steady 20 fps κ** (the reverse cursor indexes the ring), so the build is
smooth regardless of arrival jitter. INGEST (camera, uneven) is fully decoupled from RENDER (κ,
steady). No per-frame main-actor array copies (kills D2/D4).

**(T3) One clock, 20 fps content.** The single `CADisplayLink` stays κ. Content (uniforms, ring
index) advances at **20 fps** (the GIF cadence, the compute budget). Decision: present the
`CAMetalLayer` at 20 fps to *match the GIF exactly* (honest WYSIWYG) — the GPU render is so cheap that
20 fps present is a power win, not a smoothness loss; the smoothness comes from *consistent* 20 fps
delivery off the main thread, which is exactly what D1/D2 deny today.

**(T4) SwiftUI keeps** structure, the movable widgets (16×16, 64×64 — small CPU cell bakes are cheap
and fine), gestures, chrome, the FSM wiring. Only the **heavy full-screen ground** moves to the GPU.

**(T5) Palette stability (kills D5).** Quantize the burst to a **shared/stabilized palette** for the
preview (or temporally smooth it) so the backward sweep doesn't shimmer.

## 4. Keep vs change

- **KEEP:** the Haskell spec (the field math formalizes to a **shader-portable** `Spec.InfluenceField`
  with golden vectors — same law, GPU port verified like the Zig kernels), the cell-field law (discrete
  4 pt), 20 fps cadence, order/chaos, the FSM, spec-pinned geometry (`Spec.Boundary`).
- **CHANGE:** the **render backend** for the field (CPU `CellBitmap` → Metal fragment shader); the
  **frame ingest** (per-frame copies → GPU texture ring); **delete F0's main-thread per-tick bake**.
- **Unchanged math:** the field is the *same* function; only WHERE it runs moves (CPU→GPU). The
  shipped Swift `FieldModel` becomes the reference the shader is verified against.

## 5. Migration plan (each step shippable + on-device verifiable)

| Step | Work | Why first | Risk |
|------|------|-----------|------|
| **M0 (optional interim)** | Move the CPU field bake OFF the main thread (background-render the bitmap, present when ready) OR revert F0 to the cheap pre-baked ring | a fast partial win if M1 is delayed | low |
| **M1** | `FieldMetalView` (`UIViewRepresentable` + `CAMetalLayer`) + the field **fragment shader** (port `FieldModel`); SwiftUI hosts it under the widgets; delete the per-tick CPU bake | THE fluidity win — removes D1/D2/D4 | med (shader port + hosting) |
| **M2** | Burst frames → GPU **texture ring**; reverse-cursor indexes it at steady κ | kills D3 (uneven build) — the capture-specific smoothness | med (capture path; on-device) |
| **M3** | Shared/stabilized burst palette | kills D5 shimmer | low |
| **M4** | Formalize `Spec.InfluenceField` (+ `Spec.Boundary`) → shader golden parity | the spec-first law | med |

M1 is the single highest-impact change and is independently testable (it doesn't touch capture).

## 6. Risks & open decisions (for the user)

- **Adopt Metal for the UI field?** (Recommended — it is the only system that renders a full-screen
  procedural field smoothly, it's on-contract, and the infra exists.) Or stay CPU and only do M0
  (background bake) — lighter but a ceiling on smoothness.
- **Present rate:** 20 fps to match the GIF exactly [rec], vs present at display rate with 20 fps
  content held (smoother motion but no longer GIF-honest — you've said 20 fps matters).
- **Scope of GPU render:** field-only (widgets stay CPU) [rec], vs the whole surface on the GPU
  (bigger rewrite, unifies but touches everything).
- **Interim M0 now?** Want the background-thread bake as a quick partial fix while M1 is built, or go
  straight to Metal?
- **Verification:** all of this is **on-device only** (camera + GPU timing); Claude compile-checks,
  you run. Worth wiring a tiny on-device frame-time HUD (ms/tick) to make "smooth" measurable?

## 7. Bottom line

The disjointedness is the predictable result of rendering a full-screen procedural cell field on the
CPU main thread via SwiftUI, 20×/s, next to a running camera. The fix is to **render the field on the
GPU (Metal `CAMetalLayer` + fragment shader, M1)** and **feed captured frames through a GPU texture
ring read at a steady 20 fps (M2)** — keeping the cell-field law, the 20 fps cadence, and the spec
intact. Everything else (themes, easing) rides cleanly on top once the render system is right.
