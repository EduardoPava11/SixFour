# SixFour UI/UX Design Map — Dimensions First, 20 fps Governed

**Thesis.** SixFour turns a 64-frame burst into a 64×64×64-frame GIF with a learned 256-colour global palette. Its UI is not *decorated around* that artifact — it is *built from* it. This document maps the five concern areas (grid, buttons, GIF player, palette explorer, dimension-clock) onto one law: **the UI is 2D, pixels are I/O in time, and form follows function** — every visual dimension and every cadence is dictated by the GIF's data dimensions and its 20 fps rate. Claims are cited `path:line` against the live code and the canonical specs (`docs/SIXFOUR-DESIGN-LANGUAGE.md` "GRID v2.0", `docs/SIXFOUR-TOTAL-PIXELATION.md`, `spec/src/SixFour/Spec/Lattice.hs` → `SixFour/Generated/LatticeContract.swift`).

> **Maturity caveat (read first).** GRID v2.0's header states plainly: "the *numbers* in this document are locked and enforceable; the *enforcement machinery* … is **specified here but not yet built**" and that `[PLANNED]` markers must not be read as "passes a test today" (`docs/SIXFOUR-DESIGN-LANGUAGE.md:4`). This map honours that: derived numbers are treated as law; un-wired machinery is surfaced in §6, not papered over.

---

## The two governing laws

1. **Dimensional law (2D, pixels = I/O in time).** Every governed UI dimension is an integer count of the GIF pixel atom `gifPx`, and each visual axis projects exactly one data axis of the cube `(x, y, t)` or the palette `(L, a, b, t)`. Nothing on screen is free; everything traces to data.

2. **One-clock law (hardened 20 fps = GIF rate).** A single clock at `gifFrameRate = 20` (`SixFour/UI/Theme.swift:28`) drives content advance, UI refresh, AND cube orientation: **one tick = one GIF frame = one render**, no phase divisor. The same `20` parametrises the encoder (`CaptureViewModel.swift:385`) and burst capture (`CaptureViewModel.swift:197`). The 50 ms tick IS the state machine's compute budget. *Decided 2026-06-05 (ADR-1, `SIXFOUR-UIUX-ARCHITECTURE-DECISIONS.md`): harden to one `CADisplayLink` @ 20 fps (a clean divisor of 60/120 Hz panels) replacing the Foundation `Timer` (`PlaybackClock.swift:62`) and the cube's 60 Hz timer (`VoxelCubeView.swift:232`); derive the cursor from `targetTimestamp`. Until implemented, the code still uses the 20 Hz `Timer` + a separate cube clock (see §6).*

---

## Dimensions table — every dimension → its 2D-over-time projection

| Data dimension | Where it lives | How it projects onto the 2D screen over time | Cite |
|---|---|---|---|
| GIF x (0–63) | cube width | Preview columns 1–64, 1 GIF pixel = 1 `gifPx` = 6 pt | `LatticeContract.swift:57-58`; Theme `gifSideCells=64` `:24` |
| GIF y (0–63) | cube height | Preview rows 31–94 (golden-anchored 64 cells) | `LatticeContract.swift:55-56` |
| GIF t (frame 0–63) | cube depth / loop | The single `PlaybackClock.frame` cursor; playhead column in the 64-cell scrub rail | `PlaybackClock.swift:32`; transport `PlayerTransport.swift:111-114` |
| Palette count (256) | per-frame palette | 16×16 grid, treemap leaves, cloud dots — all 256 cells, 1:1 | grid/treemap/cloud in `GIFReviewView.swift:84-155` |
| OKLab L, a, b | colour 3-space | Cloud `oklabToWorld`: L→y, a→x, b→z, scale s=2, then rotate→orthographic | `PaletteCloudView.swift:142-159` |
| Palette time (per-frame) | 64 palettes | Cloud trails look back N frames at `(frame−n) mod count` on the same clock | `PaletteCloudView` trail logic; clock-sourced |
| Address radix (2/4/8-ary) | SplitTree depth | AddressPicker wheel count = `branching.depth` (8 / 4 / 2 wheels) | `AddressPickerView.swift` |
| Cube depth (3D pose) | 64 z-slices = time | VoxelCube extrudes z = frame-time, dimetric 2:1, front face (z=63) = `clock.frame` | `VoxelCubeView.swift:203-268`; `PlaybackClockContract.swift:35-37` |

