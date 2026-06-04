# SIXFOUR-DESIGN-MAP

> **What this is.** The traceability MAP from the GRID design language onto the shipped code. For every governed UI element it shows the chain **FORM → FUNCTION (the cube token it derives from) → CODE (file:line) → STATUS**, and it exposes exactly where the trace is broken (⚠️ drift) or not yet built (◷ planned). The ethos — *"form follows function + 64×64 pixel density"* — is meant to be **legible as a trace**: you should be able to point at any pixel of chrome and walk it back to a cell count derived from the 64³ cube, or see in this document precisely why you cannot.
>
> **This is the MAP, not the constitution.** The canonical specification — the Cardinal Laws, the band map, the token tiers, the lints, the exemptions — lives in **`docs/SIXFOUR-DESIGN-LANGUAGE.md`**. When this map and that document disagree about *what the law is*, the design-language doc wins; this file only records *where the code stands against it*. Every status here is derived from per-element conformance findings that were re-verified at the cited `file:line`.

---

## 0. Remediation log (Phases 1–4, 2026-06-03/04 — verified)

The gap-closing pass below is **deliberate and spec-first**; every line was gated by
`cabal test` + an iOS simulator build. Status here supersedes the per-row table in §2
where they differ. **Honesty rule (P4):** a row flips to ✅ only when the audited drift
is *fully* resolved AND enforced; partially-fixed rows stay ⚠️ with the residual named.

- **✅ Law #5 (one owner) + Law #6 (every dim a cell count) — RESOLVED & ENFORCED.**
  `Spec.Lattice.hs` (10 laws: gcd pitch theorem, closure `15·2+2·2=34`, touch floor,
  golden split) → `Generated/LatticeContract.swift` → `GlobalLattice` is now a verified
  `CGFloat` facade (the numbers live in Haskell). All capture-HUD raw point literals
  routed through `GlobalLattice.pt()`. Enforced by `scripts/lint-grid.sh` LINT-SINGLE-PITCH.
- **✅ Law #2 (grid is the render surface) — RESOLVED & ENFORCED *on the capture HUD*.**
  GlassInfoChip → flat cell strip; all opacity inks → opaque sRGB8; `dimText`/`hairline`/
  `cardCorner` off the HUD. Enforced by LINT-DRAW-VOCAB. (Residual: `StateScreens.swift`
  bootstrap/unauthorized/failure views — a *different* full-screen surface — still carry
  `RoundedRectangle`/opacity; out of the capture-HUD lint scope, tracked for a later pass.)
- **✅ Shutter closure — RESOLVED.** The `d≤13` / unspecified-annulus bug is fixed; the
  disc (r=15) and 2-cell ring band directly abut (`CellButton`, sourced from the spec
  constants). A disabled 2×2-checker state was added (no opacity).
- **✅ Diversity Ring (θ-drift) — RESOLVED.** `Spec.CellShapes.hs` (8 laws) emits the
  golden 64-tick endpoint table with a cross-language IEEE `selfCheck()`; `CellRing`
  consumes it via the closed-form `θ_k` (no per-cell `atan2`) and adds the missing axis
  circle. (Residual: the Pass-A/Pass-B *split clock* awaits `setCell`, Phase 3b.)
- **✅ Law #8 (golden gate) — PARTIAL→ENFORCED for shipped modules.** `Spec.Lattice` +
  `Spec.CellShapes` exist, are `cabal test`-gated, are in the `project.yml` codegen-drift
  gate, and LINT-GOLDEN asserts their presence at build time. (Residual: `Spec.CellFont`
  still absent — Phase 3b.)
