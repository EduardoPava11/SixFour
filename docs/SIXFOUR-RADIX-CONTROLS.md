# SixFour — Radix Controls (16²/4⁴/2⁸) = the NN Genome, tied to the Voxel Cube

> ▶ **CONSOLIDATED (2026-06-12):** architecture authority is now
> [`SIXFOUR-WIDGETS.md`](SIXFOUR-WIDGETS.md), which reframes 16²/4⁴/2⁸ as the
> **see / control / learn faces** of one tree (Family 2 — Delta Control). This doc
> remains the **file:line implementation map** for that family — keep using it for
> exact edit sites. SIXFOUR-WIDGETS wins on architecture/framing.

> Status legend used throughout: **[BUILT]** = in the shipped Swift/Haskell today;
> **[SPEC-ONLY]** = the Haskell spec has it but no Swift consumes it yet;
> **[TO BUILD]** = proposed, does not exist in any tier. This document is a
> design + build map; most of the genome↔collapse↔cube *wiring* is **[TO BUILD]**.
> Only display-side branching is wired today.

## 1. The unification (one tree, three radices, three genomes)

There is exactly **one** structure: a 256-leaf median-cut **SplitTree** built from
the collapsed pooled palette. **[BUILT, display path only]** — the Review editor
builds the tree once via `FarthestPointCollapse.collapseForDisplay(srgb8Frames:)`
(`PaletteCollapse.swift:120-133`), then `SplitTree.build(...)`
(`GlobalPaletteEditorView.swift:64-70`, `SplitTree.swift:70-84`), and every view
renders a *radix view* of that one tree via `tree.view(branching)`
(`GlobalPaletteEditorView.swift:37`, `PaletteTreeView` treemap).

The three "controls" are **radix views of the same tree** at different collapse
factors. **[BUILT]** The mapping is pinned on `PaletteBranching`
(`SplitTree.swift:38-61`):

| Radix | `factor` | `depth` | `collapseK` | Source |
|---|---|---|---|---|
| 16² (`b16`) | 16 | 2 | 4 | `SplitTree.swift:42-46` |
| 4⁴ (`b4`) | 4 | 4 | 2 | `SplitTree.swift:42-46` |
| 2⁸ (`b2`) | 2 | 8 | 1 | `SplitTree.swift:42-46` |

`factor ^ depth == 256` and `collapseK == log2(factor)`: a radix view collapses
`collapseK` binary levels of the median-cut tree into one view level. The split
itself always cuts the **widest of L/a/b** (data-dependent), so the exponent is
**tree depth, not data dimensionality** (`SplitTree.swift:51-58` blurb;
`SplitTree.swift:68-84` `widestAxis` median-cut).

Each radix is **also** an NN-genome *target* — the form the look-NN must emit when
that branching is selected. The genome types live in the spec **[SPEC-ONLY]**;
nothing in the collapse path produces them yet (see §3, §4 Step 1):

| Radix | Genome | DOF | Spec source | DOF identity |
|---|---|---|---|---|
| 16² | **Flat leaves** | 768 | `PairTreeGolden.swift:11-12` | 256 leaves × 3 (the flat leaf space) |
| 4⁴ | **`Quad4Palette`** | 513 | `Quad4.hs:107-109` | 3 root + 6 × 85 non-leaf nodes |
| 2⁸ | **`SigmaPairTree`** | 384 | `SigmaPairHead.hs:98-100`, `NetContract.swift:42-44` | 3 × 128 σ-pair generators |

**Honesty — addressing ≠ dimensions, and 768 ≠ a genome claim.**
- The 8 wheels of 2⁸ are **8 binary splits over 3 OKLab axes** of the SplitTree,
  not 8 dimensions, and there is **no embedding** — placement is by scalar rank
  (`GridAxis.hs:10-21`).
- **768 is the FLAT leaf space (256·3), explicitly NOT a 768-DOF genome claim**
  (`NetContract.swift:38-44`; `PairTreeGolden.swift:11-12` is the *flat-leaf*
  golden). The look-NN emits **384** (`NetContract.swift:31` `outputDim: 384`,
  `lookSigmaPairDOF = 384`), reconstructed *into* the 768-real leaf space. Do not
  conflate the two (matches `CLAUDE.md` "Palette: global vs per-frame").

