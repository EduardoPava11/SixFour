# SixFour UI/UX Design Language — "GRID"

**Status:** Canonical constitution (v1.0, 2026-05-31). Authoritative for every screen.
**Scope:** the capture HUD + the Review/palette content cells. Named exemptions in §9.7.
**Maturity flag (read this first):** the *numbers* in this document are locked and enforceable; the *enforcement machinery* (`Spec.Lattice`/`Spec.CellShapes`/`Spec.CellFont`, the `setCell` primitive, the single-pitch lint) is **specified here but not yet built**. Every place this matters is marked **[PLANNED]**. The single-pitch law is currently DESIGN-true and CODE-false — `SFTheme` still ships a second (6 pt) pitch on the capture path. §9.8 is the migration debt that closes that gap. Do not read any "is golden-pinned" sentence as "already passes a test today" unless it lacks the [PLANNED] tag.

---

## 0. Overview & The Cardinal Law

**SixFour is an 8-bit graphics engine wearing a camera.** A 64-frame burst becomes a 64×64×256 animated GIF, and that cube is not the app's *content* — it is the app's *law*:

> **The 64×64 GIF is not the UI's content, it is the UI's LAW.**

Every screen, control, and glyph is built from the same unit the GIF is built from: one square cell, flat indexed colour, on one 20 fps clock. The interface is *generated from* the cube, not decorated around it.

- **Target device anchor:** iPhone 17 Pro — 402 × 874 pt @3x = 1206 × 2622 px. All geometry is pinned to this anchor and shifted at runtime only for safe-area insets.
- **Contract (CLAUDE.md):** Tier-2 ships **ZERO third-party dependencies** (Apple frameworks + `simd` only). SwiftUI + Metal, hand-written. The Haskell spec + golden vectors are the source of truth (not Figma). Glass is chrome *material*, **retired on the capture HUD**, retained for Review/Settings.
- **Supersedes / organizes:** `docs/cell-lattice-widget-spec.md` (promoted to spine), `docs/cube-generated-uiux-system.md`, `docs/grid-is-the-render-surface.md`, `docs/palette-explorer-2d-3d-4d-design.md`, `~/.claude/plans/misty-greeting-panda.md`. See §10.1 for each disposition.

### The Cardinal Laws (numbered, non-negotiable)

1. **ONE CELL SIZE EVERYWHERE.** The cell = **2 pt = 6 device-px @3x**, identical for every element on every governed surface. Widgets get bigger by using **MORE cells**, NEVER by enlarging the cell. **No element has its own pitch.** The 64×64 preview's cell is the *exact same physical size* as a cell in the shutter, the ring, the wordmark, the count, and the field.
2. **THE GRID IS THE RENDER SURFACE.** Cells are flat, un-shaded, indexed colour. No anti-aliasing, no opacity, no corner-rounding on a data cell. Opacity *is* shading and is therefore forbidden on a cell. Any tint/shimmer blend is expressed as adjacent **opaque palette indices** (index dither), never alpha.
3. **ONE PITCH PER SURFACE.** A surface uses exactly one pitch: capture HUD = 2 pt; Review/palette = the 6 pt family. The two pitches **never share a screen**.
4. **ONE CLOCK.** Exactly one motion source, `frameIndex(at:rate:20,count:64)`. Only the preview and the live ring/count consume it. Everything else is a static bake.
5. **ONE OWNER FOR CELL MATH.** All cell↔point conversion lives in a single `GlobalLattice` value type. No view computes `× cellPt` itself.
6. **EVERY DIMENSION IS A CELL COUNT.** Every governed chrome dimension is an integer number of cells (`dimensionPt % cellPt == 0`). A point value anywhere except the OS safe-area boundary is a contract violation a lint can `grep` for.
7. **VISIBLE == HIT, ≥ 22 CELLS.** Every interactive target is ≥ 22 cells (44 pt) and its hit-rect equals its painted cell-rect. No invisible slugs.
8. **NOTHING SHIPS WITHOUT A GOLDEN.** No governed chrome ships without a passing `cabal test` against a `Spec.*` golden vector. **[PLANNED — see maturity flag.]**

Law #1 is the one that decides every later argument. It is not prose to be remembered; it is a machine-checkable predicate (Law #6) owned by one type (Law #5) and proven by a golden (Law #8).

---

## 1. Principles

Five tenets, **strictly ordered** P1 > P2 > P3 > P4 > P5: when two conflict, the lower number wins.

### P1 — One pitch is a hard invariant, not a guideline.
> The cell = 2 pt = 6 device-px everywhere; widgets scale by using more cells, never by enlarging the cell.

Drift happened because each widget invented its own size math. The cure is to make the single pitch a *default that cannot be violated*: one `GlobalLattice` type owns ALL conversion, and a `Spec.Lattice` golden enumerates every widget's cell-rect and asserts no element declares its own pitch (Carbon/Polaris/Uber keep systems consistent by making consistency the CI default, not by asking authors to remember rules). **[PLANNED: predicate specified in §9.3, gate not yet wired.]**

### P2 — The grid IS the render surface.
> Flat, un-shaded, indexed-colour cells. No AA, no opacity, no rounding on a data cell.

The GIF is intrinsically flat — residual ("shading") is shaped across the temporal (x, y, t) dither axis, never within a frame's cell, and every cell is a population-significant sample of a maximin-OKLab-coverage objective, so there is nothing to shade away. The whole-screen field + static chrome bake into **one** indexed bitmap drawn once as a single `PixelImage` upscaled ×6; only the preview and the live ring/count animate.

### P3 — Camera-responsive identity.
> The background field and chrome tint derive from the live scene palette (`sceneTint`), darkened and clamped so white widgets stay readable.

The app *is* the colours it sees. `sceneTint` is throttled to 4–8 Hz (a static-bake input, not on the 20 fps clock), and the luminance clamp (P5) guarantees the canvas can never visually vanish.

### P4 — Honesty / completeness (Rams §8: "nothing left to chance").
> Every dimension is a token; every token is golden-pinned; every grid-break is documented with a reason.

A widget never hardcodes a raw value — it references a token one tier up, and the build greps for bare `Pt`-suffixed chrome values and fails. Equally honest: the language *scopes itself* (§9.7). Claiming a unification the code cannot deliver is itself a form of drift; the seams are named, not hidden.

### P5 — Accessibility is structural.
> A11y is encoded as golden-tested invariants, not a review checklist.

Every cell text/icon carries a real `accessibilityLabel`; decorative cells are `accessibilityHidden`; a value is spoken by one owner only. A *true* relative-luminance function (linearized sRGB, **not** OKLab L) clamps text ≥ 4.5:1 and non-text ≥ 3:1 over all 256 palette colours, with the chrome outline luminance-flipped. Dynamic Type → integer cell-scale with system `Text` fallback at AX sizes; Reduce Motion freezes field/ring/spinner; touch floor 22 cells (44 pt), visible == hit.

---

## 2. Foundations (the geometry these principles stand on)

These are derived facts, not choices.

### 2.1 The atom: the cell
`cellPt = 2 pt = 6 device-px @3x` (`scale = 3`, `cellPx = 6`). The GIF's fat-pixel pitch and every widget's pitch, identically. Nothing on a governed surface is smaller than one cell or measured in anything but cells.

### 2.2 The global lattice (gcd-derived, unique)
`gcd(402, 874) = 2`. Two points is the **unique** pitch that tiles the iPhone 17 Pro portrait screen edge-to-edge with no remainder. At 2 pt/cell the screen is exactly **201 columns (x 0…200) × 437 rows (y 0…436)** — the global lattice. A 6 pt pitch cannot tile the full screen (`874 / 6 = 145.67`), which is *why* the HUD pitch is 2 pt. The lattice is owned by `GlobalLattice`.

### 2.3 The golden-section vertical layout
The 64-cell preview is the primary **anchor**, LOCKED at **rows 143–206, cols 68–131** (even-start on both axes so its edges fall on field cell boundaries). Of the 373 non-preview rows, the split is **143 above : 64 preview : 230 below**, where `230 / 143 ≈ 1.608 ≈ φ`. The golden split is a *consequence* of the anchor, asserted by `Spec.Lattice` (LAW-GOLDEN), not eyeballed. A full-width 384 pt preview would require a 6 pt pitch the lattice forbids; the 384→128 pt shrink is a **decisions-gate** item (§9.5), not a free parameter.