- **◷ DEFERRED (Phase 3b, task #5):** `Spec.CellFont`/`CellGlyph` masters (wordmark, 7-seg,
  Cozette — so Wordmark/CountReadout/SamplerTag stop routing through `CellText`); the
  `setCell` two-pass static bake (Law #4); `CellSelector` replacing the native
  `UISegmentedControl` in `SettingsView`; migrating call sites off the back-compat aliases.
- **Tech debt cleaned:** stray `spec/src/.../Color.hi`/`.o` removed; a real doc bug fixed
  (preview row-anchor 143 is *odd*/golden-fixed, not "even on both axes"); the two new
  contracts added to the existing codegen-drift gate.

**New enforcement:** `scripts/lint-grid.sh` runs as a `project.yml` pre-build phase
(verified failing on injected drift, passing clean) — Phases 1–3a cannot silently regress.

**Phase 3b update (the font + bake layers):**
- **3b-1 ✅ 7-seg CountReadout** — `Spec.SevenSeg` (parametric, 7 laws) → `SevenSegContract.swift` →
  `CellDigits` two-ink fixed-width field. The count NEVER reflows (§6.9); the old reflowing
  single-ink `CellText` + Unicode `◇` are gone (`◇` is now a real `CellIcon.diamond`).
- **3b-2 ✅ Settings rebuilt cell-based** — native `Form`/`UISegmentedControl`/`Toggle` RETIRED;
  `CellSelector` (accent-bordered segments) + `CellToggle` replace them. Long blurbs stay readable
  via the §6.8 system-`Text` prose fallback (pixel prose is unreadable at sentence length).
- **3b-3 ◐ setCell primitive shipped; live bake GATED.** `CellField.setCell` (the Pass-A byte
  writer, Law #4) + `image(tint:chrome:)` + `PlacedCellMask` + `CellChrome.ringAxis` are built and
  demonstrated (a `#Preview` bakes field + ring axis into one bitmap via the golden `CellShapes`
  geometry). **The full live HUD migration onto the Pass-A bake is deliberately NOT done**, gated on:
  (a) **a real §7.1 band-map bug** — the wordmark advance (cols 68–191) **overlaps the gear**
  (cols 173–196) by 19 cols; absolute baking can't place a wordmark that underlaps the gear, so the
  band map needs design resolution first; (b) text chrome (wordmark/count/sampler) needs the
  `CellFont` masters to bake; (c) the migration moves the HUD from SwiftUI flow to absolute
  positioning and needs on-device visual verification. NOTE: `setCell` is a **perf optimization**,
  not a conformance fix — the HUD already renders correctly without it.

---

## 1. Scoreboard

| Status | Count |
|---|---|
| ✅ Conformant elements | 0 |
| ⚠️ Drift elements | 14 |
| ◷ Planned elements | 0 |
| ✗ Missing elements | 0 |
| **Total governed elements** | **14** |
| **Total confirmed drifts (confirmed=true)** | **103** |

Every one of the 14 governed elements currently traces back to the cube **but the trace is broken somewhere** — there is not a single fully-conformant element on the capture HUD. The dominant failure modes are: (a) the **GlassInfoChip + raw-`Text` + opacity** timing overlay illegally sitting on the capture HUD, (b) the **`SFTheme.dimText` / `.white.opacity(…)`** opacity inks that should be opaque sRGB8, (c) **raw point literals** (`spacing: 10`, `.padding(.bottom, 16)`, `spacing: 2`) bypassing `GlobalLattice.pt()`, and (d) the **entire golden-gate layer** (`Spec.Lattice` / `Spec.CellShapes` / `Spec.CellFont`) and the **primitive layer** (`CellGlyph`, `CellIcon`, `CellButton`, `CellSelector`, `CellRing`, `setCell`) not existing yet, which is why the cell discipline cannot be machine-enforced.

> **Note on counts.** "Confirmed drifts" counts every `confirmed=true` drift *record* across all elements (103). Because the capture HUD is a shared surface, the same physical line of code (e.g. the GlassInfoChip at `CaptureView.swift:60`, the wordmark opacity at `:115`, the four raw spacings) is correctly re-confirmed under each element whose trace passes through it. The deduplicated set of distinct offending lines is much smaller (see §4); the per-element multiplicity is intentional — each element's trace is broken independently and each break must be fixed for *that* element to go green.

---

## 2. The Traceability Table

Status legend: ✅ conformant · ⚠️ drift · ◷ planned · ✗ missing. All `file:line` paths are absolute under `/Users/daniel/SixFour/`.

| Element | Intended Form | Cube Function (derivation) | Code (file:line) | Status |
|---|---|---|---|---|
| **Preview (hero)** §6.1 | 64×64 block, 128 pt square, NN ×6 upscale; one `PixelImage` on Pass B @20fps; no frame/opacity/glass; a11y-labelled, cells hidden | `previewCells = 64` — 1 cell = 1 GIF pixel; widget cell-count **is** the cube's spatial resolution (`SixFourShape.W = 64`) | `SixFour/UI/Screens/Capture/CaptureView.swift:81,83,93,108`; `SixFour/UI/Components/PixelGrid.swift:46`; `SixFour/UI/GlobalLattice.swift:21` | ⚠️ drift |
| **Background Field** (CellField) | 201×437 indexed bitmap; 4×4 Bayer two-shade dither (opaque, α=255); Pass-A only; drawn once `interpolation(.none)` ×6; chrome via `setCell` [PLANNED] | `gcd(402,874)=2` lattice — the unique pitch tiling iPhone 17 Pro edge-to-edge; the field **is** the Pass-A bitmap | `SixFour/UI/Components/CellField.swift:14,46,79`; `SixFour/UI/Screens/Capture/CaptureView.swift:51` | ⚠️ drift |
| **Wordmark "SixFour"** | 124×20 at TITLE register; 7 hand-authored 16×20 1-bit glyphs via `CellGlyph(.wordmark)`; ink `.white` opaque; `.isHeader`; NOT routed through `CellText` | `CellGlyph .wordmark` register, Pass-A bake — hand-authored master so 1 source pixel = 1 lattice cell (Law #1) | `SixFour/UI/Screens/Capture/CaptureView.swift:115`; `SixFour/UI/Components/CellText.swift:18,41`; `SixFour/UI/GlobalLattice.swift:21` | ⚠️ drift |
| **Gear / Settings** | 24×24 cells (48 pt); `CellButton`⊃`CellIcon(CellShapes.gear)`; hit==visible ≥22 cells; states idle/pressed-invert/selected-border/disabled-checker | `controlCells = 24` — HIG 48 pt comfortable target in 2 pt cells; secondary cube-HUD control | `SixFour/UI/Screens/Capture/CaptureView.swift:119`; `SixFour/UI/Components/CellSprite.swift:93`; `SixFour/UI/GlobalLattice.swift:34` | ⚠️ drift |
| **Shutter** (CellButton) | 34×34 cells (68 pt); disc Ø30 (r=15) directly abutted by 2-cell ring; closure `15·2+2·2=34`; busy = 3-cell Pass-B arc; reduce-motion → static dots; no opacity/glass | `shutterCells = 34` (fib ladder); `disc.r = 15`; `ring.thick = 2`; closure law derived from `cellPt = 2` | `SixFour/UI/Components/CellSprite.swift:75,83,84` | ⚠️ drift |
| **Diversity Ring** (CellRing) | Ø60 (R30); 64 radial ticks; 1-cell axis circle; split clock (axis+inactive Pass A / lit-band Pass B); precomputed golden tick table | `ringTicks = 64` (one per GIF frame); `ringCells = 60` (R30 from shutter closure); `coverage∈[0,1]` → ⌊cov·64⌋ ticks lit | `SixFour/UI/Components/CellSprite.swift:115,118,119`; `SixFour/UI/Screens/Capture/CaptureView.swift:134`; `SixFour/UI/GlobalLattice.swift:36,38` | ⚠️ drift |
| **CountReadout** (◇ + digits) | ◇ 12×12 `CellIcon` + fixed 3-digit two-ink 7-seg `CellGlyph` (leading ledGhost-blanked) + " colors" Cozette; Pass A, re-bake on Δ only | Two-ink fixed-width 7-seg so the count never reflows; `ledGhost=(40,40,40)` opaque off-segment (Law #2); off the 20fps clock (Law #4) | `SixFour/UI/Screens/Capture/CaptureView.swift:146,147,150,153`; `SixFour/UI/Theme.swift:81` | ⚠️ drift |
| **SamplerTag** | 6×13 Cozette `CellGlyph(.label)`; system-Text fallback if width>180; Pass-A re-bake on toggle; a11y folded into CountReadout; FLOORGUARD | `CellGlyph .label` — decorative mode identifier, off the live clock; honest reflection of current residual-shaping sampler | `SixFour/UI/Screens/Capture/CaptureView.swift:153,150,146,115`; `SixFour/UI/Theme.swift:81` | ⚠️ drift |
| **CellSelector** (Settings) | Row of `CellButton` segments sharing one band; each ≥22 cells; band widens (never subdivides); selected = 1-cell accent border; 1-cell gutter; one selected | `touchFloorCells = 22` (HIG 44 pt floor, cube-derived); `segmentCells` owned by GlobalLattice; selection = border not fill (Law #2) | `SixFour/UI/Screens/Settings/SettingsView.swift:44,59,76,109`; `SixFour/UI/GlobalLattice.swift:21` | ⚠️ drift |
| **CellText** (AX-fallback) | Mono → 1-bit cell-res mask (AA off), NN upscale, single opaque ink; integer rows only; **role bounded**: AX-fallback (≥`.accessibility1`) + sampler-overflow only; never wordmark/7-seg | AX-fallback rasteriser — bridge between cube cell discipline and iOS Dynamic Type; justified solely by the two overflow registers | `SixFour/UI/Components/CellText.swift:18`; `SixFour/UI/Screens/Capture/CaptureView.swift:115,150,153`; `SixFour/UI/Theme.swift:81` | ⚠️ drift |
| **GlobalLattice** (Law #5) | Sole `cells→pt` path; no view computes `×cellPt`; every chrome dim an integer cell count via `GlobalLattice.pt()`; owns all widget cell-counts | `GlobalLattice.pt()` — the one cells→points path; owns `cellPt=2, cols=201, rows=437, shutter=34, control=24, ring=60, ticks=64` | `SixFour/UI/GlobalLattice.swift:21`; `SixFour/UI/Screens/Capture/CaptureView.swift:60,61,63,113,115,132,140,147,150,153` | ⚠️ drift |
| **Two-pass bake** (Law #4) | Pass A bakes field + ALL static chrome into one 201×437 indexed bitmap (×6 once); Pass B animates only preview + ring lit-band/arc on one clock `frameIndex(…,20,64)`; `setCell` [PLANNED] | `setCell` (CGContext byte writer) [PLANNED]; one clock `frameIndex(at:rate:20,count:64)` owning all motion | `SixFour/UI/Components/CellField.swift:28`; `SixFour/UI/Components/PixelGrid.swift:34`; `SixFour/UI/Screens/Capture/CaptureView.swift:51,60`; `SixFour/UI/Components/CellSprite.swift:115` | ⚠️ drift |
| **VoxelCubeView** (RULE-CUBE-ISO) | Orthographic; 2:1 dimetric (az 45°/el 30°); NN art-pixel quantize (ART_RES=128); face-on==2D GIF byte-identical; flat indexed voxels, no AA/opacity/round | Law #2 in 3D — a voxel is one GIF pixel: one opaque sRGB8, same no-AA/no-opacity/no-round contract as a 2D cell | `SixFour/UI/Components/VoxelCubeView.swift:111,139`; `SixFour/Metal/Shaders.metal:604,606,609,614,660,678` | ⚠️ drift |
| **Golden gates** (Law #8) | Every governed dim golden-pinned by passing `cabal test` vs `Spec.*`; `SFTheme` is the verified mirror of `Spec.Lattice`, not an independent authority; nothing ships without a golden | The 64³ cube is the law — golden gate makes Laws #1/#5/#6 machine-checkable & merge-blocking; `cabal test` replaces author memory | `spec/spec.cabal:20`; `spec/src/SixFour/Spec/` (Lattice/CellShapes/CellFont absent); `SixFour/UI/Theme.swift:13,80,81`; `SixFour/UI/Screens/State/StateScreens.swift:79,83,87`; `SixFour/UI/Screens/Capture/CaptureView.swift:60,113,132,140,115,150,153` | ⚠️ drift |

---

## 3. Where the trace is *not yet built* (◷ planned primitives)

No element is wholly ◷, but every element's *correct* form blocks on primitives that do not exist in the Swift tree. These are tracked debt (§9.8 of the design language), not covert conformance:

- **`CellGlyph` / `CellFont`** — hand-authored 1-bit masters for the wordmark (16×20 TITLE), 7-seg count (10×18 two-ink), and Cozette label (6×13). Absent. The wordmark, CountReadout, and SamplerTag are all illegally routed through `CellText` until these ship.
- **`CellIcon` / `CellShapes`** — the ◇ diamond (12×12) and the gear mask (`CellShapes.gear(box:24)`). Absent; the diamond is a Unicode `◇` in a `CellText` string and the gear is an ad-hoc `CellSprite` midpoint-circle closure.
- **`CellButton` / `CellSelector`** — referenced only in a comment at `CellSprite.swift:73`; the four Settings selectors are native `.pickerStyle(.segmented)` (a UIKit `UISegmentedControl`).
- **`CellRing`** — listed `build` in §5; shipped `CellDiversityRing` inlines geometry, recomputes θ per cell, has no precomputed tick table, no split clock, and omits the 1-cell axis circle.
- **`setCell`** (CGContext byte writer) — the Pass-A static-chrome writer; absent, so the unified two-pass bake (Law #4) does not exist and static chrome is live SwiftUI.
- **`Spec.Lattice` / `Spec.CellShapes` / `Spec.CellFont`** — the golden gate (Law #8). No `.hs` files, not in `spec.cabal` exposed-modules (66 modules, none of these three). Until they exist, `SFTheme` is an *independent* authority rather than a verified mirror, and the cell discipline cannot be merge-blocked.

---

## 4. Drift Ledger

Every entry below is a `confirmed=true` finding, re-verified at the cited `file:line`. Grouped by severity. Identical physical lines appear once here (deduplicated) with the set of laws/elements they break; the per-element multiplicity that produced the 103 count is recorded in §1.

### 4.1 HIGH severity

- **`CaptureView.swift:60` — GlassInfoChip on the capture HUD.** Laws #2 / §6.10 / §9.7 (LINT-DRAW-VOCAB; glass RETIRED on HUD). Snippet: `GlassInfoChip(cornerRadius: SFTheme.cardCorner) { Text(summary)…foregroundStyle(.white.opacity(0.85)) }`. Glass material (`GlassControls.swift:80` → `.glassEffect(.regular, …)`) is legal only on Review/Settings (EXEMPT-GLASS-REVIEW); inside `mainCaptureScene` it is a contract break. The block compounds three independent violations (glass material, raw `Text`, `.opacity(0.85)`) plus the off-lattice `SFTheme.cardCorner=10`. **Fix:** delete lines 59–66; render the summary via the existing `bannerText(_:)` helper (`CaptureView.swift:222`) — flat `CellText`, opaque `.white` ink, `Color(srgb8: SFTheme.ledGhost)` background, `GlobalLattice.pt()` padding.
- **`CaptureView.swift:61` — raw SwiftUI `Text(summary)` on the HUD.** §5 / §6.10 (LINT-DRAW-VOCAB). Subsumed by the GlassInfoChip removal; if timing text is retained it must be `CellText(summary, rows: 11, ink: .white)`.
- **`CaptureView.swift:63` — `.foregroundStyle(.white.opacity(0.85))` inside the chip.** Law #2 (opacity is shading; §2.6 "never white.opacity"). Eliminated by the GlassInfoChip removal.
- **`CaptureView.swift:150` — `CellText("◇ … colors", rows: 11, ink: SFTheme.dimText)`.** Laws #2 / §6.10 / §9.8. `SFTheme.dimText = Color.white.opacity(0.6)` (`Theme.swift:81`) is a RETIRED opacity token on the HUD. Also the ◇ is a Unicode glyph in a system-mono string (should be `CellIcon`), and the count is a reflowing single-ink string (should be the fixed two-ink 7-seg `CountReadout`). **Fix:** opaque ink, e.g. `Color(srgb8: SIMD3<UInt8>(153,153,153))` or `Color(srgb8: SFTheme.ledGhost)`; long-term `CountReadout(bins:sampler:)` on `CellGlyph`.
- **`CaptureView.swift:153` — `CellText(samplerTag, rows: 8, ink: SFTheme.dimText.opacity(0.85))`.** Laws #2 / §6.10 / §9.8. Double opacity: `dimText` (0.6) further chained with `.opacity(0.85)`. The sampler-overflow *use* is legal; the ink is not. **Fix:** single opaque sRGB8 (≈white@0.51), e.g. `Color(srgb8: SIMD3<UInt8>(130,130,130))`; `rows: 8` is also wrong (see §4.2). No `.opacity()` chain may appear on a HUD cell.
- **`CaptureView.swift:83` / `CellSprite.swift:83,84` — broken shutter closure.** Law #6 (closure `15·2+2·2=34`). The disc is `d<=13` (Ø≈26 pt) not `d<=15` (Ø30 pt); disc and ring are **not directly abutted** — an unspecified 2-cell annulus sits at `d=13..15`. **Fix:** change the disc threshold to `d<=15`; ring `d>=15..17` then becomes correct and contiguous; correct the misleading "1-cell clear annulus" comment.
- **`CellSprite.swift:115` — Pass-B ring not on the one clock.** Law #4 (ONE CLOCK). `CellDiversityRing` is driven by `vm.sceneGauge` (~10fps), has no `frameIndex(…,20,64)`/`TimelineView`, no `frame:` parameter, and redraws all 3600 cells per update (the explicit §6.5 DON'T). **Fix:** wrap `bottomBar` in `TimelineView(.animation(minimumInterval: 1.0/20))`, thread `frameIndex(at:rate:20,count:64)`, and split into a Pass-A static bake (axis + inactive ticks) + Pass-B lit-band layer.
- **`SettingsView.swift:44,47,59,62,76,79,109,112` — native `.pickerStyle(.segmented)`.** Laws #1 / #2 / #5 / #6. All four selectors render a `UISegmentedControl` (corner-rounding, opacity blend, filled selection highlight — the exact §6.7 antipattern). No `CellButton`/`CellSelector`/`segmentCells` exists. **Fix:** build `CellButton`+`CellSelector` (selection = 1-cell accent border), add `segmentCells (≥22)` and `gutterCells=1` to `GlobalLattice`, replace all four pickers.
- **`Theme.swift:80,81` — live RETIRED opacity tokens.** Laws #8 / #2 / §9.8. `hairline = Color.white.opacity(0.18)`, `dimText = Color.white.opacity(0.6)` remain in `SFTheme` and `dimText` is actively consumed on the HUD. **Fix:** retire from the capture path; keep only as opaque KEEP-for-Review glass tokens (definition itself is legal for Review — the HUD *call-sites* are the violations).
- **`spec.cabal:20` / `spec/src/SixFour/Spec/` — golden gate absent.** Law #8. No `Lattice.hs`, `CellShapes.hs`, or `CellFont.hs`; not in the 66 exposed modules. **Fix:** author the three modules per §10.2 steps 2–4, add to `exposed-modules`, write the band-map / LAW-GOLDEN / 64-tick-endpoint / master-glyph golden suites.

### 4.2 MEDIUM severity

- **`CaptureView.swift:115` — `CellText("SixFour", rows: 24, ink: .white.opacity(0.9))`.** Laws #2 / #1 / #6 / §6.9. Three breaks: (a) opacity ink (`§2.6` "never white.opacity"); (b) wrong primitive — §6.9 says "Don't: route through `CellText`", target is `CellGlyph(.wordmark)`; (c) `rows: 24` is a bare literal with no `GlobalLattice.wordmarkRows` constant (TITLE register = 20). Also missing `.isHeader` (RULE-A11Y-LABELS) — `CellText.swift:41` applies `.accessibilityLabel` but never `.accessibilityAddTraits(.isHeader)`. **Fix:** `ink: .white`; add `GlobalLattice.wordmarkRows = 20`; chain `.accessibilityAddTraits(.isHeader)`; long-term route through `CellGlyph`.
- **`CaptureView.swift:113` — `HStack(spacing: 10)`.** Laws #5 / #6. Raw pt literal (10 pt = 5 cells) bypassing `GlobalLattice.pt()`. **Fix:** `spacing: GlobalLattice.pt(5)`.
- **`CaptureView.swift:132` — `VStack(spacing: 10)`.** Laws #5 / #6. **Fix:** `spacing: GlobalLattice.pt(5)`.
- **`CaptureView.swift:140` — `.padding(.bottom, 16)`.** Laws #5 / #6. 16 pt = 8 cells (8 is on the fib ladder; the violation is the bypass, not the magnitude). **Fix:** `.padding(.bottom, GlobalLattice.pt(8))`.
- **`CellSprite.swift:93` — `CellGear` has no pressed/selected states.** Law #6 / §6.4. Only an `ink` parameter; `showSettings` is never threaded in. **Fix:** add `isPressed`/`isSelected`; invert on press, 1-cell accent border when the sheet is open; thread `showSettings` from `CaptureView`.
- **`CellSprite.swift:153` — `SamplerTag rows: 8` vs spec 13.** Law #1 / §6.9. `CellText` maps `rows`→`monospacedSystemFont(ofSize:)`, so `rows: 8` = 16 pt, 5 cells short of the 6×13 Cozette register. **Fix:** `rows: 13`.
- **SamplerTag missing overflow + FLOORGUARD.** §6.9 / §8.2 (RULE-A11Y-SAMPLER-OVERFLOW + RULE-A11Y-FLOORGUARD). Bare `CellText`, no >180-cell Text fallback, no upward-from-row-420 floor clamp. **Fix:** build the `SamplerTag(text:maxCells:)` composite.
- **`CellText.swift:17` — no Dynamic-Type gate (role unbounded).** §6.8 / RULE-A11Y-AXFALLBACK. `CellText` renders unconditionally as the *primary* renderer; the comment at lines 15–17 concedes the gate is "a later phase". **Fix:** gate on `@Environment(\.dynamicTypeSize) >= .accessibility1` so `CellText` is the fallback, not the default.
- **`CellSprite.swift:76` — shutter busy state has no arc / no reduce-motion.** Law #2 / §6.6 / RULE-A11Y-REDUCEMOTION. Busy is only a fill-colour flip; the spec wants a rotating 3-cell Pass-B arc freezing to static quadrant dots. `accessibilityReduceMotion` is declared in `CaptureView` but never passed down. **Fix:** add `reduceMotion`, compute the time-indexed arc, static dots under reduce-motion.
- **`CellSprite.swift:115` (4 structural ring gaps).** Law #8 / §5 / §6.5 / §4. (a) `CellRing` primitive absent (inline `CellDiversityRing`); (b) θ→cell recomputed live, no precomputed golden tick table; (c) no Pass-A/B split clock; (d) 1-cell axis circle at R=30 missing (`d>=24 && d<=29` stops at 29). **Fix:** implement governed `CellRing` with precomputed 64-endpoint table + `Spec.CellShapes` golden + split clock + axis circle.
- **`StateScreens.swift:79,83,87` — BootstrapSkeleton full forbidden vocabulary.** Laws #8 / #2 / #6 / LINT-DRAW-VOCAB. `RoundedRectangle(cornerRadius: 4)` + animated `.fill(.white.opacity(…))`, raw `Text`, `VStack(spacing: 12)`, `.padding(.horizontal, 24)`, `.padding(.vertical, 60)`. **Fix:** rebuild from §5 primitives — `CellField` pulse (two opaque palette entries), `CellText` opaque ink, all spacing via `GlobalLattice.pt()` (12→pt(6), 24→pt(12), 60→pt(30)).
- **`Theme.swift:13` — `cardCorner = 10` off-lattice token.** Law #8 / §9.8. On the RETIRE list, still referenced on the HUD via GlassInfoChip. **Fix:** remove from the capture path (survives only as a KEEP-for-Review glass token).

### 4.3 LOW severity

- **`CaptureView.swift:147` — `VStack(spacing: 2)`.** Laws #5 / #6. Even though 2 pt = 1 cell = `cellPt`, it bypasses the sole owner and is not machine-checkable. **Fix:** `spacing: GlobalLattice.pt(1)`.
- **`CaptureView.swift:83` — `previewCells` not owned by GlobalLattice.** Law #5 / §9.8. Uses `SFTheme.gifSideCells` (a Review-family token) instead of a `GlobalLattice.previewCells` constant. **Fix:** add `GlobalLattice.previewCells = SixFourShape.W`; use it at line 83.
- **`CaptureView.swift:84` — preview a11y spec unmet.** Law #1 / §6.1. The `previewBlock` ZStack has no `.accessibilityLabel("Live 64-colour preview")` and no element-ignore; `allowsHitTesting(false)` alone does not satisfy it. **Fix:** add `.accessibilityLabel(…)` + `.accessibilityElement(children: .ignore)`.
- **`CellSprite.swift:98` — gear geometry not against `CellShapes.gear`.** Laws #1 / #5 / §6.4. Hand-rolled midpoint-circle closure rather than the spec `CellIcon(mask: CellShapes.gear(box:24))`; unpinned by any golden. **Fix:** swap to `CellIcon` when `CellShapes` ships; pin with a `Spec.CellShapes` golden.
- **`Shaders.metal:678` — VoxelCubeView face-multiply mismatch (doc-vs-code).** Law #2. Kernel ships side=0.82 / front=0.90 / top=1.0; `SIXFOUR-VOXEL-CUBE.md` §C2 specifies side=0.70 / front=0.85 / top=1.0. All three are discrete opaque steps (the no-continuous-shading mandate is met) — this is a numeric reconciliation, not a contract break, and is unpinned (no `Spec.*` golden). **Fix:** reconcile code↔doc (owner decides canonical values) before RULE-CUBE-ISO goldens are written.

> **Verifier scope notes (not drifts).** `CameraPreview.opacity(0)` (`CaptureView.swift:90`) is the structural tap-to-focus / AVCaptureSession passthrough layer — a functional invisibility mechanism, not a shaded data cell — and is correctly exempt. `SFTheme.gifSideCells` passed *as a cell count* to `GlobalLattice.pt()` (`:83`) is correct single-owner use. The Review/palette GIF canvas at 6 pt pitch (`GIFReviewView`, `PaletteCloudView`) is EXEMPT-REVIEW-PITCH / EXEMPT-GLASS-REVIEW and out of HUD scope. `bannerText()` (`CaptureView.swift:222–230`, opaque `CellText` over `Color(srgb8: SFTheme.ledGhost)`) is the conformant pattern these fixes target. `CellField.swift` itself is conformant (201×437, α=255 opaque, `GlobalLattice` throughout). `frameIndex()` (`PixelGrid.swift:34`) is correctly implemented and used by Review views — the drift is only that the capture-HUD ring does not wire into it.

> **Law-attribution corrections folded in.** Several findings originally mislabelled opacity/RETIRE-token violations as "Law #5" or "Law #6" (cell-math/dimension laws). The governing rules for opacity inks and retired tokens are **Law #2** (opacity forbidden on a cell) and **§6.10/§9.8** (retirement). This matters for tooling: `LINT-SINGLE-PITCH` (Law #5) and `LINT-DRAW-VOCAB`/RETIRE (Law #2/§6.10) are *different* lint passes. The ledger above uses the corrected attributions.

---

## 5. Cardinal-Law status (#1–#8)

Each law's overall state is derived from the elements whose traces depend on it.

| Law | Statement | Owner artifact | Overall state |
|---|---|---|---|
| **#1** ONE CELL SIZE | 2 pt cell everywhere; widgets grow by more cells, never bigger cells | `GlobalLattice.cellPt = 2` ← `Spec.Lattice` | ⚠️ partial — `Spec.Lattice` ships + shutter on-ladder/closure proven; residual: `CellText` glyph register ad-hoc + `CellSelector` still UIKit (Phase 3b) |
| **#2** GRID IS THE RENDER SURFACE | flat opaque indexed cells; no glass/opacity/AA/rounding on the HUD | `CellField`, `ledGhost` opaque token; `LINT-DRAW-VOCAB` | ✅ RESOLVED & ENFORCED on the capture HUD (lint fails the build on drift); residual: `StateScreens` full-screen views are a different surface (later) |
| **#3** ONE PITCH PER SCREEN | 2 pt HUD lattice and 6 pt Review pitch never share a screen | `GlobalLattice` (2 pt) vs `SFTheme.gifCellPt` (6 pt), EXEMPT-REVIEW-PITCH | ✅ honored — no cross-screen pitch mixing observed |
| **#4** ONE CLOCK | one `frameIndex(…,20,64)`; Pass A static bake / Pass B animate only | `frameIndex()` (`PixelGrid.swift:34`); `setCell` ✓ (`CellField.swift`) | ◐ primitive shipped — `setCell`/`CellChrome` bake + demo exist; the live HUD migration onto Pass-A is gated on the §7.1 band-map wordmark/gear overlap + `CellFont` text masters (a perf opt, not a conformance gap) |
| **#5** ONE OWNER FOR CELL MATH | all `cells→pt` via `GlobalLattice.pt()`; no view computes `×cellPt` | `GlobalLattice` ← `Spec.Lattice` (verified facade) | ✅ RESOLVED — numbers live in Haskell; all HUD literals via `pt()`; `previewCells`/`segmentCells`/`wordmarkRows` added; LINT-SINGLE-PITCH enforces |
| **#6** EVERY DIMENSION A CELL COUNT | every governed chrome dim an integer cell count via the owner | `GlobalLattice` cell-count constants | ✅ RESOLVED on the HUD — all spacing via `pt()`, shutter closure proven `15·2+2·2=34`; residual: UIKit-sized Settings selector (Phase 3b) |
| **#7** PIXEL LOOK IS UNIVERSAL (incl. 3D) | RULE-CUBE-ISO: orthographic, NN, flat opaque voxels; face-on == 2D GIF | `VoxelCubeView` + `Shaders.metal` | ⚠️ drift (low) — only the face-multiply doc-vs-code mismatch; flatness/no-AA/no-alpha contract met |
| **#8** NOTHING SHIPS WITHOUT A GOLDEN | every dim golden-pinned by `cabal test`; the Swift mirrors `Spec.Lattice`/`CellShapes` | `Spec.Lattice` ✓ / `Spec.CellShapes` ✓ / `Spec.CellFont` [PLANNED] | ⚠️ partial — 2 of 3 modules ship + are `cabal test`/codegen-drift/LINT-GOLDEN enforced; residual: `Spec.CellFont` absent (Phase 3b) |

*(Cardinal Law #3 is the one law no element's trace was found to break — but it is honored by separation of surfaces, not yet proven by a `Spec.*` golden, so the system remains author-memory-enforced until Law #8's gate ships.)*

---

## 6. How to re-map (repeatable procedure)

Run these from the repo root `/Users/daniel/SixFour`. The map is "green" for an element only when every grep below returns no hit on its trace **and** the golden modules exist and `cabal test` passes.

### 6.1 Lint the capture HUD (Law #2 — closed drawing vocabulary)

```bash
CAP=SixFour/UI/Screens/Capture/CaptureView.swift

# (a) opacity on a HUD cell — must be ZERO hits
grep -nE '\.opacity\(|\.white\.opacity|dimText|hairline' "$CAP"

# (b) glass material on the HUD — must be ZERO hits
grep -nE 'Glass(InfoChip|IconButton|ToolbarCluster)|glassEffect|cardCorner' "$CAP"

# (c) raw SwiftUI primitives on the HUD — Text/RoundedRectangle must be ZERO
grep -nE '\bText\(|RoundedRectangle|\.background\(\.|\.fill\(\.white' "$CAP"
```

### 6.2 Lint the bare-point bypass (Laws #5 / #6 — single owner)

```bash
# Any spacing:/padding(/frame( with a RAW number (not GlobalLattice.pt(…)) is a drift.
# Safe-area / OS values are the only legitimate raw pt — inspect each hit.
grep -nE '(spacing|padding|frame)\([^)]*[0-9]' SixFour/UI/Screens/Capture/CaptureView.swift \
  | grep -v 'GlobalLattice.pt'

# Confirm GlobalLattice is the SOLE place a cell count becomes points:
grep -rn '\* *GlobalLattice.cellPt\|\* *cellPt\|\* *2 *//' SixFour/UI \
  | grep -v 'GlobalLattice.swift'   # any hit outside GlobalLattice.swift = Law #5 break
```

### 6.3 Confirm the cube tokens are owned (Law #5)

```bash
# Every widget cell-count must be declared in GlobalLattice, not invented at the call site:
grep -nE 'previewCells|wordmarkRows|segmentCells|gutterCells|touchFloorCells|shutterCells|controlCells|ringCells|ringTicks' \
  SixFour/UI/GlobalLattice.swift
# Then grep the call sites for bare literals that SHOULD be these constants:
grep -rnE 'rows: *[0-9]+|cells: *[0-9]+' SixFour/UI/Screens/Capture/CaptureView.swift
```

### 6.4 Confirm the primitive layer exists (§5 / Laws #1, #4)

```bash
# These must all return a `struct … : View` definition once built. Empty = ◷ planned.
for t in CellGlyph CellFont CellIcon CellButton CellSelector CellRing; do
  printf '%s: ' "$t"; grep -rl "struct $t" SixFour/UI || echo 'ABSENT [PLANNED]'
done
# setCell (Pass-A byte writer) for Law #4:
grep -rn 'func setCell' SixFour/UI || echo 'setCell ABSENT [PLANNED]'
```

### 6.5 Confirm the golden gate exists (Law #8)

```bash
ls spec/src/SixFour/Spec/Lattice.hs spec/src/SixFour/Spec/CellShapes.hs spec/src/SixFour/Spec/CellFont.hs 2>&1
grep -nE 'Spec\.(Lattice|CellShapes|CellFont)' spec/spec.cabal || echo 'golden modules NOT exposed'
# When they exist, the gate is the test pass itself:
( cd spec && cabal test )    # must be green before any chrome dimension is "shipped"
```

### 6.6 Confirm the one-clock discipline (Law #4)

```bash
# Animated chrome must read frameIndex(…,20,64); the ring must not free-run on sceneGauge.
grep -rn 'frameIndex\|TimelineView' SixFour/UI/Screens/Capture/CaptureView.swift \
  || echo 'no clock wired into capture HUD — Pass-B ring is off-clock'
```

### 6.7 Confirm the 3D look (Law #7 / RULE-CUBE-ISO)

```bash
# Orthographic + nearest + the documented face-multiply triple.
grep -nE 'filter::nearest|ART_RES|float face *=' SixFour/Metal/Shaders.metal
# Reconcile the face-multiply triple against SIXFOUR-VOXEL-CUBE.md §C2 (currently side/front mismatch).
```

### 6.8 Regenerate the map

For each of the 14 elements: walk §2's row, run the relevant grep block (§6.1–6.7) against the cited lines, set the row's status (✅ if all clean + golden present, ⚠️ if any grep hits, ◷ if the primitive is ABSENT, ✗ if the element is unimplemented), and move every fresh `confirmed=true` hit into §4 under its severity. Recompute the §1 scoreboard from the row statuses, and recompute the Cardinal-Law table (§5) from which laws still have any ⚠️ element depending on them. An element flips to ✅ only when **all** its grep lints are clean **and** its backing `Spec.*` golden exists and `cabal test` is green — until Law #8's gate ships, no element on the capture HUD can legitimately be marked ✅.