**Why "set the control" *will* = "set the NN genome" (form follows function).**
This is the **design intent, [TO BUILD]**: once the collapse is branch-
parameterized (§4 Step 1), choosing 16²/4⁴/2⁸ selects the exact genome type the
NN must later occupy. The NN *output slot* is already pinned to 384 σ-pair DOF
(`NetContract.swift:25-31`), but **today the deterministic collapse produces only
raw flat leaves** (`CollapsedPalette{leaves, chosenIndices}`,
`PaletteCollapse.swift:20-23`) — it carries no branching and no genome. So the
"control surface = network output" identity is the target, not the current state.

## 2. The three controls vs the 16² "done" bar

### 16² — THE BAR (what it sets) **[BUILT]**
A dedicated, golden-gated coordinate view: `PaletteGridView.swift:1-79`,
`GridLayout` (Swift port of `Spec/GridAxis.hs`), golden-pinned tests. The five
properties any control must match:

1. **Golden-gated** — `Spec.GridAxis` + Swift bijection/dimension/order/
   determinism tests, pinned golden vector `side=2, x=L, y=a → [[0,3],[2,1]]`
   (`GridLayoutTests.swift:16-25`).
2. **Honest rank, not faked distance** — places by scalar *rank*, no embedding
   (`GridAxis.hs:10-21`; `PaletteGridView.swift:67` `GridLayout.layout`).
3. **Implicit nearest-neighbour adjacency** — `(coord, index)` tie-break preserves
   SplitTree in-order leaf clustering (`SplitTree.swift:75-78, 86-92`).
4. **Flat-cell, no alpha** — GRID Law #2: brushed slot full; others recede via an
   **opaque** `darkenStep` (35%), never alpha (`PaletteGridView.swift:36-41, 74-76`).
5. **Animation + shared `brushedIndex`** — 20 fps per-frame timeline; `brushedIndex`
   shared with cloud/picker (`PaletteGridView.swift:23, 44-51, 68-77`;
   `GIFReviewView.swift:17, 100-103`).

**Ship-gate gaps even on 16²:**
- **No per-cell accessibility value.** `PaletteGridView` uses
  `.accessibilityElement(children: .ignore)` with a single container label
  (`PaletteGridView.swift:54-55`) — no per-cell `accessibilityValue`.
- **Slots migrate frame-to-frame.** The grid is rebuilt per frame from that
  frame's palette (`PaletteGridView.swift:62-67`), so a screen cell is not a
  stable slot across frames; a fixed canonical-range binning is needed for slot
  stability. (Note: this is the **per-frame display path**; the *global* collapse
  path is stable but is only used by the structure/editor views.)

### 4⁴ — concrete improvement (Quad4 opponent-quadrant drill-down) **[TO BUILD]**
Today 4⁴ has **no dedicated view**. It is rendered by the *same* structure views
as the other radices, just with `branching = .b4` passed in: the treemap
(`PaletteTreeView`) and, in per-frame scope, the 4-wheel `AddressPickerView`
(`GIFReviewView.swift:78-96`; wheel count = `branching.depth` = 4, see below).
There is **no `.b4`-specific routing branch** — `GIFReviewView` switches on
`paletteRepresentation` (structure/grid/cloud/voxel3D) and then `paletteScope`,
never on the branching value.

The Quad4 inductive bias is therefore **invisible**: each non-leaf node is a 2×2
opponent cross, the four children being `parent ± δ₁ ± δ₂` in fixed sign order
`(+ +), (+ −), (− +), (− −)` (`Quad4.hs:128-139`). The improvement is a new
`Quad4DrillView.swift` **[TO BUILD]**: a 2×2-grid staircase showing all four
siblings' reconstructed colours at once, tap-to-descend, a breadcrumb of quadrant
signs, and honest δ₁/δ₂ edge labels (δ₁, δ₂ are independent OKLab offset *pairs*,
not pre-assigned to a/b — the median-cut axis is data-dependent, so label them
from the recovered offset components, not a fixed "δ₁ = a-chroma" legend).

