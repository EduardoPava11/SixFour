# SixFour UI/UX Architecture Decisions (ADR)

**Date:** 2026-06-05. **Status:** decided (owner-aligned), implementation pending.
**Companions:** `SIXFOUR-UIUX-DIMENSIONAL-MAP.md` (the as-built map), `SIXFOUR-DESIGN-LANGUAGE.md`
(GRID constitution), `SIXFOUR-SPEC-METHODOLOGY.md` (spec→golden→Swift discipline).

These four decisions came out of a research pass (SIMD grid ops, UI/UX state machine, render
clock, isometric movement — all iOS 26+, web-grounded) followed by owner alignment. They share
one spine:

> **One 20 fps clock advances a spec-pinned state machine; the FSM owns the frame/orientation
> math; SIMD + Accelerate bake the grid; isometric geometry is what the movement surface draws.**
> *Form follows function: the GIF's 20 fps rate is the heartbeat, and the 50 ms tick is the
> machine's compute budget.*

---

## ADR-1 — Harden to ONE 20 fps clock (content = render = GIF rate)

**Decision.** A single display-synced clock at **20 fps** drives everything: GIF content advance,
UI grid refresh, and cube/orbit orientation. There is no second clock and no phase divisor —
**one tick = one GIF frame = one render**. The 50 ms tick is the explicit compute budget the state
machine runs within before colours refresh on the grid.

**Why.** The GIF plays at 20 fps (`SFTheme.gifFrameRate = 20`, `Theme.swift:28`; burst captured at
20, `CaptureViewModel.swift:197`; encoded at 20, `:385`). Refreshing the UI faster than the content
changes buys nothing and starves compute; refreshing at the content rate gives the FSM a full 50 ms
to rebuild palettes / diff dirty cells / run iso transforms. Form follows function.

**Mechanism.**
- Replace BOTH the Foundation `Timer` in `PlaybackClock` (`PlaybackClock.swift:62`) AND the separate
  60 Hz `Timer.publish` auto-rotate in `VoxelCubeView` (`VoxelCubeView.swift:232`) with **one
  `CADisplayLink`** requesting 20 fps via `preferredFrameRateRange = CAFrameRateRange(minimum: 20,
  maximum: 20, preferred: 20)`. 20 is a clean integer divisor of both 60 Hz and ProMotion 120 Hz
  panels, so the cadence is exact on every iOS 26 device.
- Derive the frame cursor from the link's `targetTimestamp` / `CACurrentMediaTime()`, **not** a
  fragile counter, so a coalesced/dropped tick (lock-screen, thermal) never accumulates phase error.
- This RESOLVES the GRID Law #4 second-clock violation flagged in `SIXFOUR-UIUX-DIMENSIONAL-MAP.md`
  §6 by quantizing orientation down to 20 fps (not by adopting 60 Hz).
- Publish only the integer `frame` through `@Observable`; keep timestamp/internal phase in
  `@ObservationIgnored` (precedent: `PlaybackClock.swift:43`) so SwiftUI invalidates exactly once
  per frame.
- The cadence law moves from a Swift literal into `Spec.PlaybackClock` as a theorem, pinned by a
  golden table (template: `PlaybackClockContract.goldenAdvanceTable` / `selfCheck`,
  `PlaybackClockContract.swift:51-67`).

**Consequences.** Motion (orbit, transitions) is intentionally chunky at 20 fps — consistent with
the 8-bit pixel-art aesthetic. `settledFrame` gating (pause/scrub-only expensive work,
`PlaybackClock.swift:38-41`) is preserved. If a future need for smoother orientation appears, a
display-native render rate is a one-constant change (`SFTheme.renderHz` + `phaseDivisor =
renderHz / gifFrameRate`), but the default and the law are **20 fps, divisor 1**.

---

## ADR-2 — The UI/UX is per-screen, spec-pinned state machines

**Decision.** Model the UI/UX as **per-screen finite state machines** — Capture-phase, Transport,
Review-mode — each an `enum`-with-associated-values held as a plain stored property on **one**
`@Observable` class, with transitions specified Haskell→golden→Swift like the playback clock.
Defer a single global app FSM.