### 2.4 The Fibonacci size ladder
Widget *sizes* are drawn from `[8, 13, 21, 34, 55, 89]` cells (successive ratios ≈ φ). Pinned floors: interactive ≥ **22 cells** (44 pt); **shutter = 34 cells** (68 pt); **secondary control = 24 cells** (48 pt). **Ladder exemption registry** (counts and HIG/OS constants are *not* sizes and are exempt by definition): `touchFloorCells = 22` (HIG 44 pt floor), `controlCells = 24` (HIG-derived, 8 pt-grid-aligned), `ring.tick.countCells = 64` (a count = `previewCells`), `digit.glyphBoxCells = 10×18`, `title.glyph.advanceCells` (glyph metrics). Anything off-ladder that is *not* in this registry requires a new documented exemption.

### 2.5 Runtime safe-area band shift
Bands are authored against the nominal 437-row field and shifted at runtime by whole cells: `safeTopRows = ceil(insets.top / cellPt)`, `safeBottomRows = floor(insets.bottom / cellPt)`, owned by `GlobalLattice`. Dynamic Island ≈ 31 rows (top), home indicator ≈ 17 rows (bottom) — field-only; no interactive cell in a corner.

### 2.6 Colour, `sceneTint`, and the luminance model
Field and chrome tint derive from `sceneTint` (the quantized live-scene palette), darkened and clamped. Contrast uses linearized-sRGB relative luminance `Y = 0.2126·R_lin + 0.7152·G_lin + 0.0722·B_lin` (**NOT** OKLab L). The brightest *allowed* `sceneTint` is the worst case and the chrome outline is luminance-flipped against it. Anchors: `ledGhost = (40,40,40)` opaque (the only off-segment fill, never `white.opacity`); `Color(srgb8:)` is the one sRGB8→Color conversion (explicit `.sRGB`).

---

## 3. Design Tokens

Tokens are the single source shared by design and code (Material 3). **[PLANNED]** the Haskell `Spec.Lattice` *will* emit the reference + system tiers as a golden vector and `SFTheme` *will* become the verified Swift mirror; **until `Spec.Lattice` ships, `SFTheme` is the interim authority and the golden gate is a tracked TODO** (§9.8). Change the reference cell once → the whole UI cascades.

### 3.1 The tiering model & naming taxonomy
Three tiers (Material 3 / Carbon / Polaris): **reference → system/semantic → component**.

| Tier | Holds | Rule |
|---|---|---|
| **0 Reference** | raw lattice + palette primitives, HIG/OS constants | the ONLY tier that may name a literal; everything in **cells** or the one **pitch** |
| **1 System/semantic** | role tokens (`shutterCells`, `accent`) | references a tier-0 token (or a registered HIG/OS constant), documented as such; **never** a bare literal |
| **2 Component** | per-widget tokens (`shutter.idle.disc.radiusCells`) | references a tier-1 token; **never** a literal |

**Naming:** `category.role.variant-state.property`, **units in the name** — `…Cells` (integer cell count), `…Srgb8` (`SIMD3<UInt8>` palette colour), `…Pt` (**permitted ONLY at the OS safe-area boundary**). A `…Pt`-suffixed token anywhere in chrome geometry fails the naming lint (Tetrisly Context+Common-unit+Clarification formula).

> **Tier-0 carve-out for HIG/OS constants:** `touchFloorCells = 22` and `controlCells = 24` are not lattice-derived — they are the 44 pt HIG floor and the 48 pt comfortable target expressed in cells. They are reference-tier constants tagged `(HIG)`, satisfying the "no literal above tier-0" rule.

### 3.2 The full token table

#### TIER 0 — Reference
| Token | Value | Unit | Meaning |
|---|---|---|---|
| `cellPt` | 2 | pt | the one pitch (6 device-px @3x) |
| `scale` | 3 | — | pt → device-px |
| `lattice.colsCells` | 201 | cells | full-screen width |
| `lattice.rowsCells` | 437 | cells | full-screen height |
| `fib.ladderCells` | [8,13,21,34,55,89] | cells | the φ size scale |
| `previewCells` | 64 | cells | cube law (1 cell = 1 GIF px) |
| `touchFloorCells` | 22 | cells (HIG) | 44 pt minimum hit |
| `controlCells` | 24 | cells (HIG) | 48 pt secondary control |
| `palette.tableSrgb8` | 256× SIMD3<UInt8> | srgb8 | the colour table |
| `ledGhost.fillSrgb8` | (40,40,40) | srgb8 | opaque unlit cell |
| `motion.rateFps` | 20 | fps | the one clock |

#### TIER 1 — System / semantic
| Token | Value | Unit | References |
|---|---|---|---|
| `shutterCells` | 34 | cells | `fib` (68 pt) |
| `gutterCells` | 1 | cell | `cellPt` (Swiss gutter) |
| `safeArea.top.insetPt` | runtime | pt | OS (→ `safeTopRows`) |
| `safeArea.bottom.insetPt` | runtime | pt | OS (→ `safeBottomRows`) |
| `ink.fillSrgb8` | white, clamped | srgb8 | contrast clamp |
| `paper.fillSrgb8` | near-black | srgb8 | chrome ground |
| `ground.fillSrgb8` | `darken(sceneTint, Y≤Y_groundMax)` | srgb8 | `sceneTint`, `Y_groundMax` |
| `accent.fillSrgb8` | `clamp(sceneTint, ≥3:1)` | srgb8 | `sceneTint`, luminance clamp |

#### TIER 2 — Component (examples; full set in §6)
| Token | Value | Unit | References |
|---|---|---|---|
| `shutter.idle.disc.radiusCells` | 15 | cells | `shutterCells` |
| `shutter.idle.ring.thicknessCells` | 2 | cells | `shutterCells` |
| `ring.axis.diameterCells` | 60 | cells | `previewCells` |
| `ring.tick.countCells` | 64 | — | `previewCells` |
| `ring.tick.lengthCells` | 3 | cells | `ring.axis` |
| `digit.glyphBoxCells` | 10×18 | cells | (glyph metric) |
| `title.glyph.boxCells` | 16×20 | cells | (glyph metric) |
| `gear.idle.boxCells` | 24 | cells | `controlCells` |

### 3.3 Closure laws (golden-checked) **[PLANNED]**
- **Shutter closure:** `disc.radiusCells·2 + ring.thicknessCells·2 == shutterCells` → `15·2 + 2·2 = 34` ✓. (Disc Ø 30 + 2-cell ring band each side = 34; the old shipped 72 pt/36-cell box is **retired**, see §3.5. The spec picks **34 cells = 68 pt** — the ladder value — and the 72→68 pt shrink passes the decisions-gate.)
- **Ring/axis concentric:** ring center == shutter center == **col 99.5 / row 269.5** (the geometric center of the 34×34 block at cols 83–116, rows 253–286; the 2-cell center pair is cols 99–100 / rows 269–270). The ring axis Ø 60 is concentric on this exact center; the clear annulus is symmetric.

### 3.4 The camera-tint derivation + contrast clamp
The field/chrome derive from `sceneTint` but a token must keep white widgets readable. The clamp uses the true relative-luminance `Y` of §2.6, golden-proven over all 256 palette colours:
```
ground.fillSrgb8 = darken(sceneTint) per-channel until Y(ground) ≤ Y_groundMax   // text pair ≥ 4.5:1
accent.fillSrgb8 = clamp(sceneTint)  until boundary pair ≥ 3:1                    // non-text
```
`Y_groundMax` is the exact constant such that white-on-ground holds ≥ 4.5:1; the `darken` operator is **per-channel linear scale**, golden-pinned. The brightest allowed `sceneTint` is the worst case; chrome ink is **luminance-flipped** → the canvas can never visually vanish. `sceneTint` re-bake throttled to 4–8 Hz. Increase-Contrast / Reduce-Transparency degrade `ground` to solid black + chrome to solid ink. (The shipped `SFTheme.accent(towardWhite:)` blend is refactored to emit an opaque, luminance-clamped `srgb8` — its current lifted-white feel is removed.)

### 3.5 RETIRED off-lattice tokens (explicit)
These shipped `SFTheme` tokens carry a **second pitch** (the 6 pt `gifCellPt` chrome family) or **opacity-on-a-cell**, both of which violate Law #1/#2 on the capture HUD. **Retired from chrome geometry**, re-derived from the tiered cells above:

`shutterSidePt=72` (was `gifCellPt*12` = 36 cells → re-land at **34 cells/68 pt**) · `shutterInnerPt=60` · `controlSidePt=48`/`glassIconButtonSize=48` (→ `controlCells=24`) · `controlGutter=12` (→ `2·cellPt`) · `decorGutter=6` (→ `1·cellPt`) · `glassClusterSpacing=12` · `diversityRingDiameter=84` (→ `ring.axis.diameterCells=60`) · `diversityTickLength=6`/`diversityTickWidth=2` (→ `ring.tick.lengthCells=3`/`widthCells=1`) · `groundWashOpacity=0.32` · `mutedFill=.06`/`hairline=.18`/`mutedText=.85`/`dimText=.6` (opacity tokens) · the literal corners `84/70/60/49/40/14/10/7/4`.

> **Scoped exemption (named, not hidden):** `gifCellPt=6`, `gifCanvasPt=384`, `paletteCellPt=24`, `canvasEdge(forAvailable:cells:)` are **retained for the Review/palette screens only** (one palette cell = a 4×4 block of GIF cells). They are out of scope for the capture HUD's single-pitch law (EXEMPT-REVIEW-PITCH, §9.7). Glass material is likewise retained for Review/Settings, retired on the capture HUD.

### 3.6 Single source of truth **[PLANNED]**
The reference + system tiers **will be** emitted and golden-pinned by `Spec.Lattice`; `SFTheme` **will become** the verified Swift mirror, not an independent authority. `cabal test` gates every change once the module exists. Until then, this is tracked debt (§9.8), not a present fact.

---

## 4. Render Model

The one drawing law (P2), made concrete.

- **Two passes.** **Pass A (static bake):** the whole-screen field + ALL static chrome (wordmark, gear idle, shutter idle disc+ring, diamond, count digits + `ledGhost`, label, sampler, ring axis + inactive ticks) bake into **one** indexed `CGContext` bitmap (201 × 437), drawn once as a single `PixelImage` upscaled ×6 → 402 × 874 pt. **Pass B (animated):** only the preview and the live ring lit-band / busy arc redraw on the single clock `frameIndex(at:rate:20,count:64)`. The count text is **not** on the clock — it re-bakes on value change only.
- **Re-bake triggers (Pass A):** `occupiedBins` delta, sampler toggle, press/disabled/settings-open, or a `sceneTint` change throttled to **4–8 Hz**. Never per 20 fps frame.
- **Write primitives.**
  - `setCell(col:row:srgb8:)` — **[PLANNED — NOT YET BUILT]** a `CGContext` byte writer into the Pass-A indexed buffer; the *only* way HUD cells are written. Distinct from `fillCell`. `CellField` must be extended to accept a static-chrome cell list and bake it via `setCell`.
  - `fillCell(_:srgb8:)` — **shipped** (`PixelGrid.swift`, a `GraphicsContext` extension). It is the **Review-screen palette + treemap** flat-fill (≤ 256 cells / non-uniform treemap leaves). It is **contractually forbidden on the 201×437 capture field** (LINT-FILLCELL-SCOPE). HUD Canvas `fillCell` only becomes a violation once `setCell` exists; until then the migration note in §9.8 governs.
  - `Color(srgb8:)` — the one sRGB8→Color conversion. `PixelImage` (`.interpolation(.none)`, exact `.frame`, never `.scaledToFit`) is the one nearest-neighbour upscaler.
- **Performance budget.** ~88k px built once per bake (NOT 88k Canvas fills). A press composites as a tiny Pass-B overlay, never a full field re-bake. **[PLANNED gate]** a perf assertion in GATE-LAYOUT-GOLDEN measures Pass-A re-bake cost on device and fails if a re-bake would force a preview frame drop.

---

## 5. Primitives (the closed drawing vocabulary)

A governed widget is built ONLY from these. Introducing a raw `Circle()`/`Rectangle().stroke`/`RoundedRectangle`/`Text`/glass/opacity/glow/rounding on the capture HUD is a contract violation (LINT-DRAW-VOCAB).

| Primitive | Status | Purpose | Consumes tier | Golden |
|---|---|---|---|---|
| `GlobalLattice` | **build** | sole owner of all cell↔pt math, band map, safe-area shift | 0/1 | `Spec.Lattice` [PLANNED] |
| `PixelImage` | **shipped** | nearest-neighbour CGImage ×6 upscale; preview + field renderer | — | existing GIF goldens |
| `Color(srgb8:)` | **shipped** | the one sRGB8→Color conversion | 0 | — |
| `fillCell` | **shipped** | Review-only flat fill (palette + treemap, ≤256 / non-uniform) | 0 | — |
| `setCell` | **[PLANNED]** | `CGContext` byte writer for the Pass-A bake buffer | 0 | `Spec.Lattice` [PLANNED] |
| `CellField` | **shipped (extend)** | the 201×437 Bayer-tiled background; must gain a static-chrome cell-list bake | 1 | `Spec.Lattice` [PLANNED] |
| `CellShapes` | **build** | midpoint circle/disc/ring/tick/line masks + the 64-tick endpoint table | 2 | `Spec.CellShapes` [PLANNED] |
| `CellGlyph`/`CellFont` | **build** | hand-authored 1-bit master glyphs (wordmark 16×20, Cozette 6×13, 7-seg 10×18) | 2 | `Spec.CellFont` [PLANNED] |
| `CellIcon` | **build** | pixel iconography (gear, diamond) via the `PixelImage` path | 2 | `Spec.CellShapes` [PLANNED] |
| `CellRing` | **build** | 64-tick diversity gauge (split clock) | 2 | `Spec.CellShapes` [PLANNED] |
| `CellButton` | **build** | the one interactive primitive (shutter; base of every control) | 1/2 | `Spec.CellShapes` + `Spec.Lattice` [PLANNED] |
| `CellSelector` | **build** | a row of `CellButton`s (Settings) | 1/2 | `Spec.Lattice` [PLANNED] |
| `CellText` | **shipped** | **AX-fallback only** — rasterize-and-snap monospaced system text at ≥ `.accessibility1` and on sampler overflow; NOT a primary glyph path | — | (none; pins the registers it falls back for) |

Adding a primitive is itself a GATE-DECISIONS proposal (§9.5), never done ad hoc inside a widget.

---

## 6. Components

> **Reading order is fixed.** Every component uses the same seven-section template — **Anatomy → Sizing → States → Behavior → Do/Don't → Accessibility → Code API** (Carbon's highest-leverage artifact). A new widget that omits a section is not done. The cardinal law applies to every entry: a widget grows by using **more cells**, never by enlarging the cell; a `Code API` may take a cell **count**, never a cell **size** in points.
>
> **States are expressed ONLY as cell transforms:** idle (base) · pressed (invert the hit-block) · selected (1-cell accent border one cell *outside* the block) · disabled (50% 2×2 checker over the block) · busy (animated rim/arc on the 20 fps clock). NO opacity, NO glow, NO glass, NO blur, NO rounding as a state affordance.

### 6.0 The component index

| Component | Class | Cell footprint | Grid rect (cols × rows) | Clock | Hit ≥ 22 |
|---|---|---|---|---|---|
| **Preview** | hero (`PixelImage`) | 64 × 64 | 68–131 × 143–206 | Pass B (20 fps) | n/a |
| **Wordmark "SixFour"** | glyph (`CellGlyph`) | 124 × 20 | 68–191 × 96–115 | Pass A | n/a |
| **Gear / Settings** | control (`CellButton`+`CellIcon`) | 24 × 24 | 173–196 × 96–119 | Pass A | ✓ 24 |
| **Shutter** | control (`CellButton`) | 34 × 34 | 83–116 × 253–286 | A idle / **B busy** | ✓ 34 |
| **Diversity Ring** | instrument (`CellRing`) | Ø 60 (R 30) | center 99.5 / 269.5 | A axis / **B lit-band** | n/a (value on shutter) |
| **CountReadout** (◇ + digits + " colors") | glyph composite | left-anchored run | 70–143 × 306–323 | Pass A (re-bake on Δ) | n/a |
| **SamplerTag** | glyph (`CellGlyph`) | ≤ 162 × 13 | center col 100 × 327–340 | Pass A (re-bake on toggle) | n/a |
| **Background Field** | surface (`CellField`) | 201 × 437 | 0–200 × 0–436 | Pass A (re-bake ≤ 8 Hz) | n/a |
| **CellSelector** | composite (Settings) | band grows; segments ≥ 22 | (Settings screen) | Pass A | ✓ per-segment 22 |

