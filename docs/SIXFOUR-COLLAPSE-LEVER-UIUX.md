# SixFour — The Collapse Lever: UI/UX Plan (2⁸/4⁴/16² grids → one palette → 16³/64³/256³ GIFs)

> Keywords: collapse lever, radix grid, 16²/4⁴/2⁸, cut-level slider, 16³ preview, 64³ hero, 256³ export,
> PaletteBranching, BranchedPalette.projectQ16, cell-field law, ColorIdentity, Surface FSM.

**Status:** UI/UX plan (2026-06-08). Gate before writing the collapse-lever spec. Companion to
`SIXFOUR-PALETTE-IS-MOTION-WORKFLOW.md` (the math) and `SIXFOUR-JEPA-256-SUPERRES-WORKFLOW.md` (the renders).
**SixFour owns all code.** Determinism is the decision — so the user steers via UI controls, not an NN.

This plan answers: **(1)** how `2⁸/4⁴/16²` live in the UI grid cells, and **(2)** what buttons/sliders
surface so the user can *collapse* the 64 per-frame palettes + 64³ voxels into **one** global palette, see
a **16³ GIF** of the simplified result, and emit the **64³ + 256³** GIFs from that one palette.

---

## 0. The control model — two ORTHOGONAL axes (do not conflate)

The whole lever is two knobs. Keep them separate in the UI, because they are different mathematical axes
(this is the resolution-funnel-vs-palette-radix distinction from the prior docs):

| Axis | What it picks | Range | Backing |
|---|---|---|---|
| **A. Palette TREE** | *which factorization* groups the 256 colors | `16² / 4⁴ / 2⁸` | `PaletteBranching {b16,b4,b2}` (**built**, persisted in `AppSettings.paletteBranching`) |
| **B. Cut LEVEL** | *how deep* to collapse that tree | `0 … depth` (16²→2, 4⁴→4, 2⁸→8) | `SplitTree.view(branching).collapse(collapseK)` (**built**, needs a slider) |

`(tree, cut)` → **one global palette**. Per the motion doc: raising the cut folds *more* color-motion into
the static palette (calmer); lowering it keeps more as live residual. **The cut slider IS the
motion-bandwidth control**, surfaced.

> One palette, three resolutions. The collapsed palette feeds **all three** renders — `16³` preview, `64³`
> hero, `256³` export — so what the user sees at `16³` is honestly the same palette they ship at `256³`.

---

## 1. Question 1 — how `2⁸/4⁴/16²` live in the grid cells

Each factorization is **a different way to lay the same 256 colors into cells**, and a different way to
*cut* (collapse). All three render into the ONE cell-field law (`CellField`/`CellSprite`, `View.place`,
golden `Spec.GridLayout`). The three genome projections already exist byte-exact
(`BranchedPalette.projectQ16`, `GenomeFixedGolden.swift`):

| Radix | Cell layout | Cut-level meaning | Status |
|---|---|---|---|
| **16²** = 16×16 flat | 256 cells in a 16×16 grid (rank-sorted) | median-cut depth: cut k → 4^k super-cells | `PaletteGridView` **BUILT, golden** (`PaletteGridView.swift:16`) |
| **4⁴** = nested 4×4 | a 4×4 of 4×4 (depth-4 quaternary drill); each level = one opponent split | cut k → keep k of 4 levels | `Quad4` genome **BUILT** (`BranchedPalette.swift:126`); **`Quad4DrillView` TO BUILD** |
| **2⁸** = depth-8 binary | 8 binary wheels / a Haar cascade; each level halves | cut k → keep k of 8 σ-levels | σ-pair genome + Zig `s4_haar` **BUILT**; **8-wheel picker TO BUILD** (was `AddressPickerView`, removed) |

**Visual law (all three):** cells *below* the cut render their own color; cells *above* the cut render
their **parent's merged color** — so the grid literally *shows the collapse*: drag the cut up and watch
cells fuse into fewer, larger color blocks. This reuses `CellSprite`'s closure `(col,row)->color` with the
color resolved by `SplitTree.view(branching).collapse(cut)`.