**Why.** The repo already has the safe shape (`CaptureViewModel.Phase`, `CaptureViewModel.swift:81`)
and a proven spec→golden→Swift transition template; the methodology sanctions Layer-2a state-machine
specs with golden vectors as "mandatory and sufficient" (`SIXFOUR-SPEC-METHODOLOGY.md:24,41,44,50`).
A single global enum risks the iOS 26 **nested-observable-enum** SwiftUI re-render bug
(swift-composable-architecture #2887) and a churning spec matrix; per-screen machines stay small and
evolvable, and cross-screen routing stays in the working `.sheet` / `.fullScreenCover` plumbing
(`CaptureView.swift:16-24`).

**Mechanism / cleanups folded in.**
- Fold the parallel stringly-typed `deterministicStage: String?` (`CaptureViewModel.swift:99`) into
  `Phase` as `.rendering(stage:)`.
- Replace `PlaybackClock`'s boolean transport (`playing`/`reduceMotion`/`frame`/`settledFrame`) with
  an explicit `enum Transport`, preserving `settledFrame` semantics (`PlaybackClock.swift:38-41,94`).
- The rendered grid is a pure function of `(state, frame)` — the FSM is the only mutator.

---

## ADR-3 — A general isometric/dimetric movement language (unified orbit)

**Decision.** Promote isometric geometry to a **first-class spec module** serving both the 2D
movement surface and the 3D cube, with **one** orbit basis.

**Why.** The repo already owns parity-locked 2:1 dimetric orbit (`VoxelIso.orbit == voxelOrbit`,
`VoxelCubeView.swift:125-131` / `Shaders.metal:564-570`) with the correct pixel-art pose (yaw π/4,
pitch π/6 ⇒ sin30 = 0.5 = exact 2:1). But two orbit conventions diverge under general orbit
(CloudProjection pitches about world-X; VoxelIso about camera-right), there is a named codegen debt
(no `Codegen.CloudProjection`, `CloudProjection.hs:76-80`), and no 2D screen↔grid tile transform
exists.

**Mechanism.**
- Canonical 2D dimetric pair: `sx = (gx − gy)·W/2`, `sy = (gx + gy)·H/2`, plus its inverse and the
  draw-order key `gx + gy (+ t)`; pixel-snapped. ~2–3 `simd` matmuls.
- Unify on the **VoxelIso camera-right** basis; prove `CloudProjection` equal (or retire it); close
  the codegen debt with a `Codegen.CloudProjection` emitter + parity test.
- Golden-pinned, SIMD, Swift+Metal bit-for-bit. **Guardrails:** iso skew is confined to a designated
  movement surface and must NEVER bleed into the orthogonal GRID chrome lattice (Law #1,
  `GlobalLattice.swift`); `RULE-CUBE-2D-IDENTITY` (flat pose byte-1:1 with the 2D GIF,
  `Shaders.metal:640-644`) stays inviolate via a flat-pose golden.
- This is the geometry of "frame movement": the time axis as iso depth and transitions over the loop,
  all advanced by the one 20 fps clock.

---

## ADR-4 — Grid bake: Accelerate vImage index→colour, LAYOUT/LOOK split

**Decision.** Refactor the cell bake into two stages: shapes write an **8-bit index plane**
(LAYOUT); one **Accelerate vImage** table-lookup expands the whole plane to ARGB8888 through a
**256-entry `SIMD3<UInt8>` table** (LOOK). Keep cell-shape predicates scalar; use `simd` lane ops +
iso math; **Metal stays 3D-cube-only**.

**Why.** The load-bearing correction from research: **Swift `simd` has no gather/shuffle primitive
(SE-0229)**, so a palette index→colour lookup is *provably not* expressible as one wide SIMD op —
the naive "SIMD does the colouring" is unimplementable that way. vImage table-lookup is the
purpose-built deterministic-integer API for exactly this, and it decouples layout from look (the same
factoring the app already pursues). `setCell` (`CellField.swift:42-46`) writes an *index*, not 4
bytes, killing the per-byte RGBA store loops in `CellSprite.image` (`:15-34`) / `CellField.image`
(`:53-95`). Accelerate is an Apple framework → in-contract (zero third-party deps).

**Why not Metal for 2D.** Promoting the 9.7k-cell field to a float GPU bake reintroduces the
`display ≠ GIF` determinism risk that `sixfour-deterministic-gif-core` is actively removing, and
duplicates every `CellSprite`/`CellGlyph` predicate in MSL (drift vs the Haskell goldens). The survey
reserves Metal for ≥64³ (`ios26-render-survey.md`). Metal keeps the 3D voxel cube only.

**Mechanism / caveats.** Surfaces are small (67×145 ≈ 9.7k cells; widgets ≤576), so the payoff is
**determinism + LOOK/LAYOUT separation + removing store loops**, not FPS. Keep all grid/palette math
integer/fixed-point. Add a golden-vector check that vImage reproduces the existing bytes exactly
before switching. Transcendental shape masks (gear `atan2`, ring turn) stay scalar.

---

## ADR-5 — Capture-screen geometry + the Haar-pyramid abstraction cascade

**Decision.** The capture screen is three framed grids, each a coarser **Haar level** of the one
below, sized self-similarly on the iPhone 17 Pro screen (402×874 pt, exact):

| Element | Grid | Cell | Size | Source (what Zig computes) |
|---|---|---|---|---|
| **GIF preview** | 64×64 | 6 pt | **384 pt** | the rendered GIF frame |
| **Palette** | 16×16 (256) | 12 pt | **192 pt** | the 256 maximin leaves (`s4_quantize_frame` / `s4_global_collapse`) |
| **Capture shutter** | 4×4 (16) | 24 pt | **96 pt** | **Haar level-4 parent colours** of the palette tree |

The cascade is **self-similar**: each level size ×½, cell ×2, count ÷4-per-side (64²→16²→4²). No
title; one consistent thin frame on all three (they read as one family). Golden vertical rhythm,
≈109 pt slack. The shutter is square, on-brand, and **content-aware** — it IS the image reduced to
its 16 essential colours.

**Why (the abstraction is real, not cosmetic).** The owner's chain — *palette = abstraction of the
GIF; shutter = abstraction of the palette* — maps exactly onto the **Haar tree** the core already
builds (`Spec/PairTree.hs:18`, `Spec/PairTreeFixed.hs`, Zig `s4_haar_analyze`/`reconstruct`
`Native/src/kernels.zig:497,540`): 256 leaves = level 8, **16 = level 4**, **4 = level 2**. The
shutter's colours are the *parent averages* of the palette's subtrees — genuine tree levels, not a
median-cut. The size cascade is the pyramid's own geometry (a parent covers 2× the range ⇒ cell ×2).

**The honest-surfacing gap (→ ADR-5a).** Zig currently exposes only `root + offsets` and the full
256 leaves — **not** the intermediate-level node colours. Per the project law "only surface what the
Zig computes," the 16/4 abstractions require a new core function:

> **ADR-5a.** Add `s4_haar_level_nodes(level, root_q16, offsets_q16, out_q16)` to the Zig core,
> spec-first: define `levelNodes :: Int -> HaarPalette -> [OKLab]` in `Spec.PairTree`
> (+ the Q16 form in `PairTreeFixed`), golden-pin it, then port to Zig byte-exact. The UI surfaces
> the level-4 nodes for the shutter and (optionally) level-2 for a deeper drill. Until this lands the
> shutter MUST fall back to what Zig exposes today (leaves or root) — no UI-invented reduction.

Note: the palette operator is **maximin (farthest-first / Gonzalez)**, *not* median-cut/k-means/Wu
(`kernels.zig:332`). The disposable mockups (`~/sixfour_mockups/`, render.py) illustrate the
structure; production colours come from the Zig path above.

---

## Phased implementation (proposed)

Each phase is spec-first (Haskell law + golden) then Swift, gated by `cabal test` + the existing
golden discipline. Order chosen so the clock spine lands first (it resolves a live violation) and the
risky refactors are isolated.

1. **Clock spine.** `Spec.PlaybackClock` phase law (content=render at 20 fps, `targetTimestamp`
   derivation) → one `CADisplayLink` in `PlaybackClock`; remove the cube's 60 Hz timer; cube
   orientation steps on the shared tick. Update `SIXFOUR-UIUX-DIMENSIONAL-MAP.md` §6.
2. **Transport FSM.** `enum Transport` + golden table replacing the booleans; preserve `settledFrame`.
3. **Capture FSM.** Fold `deterministicStage` into `Phase`; spec the phase transitions.
4. **vImage bake.** Index-plane refactor of `setCell` + vImage table-lookup; golden byte-parity gate.
5. **Iso module.** `Spec.Iso` (2D dimetric pair + unified orbit) + `Codegen` emitter + Swift/Metal
   parity; confine skew to the movement surface; flat-pose identity golden.
6. **Haar level-nodes (ADR-5a).** `Spec.PairTree.levelNodes` (+ `PairTreeFixed` Q16) + golden →
   Zig `s4_haar_level_nodes` (byte-exact) → Swift surface. Then build the capture screen: GIF 384 /
   palette 192 (leaves) / shutter 96 (level-4 nodes), framed, no title, on `GlobalLattice`-snapped
   golden gaps. This is the settled capture-screen geometry (ADR-5).

---

## Resolves (from the dimensional map §6 open questions)

- VoxelCube 60 Hz second clock → **ADR-1** (quantized to the one 20 fps tick).
- "Fixed-60 vs display-native" fork → **ADR-1** (hardened to 20 fps; render rate is a one-constant seam).
- FSM scope fork → **ADR-2** (per-screen).
- Cloud-projection constants un-spec'd / orbit divergence → **ADR-3**.
- Per-byte bake loops / LOOK-LAYOUT coupling → **ADR-4**.

---

## ADR-6 — One ScreenLattice: divide the screen into cells, assign by region

**Context.** A recurring structural bug (audited 2026-06-05 via the
`sixfour-screen-lattice-audit` workflow, grounded in an on-device screenshot): the capture screen
was **two spatial systems** — a fixed centred `CellField` background + a floating `VStack`+`Spacer`
column of widgets — running **four pitches** (field 6 pt, palette 12 pt, shutter 24 pt, spacing
2 pt) with **no safe-area awareness**. Result: the preview bled under the Dynamic Island and content
floated off-grid with dead black gaps. The doc's own geometry was contradictory (v2.0 §0.0.4 67×145
vs leftover v1.0 §2.3/§2.5 437-row @2 pt) — the recurrence vector.