---

### 6.1 Preview — the hero (`PixelImage`)

**Anatomy** — a single 64×64 block of GIF cells at the locked rect **cols 68–131 × rows 143–206**, at the golden section (143:64:230, 230/143 ≈ φ). Even-start; the field is its border. No frame, no rounding, no inset.

**Sizing** — `previewCells = 64` → 128 pt square. The *only* legal size at the 2 pt pitch. "Bigger" only via the decisions-gate (the 384 pt full-width hero is a *different surface*, §6.10/§7.2), never by changing the pitch.

**States** — live (animating) · frozen (single frame; Reduce Motion / paused) · empty (black cells, never a spinner overlay). Non-interactive.

**Behavior** — its own `PixelImage` on Pass B, advanced by `frameIndex(at:rate:20,count:64)`. Nearest-neighbour, integer-edge. Reduce Motion → holds frame 0.

**Do / Don't**
| ✅ DO | ❌ DON'T |
|---|---|
| Keep 64 cells at 2 pt | Scale to 192 pt by making its cell 3 pt |
| Let the field be the border | Add a rounded frame / drop-shadow |
| Hold frame 0 under Reduce Motion | Cross-fade frames |

**Accessibility** — `accessibilityLabel("Live 64-colour preview")`; cells hidden; non-interactive. **Scope seam:** preview cells are coloured by the scene/GIF, not by `sceneTint` (EXEMPT-PREVIEW-CELLS).

**Code API**
```swift
PixelImage(image: gifFrame, edge: lattice.points(cells: 64))   // 128 pt; cell count, never a pt size
```
Golden: `Spec.Lattice` pins the rect (68–131 × 143–206) + integer pitch; GIF bytes pinned by existing GIF goldens. **[PLANNED]**

---

### 6.2 Background Field — `CellField`

**Anatomy** — the whole screen, 201 × 437, every non-widget cell a darkened, camera-responsive shade of `sceneTint` with a 4×4 Bayer two-shade texture (expressed as adjacent **opaque** indices — index dither, never alpha) so the lattice reads as tiled. All static chrome is composited into this same buffer via `setCell` — the field *is* the Pass-A bitmap.

**Sizing** — fixed 201 × 437 (the unique gcd-derived pitch). Runtime band shift by `safeTopRows`/`safeBottomRows`.

**States** — idle (tinted Bayer field) · increase-contrast/reduce-transparency (degrade to solid black + solid chrome) · reduce-motion (single frozen Bayer phase). No interactive states.

**Behavior** — Pass A only. Re-bakes on a state change or a `sceneTint` change throttled to 4–8 Hz. One `PixelImage(.interpolation(.none))` ×6. **Never** `fillCell` on this surface.

**Do / Don't**
| ✅ DO | ❌ DON'T |
|---|---|
| Bake field + static chrome into one bitmap, draw once | Per-cell `Canvas`/`fillCell` on the big surface |
| Throttle `sceneTint` re-bake to 4–8 Hz | Re-bake every 20 fps frame |
| Composite press/disabled as a tiny Pass-B overlay | Re-bake the whole 88k-px field on a press |
| Use opaque darkened tint (index dither) | `white.opacity()` washes (P2 violation) |

**Accessibility** — `accessibilityHidden(true)`. **Contrast invariant (hard):** field max-luminance = brightest allowed `sceneTint` post-clamp; white chrome + ring/border hold ≥ 3:1 (WCAG 1.4.11) with a luminance-flipped outline — the canvas can never visually vanish.

**Code API**
```swift
CellField.image(tint: sceneTint, chrome: staticChromeCells)   // 201×437 indexed CGImage; chrome via setCell [PLANNED]
CellFieldView(tint: sceneTint)                                // one PixelImage ×6, ignoresSafeArea, a11y-hidden
```
Golden: `Spec.Lattice` pins lattice dims, band map, contrast clamp over the 256-colour table. **[PLANNED]**

---

### 6.3 CellGlyph / CellFont — the hand-authored master glyph path

**Anatomy** — `CellGlyph` renders a hand-authored 1-bit master (bit-packed) into a tiny indexed CGImage, ×6 `.interpolation(.none)` — the identical path as `PixelImage`. `CellFont` is the master table: three registers — the **16×20 "SixFour" wordmark** (7 glyphs: S, i, x, F, o, u, r), the **6×13 Cozette-metric alphabet**, the **10×18 7-segment digit** (0–9).

**Sizing** — register boxes (integer multiples, AA off): TITLE 16×20 box; LABEL 6×13; DIGIT 10×18. Cap/x-height/ascender/descender land on real cell bands. (Wordmark advance per §6.9: 7 × 16-cell box + 6 × 2-cell gaps = 124 cells.)

**States** — single ink for mono glyphs; the 7-seg digit is the one two-ink glyph (lit = white, unlit = opaque `ledGhost` so a digit never reflows). No interactive states.

**Behavior** — Pass A. Re-bakes only when the underlying string changes.

**Do / Don't**
| ✅ DO | ❌ DON'T |
|---|---|
| Author 7-seg as a two-ink master | "Simplify" digits onto single-ink `CellText` (ghost vanishes, reflows) |
| Use 6×13 Cozette for descender labels | Snap labels from system mono (stems drop at 6×13) |
| Pin every register byte-exact | Hand-edit a master without regenerating goldens |

**Accessibility** — `accessibilityHidden(true)`; the real string lives on the container.

**Code API**
```swift
CellGlyph(register: .wordmark, text: "SixFour", ink: .white)
CellGlyph(register: .sevenSeg, digits: occupiedBins, lit: .white, ghost: Color(srgb8: SFTheme.ledGhost))
CellGlyph(register: .label,    text: " colors", ink: .white)
```
Golden: `Spec.CellFont` pins all three master tables byte-exact. **[PLANNED]**

---

### 6.4 CellIcon — pixel iconography (Gear, Diamond)

**Anatomy** — a cell mask in a `box × box` rect via the `PixelImage` path. Gear: midpoint-circle hub r≈5, eight 2×2 teeth on r≈10 at 45°, 3×3 inverted hole, stroke 2. Diamond ◇: 4 midpoint-line edges, 2-cell stroke, 2×2 center.

**Sizing** — Gear = `controlCells = 24` (48 pt). Diamond = 12 (decorative). Even dims → 2-cell geometric center.

**States** — Gear (interactive, inside a `CellButton`): idle / pressed (invert) / selected (1-cell accent border when the sheet is open) / disabled (2×2 checker). Diamond: ink only.

**Behavior** — Pass A. No animation.

**Do / Don't**
| ✅ DO | ❌ DON'T |
|---|---|
| Grow the gear 24 → 34 cells if needed | Scale the gear's cell to 3 pt |
| Keep 1-cell gaps between teeth | Use `Circle().stroke` (AA fringe, off-vocabulary) |
| 2-cell center on even boxes | Center on a single cell (asymmetric) |