**Why three trees, not one:** they give different *kinds* of authoring. `16²` = a flat painter's grid
(matches the shipped 16×16). `4⁴` = opponent-quadrant drill (warm/cool, light/dark splits — the R,G,B,T
mixer). `2⁸` = the finest octave-by-octave Haar control. Same 256 leaves, three bases (wavelet-packet
"library of bases"); the cut point differs, the finest resolution is identical.

---

## 2. Question 2 — the controls and the three GIFs

### 2.1 The collapse lever (Review phase)
Two controls in the Review action row (`ReviewPhaseField.swift:136`), beside the existing branching
selector:

1. **Tree selector** — 3-way `CellSelector` over `PaletteBranching.allCases` (**already synced** to the
   treemap). Picks `16²/4⁴/2⁸`.
2. **Cut-level slider** — NEW. A cell-rendered slider (per `SIXFOUR-TOTAL-PIXELATION` — chrome is cells,
   not SwiftUI `Slider`). Range = `0…tree.depth`. Drives `collapseK`.

Both write to `AppSettings`; both trigger a **live 16³ preview** re-render (cheap) and gate a **64³/256³
re-render** behind an explicit **"Apply"** (expensive, FSM stage).

### 2.2 The 16³ preview GIF — the "simplified version", live
- **What:** a small looping GIF, **16×16 spatial × 16 frames**, rendered from the **collapsed palette** —
  the fast, honest proxy of "what your simplification looks like." Updates *live* as the cut slider moves
  (no re-encode; pure projection @20fps via the `SurfaceClock`).
- **How (reuse):** add `ColorIdentity.previewSmall16` to the movable-widget system
  (`MovableColorWidget.swift` + `Spec.MovableLayout` codegen). Render a `CellSprite` whose closure reads a
  **deterministic 16³ downsample** of `surface.indexCube` (4× spatial decimation + 4× temporal stride)
  mapped through the **one collapsed palette**. Place/move with the proven `region(for:at:)` + `.movable()`.
- **Why 16³:** it is the *coarse rung* of the resolution funnel — small enough to recompute every slider
  tick, honest because it uses the exact shipping palette. This is the user's "16×16×16 GIF playing."

### 2.3 The 64³ hero — already shipped
- The GIFA Review hero (`ReviewPhaseField.swift:85`, `CellSprite` over `surface.gifCell`). On **Apply**,
  re-run `DeterministicRenderer.renderGlobalPalette(tiles, branching:, cut:)` (the genome already routes
  through `BranchedPalette.projectQ16` at `DeterministicRenderer.swift:363`). Add a **Share 64³** button
  (reuse the existing Share pattern, `ReviewPhaseField.swift:137`).

### 2.4 The 256³ export — from the one global palette
- **Phase-0 (ship first): index replication.** `replicate4x(indices, side:64) -> 256²` per frame +
  4× temporal = `256³`, then `GIFEncoder(256,256)`. **Byte-safe: no re-quantize, palette unchanged** — the
  256³ GIF uses the *same* collapsed palette as the 16³ preview and 64³ hero. (Spec `Spec.Export`, designed;
  **TO BUILD**.) Container note: a true `256×256×256` exceeds GIF's practical size; ship `256²×256f` as
  APNG/HEVC or down-sample, per the super-res doc §4.3.
- **Phase-1 (quality upgrade): OT/flux super-res.** Replace naive replication with the deterministic
  displacement-interpolation (color) + flux-advection (space) from the motion doc. Same UI button; better
  pixels. Gated behind a measured win.

### 2.5 Scope toggle (free win, currently a seam)
`paletteScope {.global,.perFrame}` is routed but has **no UI**. Surface it as a 2-cell toggle in Review:
`per-frame` (64 palettes, GIFA) vs `global` (the collapsed one, GIFB). This is the literal
"collapse 64 palettes → 1" switch the user asked for.

---

## 3. The flow (Surface FSM)