**The forward analyser already exists** — `quad4Analyze` is in
`Quad4.hs:152-166` (an exact inverse of `reconstruct` on the Quad4 subspace; a
mean-pyramid *projection* for arbitrary leaves, with the per-node balance
constraint `c₀ − c₁ − c₂ + c₃ = 0`, `Quad4.hs:146-151`). So this is **not**
blocked on new spec — only on a Swift port + the new view.

### 2⁸ — the σ-pair-mirror behaviour the locked NN form dictates **[TO BUILD]**
The genome is **384 DOF / 128 generators / σ-interleaved**
`[c₀, σ(c₀), c₁, σ(c₁), …, c₁₂₇, σ(c₁₂₇)]` (`SigmaPairHead.hs:90-100, 112-116`),
where σ is the isometry `σ(L, a, b) = (L, −a, −b)` (`sigmaReflect`). The 2⁸ control
must therefore:

- **Keep 8 wheels, not 7.** The picker shows `branching.depth` wheels = 8 for `b2`
  (`AddressPickerView.swift:65-67` `depth = branching.depth`, `selectedDigits`
  has `depth` entries; `:33` `ForEach(0..<selectedDigits.count)`). All 8 are real
  binary tree levels. **The σ-reflection is a post-leaf isometry on the palette,
  NOT a 9th split and NOT a removable level** — there is no "8th split is the σ
  reflection." (This corrects the earlier "show 7 wheels" claim.)
- **Brush a colour → surface its σ-mirror.** Selecting leaf `2i+1` should also
  light `2i` (and vice-versa). Today `AddressPickerView` emits a single leaf index
  via `leafIndexForAddress`; the σ-pair partner highlight is not implemented.
- **Mirror-locked nudge.** Editing Δa/Δb on one leaf should apply −Δa/−Δb to its
  σ-partner (ΔL free), to stay in the σ-symmetric eigenspace. Today
  `GlobalPaletteEditorView.applyDelta` nudges every leaf in the selected node
  **independently**, with no pairing (`GlobalPaletteEditorView.swift:103-113`).
- **Read "384 / 128 generators," not 768.** Any DOF readout for the 2⁸ genome must
  show 384; `PairTreeGolden.degreesOfFreedom = 768` is the **flat-leaf** golden
  (`PairTreeGolden.swift:11-12`), not the genome size.
- **Honesty separation (SplitTree vs σ-Haar).** `AddressPickerView` *today*
  addresses the **data-dependent median-cut SplitTree** and reads its labels from
  "the actual SplitTree collapse" (`AddressPickerView.swift:4-9, 16-17`). The NN's
  σ-pair `SigmaPairTree` is a *different, σ-locked* structure. The picker must
  declare which it is addressing (display SplitTree vs σ-locked genome); these are
  conflated in the copy today.

## 3. Tie to the 3D voxel cube

**Each control is meant to brush the cube through the shared `brushedIndex`.**
Today `GIFReviewView` owns `@State brushedIndex: Int?` (`GIFReviewView.swift:17`)
and the grid / cloud / address-picker read or write it
(`GIFReviewView.swift:91-94, 100-103, 108-116`). **But `VoxelCubeView` is not on
this binding at all** — its initializer is `init(data:edge:settings:)` with **no
`brushedIndex` parameter** (`VoxelCubeView.swift:133`), and the raymarcher does
not consume one. **[gap, TO BUILD]**

The cube *has* the data to consume a brush: `VoxelCubeData.frameIndices`
(64 × 4096 palette indices) and `srgbPalettes` (64 × 256)
(`VoxelCubeView.swift:38-57`), so a brushed index maps to every voxel using that
colour.

Required wiring **[TO BUILD]**:
1. Add `brushedIndex: Int?` to `VoxelCubeView.init` and thread it from
   `GIFReviewView` (`GIFReviewView.swift:117-122`, where the cube is constructed).