**Accessibility** — `accessibilityHidden(true)`; label on the enclosing `CellButton` (Gear → "Settings") or container (Diamond → part of the count's combined label).

**Code API**
```swift
CellIcon(mask: CellShapes.gear(box: 24), boxCols: 24, boxRows: 24, ink: .white)
CellIcon(mask: CellShapes.diamond(box: 12), boxCols: 12, boxRows: 12, ink: .white)
```
Golden: `Spec.CellShapes` pins the masks byte-exact. **[PLANNED]**

---

### 6.5 CellRing — the diversity instrument

**Anatomy** — a 1-cell midpoint **axis circle** at center **col 99.5 / row 269.5, R = 30** (concentric with the shutter, §3.3), plus **64 radial ticks** at θ = 2πk/64 (k = 0 top, clockwise). Active ticks (k < ⌊coverage·64⌋) = 3-cell stub in `accent`; inactive = 1-cell dim outer stub. Spacing ≈ 2.9 cells → ≥ 1 clear cell, no merge.

**Sizing** — R 30 → Ø 60 cells (120 pt). The 64 tick endpoints are a **precomputed golden table** (θ→cell is the single float step, pinned so rounding cannot drift per-widget).

**States** — idle (axis + inactive ticks, static) · live (lit band grows) · reduce-motion (snap to value). No interactive states (instrument).

**Behavior** — split clock: axis + inactive ticks bake into Pass A; only the lit-tick band (≈ 64 cells) re-evaluates on Pass B. Reduce Motion freezes the band transition.

**Do / Don't**
| ✅ DO | ❌ DON'T |
|---|---|
| Bake axis + inactive ticks once | Redraw all 60+ cells every frame |
| Use the precomputed golden tick table | Recompute θ→cell live (draw/golden drift) |
| Speak coverage once, on the shutter | Expose 64 AX nodes (double-speak) |

**Accessibility** — the 64 tick cells are `accessibilityHidden(true)` — not 64 AX nodes. Coverage is spoken once as the shutter's `accessibilityValue`. Luminance-flipped outline keeps the ring ≥ 3:1.

**Code API**
```swift
CellRing(ticks: 64, lit: Int((coverage * 64).rounded()),
         center: lattice.point(col: 99.5, row: 269.5), radiusCells: 30,
         activeTint: SFTheme.accent(sceneTint), inactiveInk: Color(srgb8: SFTheme.ledGhost),
         reduceMotion: reduceMotion, frame: frameIndex(at: now, rate: 20, count: 64))
```
Golden: `Spec.CellShapes` pins the 64-tick endpoint table + ring/axis parity. **[PLANNED]**

---

### 6.6 CellButton — the interactive primitive (Shutter; base of every control)

**Anatomy (Shutter)** — center **col 99.5 / row 269.5**, block **cols 83–116 × rows 253–286** (34×34). Idle = a **2-cell ring band** around a **filled disc of Ø 30 (radius 15)**, satisfying the closure law `15·2 + 2·2 = 34` (§3.3). 2-cell geometric center (cols 99–100 / rows 269–270).

```
 ┌──── 34 cells ────┐
 │  ◜▔▔▔▔▔▔▔▔◝       │ ← 2-cell ring band
 │  ▏  ███████  ▕    │ ← filled disc (Ø 30, r=15)
 │  ◟▁▁▁▁▁▁▁▁◞       │
 └──────────────────┘  transparent Button frame == this 34×34 cell-rect
```

**Sizing** — `shutterCells = 34` (68 pt). **Floor proof:** 34 ≥ 22 ✓. Secondary controls = `controlCells = 24` (48 pt) ✓. Grow by using more cells (24→34), never by enlarging the cell. **Hit == visible:** the transparent `Button` frame is the *same* 34×34 cell-rect used to paint it. (Resolves the prior 72→68 pt / 36→34 cell discrepancy in favour of the ladder value 34 = 68 pt; routed through the decisions-gate.)

**States** — cell transforms only: idle · pressed = **invert** the hit-block (the inverted disc is also covered by the luminance-flip contrast check, so it never drops below 3:1 on a dark scene) · selected = 1-cell accent border one cell outside (Gear when its sheet is open) · disabled = 50% 2×2 checker · busy = rotating 3-cell rim arc on the 20 fps clock (recording → 9-cell rounded-square stop). Reduce Motion → static quadrant dots.

**Behavior** — idle/selected/disabled in Pass A (or a tiny Pass-B overlay to avoid a full re-bake on press); busy arc is Pass B. Wraps a transparent `Button` + a `ButtonStyle` exposing `isPressed`. Keeps existing `vm.capture()`/`focus()`/Haptics wiring.

**Do / Don't**
| ✅ DO | ❌ DON'T |
|---|---|
| Pin the Button frame to the painted cell-rect | Add an invisible larger hit slug |
| Express pressed as invert, disabled as 2×2 checker | Use opacity/glow/glass/rounding for a state |
| Freeze busy spinner to quadrant dots under Reduce Motion | Keep rotating under Reduce Motion |
| Composite press as a Pass-B overlay | Re-bake the full field on every press |

**Accessibility** — `accessibilityLabel("Capture 64-frame burst")`, `accessibilityValue("Scene diversity N percent")` (sole owner of the ring value), hint "Holds focus and exposure, captures sixty-four frames at twenty fps"; busy/disabled via `.disabled()`. Gear: label "Settings", `.isSelected` when the sheet is open. Cells hidden; ≥ 22-cell touch; visible == hit.

**Code API**
```swift
CellButton(block: lattice.rect(cols: 83...116, rows: 253...286),   // cell-rect; no pt size
           state: shutterState,                                    // .idle/.pressed/.selected/.disabled/.busy(frame:)
           glyph: .shutterDisc, reduceMotion: reduceMotion,
           label: "Capture 64-frame burst", value: "Scene diversity \(pct) percent",
           action: vm.capture)
```
Golden: `Spec.CellShapes` (disc/ring parity) + `Spec.Lattice` (block rect, ≥ 22-cell + closure assertions). **[PLANNED]**

---

### 6.7 CellSelector — a control built from CellButtons (Settings)

**Anatomy** — a horizontal row of N segment `CellButton`s sharing one band; the selected segment carries the 1-cell accent border; a 1-cell gutter between segments; exactly one selected.

**Sizing** — **the selector grows by widening the band (more cells)**, so every segment stays ≥ `touchFloorCells = 22`. It must never add a segment by subdividing a fixed band below 22 cells (that breaks the touch floor *and* smuggles in a per-segment pitch shrink). `Spec.Lattice` asserts per-segment ≥ 22 + band-grows-not-shrinks.

**States** — per segment: idle / pressed (invert) / selected (accent border) / disabled (2×2 checker). Exactly one selected.

**Behavior** — Pass A (selection change re-bakes, or a tiny Pass-B overlay). Tap = select; Haptics on change.

**Do / Don't**
| ✅ DO | ❌ DON'T |
|---|---|
| Widen the band to add a segment | Shrink segments below 22 cells |
| Mark selection with a 1-cell accent border | Use a filled glow/tint behind the selected segment |

**Accessibility** — the row is `accessibilityElement(children: .contain)`; each segment a `Button` labelled by its option ("Blue-noise dither, 3D"); `.isSelected` on the active one; single spoken value.

**Code API**
```swift
CellSelector(options: samplerOptions, selection: $config.dither, segmentCells: 22, gutterCells: 1)
```
Golden: `Spec.Lattice` (per-segment ≥ 22-cell + band-grows-not-shrinks). **[PLANNED]**

---

### 6.8 CellText — the AX-fallback rasteriser (reused primitive)

**Anatomy** — a monospaced string rasterised into a 1-bit mask at cell resolution (AA off), nearest-neighbour upscaled. Single ink (`.renderingMode(.template)`).

**Sizing** — integer cells only. **Not a primary glyph register.**

**States** — ink color only.

**Behavior** — static. **Role strictly bounded:** the Dynamic-Type AX fallback (≥ `.accessibility1`) and the sampler-overflow fallback — `UIFont.monospacedSystemFont` drops/merges stems at 6×13 before upscale, so it never renders the wordmark or 7-seg.

**Do / Don't**
| ✅ DO | ❌ DON'T |
|---|---|
| Use as the AX `Text` fallback at ≥ `.accessibility1` | Render the wordmark or 7-seg count through it |
| Keep its built-in `accessibilityLabel(text)` | Give it two inks (single-ink template) |

**Accessibility** — carries `accessibilityLabel(Text(text))`; cells decorative.

**Code API**
```swift
CellText("256 colors", rows: 7, ink: .white)   // shipped; AX-fallback register only
```

---

### 6.9 Glyph composites — Wordmark, CountReadout, SamplerTag

`CellGlyph` compositions; each is decorative cells + one container label. **These are left-to-right text runs, not radial widgets — they are explicitly EXEMPT from PATTERN-CENTERLINE (§7.0); their position is their left/center extent, not the col-99.5 axis.**

- **Wordmark "SixFour"** — **124 × 20** at cols 68–191 × rows 96–115 (left-aligned to the preview). **7 glyphs (S,i,x,F,o,u,r)**: 7 × 16-cell box + 6 × 2-cell gaps = **124 cells** (matches cols 68–191). `accessibilityLabel("SixFour") + .isHeader` — the one non-hidden decorative element. Pass A. **Do:** add personality via the master's characterful forms. **Don't:** route through `CellText`.
- **CountReadout** — ◇ Diamond (12×12 `CellIcon`) + a **fixed 3-digit field** (max 256; each digit 10×18 two-ink 7-seg, leading digits `ledGhost`-blanked when unused so it never reflows) + " colors" (6×13 Cozette), left-anchored at cols 70–143 × **rows 306–323** (worst-case 3-digit rect bounded inside the READOUT band). Driven by `vm.occupiedBins ∈ 0…256`. Pass A — re-bakes on value change, **not** on the clock. One combined label: `"\(occupiedBins) colors, sampler \(spokenSamplerTag)"`. **Do:** keep the 7-seg two-ink fixed-width. **Don't:** put it on the clock.
- **SamplerTag** — 6×13 Cozette line centered on col 100, **rows 327–340** (one line; worst-case ≈ 162 cells fits within the band). Falls back to system `Text` if measured width > 180 cells, at any size. Pass A (re-bake on toggle). Cells hidden; value folded into the CountReadout's combined label. **Do:** honour descenders ('diffusion', 'serpentine'). **Don't:** let the fallback `Text` cross the row-420 home-indicator floor — the AX fallback container grows **upward** from a bottom edge at row 420 (RULE-A11Y-FLOORGUARD).

```swift
CellGlyph(register: .wordmark, text: "SixFour", ink: .white)
CountReadout(bins: vm.occupiedBins, sampler: vm.samplerTag)   // ◇ + fixed-3-digit 7-seg + label, Pass A
SamplerTag(text: vm.samplerTag, maxCells: 180)                // 6×13, Text-fallback on overflow
```
Goldens: `Spec.CellFont` (masters) + `Spec.Lattice` (rects, wrap rule, AX-floor clamp). **[PLANNED]**

---

### 6.10 What this layer forbids (the closed vocabulary) + Glass retirement

A new capture-HUD widget **must** be composed from §5 primitives. Introducing a raw `Circle()`, `Rectangle().stroke`, `RoundedRectangle`, `Text`, glass material, opacity, glow, or corner-rounding on the capture HUD is a contract violation — lint-flagged and golden-gated.

**Explicitly RETIRED from the capture HUD** (concrete migration targets, not silent obsolescence): `GlassIconButton`, `GlassToolbarCluster`, `GlassInfoChip`, and the `SFTheme` tokens `glassIconButtonSize`, `glassClusterSpacing`, `hairline`, `mutedFill`, `mutedText`, `dimText`, `groundWashOpacity`. These are **REMOVED from the capture HUD** and **KEPT for Review/Settings** (EXEMPT-GLASS-REVIEW, §9.7). This retirement is a GATE-DECISIONS item (§9.5).

---

## 7. Patterns

> Patterns fix how widgets sit together on the one 201×437 lattice. Every pattern is a **band map** — a contiguous partition of the 437 rows with no gaps and no overlaps. On a single-pitch lattice, layout IS the assignment of cells to widgets; there is no free-floating positioning.

### 7.0 Vocabulary

| Term | Meaning |
|---|---|
| **Band** | A contiguous run of rows owned by one purpose. Bands tile 0–436 with no gaps/overlaps. |
| **Air band** | Field-only — **no chrome, no glyphs**. The Swiss gutter; load-bearing, not leftover. |
| **Safe band** | Reserved for an OS surface; field renders under it, no chrome enters. Shifts via `safeTopRows`/`safeBottomRows`. |
| **Anchor** | A locked cell-rect others place relative to. The **preview** (rows 143–206) is the primary anchor. |
| **PATTERN-CENTERLINE** | The radial axis at **col 99.5** (2-cell center 99–100). Shared by the ring, shutter, diamond. **Text runs (CountReadout, SamplerTag) are EXEMPT** — they are left/center-anchored runs, not radial widgets. |

### 7.1 The Capture HUD band map (PATTERN-CAPTURE)

One cached field+chrome bitmap (Pass A) + two animated overlays (Pass B: the live ring/count; the preview). Authored against the nominal 437-row field; runtime-shifted by the safe bands. **The TITLE band is widened to start at row 92** so the gear (rows 96–119) and wordmark both sit wholly inside TITLE and no chrome enters an Air band.

```
ROWS      H   BAND                 CONTENT                                  CLOCK
──────────────────────────────────────────────────────────────────────────────────
  0– 30   31  TOP SAFE             Dynamic Island. Field only.              static
 31– 91   61  UPPER AIR (a)        Pure field.                              static (tint ≤8Hz)
 92–119   28  TITLE                "SixFour" wordmark (cols 68–191, rows    static
                                   96–115) + Gear (cols 173–196, rows 96–119).
120–142   23  UPPER AIR (b)        Field. Title→preview gutter.             static
143–206   64  PREVIEW  ◀ ANCHOR    64×64 PixelImage @2pt, cols 68–131.      20 fps
207–239   33  LOWER AIR (a)        Field. Preview→instrument gutter.        static
240–300   61  DIVERSITY RING       center col 99.5 / row 269.5, R=30.       20 fps (lit band)
253–286   34  SHUTTER (in ring)    34-cell disc, center 99.5/269.5.         20 fps (busy only)
301–305    5  LOWER AIR (b)        Field. Ring→readout gutter.              static
306–323   18  READOUT count        ◇ + 7-seg digits + " colors" (cols      static (re-bake on Δ)
                                   70–143, a LEFT-anchored run).
324–326    3  micro-air            Field.                                   static
327–340   14  SAMPLER tag          6×13 Cozette line, centered.             static
341–419   79  LOWER AIR (c)        Field.                                   static
420–436   17  BOTTOM SAFE          Home indicator. Field only.              static
```

The golden split is a *consequence* of the anchor: 143 rows above the preview : 230 below; 230/143 ≈ 1.608 ≈ φ (LAW-GOLDEN). Moving the TITLE band edge does not disturb the split (it depends only on the preview anchor) — confirmed in the golden.

### 7.2 The Review / palette composition (PATTERN-REVIEW)
Review is a **separate surface with its own commensurate pitch** (EXEMPT-REVIEW-PITCH). It uses the **6 pt family** (`gifCellPt=6`, `gifCanvasPt=384`, `paletteCellPt=24`): a 64×64 GIF shown for *inspection* is a full-width 384 pt hero, not a 128 pt postage stamp. The seam is named (RULE-REVIEW-PITCH): a surface uses *exactly one* pitch; the two never share a screen.
- **GIF hero:** 384 pt `PixelImage`, `.interpolation(.none)`, the 20 fps clock.
- **Palette grid:** 16×16 at `paletteCellPt=24` (one palette cell = a 4×4 block of GIF cells). The ONE place `fillCell` is contractually allowed.
- **Action row:** glass MATERIAL retained (EXEMPT-GLASS-REVIEW) — chrome over content, glass's documented use.
- The palette-explorer modes (`treemap2D`, `grid2D`, `cloud4D`) are Review content on the 6 pt family.

> **Lint scope (explicit):** LINT-SINGLE-PITCH and LINT-TOKEN-NAMING apply to (a) all capture-HUD cells and (b) Review/palette **content cells**, but **NOT** to the retained Review **glass chrome material** (its analog corner radii, e.g. `pillCorner=14`, are out of lattice scope *by exemption*). The lint must not fire on KEEP-for-Review glass tokens.

### 7.3 The capture→commit→review handoff (PATTERN-HANDOFF)
The "you live inside the 64³ world" claim requires spatial continuity:
1. **Capture** the 64-frame burst; the preview keeps animating at its 128 pt @2 pt rect.
2. **Commit:** the preview tile uses the *same render path and palette* as the eventual review hero.
3. **Review** at 384 pt. RULE-HANDOFF-SAMEPIXELS: the indexed bytes and palette are **byte-identical** to the live preview; the transition is a re-bake (cross-fade/push), never an attempt to interpolate the lattice. **Precise magnification:** capture preview = 2 pt per GIF pixel; review hero = 6 pt per GIF pixel — a **×3 on-screen magnification** (128 pt → 384 pt). Only on-screen size changes; the bytes/colors/encoder do not.

### 7.4 The thumb-zone layout law (PATTERN-THUMB-ZONE)
- **RULE-THUMB-PRIMARY:** the shutter sits bottom-center of the content zone (center col 99.5, row 269.5) — most reachable one-handed; never a top corner.
- **RULE-THUMB-SECONDARY:** secondary controls (gear) sit in the upper periphery, out of the primary thumb arc, so they aren't hit during a capture.
- **RULE-THUMB-NOCORNER:** no *primary* target in a top corner. (Gear is secondary/low-frequency, hence allowed in the title margin.)
- The bottom 17-row safe band is never an interactive target.

### 7.5 The camera-responsive identity pattern (PATTERN-SCENETINT)
- **RULE-TINT-SOURCE:** field per-cell color = darkened, clamped, quantized `sceneTint`; chrome ink from `accent`.
- **RULE-TINT-THROTTLE:** `sceneTint` re-bakes Pass A at 4–8 Hz only — responsive, not animated. **[PLANNED]** GATE-LAYOUT-GOLDEN measures the re-bake cost and fails if a re-bake forces a preview frame drop.
- **RULE-TINT-CLAMP:** the brightest allowed tint holds white chrome ≥ 3:1 (§8); the tint can never make the chrome vanish.
- Reduce Motion freezes the cross-fade (snap to value). Increase Contrast / Reduce Transparency → solid black (hard degrade).

---

## 8. Accessibility & Contrast Spec

> A11y is encoded as invariants, golden-tested or lint-checked. These rules also appear per-component in §6; this is the cross-cutting contract.

### 8.1 Labels & the single-owner rule
- **RULE-A11Y-LABELS:** every interactive cell-block is a real control with a real `accessibilityLabel`; all painted cells are `accessibilityHidden(true)`. The one exception: the wordmark carries `accessibilityLabel("SixFour") + .isHeader`.
- **RULE-A11Y-SINGLEOWNER:** a value is spoken by exactly one element. Ring coverage → the shutter's `accessibilityValue`; the count → one combined `"<n> colors, sampler <spoken tag>"` element. No double-speak.
- **RULE-A11Y-SPOKEN-EXPANSION:** abbreviated tags ("FS · serpentine") expand to speech ("Floyd-Steinberg, serpentine").

### 8.2 Dynamic Type → integer cell-scale, with Text fallback
- **RULE-A11Y-CELLSCALE:** at standard Dynamic Type sizes, `CellGlyph` masters scale by **integer cell factors only** (never fractional; the glyph never blurs).
- **RULE-A11Y-AXFALLBACK:** at `dynamicTypeSize >= .accessibility1`, ALL text registers fall back to system `Text` with the same string + ink (via `CellText`). Instruments (ring, shutter, gear) stay cell-art (controls, not text).
- **RULE-A11Y-FLOORGUARD:** the AX-fallback container is anchored to grow **upward** from a bottom edge at **row 420**, so reflowing text can never cross the home-indicator floor. Asserted in the layout golden.
- **RULE-A11Y-SAMPLER-OVERFLOW:** the sampler line falls back to system `Text` at any size when its width would overflow 180 cells.

### 8.3 Motion
- **RULE-A11Y-REDUCEMOTION:** Reduce Motion freezes (a) field Bayer shimmer, (b) ring lit-tick transition (snap to value), (c) tint cross-fade, AND (d) the shutter busy spinner (rotation → static quadrant dots). The spinner freeze is explicit because it is the one most commonly forgotten.

### 8.4 Touch
- **RULE-A11Y-TOUCH:** every interactive target ≥ 22 cells = 44 pt. Shutter 34 / gear 24 clear it.
- **RULE-A11Y-VISIBLEISHIT:** the hit-rect equals the visible cell-rect. No invisible slugs.

### 8.5 The contrast invariant (HARD math, golden-proven) **[PLANNED golden]**
- **RULE-CONTRAST-LUMINANCE:** true WCAG relative luminance of linearized sRGB, `Y = 0.2126·R_lin + 0.7152·G_lin + 0.0722·B_lin` (NOT OKLab L). A pure function golden-pinned in `Spec.Lattice`/`Spec.Contrast`.
- **RULE-CONTRAST-TEXT:** every text-vs-ground pairing ≥ 4.5:1 (WCAG 1.4.3).
- **RULE-CONTRAST-NONTEXT:** every non-text boundary (ring axis, button border, icon stroke) ≥ 3:1 (WCAG 1.4.11).
- **RULE-CONTRAST-WORSTCASE:** the field's brightest *allowed* `sceneTint` (post `accent()` clamp) is the worst case, proven over all 256 palette colours. `Y_groundMax` is *derived from* this requirement, not guessed.
- **RULE-CONTRAST-FLIP:** chrome/outline luminance is flipped against the field as a tested invariant — "the canvas can never visually vanish" is proven, not hoped.
- **NOTE-LEDGHOST:** `ledGhost=(40,40,40)` is opaque, ~1.6:1 on black — a deliberate off-segment dim, never load-bearing text; exempt from RULE-CONTRAST-TEXT by definition (carries no information when unlit).

### 8.6 High-contrast degrade
- **RULE-A11Y-DEGRADE:** under Increase Contrast / Reduce Transparency, the wash drops to solid black field + solid chrome (no tint, shimmer, or glass). A hard, tested path.

---

## 9. Governance & Enforcement

> The user's demand is that **drift becomes impossible to merge** — a governance property, not a documentation one. Consistency is structural: a single source of truth, machine-checkable gates, an explicit lifecycle (Carbon/Polaris/Uber/Shopify; CI blocks merges, authors aren't asked to *remember* rules).

