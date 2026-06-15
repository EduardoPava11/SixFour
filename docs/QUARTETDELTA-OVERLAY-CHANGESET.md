# QuartetDelta Review Motion-Overlay — Implementation Change-Set Map

Scope: three traced targets, ordered by priority. Part 1 (the QuartetDelta Act-II
Review motion overlay) is the real build; Parts 2–3 are verification-gate
confirms. Conservative, reuse-first: **no new files**, every change lands in an
existing module.

---

## Map orientation — where these targets sit on the spec map

Start any exploration at `SixFour.Spec.Map` (the categorised index). The three
targets land in three categories:

| Target | Spec module | `Spec.Map` category | Import-graph position |
|---|---|---|---|
| **Part 1** QuartetDelta overlay | `Spec.QuartetDelta` | **Cat 5** "The authoring STORY (Acts I–IV)" — **Act II, `4⁴` quartet core** (doc `docs/SIXFOUR-PALETTE-STORY-WORKFLOW.md`) | single-dependency **leaf**: OUT = imports only `Spec.Color`; IN = `Spec.HaarRibbon` (Act III consumes `coreColors` as its protect-set) + `Codegen.QuartetDelta` (emits `QuartetDeltaGolden.swift`) |
| **Part 2** Dither gate | `Spec.Dither` | **Cat 6** "Dither & index encoding" | OUT = `Spec.Color`, `Spec.PairTree`; IN = `Spec.Scale` (the 64³ spec-gif harness pulls in the dither realizer) |
| **Part 3** Scale gate | `Spec.Scale` | **Cat ★** "The core: the NN design" (all-layers-at-64³ harness) | heavy **hub leaf**: OUT = `Color,Cyclic,Dither,GMM,Indices,Layer,LookCore,LookNet,PairTree,Palette`; IN = none from Spec (only `app/Gif.hs` render guard + `test/Properties/Scale.hs`) |

Act-line neighbours of Part 1: `StageA` (Act I, 16²) → **QuartetDelta (Act II)**
→ `HaarRibbon` (Act III, 2⁸) → `Export` (Act IV) → `Upscale256` (Act IV 256³).

**How the spec is the app map here:** `Spec.QuartetDelta` is the byte-exact
source of truth for the overlay's core/motion classification math
(`toSlots`/`slotDisplacement`/`coreColors`/`corenessRanked`), the Swift port
mirrors it 1:1 (`SixFour/Palette/QuartetDelta.swift`), and the golden
(`QuartetDeltaGolden.swift`) pins the rule so the SwiftUI view can never
hand-roll un-gated classification math. The view is pure projection: it calls
the proven functions and only decides *colour per cell*.

---

## Part 1 — QuartetDelta Review motion overlay (PRIORITY 1)

**Intent:** in Review, toggle an overlay that recolours the existing 16² palette
strip so **core** (low-displacement) quartet slots stay full-colour and
**motion** (high-displacement) slots recede — a cell-colour brightness split, no
strokes, no text. The quartet is the **fixed** frames `[0,21,42,63]`.

### Data path
```
surface.palettesPerFrame
  → pick fixed frames [0,21,42,63]  (filter $0 < count; need exactly 4)
  → each frame's 256 sRGB8 SIMD3<UInt8>
  → ColorScience.srgb8ToOKLab(r,g,b).simd  (SIMD3<Float>)
  → SIMD3<Double>(...)                       (lossless widen)
  → QuartetDelta.toSlots([f0,f21,f42,f63])   → 256 four-sample trajectories
  → thr = QuartetDelta.medianDisplacementThreshold(slots)   [NEW spec fn, recomputed per run]
  → core = Set(QuartetDelta.coreColors(thr, slots))          → Set<Int> in ORIGINAL slot order
  → permute to grid-rank order to match paletteStrip's `ordered`
  → in the existing CellSprite closure:
        core cell  → ordered[rank]                 (full colour)
        motion cell→ Self.darkenCell(ordered[rank]) (receded, GRID Law #2)
Toggle: motionOutlineOn in actionRow.
```

### Spec + codegen side (do FIRST — golden is the contract)

The relative-threshold rule (median displacement) currently lives **only inside**
`Codegen.QuartetDelta` as a fixture-construction detail. Promote it to one named,
lawful, golden-gated spec function so the emitter and the Swift port share it.