2. In the raymarcher, when `voxel.paletteIndex == brushedIndex`, highlight via an
   **opaque step, not alpha** (GRID Law #2, mirroring `PaletteGridView` §2 point 4).
3. Reverse direction: tap a voxel → emit its palette index → set `brushedIndex`,
   lighting grid/picker/cloud/tree.
4. For 2⁸, the brush must light **both σ-pair leaves** (`2i` and `2i+1`) in the
   cube, consistent with §2's σ-mirror brush.

**Rest-pose invariant — overlays gated `!flat`.** Cube highlight/split overlays
should render only off the flat 16² rest pose, so the default look is undisturbed.
**[TO BUILD]**

**Is the collapse already branch-parameterized? NO. [confirmed gap]**
`PaletteCollapse.collapse(perFramePalettes:k:)` takes **no branching parameter**
(`PaletteCollapse.swift:13-15`) and returns flat `CollapsedPalette{leaves,
chosenIndices}` (`PaletteCollapse.swift:20-23`). Branching is applied **post-
collapse, for display only**, at `tree.view(branching)`
(`GlobalPaletteEditorView.swift:37`). The cube reconstructs from raw per-frame
palettes (`VoxelCubeData`, not the collapsed genome). So **today no control choice
reaches either the collapse output or the cube** — display branching
(`tree.view`) and genome branching (the NN's I/O shape) are entirely separate, and
only display is wired.

## 4. Set-before-NN order + build steps

Each step is **spec-first** and **gated where it touches the genome** (golden
round-trip `analyze ∘ reconstruct == id` on the genome subspace before any Swift
port ships). Steps 1–2 give genome-driven collapse + cube with **zero trained NN**
(form fixed first); Steps 3–5 raise 4⁴ and 2⁸ to the 16² bar.

**Step 1 — Branch-parameterize the deterministic collapse (no NN). [largest step]**
This is bigger than a signature tweak: **every downstream consumer** (cube, GIF
re-index, Review editor) must consume the branching-aware genome, not just display.

- *Spec-first:* the genome analysers already exist — `quad4Analyze`
  (`Quad4.hs:152-166`) and `SigmaPairHead.reconstructPaired` (`SigmaPairHead.hs:
  112-116`). What is **missing in spec** is a σ-pair *forward analyser*
  (`leaves → SigmaPairTree`); add it with a round-trip law before porting.
- Introduce a `BranchedPalette` genome type (`.flat | .quad4 | .haar`) — **does
  not exist in any tier yet** (proposed in `docs/global-palette-skeleton-design.md`).
- Add a branching-aware collapse: extend `PaletteCollapse`
  (`PaletteCollapse.swift:13-15`) and `CollapsedPalette`
  (`PaletteCollapse.swift:20-23`) to carry `branching` + the genome. Route
  maximin → dequantize → analyse(branching) → reconstruct sRGB inside
  `FarthestPointCollapse` (`PaletteCollapse.swift:33-38`,
  `collapseForDisplay` `:120-133`).
- **Gate:** Flat is identity (768-leaf passthrough). Quad4 513-DOF round-trip
  golden via `quad4Analyze` green. σ-pair needs the **new** forward analyser
  (`PaletteHaarTree.swift` is a plain binary tree, **not σ-pair-aware**) plus its
  `sigmaSwapAndReflect == id` law (`SigmaPairHead.hs:126-130`) green.

**Step 2 — Drive the cube from genome selection + `brushedIndex` (no NN).**
- *Spec-first:* define the brush→voxel-highlight contract (opaque step, `!flat`
  gating).
- Add `brushedIndex` to `VoxelCubeView.init` (`VoxelCubeView.swift:133`) + the
  raymarcher highlight; wire voxel-tap → `brushedIndex`; thread the binding from
  `GIFReviewView.swift:117-122` (§3 items 1–3).
- Feed the branch-aware genome leaves (Step 1) so the cube reconstructs exactly
  the leaf set the controls address.

**Step 3 — Bring 4⁴ to the bar.**
- Build `Quad4DrillView.swift` **[TO BUILD]**: 2×2 opponent-quadrant staircase,
  breadcrumb of quadrant signs, δ₁/δ₂ labels (read from recovered offsets, not a
  fixed axis legend), tap-to-descend, `brushedIndex`-linked.
- Add a `.b4`-aware routing branch in `GIFReviewView` (`GIFReviewView.swift:77-96`
  — currently switches only on `paletteRepresentation`/`paletteScope`, **so a new
  branch is required**) to present `Quad4DrillView` instead of the generic
  treemap/picker.
- Match 16² points 2–6 (golden via `quad4Analyze`, honesty labels, in-order
  adjacency, no-alpha, 20 fps).
- **Gate:** Quad4 513-DOF round-trip golden green before the view reads it.

**Step 4 — Add σ-pair-mirror to 2⁸.**
- *Spec-first:* `sigmaReflect` + `sigmaSwapAndReflect` are already algebraic
  (`SigmaPairHead.hs:112-130`); add a σ-partner index law (`partner(2i) = 2i+1`).
- **Keep the 8 wheels** (`AddressPickerView.swift:65-67`); they are correct. Add
  σ-pair **partner highlighting** so `leafIndexForAddress` lights both `2i` and
  `2i+1` (or emits a 0..127 generator index the views expand to the pair).
- Mirror-lock the nudge in `GlobalPaletteEditorView.applyDelta`
  (`GlobalPaletteEditorView.swift:103-113`): Δa,Δb → −Δa,−Δb on the σ-partner; ΔL
  free.
- Fix any 2⁸ DOF readout to **384 / 128 generators** (not the 768 flat-leaf golden,
  `PairTreeGolden.swift:11-12`).
- Add the SplitTree-vs-σ-Haar honesty copy (`AddressPickerView.swift:4-17`).
- **Gate:** σ-fixed eigenspace law `sigmaSwapAndReflect == id` on interleaved
  palettes (`SigmaPairHead.hs:126-130`) green; the GIF global colour table must
  serialize in σ-interleaved order.

**Step 5 — Unify control↔cube brushing across all three radices.**
- Wire each control's selection through the same `brushedIndex` to the cube
  (Step 2), with 2⁸ lighting **both** σ-mirror leaves and 4⁴ lighting the
  four-sibling quadrant.
- **Gate:** cross-view brush golden (one index → identical highlight in
  grid/tree/cloud/picker/cube), overlays `!flat`, rest pose unchanged.

**Net.** Steps 1–2 make genome selection deterministically drive **both** the
collapse output and the cube with **zero trained NN** (form fixed first); Steps
3–5 raise 4⁴ and 2⁸ to the 16² bar and lock the σ-pair mirror — exactly the genome
the NN must later emit. The single biggest correction to bear in mind: **today
only display branching is wired; the genome/collapse/cube spine in §3–§4 is the
work, not a description of the present.**

---

### Relevant files
- `/Users/daniel/SixFour/SixFour/Palette/PaletteCollapse.swift`
- `/Users/daniel/SixFour/SixFour/Palette/SplitTree.swift`
- `/Users/daniel/SixFour/SixFour/Palette/PaletteHaarTree.swift`
- `/Users/daniel/SixFour/SixFour/UI/Components/PaletteGridView.swift`
- `/Users/daniel/SixFour/SixFour/Palette/GridLayout.swift`
- `/Users/daniel/SixFour/SixFour/UI/Components/PaletteTreeView.swift`
- `/Users/daniel/SixFour/SixFour/UI/Components/AddressPickerView.swift`
- `/Users/daniel/SixFour/SixFour/UI/Components/GlobalPaletteEditorView.swift`
- `/Users/daniel/SixFour/SixFour/UI/Components/VoxelCubeView.swift`
- `/Users/daniel/SixFour/SixFour/UI/Screens/Review/GIFReviewView.swift`
- `/Users/daniel/SixFour/SixFour/Generated/NetContract.swift`
- `/Users/daniel/SixFour/SixFour/Generated/PairTreeGolden.swift`
- `/Users/daniel/SixFour/spec/src/SixFour/Spec/GridAxis.hs`
- `/Users/daniel/SixFour/spec/src/SixFour/Spec/Quad4.hs`
- `/Users/daniel/SixFour/spec/src/SixFour/Spec/SigmaPairHead.hs`
- `/Users/daniel/SixFour/docs/global-palette-skeleton-design.md`
- `/Users/daniel/SixFour/docs/SIXFOUR-HIGHDIM-UIUX.md`
- (new) `/Users/daniel/SixFour/SixFour/UI/Components/Quad4DrillView.swift`