The recurring move is **honest projection**: 3-space → screen 2-space by orthographic map (distance-true), and the 4th axis (time) is *scrubbed*, never embedded (no t-SNE/UMAP) because OKLab is already meaningful 3-space (`PaletteCloudView.swift:142-159`; `docs/SIXFOUR-HIGHDIM-UIUX.md §0/§7-P4`).

---

## §1 — HOW the pixelation grid is set

**The atom is forced, not chosen.** `gifPx = 6 pt = 18 device-px @3x` (`LatticeContract.swift:22-23`). It is the largest integer pitch at which the 64-wide preview fits portrait width: `64·6 = 384 ≤ 402`, and `64·7 = 448 > 402` overflows. This is proven as a theorem in `Spec/Lattice.hs lawAtomIsGifPx` (cited `:242-247` by the grid map) and re-asserted at runtime: `selfCheck()` requires `previewCells * gifPx <= screenWidthPt && previewCells * (gifPx+1) > screenWidthPt` (`LatticeContract.swift:70-71`). 18 device-px @3x is integer, so the preview resamples never (nearest-neighbour upscale, `PixelGrid.swift:38-54`).

**One pitch, plus a commensurate sub-pixel.** `subPt = 2 pt = gifPx/3` (`LatticeContract.swift:24-25`; checked `gifPx % subPt == 0 && gifPx/subPt == 3` at `:69`). `subPt` is legal only for fine spacing, gutters, and text legibility — never a widget's own pixel size. `GlobalLattice` is the *sole owner* of the atom→point conversion (GRID Law #5), re-typing the generated constants as `CGFloat` and exposing `gif(_ cells:)` and `pt(_ subcells:)` (`SixFour/UI/GlobalLattice.swift:24-79`); no view multiplies by `gifPx` itself.

**The screen tiles exactly.** `402 / 6 = 67` cols, `874 / 6 = 145.67 → 145` rows + a 4 pt vertical bleed (`LatticeContract.swift:29-31`); `selfCheck()` requires `cols*gifPx == screenWidthPt && bleedPt == screenHeightPt - rows*gifPx && bleedPt < gifPx` (`:72-74`). `CellFieldView` sizes its bitmap to exactly `gif(67) × gif(145) = 402 × 870 pt`, then upscales ×1 (grid concern map, `CellField.swift:107-130`).

**The hero is golden-anchored.** The preview occupies cols 1–64 × rows 31–94 (`LatticeContract.swift:55-58`), splitting the column 31 above : 64 preview : 50 below; `50/31 ≈ 1.61 ≈ φ`. `selfCheck()` enforces `aboveRows + previewCells + belowRows == rows && aboveRows < belowRows` (`:81`). (Note: the golden ratio is *approximate* by construction — see §6.)

**Widgets grow by more atoms, never bigger atoms.** Sizes come off a Fibonacci ladder `[8,13,21,34,55,89]` (`LatticeContract.swift:38`): touch floor = 8 atoms = 48 pt = `ceil(44/6)·6` (`selfCheck` `:77-78`), shutter = 12 atoms = 72 pt, ring = 20 atoms = 120 pt (`:42-46`).

---

## §2 — HOW buttons are deterministically outlined + their lifecycle

**Buttons are pure geometry, not images.** The shutter renders by evaluating a closure predicate per cell at paint time: cell `(c,r)` is in the shape iff `d <= discRadius || (d <= discRadius + thickness)`, `d` = Euclidean distance from centre (`SixFour/UI/Components/CellSprite.swift:84-110`). Disc radius = 5 atoms, ring thickness = 1 atom each side (`shutterDiscRadiusCells=5`, `shutterRingThicknessCells=1`, `LatticeContract.swift:51-52`).

**The 12-cell size is a theorem.** `5·2 + 1·2 = 12` is enforced in `selfCheck()`: `shutterDiscRadiusCells*2 + shutterRingThicknessCells*2 == shutterCells` (`LatticeContract.swift:75`), and `shutterCells*2 == controlCells*3` (`:80`). The shutter is a *constraint*, not a chosen size (closure law, `docs/SIXFOUR-DESIGN-LANGUAGE.md §3.3`).