1. **`spec/src/SixFour/Spec/QuartetDelta.hs`**
   - *Anchor:* export list "The core outline" section (~L34–36, after
     `corenessRanked`, `coreColors`); function body after `coreColors`.
   - *Change:* add and export
     ```haskell
     -- | The median per-slot displacement; the relative core/motion cut used by
     -- the Review overlay and the golden — guarantees a non-trivial split.
     medianDisplacementThreshold :: [QSlot] -> Double
     medianDisplacementThreshold ss =
       let ds = sort (map slotDisplacement ss)
       in if null ds then 0 else ds !! (length ds `div` 2)
     ```
     This is the exact expression the emitter inlines today
     (`Codegen/QuartetDelta.hs:88–90`), promoted verbatim.
   - *Optional (keep light, Layers 0–2):* one law
     `lawMedianSplitsNonTrivially` in `Properties.QuartetDelta` — when
     displacements differ, the median keeps ≥1 slot and drops ≥1.

2. **`spec/src/SixFour/Codegen/QuartetDelta.hs`**
   - *Anchor:* import list (~L31) and the `where`-block `thr` binding
     (verified at **L88–90**).
   - *Change:* import `medianDisplacementThreshold`; replace the inline
     `disps = sort (...)` / `thr = disps !! (length disps `div` 2)` with
     `thr = medianDisplacementThreshold slots`. Emitted Swift shape unchanged;
     `coreThreshold` becomes the **output of the spec fn** (now golden-gated, not
     a codegen-private literal). The literal value is unchanged
     (**`1.7641107133386333`**) — confirm with `git diff` that only the
     provenance moved.

### Swift port (1:1 mirror)

3. **`SixFour/Palette/QuartetDelta.swift`**
   - *Anchor:* inside `enum QuartetDelta`, after `corenessRanked` (verified at
     **L55–59**), before `coreColors` (**L63**).
   - *Change:* add the only new Swift symbol the overlay needs —
     ```swift
     /// Median per-slot displacement — the relative core/motion cut (mirrors
     /// Spec.QuartetDelta.medianDisplacementThreshold). Recomputed per run.
     static func medianDisplacementThreshold(_ slots: [[SIMD3<Double>]]) -> Double {
         let ds = slots.map { slotDisplacement($0) }.sorted()
         return ds.isEmpty ? 0 : ds[ds.count / 2]
     }
     ```
   - `corenessRanked` (L55) and `coreColors` (L63) **already exist** — call them,
     do not rewrite.

4. **`SixFourTests/QuartetDeltaGoldenTests.swift`**
   - *Anchor:* new `@Test` after `coreColorsMatchGolden` (~L65).
   - *Change:* `medianThresholdMatchesGolden` —
     `QuartetDelta.medianDisplacementThreshold(toSlots(palettes)) ≈
     QuartetDeltaGolden.coreThreshold` within tol. Pins the Swift threshold port
     against the spec-emitted value so the overlay's runtime rule cannot drift.

### Swift view seam (`SixFour/UI/Surface/ReviewPhaseField.swift`)

5. **State toggle** — *anchor:* after `@State private var rungPickerOpen = false`
   (~L56). Add `@State private var motionOutlineOn = false`. Same view-local
   sub-state pattern as `rungPickerOpen`/`groupPickOpen`; resets on retake when
   the field leaves the hierarchy. **No new ColorIdentity, no movable-widget
   identity → no MoveContract/codegen regen.**

6. **Core-set computation** — *anchor:* new `private var motionCoreSet: Set<Int>`
   placed after `paletteStrip` (~L165), before `// MARK: - Actions`.
   - `let idx = [0,21,42,63].filter { $0 < surface.palettesPerFrame.count }`;
     guard `idx.count == 4`.
   - Map each picked frame's 256 sRGB8 → OKLab Double:
     `SIMD3<Double>(ColorScience.srgb8ToOKLab(c.x,c.y,c.z).simd)`.
   - `let slots = QuartetDelta.toSlots(fourFrames)`;
     `let thr = QuartetDelta.medianDisplacementThreshold(slots)`;
     `return Set(QuartetDelta.coreColors(thr, slots))`.
   - **Cursor-INDEPENDENT** (the quartet is fixed 0/21/42/63), so this is
     computed once per clip, not per cursor frame.
   - Doc-comment tying it to `Spec.QuartetDelta` Act II.

7. **Recolour the strip** — *anchor:* the body of `paletteStrip` (verified at
   **L153–165**), keeping signature `private var paletteStrip: some View`.
   - Keep the existing `ghost`/`frame`/`padded`/`ordered` build **verbatim**
     (L154–158).
   - **Index-basis fix (most likely defect):** `paletteStrip` builds `ordered`
     via `GridScript.capture(side: 16).surfaceColors(palette: padded)` (L158),
     which permutes the 256 colour payloads into grid-rank order;
     `coreColors`/`motionCoreSet` returns indices in **original slot order**. To
     mark the right cells, permute. Cleanest: build a length-256
     `isCore: [Bool]` indexed by original slot, then permute it through the SAME
     `GridScript.capture(side:16)` ordering used for the colours — i.e. feed an
     index payload through `surfaceColors` so `orderedCore[rank]` aligns
     cell-for-cell with `ordered[rank]`.
   - Inside the existing `CellSprite { c, r in let rank = r*16+c; ... }` closure,
     gate strictly on the flag:
     ```swift
     guard motionOutlineOn else { return rank < ordered.count ? ordered[rank] : ghost }
     let base = rank < ordered.count ? ordered[rank] : ghost
     return orderedCore[rank] ? base : Self.darkenCell(base)
     ```
   - Same grid, same pitch (`GlobalLattice.gifPx`), same order → cell-for-cell
     alignment. With `motionOutlineOn == false` the closure is **byte-identical**
     to current.