### 9.1 Single source of truth
- **RULE-SSOT:** layout source of truth = the Haskell spec + golden vectors (not Figma, not per-widget Swift constants). Mirrors the project's Tier-0 ethos.
- **RULE-LATTICE-OWNER:** ALL cell math lives in one `GlobalLattice` type, proven by `Spec.Lattice` **(to be authored — does not yet exist on disk; verified 2026-05-31)**. No widget computes its own pitch, golden split, or safe-area shift.
- **RULE-NO-GENERATED-EDIT:** never hand-edit `SixFour/Generated/`; change `spec/src/SixFour/Codegen/` and regenerate (CLAUDE.md).

### 9.2 The build gate
```bash
cd spec && cabal build && cabal test && cabal run spec-codegen   # 1. verify + emit goldens
cd .. && xcodegen generate                                       # 2. regen project
xcodebuild -scheme SixFour \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build # 3. build
# 4. LAYOUT GOLDEN (release gate, §9.4) — must pass before ship
```
`cabal test` must be green before any chrome change ships **once `Spec.Lattice`/`Spec.CellShapes`/`Spec.CellFont` exist** (§10.2 build plan). Today, rule 8 ("nothing ships without a golden") is a tracked TODO, not a present guarantee.

### 9.3 The lints (the single-pitch law, machine-checkable) **[PLANNED]**
- **LINT-SINGLE-PITCH:** `Spec.Lattice` enumerates every widget's cell-rect and asserts no element declares its own pitch — `chromeDimensionPt % cellPt == 0` for every governed dimension, AND `interactive ⇒ cells ≥ 22`. Enlarging the cell fails the lint. *Scope:* capture-HUD cells + Review/palette content cells; NOT retained Review glass chrome (carve-out per §7.2).
- **LINT-TOKEN-NAMING:** names follow `category.role.variant-state.property` with units in the name; a bare `…Pt` suffix is legal ONLY at the OS safe-area. The lint greps chrome tokens for `…Pt`/opacity and fails the build. Carve-out: KEEP-for-Review glass tokens are exempt.
- **LINT-DRAW-VOCAB:** a capture-HUD widget may only compose from §5 primitives. A raw `Circle()`/`Rectangle().stroke`/`Text`/glass on the capture HUD is a violation. **Additional HUD guard:** any capture-HUD source that references `gifCellPt` fails the lint (the 6 pt family is frozen to Review/palette).
- **LINT-FILLCELL-SCOPE:** `fillCell` may appear only in palette-screen paths (≤256 cells / treemap); its use on the 201×437 field is a violation. (Becomes enforceable once `setCell` ships.)