**States are cell-space transforms, never opacity (GRID Law #2).** Busy = colour swap `SIMD3(220,60,60)` red vs `SIMD3(255,255,255)` white (`CellSprite.swift:85-86,94`). Disabled = a 2×2 checker `checkOn = ((c/2)+(r/2)) % 2 == 0`, value `checkOn ? fill : ledGhost` (`CellSprite.swift:101-104`) — the only opaque way to dim a block, since alpha is forbidden on a data cell. Ring ticks are precomputed golden endpoints (64, one per frame, `θ=2πk/64` with floor-not-round for Haskell↔Swift parity), scanned per cell (`CellSprite.swift:252-294`; `CellShapesContract.swift`).

### State machine (driven by `vm.phase`, not an internal timer)

| State | Trigger | Render | Cite |
|---|---|---|---|
| idle | initial / capture complete | white disc + ring | `CellSprite.swift:84-110` |
| capturing/locking/renderingStageA/renderingEncode | user tap → `vm.capture()` | red fill (`busy:true`) | `CaptureView.swift:196-217`; `CaptureViewModel` phase |
| disabled | `vm.phase == .configuring \|\| .unauthorized` | 2×2 checker + `.disabled()` | `CaptureView.swift:205`; `CellSprite.swift:101-104` |
| (ring gauge) | `vm.sceneGauge` change (~10 Hz preview cadence) | lit-tick count = `INT(gauge·64)` | `CaptureViewModel.swift:155-169` |

**The button is a static bake, decoupled from the 20 fps clock.** The shutter re-renders only when `vm.phase` mutates (SwiftUI `@Observable`); the ring re-renders only when `sceneGauge` publishes (~10 Hz), *not* on the 20 fps timer (`docs/SIXFOUR-DESIGN-LANGUAGE.md §6.6`; buttons concern map). The press-feedback is a synchronous state mutation, not a temporal animation.

---

## §3 — HOW GIFs are shown (the 20 fps single clock)

**One clock, spec-pinned arithmetic.** `PlaybackClock` is `@MainActor @Observable` and owns *state + the timer only*; all cyclic math is delegated to the generated `SixFourPlaybackClock` (`PlaybackClock.swift:4-16, 73-75`). The timer: `Timer.scheduledTimer(withTimeInterval: 1.0 / Double(SFTheme.gifFrameRate), repeats: true)` (`PlaybackClock.swift:62`). Each 50 ms tick calls `advance()` → `frameAfter(frame, count: count)` (`PlaybackClock.swift:75`; `PlaybackClockContract.swift:20-22`), incrementing the cursor mod 64.

**It replaced four drifting clocks.** The header documents that this one clock "replaces the four uncoordinated clocks that used to drift (the 2D `GIFCanvas` `Timer`, the status-line `TimelineView`, and the cloud / voxel 60 Hz publishers)" (`PlaybackClock.swift:4-9`).

**`frame` is the single "now".** It feeds the 2D image, the 3D cube front face, the status line, and every palette analyzer (`PlaybackClock.swift:29-32`). The 2D/3D agreement is *proven*: `frontFaceFrame` (z = N−1) equals `twoDFrame` for every cursor, asserted in `SixFourPlaybackClock.selfCheck()` (`PlaybackClockContract.swift:35-37, 45-49, 62-66`).

**Expensive work is gated off the 20 fps tick.** `settledFrame` updates only on pause/scrub (`PlaybackClock.swift:38-41, 94`), so median-cut rebuilders never run 20×/sec. This is a *performance gate, not a second clock*.

**Form follows function.** 64 frames / 20 fps = 3.2 s loop; the burst is captured at the same 20 fps (`CaptureViewModel.swift:197`); the encoder writes at the same 20 (`CaptureViewModel.swift:385`); the ring's 64 ticks (one lit per frame) visualise the 20 fps rate directly. The GIF pixel dimension (64) becomes 384 pt at 6 pt/pixel — byte-and-size identical to the GIF handoff (`Theme.swift:38`).

**Reduce Motion.** `start()` is a no-op when `reduceMotion` is set; the cursor pins to frame 0 and only discrete `scrub` may move it (`PlaybackClock.swift:25-27, 59-66, 86-92`).

---

## §4 — HOW palettes are shown (honest projection)

The Review screen orchestrates three modes plus drill tools, all reading the *same* `clock.frame` (`SixFour/UI/Screens/Review/GIFReviewView.swift:84-155`). Data: `o.palettesForDisplay` (64×256 sRGB8), `o.perFrameCells` (population, cloud only), `settledPalette` (single frame, for tree rebuilds).

- **Grid (2D → 16×16):** pure sort — sort 256 by `(xAxis.scalar, index)`, chunk 16, sort each chunk by `(yAxis.scalar, index)`, transpose; y-up flip (row 0 at bottom) (`SixFour/Palette/GridLayout.swift:56-95`; `PixelGrid.swift:79`). Cell size *follows* count and viewport: `cell_pt = viewport/16`, aspect 1:1 forced (`PixelGrid pixelFrame():120`). Picking the same dimension for X and Y swaps them so the grid never collapses to 1D (`GridAxisSelector.assign:139-147`). Brushing darkens by an opaque step, never alpha (GRID Law #2, `PaletteGridView.swift:37-41`).
- **Treemap:** `SplitTree` via median-cut in OKLab; leaf→fillCell, branch→subdivide + recurse + opaque inset border (`PaletteTreeView.swift:48-70`). Frame passed live from `clock.frame` (`GIFReviewView.swift:116`).
- **Cloud (OKLab 3D → 2D):** `oklabToWorld` L→y, a→x, b→z, scale 2; rotate by `(yaw, pitch)` then orthographic (distance-true) or perspective (labelled lossy). Dot radius = `2.0 + 5.0·√(pop/maxPop)` — an **area-true √-law** so dot *area* reads population (`PaletteCloudView.swift:142-159, 396-399`). Plane picker snaps orbit to golden `(yaw, pitch)`; the projection IS the control. Trails read `(frame−n) mod count`, temporally coherent with the playhead, not a separate animation (`PaletteCloudView`; clock-sourced).
- **Address picker (radix):** wheel count = `branching.depth` (2⁸→8 wheels, 4⁴→4, 16²→2); each digit → binary path → walk `SplitTree` → read live `(SplitAxis, pos)` labels (`AddressPickerView.swift`). Path length *follows* tree structure, not configurable.
- **Quad4 drill:** 2×2 opponent quadrants (parent ± δ₁ ± δ₂), tap to descend, depth 4 → resolve leaf; opaque fill, inset border (`Quad4DrillView.swift`).

**Honesty is the design principle:** orthographic is sticky-default because distance-true = honest; perspective and AABB-hull modes are *labelled lossy* (`docs/SIXFOUR-HIGHDIM-UIUX.md §2.2`). A brushed index `@Binding` cross-links all views (instant highlight, not clock-tied).

---

## §5 — Form-follows-function derivations

1. **`gifPx = 6` ⟸ "display 64 pixels wide, fit portrait, no resample."** Max integer pitch with `64·gifPx ≤ 402` and integer device-px (`LatticeContract.swift:70-71`; `Spec.Lattice lawAtomIsGifPx`). Not aesthetic.
2. **67×145 lattice ⟸ the atom tiles the width exactly.** `402/6 = 67`; `874/6 → 145 + 4 pt bleed` (`LatticeContract.swift:29-31, 72-74`).
3. **Golden preview placement ⟸ hero-is-anchor.** 31 above : 64 : 50 below, `50/31 ≈ φ` (`LatticeContract.swift:55-60, 81`).
4. **Shutter = 12 ⟸ closure law.** `disc(5)·2 + ring(1)·2 = 12` (`LatticeContract.swift:75`). A constraint, not a size.
5. **Touch floor = 8 (48 pt) ⟸ HIG 44 pt rounded up to atoms.** `ceil(44/6)·6 = 48` (`LatticeContract.swift:77-78`).
6. **20 fps ⟸ the GIF is 20 fps and the burst is 20 fps.** One definition (`Theme.swift:28`) cascades to clock, encoder, and capture (`CaptureViewModel.swift:197, 385`).
7. **Grid/cloud projections ⟸ the data's own geometry.** OKLab is 3-space, so 3D→2D orthographic + scrub the time axis; no embedding (`PaletteCloudView.swift:142-159`).
8. **VoxelCube rest pose ⟸ 1:1 honesty.** yaw=0/pitch=0 renders the GIF as a flat front face, 1 GIF pixel = 1 `gifPx` = 1 voxel at z=63; orbited, z extrudes as frame-time, dimetric 2:1 (the canonical 8-bit angle) (`VoxelCubeView.swift:203-268`; `docs/SIXFOUR-VOXEL-CUBE.md RULE-CUBE-ISO`).

---

## §6 — Open questions + gaps (where the maps flag drift/contradictions)

**Clock-law violations / motion sources beyond the one clock.** *(RESOLVED in principle 2026-06-05 — ADR-1 in `SIXFOUR-UIUX-ARCHITECTURE-DECISIONS.md`: harden to one `CADisplayLink` @ 20 fps; the cube's orientation quantizes to that tick. Implementation pending — the items below describe the current pre-ADR code.)*
- **VoxelCube 60 Hz auto-rotate is a second motion source.** `rotateClock = Timer.publish(every: 1.0/displayHz …)` (`VoxelCubeView.swift:232`) drives orientation only; the *frame* cursor is correctly the shared `PlaybackClock`. → ADR-1 collapses this onto the one 20 fps tick (resolves the Law #4 violation by quantizing down, not by adopting 60 Hz).
- **`MTKView.preferredFramesPerSecond = 60`** (`VoxelCubeView.swift:468`) is a GPU presentation cadence above the 20 fps conceptual clock — under-explained in `docs/archive/SIXFOUR-VOXEL-CUBE.md`. → ADR-1: drop to the 20 fps tick.
- **Residual-drift evidence.** `PaletteCloudView.swift:203` comment "60 Hz `Timer` was removed" confirms a removed second clock; verify no remnants linger.
- **No `GATE-PERF` lint** to catch an analyzer accidentally rebuilding on the 20 fps tick (`settledFrame` is convention, not enforced) — `[PLANNED]` per `docs/SIXFOUR-DESIGN-LANGUAGE.md §4`.

**Enforcement machinery not yet built (`[PLANNED]`).**
- The `setCell(col:row:srgb8:)` Pass-A static-chrome byte writer is `[PLANNED]`; HUD chrome (wordmark, count, sampler) is not yet migrated to the bake; shutter/ring/ticks remain dynamic overlays (grid + buttons maps; `docs/…DESIGN-LANGUAGE.md §4-§5`).
- **CellFont 1-bit masters not generated** — glyphs go through `CellText` (rasterise system text), so the app still uses SwiftUI text rendering (grid map; `…DESIGN-LANGUAGE.md §5`).
- **Busy-arc spinner not wired.** GRID §6.6 prescribes a "3-cell rotating arc on the 20 fps clock"; today only the colour swaps (white↔red). The *one place the button would legitimately couple to 20 fps* is not built (buttons map).
- **`pressed` state missing.** No `@GestureState`/`isPressed`; the spec'd "invert the hit-block" is unrendered — only the async downstream phase change is visible (buttons map).
- **No `LINT-DRAW-VOCAB`** build check forbidding raw `Circle/Rectangle/Text/glass` on the HUD; ring luminance-flipped outline `[PLANNED]` (buttons map).

**Naming / structural drift (value correct, name stale).**
- **Dual-pitch naming persists in `Theme.swift`.** GRID v2.0 retires the separate "Review pitch", yet `SFTheme` still carries `gifCellPt`/`gifCanvasPt` and comments them "EXEMPT-REVIEW-PITCH; the two pitches never share a screen" (`Theme.swift:34, 38, 52`). The value is right (`gifCellPt = reviewPitchPt = 6`, `:34`), but the framing contradicts the one-atom amendment.
- **Live glass tokens still defined** for chrome accents (`Theme.swift:83-96`, `glassIconButtonSize`, `glassClusterSpacing`, `hairline = .opacity(0.18)`) — opacity values that GRID Law #2 forbids on data cells; remnant of the pre-GRID glass layer. (Note: `CLAUDE.md` permits Apple system frameworks, so glass is not a dependency violation — only a design-language one if applied to cells.)
- **Safe-area shift partially wired.** `safeTopPt`/`safeBottomPt` *are* emitted and used in `selfCheck()` clearance asserts (`LatticeContract.swift:34-35, 86`), but the runtime *whole-cell band shift* the doc describes is not applied by `GlobalLattice` (grid map §Gaps; partially corrects the "unused" claim — they are referenced, just not used to *shift*).
- **Golden split is approximate.** `selfCheck()` checks `aboveRows < belowRows` (`:81`), not an exact φ; `50/31 ≈ 1.6129 ≠ φ`. The grid map's note of a tolerance check is consistent with this.

**Palette honesty gaps.**
- Cloud projection constants (scale 2.0, eye 2.2, radius 2–7 pt) are **not** spec-generated from `Spec.CloudProjection`; no `Codegen.CloudProjection` emitter or parity test (palette map §Gaps).
- Subtree AABB-hull rendering is documented "tagged LOSSY when 4-ary" but **not drawn** (math exists, not shipped) (palette map §Gaps).
- Address-picker tree-structure sensitivity: a live scrub can shift a settled address's leaf index on re-pause; honest in code but no UI affordance warns the user (palette map §Gaps).
- Reduce-Motion collapses cloud trails to a static streak at frame 0 — a conceded hard loss of the temporal signal for accessibility users (palette + dimension-clock maps).

**Async lifecycle.**
- `PlaybackClock` starts on appear before frames may have loaded (`GIFPlayer.swift:38`); Reduce-Motion correctness depends on the `@Environment` binding staying live (`GIFPlayer.swift:36`); scrub-rail rounding unspecified (`PlayerTransport.swift:117-121`) (gif map §Gaps).