8. **Toggle button** — *anchor:* inside `actionRow` HStack, after the `Groups`
   button (~L249).
   - ```swift
     Button { motionOutlineOn.toggle() } label: {
         CellActionButton(icon: .grid3x3, title: "Motion")
     }
     .buttonStyle(.plain)
     .accessibilityLabel("Outline motion vs core colours")
     ```
   - Lives in the **immovable bottom chrome** action row (reuse `CellActionButton`
     like Groups/Atlas/Retake). It modulates how `paletteStrip` paints — it is
     **not** a movable widget. `.grid3x3` already exists in the CellIcon set; a
     dedicated motion glyph is optional polish.

### Helpers to reuse (do NOT rewrite)
- `QuartetDelta.toSlots` (`SixFour/Palette/QuartetDelta.swift:21`),
  `slotDisplacement` (`:36`), `corenessRanked` (`:55`), `coreColors` (`:63`),
  `slotMean` (`:41`), `quartetCore` (`:47`).
- `ReviewPhaseField.darkenCell` (`:373`, static, opaque 35% darken, GRID
  Law #2 — the same recede the group-pick tool uses at `:316`).
- `ColorScience.srgb8ToOKLab` (`SixFour/Color/ColorScience.swift:66`) + `OKLab.simd`
  (`:9`) for the sRGB8→OKLab bridge (same call pattern as
  `PaletteGridView.swift:57` / `PaletteTreeView.swift:50`).
- The existing `paletteStrip` `CellSprite` + `GridScript.capture(side:16)`
  ordering (`:158`) — overlay is the SAME view, recoloured.

### Cell-field-law constraints
- The cue MUST be **cell colour only** (brightness split via `darkenCell`). **No**
  SwiftUI outline/stroke/border, **no** `Text`, **no** SF-Symbol. A "true"
  outline, if wanted later, is a ring of darkened/lit CELLS — the brightness
  split is the law-safe MVP.
- The toggle is cell-native (`CellActionButton`), in the immovable action row.
- Default screen (`motionOutlineOn == false`) is byte-identical — gate the
  recolour strictly on the flag.

---

## Part 2 — Dither gate (PRIORITY 2a)

`Spec.Dither` (Cat 6) is consumed by `Spec.Scale`'s 64³ spec-gif harness
(the Scale↔Dither coupling). The dither math
(`ditheredColor`/`realize`/`temporalMean`, laws `lawDitheredColorConvex` /
`lawDitherMeanRecoversP` / `lawVarianceMaxAtHalf` in `Properties.Dither`) is
already lawful and gated. **It is exercised at the real 64³ transitively through
Part 3** (`layerLawReport`'s L9 "Dither: temporal mean recovers p" over
`p ∈ {0.25, 0.382, 0.5, 0.75}`). No standalone code change is required for this
target — the Dither contract is already pinned both by `Properties.Dither`
(unit laws) and by the Scale harness (64³ in-situ). Checklist:

1. **CONFIRM** `Properties.Dither` runs in `cabal test` (no edit).
2. **CONFIRM** the L9 dither contract appears in `layerLawReport` and is asserted
   by Part 3's seed gate (no edit).

---

## Part 3 — Scale gate (PRIORITY 2b) — **NO-OP / CONFIRM**

**Finding: already done.** The briefing's premise ("only asserted inside the
spec-gif exe render guard") is FALSE. `Properties.Scale` already HARD-asserts the
64³ all-layers proof over **3 seeds** as a standing `cabal-test` gate.

As-built (`spec/test/Properties/Scale.hs`, 33 lines):
- `seeds = [1,2,7]` (≥3 distinct 64³ captures ✓).
- three `testProperty "all layer contracts hold at 64^3 (seed N)" $ once $`
  `let fails = failingLayers (fromIntegral s) in counterexample (...) (null fails)`
  — evaluating `synthLookInput @64 @64 @64 @256` at the real `scaleT/H/W/K`.
- a 4th snapshot `testProperty "layer-law report snapshot (seed 1)"` over
  `all snd (layerLawReport 1)`.
- Listed in `spec/spec.cabal` test-suite `other-modules` (L331) and dispatched
  from `test/Spec.hs`.

Checklist:
1. **CONFIRM** the `Scale (the spec holds for ALL layers at the real 64³)` group
   passes in `cabal test` (no edit).
2. **CONFIRM** `Properties.Scale` is in `spec.cabal` `other-modules` (L331) — it
   is (no edit).
3. **OPTIONAL, only if a code delta is mandated** (neither closes a gap):
   - (a) add `allLayersHold` to the import list and assert it by name beside
     `null fails` (`allLayersHold = null . failingLayers`, so already covered);
   - (b) widen `seeds` to e.g. `[1,2,7,13,42]` — heavy (full 64³ pipeline per
     seed → slower CI).
4. **Do NOT** touch `Scale`'s `import SixFour.Spec.Dither` — Scale feeds
   `app/Gif.hs`'s render guard; adding no consumers keeps spec-gif green.

---

## Verification recipe

### Part 1 (spec + Swift, golden changes)
```bash
cd spec
cabal build && cabal test          # Properties.QuartetDelta laws + new median law
cabal run spec-codegen             # regen QuartetDeltaGolden.swift
git diff -- SixFour/Generated/QuartetDeltaGolden.swift
#   EXPECT: only coreThreshold PROVENANCE changed; literal 1.7641107133386333 UNCHANGED
spec/scripts/spec-docs.sh          # Map lint passes (same module, no new Map line);
                                   #   new exported fn needs its -- | doc to stay Haddock-clean
cd ..
xcodegen generate
xcodebuild -scheme SixFour -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build
#   BUILD SUCCEEDED is the bar (camera app: compile-check only, never run — sim has no camera)
#   run SixFourTests/QuartetDeltaGoldenTests → medianThresholdMatchesGolden must pass
#   confirm motionOutlineOn=false leaves paletteStrip byte-identical to current
```
**Pinned by:** `SixFour/Generated/QuartetDeltaGolden.swift` (via
`SixFourTests/QuartetDeltaGoldenTests.swift`: `slotDisplacementsMatchGolden`,
`coreColorsMatchGolden`, + new `medianThresholdMatchesGolden`).

### Part 2 (Dither) — no golden change
```bash
cd spec && cabal test    # Properties.Dither laws + (transitively) Scale L9 dither @64³
```
**Pinned by:** `Properties.Dither` unit laws + the L9 entry inside
`layerLawReport` (Part 3 seed gate).

### Part 3 (Scale) — no edit
```bash
cd spec && cabal test
#   group "Scale (the spec holds for ALL layers at the real 64³)":
#   3× "all layer contracts hold at 64^3 (seed 1|2|7)" + snapshot — all PASS
#   To prove it is a real gate: temporarily break one layer law → a seed assertion
#   FAILS with counterexample "failing layers: [...]". No codegen/Map/cabal edits.
```
**Pinned by:** `spec/test/Properties/Scale.hs` (`failingLayers`/`layerLawReport`
at real `scaleT/H/W/K=64³`).

---

## Open decisions (confirm before coding)

1. **Toggle placement** — recommended: bottom **immovable `actionRow`**
   (`CellActionButton`, alongside Groups/Atlas/Retake), because it modulates an
   existing widget's paint and must travel with the Review chrome. Alternative
   (defer): a per-widget long-press affordance. *Decision needed.*
2. **Threshold: recompute vs golden** — RESOLVED in this map: recompute per run
   via `medianDisplacementThreshold(slots)`. `QuartetDeltaGolden.coreThreshold`
   is fixture-bound to the synthetic LCG palettes and meaningless for real
   captures; the golden's role is to **pin the rule**, not supply the runtime
   number. *Confirm acceptance.*
3. **Core membership reading** — the quartet is 4 FIXED frames, so
   `motionCoreSet` is cursor-INDEPENDENT (computed once). But `paletteStrip`
   shows the **cursor frame's** colours, so a "core" slot is marked on whatever
   colour that slot holds at the current cursor (core membership is per-slot/
   global; the displayed colour breathes). *Confirm this is the intended reading.*
4. **Median vs draggable threshold** — ship median now (the existing, proven
   choice; matches `lawCoreMonotoneInThreshold`). A user-draggable percentile is
   a later Act-II UI lever — `coreColors` already takes an arbitrary `Double`, so
   no spec change is needed to add a slider later. *Defer.*
5. **Frame-count guard** — `[0,21,42,63]` assumes ≥64 frames. The overlay
   no-ops (renders normally) if fewer than 4 distinct frames exist. *Confirm the
   silent no-op is acceptable vs. disabling the toggle.*