### 9.4 The layout golden (release gate) **[PLANNED]**
- **GATE-LAYOUT-GOLDEN:** on-device snapshots across **{idle, pressed, busy, disabled, settings-open} × {default Dynamic Type, AX Dynamic Type}** assert: (a) preview pixel pitch is an exact integer; (b) no glyph below the legibility floor; (c) field worst-case contrast ≥ 3:1; (d) AX fallback text stays above row 420; (e) Pass-A re-bake cost does not force a preview frame drop (§7.5). Nothing ships until it passes.

### 9.5 The decisions gate (what stops per-widget drift)
- **GATE-DECISIONS:** any change that **alters the look a user sees** is signed off **before code**, never shipped silently. The canonical open items this session: (a) preview **384→128 pt** shrink; (b) shutter **72→68 pt (36→34 cells)**; (c) **retiring Glass on the capture HUD**. A new color, a moved band, a resized widget — all pass this gate first. *This is the rule that directly answers the user's anger:* look-changes can no longer be made unilaterally inside one widget's code.

### 9.6 Component lifecycle
- **RULE-LIFECYCLE:** `propose → review → build → document → release → deprecate`. "Document" = a §6 entry (anatomy/sizing/states/behavior/do-don't/a11y/API) + a `Spec.*` golden. "Propose" passes GATE-DECISIONS if it alters the look.
- **RULE-NEW-FROM-PRIMITIVES:** a new widget MUST be composed from §5 primitives. Adding a primitive is itself a GATE-DECISIONS proposal that updates §5 — never ad hoc inside a widget.

### 9.7 Scope & documented exemptions
| Exemption | What | Why |
|---|---|---|
| **EXEMPT-OS** | Dynamic Island, status bar, Share/Settings sheets | OS-owned; the lattice renders under them, places no chrome there. |
| **EXEMPT-PREVIEW-CELLS** | the camera preview's pixels | coloured by the scene, not the palette — content, not chrome cells. |
| **EXEMPT-AXTEXT** | the AX-size system-`Text` fallback | reflowing system text above the floor; not cell-art by design. |
| **EXEMPT-GLASS-REVIEW** | glass MATERIAL on Review/Settings chrome | chrome-over-content (its documented use); retained on Review, RETIRED on capture HUD. **Defined in detail in `docs/SIXFOUR-GLASS-LANGUAGE.md` ("GLASS").** |
| **EXEMPT-REVIEW-PITCH** | Review/palette use the 6 pt family | the inspection hero wants 384 pt; one surface = one pitch, the two never share a screen. |

### 9.8 Token migration debt (governance-tracked)
`SFTheme` (Theme.swift) currently ships **both** pitch families and several off-lattice legacy tokens. Until migrated, **the Cardinal Law is CODE-false on the capture path.** Tracked:
- **RETIRE (off-lattice point / opacity):** `pillCorner=14`, `cardCorner=10`, `stripCorner=4`, `pillVerticalPad=7`, `pillHorizontalPad=14`, `sectionSpacing=14`, `treemapPlaneMaxWidth=2.5`, `hairline=.18`, `mutedFill=.06`, `mutedText=.85`, `dimText=.6`, `groundWashOpacity=.32`. (LINT-TOKEN-NAMING flags the `…Pt`/opacity ones; the corner radii survive only as KEEP-for-Review glass.)
- **RESCOPE (capture chrome → cell tokens):** `shutterSidePt=72`, `shutterInnerPt=60`, `controlSidePt=48`, `controlGutter=12`, `decorGutter=6`, `glassIconButtonSize=48`, `glassClusterSpacing=12`, `diversityRingDiameter=84`, `diversityTickLength/Width` — currently `gifCellPt`-derived; re-express in `cellPt=2` cells (shutter 34, gear 24, ring R 30) and rename `…Cells`. **The single-pitch lint must FAIL if any capture-HUD file references `gifCellPt`.**
- **KEEP (Review/palette, EXEMPT-REVIEW-PITCH):** `gifCellPt=6`, `gifCanvasPt=384`, `paletteCellPt=24`, `canvasEdge(forAvailable:cells:)`.
- **KEEP (cross-surface):** `cellPt=2`, `ledGhost=(40,40,40)`, `diversityTickCount=64`, `accent(_:towardWhite:)` (refactored to emit opaque clamped srgb8).

---

## 10. Migration Map & References

### 10.1 What each existing doc becomes
| Existing doc | Disposition |
|---|---|
| `docs/cell-lattice-widget-spec.md` | **PROMOTED to the spine.** Its resolutions/band map/widget table/primitives/font decision/perf model/a11y/build plan feed §2–§9. The resolved authority. **Fix in lockstep:** delete its stray "said 36 cells" digression so a future author cannot re-derive 36; pin shutter = 34 cells in `Spec.Lattice`. |
| `docs/cube-generated-uiux-system.md` | **SUPERSEDED for sizing (pending migration).** Add an in-file header banner marking it superseded. Its modular-scale + Rams §8 completeness rule → LINT-SINGLE-PITCH; round-vs-square / hit==visible / preview-blend reasoning → §6/§7. The 6 pt cube pitch survives only as the Review family (EXEMPT-REVIEW-PITCH). *Left un-marked, it keeps regenerating 6 pt tokens — the exact failure the user is angry about.* |
| `docs/grid-is-the-render-surface.md` | **FOLDED into the Render Model (§4).** `Color(srgb8:)`/`PixelImage`/`PixelGrid` + the flat-cell contract are the vocabulary; its "look-decision the user must confirm" → GATE-DECISIONS. |
| `docs/palette-explorer-2d-3d-4d-design.md` | **SCOPED to Review (§7.2)** — the 2D/3D/4D modes are Review content on the 6 pt family. |
| `~/.claude/plans/misty-greeting-panda.md` | **ABSORBED** — reconciled by the §9 build/lint/golden gates. |

### 10.2 Spec-first ordered build plan (each phase: `cabal test` green before Swift)
1. **GATE-DECISIONS (no code)** — user sign-off on: 128 pt preview, 68 pt shutter, Glass retirement on capture.
2. **`Spec.Lattice` + goldens** — band map, golden split (LAW-GOLDEN), token tiering, the single-pitch predicate, the closure laws (§3.3), the θ→cell tick table, the relative-luminance/contrast functions.
3. **`Spec.CellShapes` + goldens** — midpoint circle/disc/ring/tick/line parity + the 64-tick endpoint table.
4. **`Spec.CellFont` + goldens** — 16×20 wordmark (7 glyphs), 6×13 Cozette, 10×18 7-seg masters.
5. **`SFTheme` migration (§9.8)** — add `cellPt`/`ledGhost`/glyph-box tokens; rescope capture chrome to cells; freeze `gifCellPt` to Review; run LINT-TOKEN-NAMING + the `gifCellPt`-on-HUD guard.
6. **`setCell` + `CellField` extension** — build the byte writer + static-chrome cell-list bake.
7. **Swift primitives** — `GlobalLattice`, `CellShapes`, `CellGlyph`/`CellIcon`, `CellRing`, `CellButton`, `CellSelector` — each verified byte-exact vs goldens.
8. **CaptureView integration** — replace glass/vector chrome with the cached field `PixelImage` + Pass-B overlays; keep capture/focus/haptics.
9. **A11y wiring (§8)** — labels/values/hidden, AX fallback with floor guard, Reduce-Motion freezes.
10. **GATE-LAYOUT-GOLDEN** — the release gate across the state × Dynamic-Type matrix.

### 10.3 References
- **Apple HIG** — section order (Foundations→Patterns→Components), 44 pt touch floor, thumb-zone reachability. https://developer.apple.com/design/human-interface-guidelines
- **Material Design 3 — Foundations & Design Tokens** — tokens as single shared source; one change cascades. https://m3.material.io/foundations · /foundations/design-tokens
- **Three-tier tokens (global→alias→component)** — Yanamala. https://medium.com/@yamini1020.yanamala/design-system-what-are-global-alias-and-component-tokens-part-1-78420a5827a1
- **Token taxonomy (Context+Common-unit+Clarification)** — Tetrisly. https://medium.com/design-bootcamp/design-tokens-variables-architecture-in-tetrisly-design-system-part-2-taxonomy-2504f959cbb1
- **Component specifications / anatomy** — Curtis, EightShapes. https://medium.com/eightshapes-llc/component-specifications-1492ca4c94c
- **Anatomy diagrams + Do/Don't pairs (Carbon)** — Figma DS-103. https://www.figma.com/blog/design-systems-103-documentation-that-drives-adoption/
- **Governance prevents drift via lifecycle + default-consistency** — UXPin. https://www.uxpin.com/studio/blog/design-system-governance/
- **Code (CI) is the source of truth, not Figma** — Builder.io. https://www.builder.io/blog/governance-beyond-figma
- **Contract precedents (codebase)** — `docs/grid-is-the-render-surface.md`, `docs/cube-generated-uiux-system.md`, `docs/cell-lattice-widget-spec.md`; the Zig deterministic-core byte-exact golden ethos; WCAG SC 1.4.3 / 1.4.11 relative luminance.