```
Review (σ.phase=.review)
  ├─ hero:        64³ GIFA           (CellSprite over surface.gifCell)           [BUILT]
  ├─ radix grid:  16²/4⁴/2⁸ cells    (collapse shown by cell-fusion at cut)      [16² built; 4⁴/2⁸ to build]
  ├─ tree sel:    PaletteBranching    (CellSelector)                              [BUILT, sync’d]
  ├─ cut slider:  0…depth → collapseK (cell slider)                              [TO BUILD]
  ├─ preview:     16³ GIF, live       (ColorIdentity.previewSmall16)             [TO BUILD, small]
  ├─ scope:       per-frame|global    (2-cell toggle)                            [seam → wire]
  └─ actions:     [Apply 64³] [Share 64³] [Export 256³]
        Apply   → σ.step(.applyGenome) → renderGlobalPalette(branching,cut) → hero updates   [wire FSM]
        Export  → replicate4x → GIFEncoder(256,256) → Share sheet                             [TO BUILD]

Slider drag (cheap): recompute collapsed palette → 16³ preview re-projects live. NO 64³/256³ re-render.
Apply (expensive):   FSM rendering stage re-encodes 64³; Export emits 256³. Both from the SAME palette.
```

`★ The single source of truth:` the collapsed palette computed by `(tree, cut)` is computed **once** and
fed to all three resolutions. The 16³ is not a separate artifact — it is the 64³ cube viewed coarsely
through the identical palette. That is what makes the preview *honest*.

---

## 4. Build ledger (reuse-first)

| Piece | Reuse | New work |
|---|---|---|
| Tree selector | `PaletteBranching`, `CellSelector`, treemap sync | place in Review action row |
| **Cut-level slider** | `SplitTree.view().collapse(collapseK)` | cell-rendered slider + `AppSettings.collapseCut` |
| **16² grid (collapse-shown)** | `PaletteGridView` (golden) | tint cells by cut (parent-merge) |
| **4⁴ drill view** | `Quad4` genome (byte-exact) | `Quad4DrillView` (4×4-of-4×4) |
| **2⁸ wheel/cascade view** | σ-pair genome + Zig `s4_haar` | 8-level binary picker (re-add AddressPicker-style) |
| **16³ live preview** | `CellSprite`, `region/movable`, `SurfaceClock` | `ColorIdentity.previewSmall16` + `s4`/Swift 16³ downsample |
| 64³ hero re-render | `DeterministicRenderer.renderGlobalPalette(branching:)` | `.applyGenome` FSM event + cut param |
| **256³ export** | `GIFEncoder`, index domain | `replicate4x` (Phase 0) → OT/flux super-res (Phase 1) |
| Scope toggle | `paletteScope` (routed) | 2-cell toggle UI |

---

## 5. Specs to write (the math↔UI contracts)

Spec-first per `SIXFOUR-SPEC-METHODOLOGY.md` — Haskell oracle → golden → Swift/Zig. Order:

1. **`Spec.CollapseLever`** (keystone, write first): `(tree ∈ {b16,b4,b2}, cut ∈ [0..depth])` →
   surviving-color set + per-frame reindex map. Laws: monotone (higher cut ⇒ ≤ colors), idempotent at a
   level, refines existing `Spec.Collapse` + `Spec.SplitTree`, `cut=0` ⇒ root color, `cut=depth` ⇒ full
   256. Golden-pinned against the three `BranchedPalette.projectQ16` genomes.
2. **`Spec.PreviewProxy`**: deterministic `64³ → 16³` downsample (4× spatial decimation + 4× temporal
   stride) through the collapsed palette. Law: re-projecting the preview never re-quantizes (palette-exact).
3. **`Spec.Export`**: `64³ → 256³` index `replicate4x` (Phase 0, byte-exact, palette-invariant), with a
   hook for the OT/flux super-res (Phase 1).

---

## 6. Honest gaps
- `4⁴` and `2⁸` *authoring views* are TO BUILD (the genomes exist; the cell-grid drill/wheel UIs don't).
- The cut-level slider is new chrome — must be **cell-rendered** (pixelation law), not SwiftUI `Slider`.
- `256×256×256` true GIF is impractical (size + 256-color cap); ship `256²×256f` in a non-GIF container or
  down-sample back to `64³` for the legacy GIF surface (super-res doc §4.3).
- The 16³ preview's *spatial* downsample is naive decimation in Phase 0; the OT-coherent downsample is a
  Phase-1 upgrade (same as the export's two phases).