**Decision (owner-aligned).**
1. **One pitch** — `gifPx = 6 pt`, no exceptions (the 2 pt `subPt` is retired; a region's cell is
   N atoms, the atom is always 6 pt).
2. **Fixed safe margins** — reserve top 11 rows (62 pt, clears the Island) / bottom 6 rows (34 pt)
   on the fixed iPhone 17 Pro geometry (402×874; *not* Pro Max). No runtime inset read.
3. **One assigned grid** — a single `ScreenLattice` (`SixFour/UI/ScreenLattice.swift`) owns the
   67×145 @6 pt grid; every region (preview / palette / shutter / gear / ground) is pinned to
   **absolute cell coordinates** via `.latticeRegion(_:)`. No `VStack`/`Spacer` for content.
4. **One geometry** — §0.0.4 v2.0 is canonical; the v1.0 §2.1/§2.3/§2.5/§3.2 numbers were
   reconciled inline (this pass) so the doc no longer contradicts itself.

**Status.** Implemented on `CaptureView.latticeScene` (legacy floating HUD kept behind
`gridFirstCapture`); device build + GRID lint green. The screenshot's three defects map to the three
removed causes: island-bleed ← no safe rows; float/gaps ← VStack+Spacers; off-grid sizes ← four
pitches.

**Regression guard (planned, ADR-6a).** Make the structure un-regressable: (a) a CI lint failing on
`Spacer(`/`maxHeight: .infinity` for content positioning; (b) a one-pitch lint failing on numeric
`cellPt:` literals or `GlobalLattice.pt(...)` used for widget SIZE; (c) a coverage unit test that
every one of the 67×145 cells maps to exactly one `ScreenLattice` region (the divide→assign
contract); (d) a codegen/doc check that §2.x numbers equal the §0.0.4 band-map. Because the lattice
is generated from `Spec.Lattice` and gated by `cabal test`, re-introducing a second pitch or a
floating layout fails before merge.

**Root anti-pattern to avoid forever:** *widget-composition* (additive VStack that stacks views and
hopes they fit) instead of *lattice-assignment* (every region claims specific cells from one grid
that already accounts for the safe area). The latter is the law.

---

## Phase 6+ implementation status (this session)

- **Haar level-nodes (ADR-5a):** DONE — `Spec.PairTree.levelNodes` / `PairTreeFixed.levelNodesFixed`
  → Zig `s4_haar_level_nodes` (golden byte-exact) → Swift `SixFourNative.haarLevelColors`. Used by
  the 4×4 shutter (`HaarShutterView`) in review + capture.
- **Capture live-frame fix:** DONE — `burstFrameCallback` streams each frame to the preview at the
  ~20 fps burst cadence (no more frozen screen).
- **Grid-first cascade:** DONE on review + capture (GIF → 16×16 palette → 4×4 Haar shutter); legacy
  explorer/HUD suspended behind flags.
- **ScreenLattice (ADR-6):** DONE on capture; review screen + the regression guards are the next step.
