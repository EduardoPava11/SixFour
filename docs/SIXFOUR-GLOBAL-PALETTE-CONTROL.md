# SIXFOUR — Global-Palette Creation Control

The single design for **how the user controls creation of the ONE global palette
(GIFA → GIFB)** from the Review surface. This is the UI/UX projection of
**SIXFOUR-WIDGETS Family 2 — The Delta Control** (`docs/SIXFOUR-WIDGETS.md §4`);
it does not re-derive that family, it grounds it on the cell grid and the
real-estate budget.

> One sentence: a **`.review` sub-state** called **PALETTE** that re-reads the ONE
> 256-leaf global collapse on a 16×16 cell surface, switched between the
> **16² / 4⁴ / 2⁸** faces by a 3-segment selector, read in **honest LAB rank** by
> two axis selectors, with creation reaching the GIFB bytes by **construction**
> (`projectQ16(flatGlobalLeaves, branching)` ≡ `makeURL`). The **δ / cut** levers
> are gated behind one new spec'd primitive (`Spec.LeafOverride`) and degrade
> honestly until it lands.

Chosen lens: **LAB-Axes-Plus-Radix (sub-state)** — the buildable, byte-honest
intersection of the two top-scoring designs (LAB-Axes-Plus-Cut-Lever and
Triptych, both 52/100), with the *vapor* levers (cut, free δ) stripped to where
they actually have backing and the best grafts from the runners-up folded in.

---

## 0. Why this design (and why not the others, honestly)

Four designs were scored. All four converge on the SAME verified-true spine and
diverge only on unbuilt levers. The repo facts that decide it (all verified
against source this session):

| Claim under test | Source of truth | Verdict |
|---|---|---|
| `makeURL` / `collapse(_,branching:)` take a **cut / δ** parameter | `LadderExport.swift:38-47`, `PaletteCollapse.swift:25-30` | **FALSE** — signature is `(k, branching)` only |
| `collapse(branching:)` is a **pure** projection of `flat.leaves` | `PaletteCollapse.swift:27-29` | **TRUE** — `projectQ16(flat.leaves, branching)`, no δ injection |
| A **`cutLevel`** is persisted anywhere | `AppSettings.swift` (only `paletteBranching` at :120) | **FALSE** — does not exist |
| **cut ≠ face** (independent DOF) | `SplitTree.swift:46` `collapseK = 4/2/1` is *derived from* `PaletteBranching` | **FALSE** — cut **is** the face's factorization arity |
| Review widgets are a **static, provably-disjoint** scene | `ReviewPhaseField.swift:83-88` `.movable(.field64…)/.movable(.palette16…)` | **FALSE** — they are **user-draggable**; only `captureScene` is proven (`GridLayout.hs:92`); **no `reviewScene` exists** |
| `flatGlobalLeaves` ≡ what `makeURL` ships (preview≡ship) | `LadderExport.swift:46-47` vs `:74-78` — **both** run `FarthestPointCollapse().collapse(…)` then take `.leaves`/`.branchedLeaves` | **TRUE for the radix face** |
| σ-mirror δ can be pushed into **leaf space** | `BranchedPalette.swift:82-98` `sigmaPairProjectQ16` keeps only **even** leaves, Haar round-trips, **regenerates** odds as σ(even) | **FALSE** — a per-leaf leaf-space δ is discarded; the edit must live in **generator space** |

**Consequence.** Every design that names a **cut slider** or a **free leaf δ** as
its *headline* control is selling a no-op: the GIFB producer reads neither.
- **Triptych (52)** — correct spine, but its three δ-nudge faces all require a
  leaf-override store that does not exist; preview≡ship breaks on first nudge.
- **LAB-Axes-Plus-Cut-Lever (52)** — correct spine + the best LAB axis reader,
  but its headline **cut lever drives nothing** and is the same DOF as the face.
- **Brush-Delta-Direct (34)** — `fitsRealEstate=false` by its own arithmetic
  (4 axis segments + radix + slider + readout > 100 cols at touch floor); its
  "risk-free bottom band rows 190-209" assumes fixed widget positions that are
  in fact **movable**. Salvage: brush-on-existing-grid, honest "what-did-I-grab"
  readout, and the **generator-space δ** insight.
- **Palette16-Footprint-Inline (38)** — `fitsRealEstate=true` but forces a
  cross-phase footprint mutation of `palette16` (which IS the live **shutter**),
  re-geometering capture; its cut slider is the same no-op; mode-swap is a data
  hazard. Salvage: the **instant-radix-preview cache** and **σ-dual-light**.

**This design** ships exactly the spine that is true today, places the δ/cut
levers behind one honestly-named, spec-first primitive, and **degrades gracefully**
(the panel is fully useful as a radix+LAB creation tool with the δ row simply
absent) rather than shipping a fake slider.

---

## 1. The chosen design — concrete cell layout + footprint proof

### 1.1 Envelope decision: SUB-STATE (not a coexisting band)

The irreducible creation surface is **one 16×16 leaf grid at the 4 pt atom =
64×64 cells = 256 pt** (the same `CellSprite(cols:16,rows:16,cellPt:gifPx)` the
review `paletteStrip` already is — `ReviewPhaseField.swift:142`). That alone is
**3.2×** the only risk-free coexisting band (rows 190-209 = 20 cells = 80 pt). It
**cannot** be a band. Furthermore the "band is provably disjoint" claim is false:
review widgets are **movable** (`.movable`), so a user can drag `palette16`
(default `42,145`) or `diversityRing` (default `40,170`) into any band, and
`MoveContract.isDisjoint` only tests movable-vs-movable, never movable-vs-chrome.

Therefore the panel is a **`.review` sub-state**, the *proven* `atlasCurationField`
pattern (`ReviewPhaseField.swift:254-281`): flag-gated, view-local `@State`,
mutually exclusive with normal review, leaves the hierarchy and resets on
`.retake`. **It claims no `LRegion`, so it needs NO `GridLayoutContract` /
`MoveContract` regen and NO new movable `ColorIdentity`** — it replaces the scene.

### 1.2 ASCII cell layout (all dims in 4 pt atoms unless noted)

Usable envelope after safe areas: top inset 62 pt ⇒ first clear row **16**
(`16·4 = 64 ≥ 62`); bottom inset 34 pt ⇒ last clear row **209** (`210·4 = 840 ≤
874−34`). Usable height = rows 16…209 = **194 cells = 776 pt**, full width **100
cols = 400 pt**. VStack, `spacing: gif(gutterCells)=4 pt`.

```
col:  0                                                            99   (100 cols = 400pt)
     +----------------------------------------------------------------+
r16  | CellText  "PALETTE · 16² SEE"   rows:11                        |  9 cells  (title; CellText
     |                                                                 |          rows are subPt=2pt →
r25  +----------------------------------------------------------------+          11 rows ≈ 22pt; place
     | (gutter 1)                                                      |  1       in a 9-atom band)
r26  +----------------------------------------------------------------+
     | FACE   [  16²  ] [  4⁴  ] [  2⁸  ]   CellSelector 3-seg         | 11 cells (gif(touchFloor)=44pt)
     |        each seg gif(segmentCells)=22 atoms=88pt                 |          3·22 + 2·1 = 68 cols,
r37  +----------------------------------------------------------------+          centered col 16..83
     | (gutter 1)                                                      |  1
r38  +----------------------------------------------------------------+
     |        ┌────────────────────────────┐                          |
     |        │  THE ONE 16×16 LEAF SURFACE │  col 18..81 (centered:   | 64 cells = 256pt
     |        │  CellSprite 16×16 @ gifPx   │   (100-64)/2 = 18 )      |  (1 GIF-px per cell,
     |        │  re-laid per FACE:          │                          |   nearest-neighbour,
     |        │  16²=GridLayout rank        │                          |   no AA — paletteStrip
     |        │  4⁴ =Quad4 quadrants        │                          |   discipline)
     |        │  2⁸ =σ-pair adjacency       │                          |
r102 +----------------------------------------------------------------+
     | (gutter 1)                                                      |  1
r103 +----------------------------------------------------------------+
     | X-AXIS  [L][a][b][chr][hue][idx]   CellSelector (16² face only) | 11 cells (6 segs wrap; see
r114 +----------------------------------------------------------------+          §1.3 — 6×22 won't fit
     | Y-AXIS  [L][a][b][chr][hue][idx]   CellSelector (16² face only) | 11 cells  one row)
r125 +----------------------------------------------------------------+
     | READOUT  CellText "16 leaves · column · rank by L"             |  9 cells (HONEST: names what
r134 +----------------------------------------------------------------+          a tap grabbed; graft
     | (gutter 1)                                                      |  1        from Brush-Delta)
r135 +----------------------------------------------------------------+
     | δ ROW (gated on Spec.LeafOverride; absent until it lands):     | 11 cells (CellSlider, see §2.4
     |   AXIS [ΔL][Δa][Δb][cut] CellSelector + CellSlider knob        |          — degrades to absent)
r146 +----------------------------------------------------------------+
     |              … free rows 146..192 (47 cells slack) …           |          reserved; never the
     |                                                                 |          2nd 16×16 surface
r193 +----------------------------------------------------------------+
     | ACTION  [ Export 16³ ] [ Export 64³ ] [ Done ]  CellActionBtn  | 11 cells (minHeight 44pt)
r204 +----------------------------------------------------------------+  (clears r209 bottom safe)
```

### 1.3 Footprint math (proves it fits — corrected for real primitive geometry)

**Vertical (VStack of atom-blocks + 1-atom gutters), columns of the budget:**

```
title 9 + g1 + face 11 + g1 + surface 64 + g1 + Xaxis 11 + Yaxis 11
        + readout 9 + g1 + δrow 11 + g1 + action 11
  = content 137 + gutters 6 = 143 cells used  of 194 available
  ⇒ slack = 51 cells (204 pt).  WITHOUT the δ row (degraded): 131 cells.
```

**Horizontal, the load-bearing checks (using the VERIFIED primitive sizes):**

- **FACE selector** — `CellSelector` segment width = `gif(segmentCells)` =
  **22 atoms = 88 pt** (`CellControls.swift:35`, `GlobalLattice.segmentCells=22`).
  3 segments = `3·22 + 2·1 = 68 cols ≤ 100`. ✓ Centered at col 16.
- **Surface** — 16 swatches × 4 atoms = **64 cols = 256 pt**, centered at
  `(100−64)/2 = 18` (cols 18…81) — the exact column the proven `captureScene`
  preview already uses. ✓
- **X/Y axis selectors** — 6 GridAxis cases × 22-atom segments = `6·22 + 5 = 137
  cols > 100`. **DOES NOT FIT one row.** Resolution: each axis selector is a
  **two-row wrap of 3 segments** (`3·22+2·1 = 68 cols`, two 11-cell rows), OR a
  single-tap **cycle** through `GridAxis.allCases` with the active axis named in
  the READOUT. We take the **cycle** (one 11-cell row each for X and Y, label
  "X: L", "Y: b"), keeping the row budget and discoverability via the readout.
  This is the honest cost the runner-ups buried.
- **Action row** — 3 `CellActionButton`s, each `minHeight 44 pt`,
  `fillWidth:false`, split across 100 cols with 1-atom gutters. ✓

**Touch floor (≥ 44 pt = 11 atoms, both dims):** FACE segments 88×44 pt ✓;
axis-cycle buttons span ≥ 22 cols × 44 pt ✓; CellSlider `minHeight 44` ✓;
action buttons `minHeight 44` ✓. All clear `lawInteractiveTouchFloor`
(`GridLayout.hs:147`) — though as a sub-state it is NOT a `Scene`, so the law is
honored by construction, not by codegen.

> **Honest budget statement.** The panel fits the sub-state with 51 cells (204 pt)
> of slack *with* the δ row, 63 cells without it. What does **not** fit anywhere:
> (a) a coexisting band (3.2× over), (b) six axis segments on one row (1.37×
> over — degraded to a cycle), (c) a **second** 16×16 live-preview echo (it would
> be another 64 cells — the surface IS the preview, so the echo is redundant *and*
> would overflow). These are stated, not hidden.

---

## 2. How the user controls creation (16² / 4⁴ / 2⁸ · RGBT δ · cut)

Three coupled levers, in honest order of how-real-they-are-today:

### 2.1 RADIX FACE — the genome (REAL, ships today)

The 3-segment `CellSelector` writes `settings.paletteBranching ∈ {.b16, .b4,
.b2}`. This is **not a display toggle** — it sets which **genome** the maximin
leaves project onto:

| Face | `PaletteBranching` | Genome | Projection | Loss |
|---|---|---|---|---|
| 16² SEE | `.b16` Flat-768 | identity | `projectQ16` returns leaves unchanged | lossless |
| 4⁴ CONTROL | `.b4` Quad4-513 | opponent-quadrant | exact ÷4 `quad4ProjectQ16` | lossy (the inductive bias) |
| 2⁸ LEARN | `.b2` σ-pair-384 | σ-mirror | Haar + exact σ-reflect | lossy (the inductive bias) |

The face reaches the **GIFB bytes**: `makeURL(…, branching:)` →
`collapse(…, branching:).branchedLeaves` = `projectQ16(leaves, branching)`
(`LadderExport.swift:46`, `PaletteCollapse.swift:59`, `BranchedPalette.swift:33`).
**"Set the control = set the genome"** is TRUE at the collapse output today.

### 2.2 LAB rank reading — the SEE face (REAL, ships today)

On the 16² face two axis controls assign the surface's X/Y to a `GridAxis`
(`L / a / b / chroma / hue / index`, `GridLayout.swift:24`). `GridLayout.layout(x:
y:colors:)` places the 256 leaves by **scalar rank** with `(scalar, index)`
tie-break — pure sort key, **no embedding** (§3). The READOUT names the active
axes. The opponent cross (a=green↔red on X, b=blue↔yellow on Y) is the canonical
reading and the axis the σ-genome is symmetric about.

### 2.3 BRUSH select + honest readout (REAL on selection; graft from runners-up)

Tap/drag a region of the surface (DragGesture lives **inside** `CellSprite`, a
`Cell*.swift` primitive that is lint-exempt — `lint-grid.sh:40`; the brush does
`location/gifPx → (col,row)` math, never a `.position`). The brushed leaves light
full; others recede via opaque `darkenStep` (`PaletteGridView`, never alpha — GRID
Law #2). Two grafts make this honest, not decorative:

- **σ-dual-light (from Inline):** on `.b2`, brushing leaf `2i` also lights `2i+1`
  (its σ-partner). Because the surface is rank-placed by `b`, the σ-partner
  (σ negates a,b) appears as a **vertical reflection** — the opponent symmetry of
  the genome made literally visible. Pure `PaletteGridView` brush extension, no
  new primitive.
- **"What did I grab" readout (from Brush-Delta):** the READOUT names the grabbed
  object per face — **column-of-16 rank band** (16²), **quadrant-of-64 → drill to
  16** (4⁴), **σ-pair-of-2** (2⁸). On a rank grid a "column" is a *rank band*, not
  a tree subtree; naming it prevents a false mental model.

### 2.4 RGBT δ + cut — DEFERRED behind one spec'd primitive (HONEST)

The δ row and the cut are **gated** on a new primitive, `Spec.LeafOverride`
(§6.2), and are **absent from the panel until it lands**. Reason: verified, the
GIFB producer reads **no δ and no cut**, and three sub-problems must be solved
*correctly*, not bolted on:

1. **The override must reach BOTH paths.** Today `makeURL` and `flatGlobalLeaves`
   each *recompute* leaves from scratch. A δ in view-local `@State` would make the
   surface show nudged leaves while Export re-derives un-nudged leaves —
   **preview ≢ ship** on the first nudge. Fix: a single `[OKLabQ16]` (or
   delta-layer) override threaded into `makeURL` **and** the preview projection so
   both share one input.
2. **δ must live in GENERATOR space, not leaf space** (the Brush-Delta critique's
   correct insight, verified): `sigmaPairProjectQ16` **discards** the odd leaves
   and regenerates them as σ(even), and the Haar round-trip redistributes any
   per-leaf offset. So a σ edit must push **Δa on the even generator cᵢ ⇒ −Δa on
   its σ-partner** *before* projection (ΔL free), keeping the genome in the
   σ-symmetric eigenspace **by construction**. Likewise a 4⁴ δ pushes the node's
   **δ₁/δ₂ opponent offsets** (`Quad4Nav.nodeAndChildren`,
   `BranchedPalette.swift:192`), not reconstructed leaves.
3. **The "cut" is NOT a second DOF over today's path.** `collapseK = 4/2/1` is
   *derived from* the face (`SplitTree.swift:46`); the face already chooses it.
   A genuine cut-lever (Axis B: how much colour-motion folds into the static
   table vs. residual for super-res) is a **new SplitTree-backed collapse path**,
   not a slider over the existing maximin. It is a separate Family-2 build, spec
   first (`Spec.CollapseLever` exists but is un-wired), and is **out of scope** of
   this panel until that path is real. Shipping a slider that drives the existing
   path would be the no-op the brief warns against.

**Degradation contract:** until `Spec.LeafOverride` lands, the panel is a complete
**radix + LAB-rank creation tool** (the δ row is simply not rendered; the action
row moves up 12 cells). When it lands, the δ row appears with `AXIS [ΔL][Δa][Δb]`
(the σ-locked / Quad4-δ generator edit) — and the **cut** remains deferred to its
own workflow. No fake levers ship at any stage.

---

## 3. How it leverages LAB — honest rank

The 16² surface is `GridLayout.layoutN(side:16, x:, y:, colors:)`, the Swift port
of `Spec.GridAxis` (golden side=2, x=L y=a → `[[0,3],[2,1]]`). Placement is by
**`(scalar, index)` SORT KEY ONLY** (`GridLayout.swift:40-47`): `GridAxis.scalar`
returns a raw `Float` used purely as an ordering key — magnitude and origin are
irrelevant, there is **no coordinate embedding**.

- `L = oklab.x`, `a = oklab.y`, `b = oklab.z`, `chroma = √(a²+b²)`,
  `hue = atan2(b,a)`. The opponent axes are first-class selectable axes.
- **Honest distance:** equal cell steps are equal **RANK** steps, **not** equal ΔE
  steps. The panel **never** claims cell-distance == OKLab-distance. All collapse /
  reindex comparisons use squared Q16 OKLab distance
  (`FarthestPointCollapse.distSqQ16`, `PaletteCollapse.swift:82`) — the same metric
  the maximin uses, no perceptual fudge.
- **Honest rank of LAB use:** (1) rank-axis *reading* of the leaf set — REAL,
  golden-gated; (2) σ-mirror as the **exact** opponent reflection σ(L,a,b)=(L,−a,−b)
  visualized as a vertical flip — REAL as a view, REAL as an edit only once the
  generator-space override lands; (3) 4⁴ δ₁/δ₂ as the two opponent-axis offsets —
  REAL as a view (`Quad4.analyze`), edit deferred. LAB is leveraged honestly as a
  **rank + symmetry** structure, not as a fake metric plane.

---

## 4. The preview ≡ ship guarantee

**For the radix face (today): TRUE by construction.** The surface paints
`BranchedPalette.projectQ16(LadderExport.flatGlobalLeaves(palettesPerFrame),
branching)`. `flatGlobalLeaves` is the branching-INDEPENDENT maximin `.leaves`
(`LadderExport.swift:74-78`, run **once** off-thread). `makeURL(…, branching:)`
runs the **same** `FarthestPointCollapse().collapse(…)` and takes
`.branchedLeaves = projectQ16(leaves, branching)` (`LadderExport.swift:46-47`).
Same leaves, same projection ⇒ **byte-identical**. Radix switching is a cheap
re-projection of the cached flat leaves (the **instant-radix-preview cache**
grafted from Inline) — the ~seconds maximin runs once on sub-state entry,
pre-warmed when Review is entered.

**For the δ levers (deferred): preserved by the override primitive.** The whole
reason §2.4 gates δ on `Spec.LeafOverride` is to keep this guarantee: the override
is the **single input** both the preview projection and `makeURL` consume, so a
nudged surface and the exported GIFB share one source. Any δ design that does not
route through one shared override breaks preview≡ship on the first nudge — which is
exactly why no fake δ ships before the primitive.

**Degenerate guard:** `GridLayout.layoutN` requires `side²=256` colours; the
projected leaves are always 256, but a degenerate clip can yield `<256` distinct
leaves and `layout` returns `[]`. The surface ghost-fills the shortfall exactly as
`paletteStrip` does (`ReviewPhaseField.swift:140`), so it never blanks.

---

## 5. `lint-grid.sh` compliance

- **(a) LINT-PLACEMENT** — the sub-state is a `VStack` (the `atlasCurationField`
  precedent at `ReviewPhaseField.swift:255`, which passes today); **no raw
  `.position`/`.offset`** at the composition site. The brush `DragGesture` lives
  inside `CellSprite` (a `Cell*.swift`, basename-exempt — `lint-grid.sh:40`) and
  does `location/gifPx` math, not a `.position`. `lint-grid.sh` forbids
  `.position/.offset`, **not** `DragGesture`.
- **(b) LINT-SINGLE-LATTICE** — every dimension threads `GlobalLattice.gif()`/
  `.pt()`; no second atom, no `CaptureGrid` clone.
- **(c) LINT-DRAW-VOCAB** — only `CellText / CellSelector / CellSlider /
  CellActionButton / CellSprite`; no glass, no opacity-on-cell (de-emphasis is
  opaque `darkenStep`), no SF-Symbol on a label, no raw `Text`/`RoundedRectangle`.
- **(d) LINT-SINGLE-PITCH** — no bare point literals; FACE selector reuses
  `segmentCells`, slider `cols:` is a cell count. (Note: `CellActionButton`/
  `CellSlider` carry `minHeight: 44` *in points* inside the **primitive files**,
  which are exempt — composition sites add none.)
- **(e) LINT-GOLDEN** — adds **no** new golden source for the radix/LAB ship:
  reuses `Spec.GridAxis`, `Spec.Quad4(Fixed)`, `Spec.SigmaPair(Fixed)`, all
  already gated. The sub-state claims **no `LRegion`**, so it needs **no**
  `GridLayoutContract`/`MoveContract` regen and introduces **no** drift. The
  deferred δ ships **one** new golden, `Spec.LeafOverride` (§6.2), only when built.

---

## 6. Build plan (sequenced, spec-first where it must be)

Reuse, not reinvention. Existing primitives/back-end carry most of the weight.

### Phase A — RADIX + LAB panel (ships now, zero new collapse math, zero golden)

1. **`AppSettings`** — add `paletteControlEnabled: Bool` (default `false`,
   mirrors `colorAtlasEnabled`) + persist `paletteXAxis`/`paletteYAxis:
   GridAxis` (default `.L`/`.b`). `paletteBranching` already exists
   (`AppSettings.swift:120`).
2. **`PaletteControlField.swift`** (new, `SixFour/UI/Surface/`) — the sub-state
   view, modeled on `atlasCurationField` (`ReviewPhaseField.swift:254`):
   flag-gated `@State paletteOpen`, view-local override-free state, `onDisappear`
   cleanup, `Done` button. Composes:
   - **FACE** `CellSelector` over `PaletteBranching.allCases` →
     `settings.paletteBranching`.
   - **Surface** `CellSprite(cols:16,rows:16,cellPt:gifPx)` re-laid per face:
     16² via `GridLayout.layoutN`; 4⁴ via `Quad4.analyze`+`Quad4Nav`; 2⁸ via
     `BranchedPalette.sigmaPairProject` adjacency. Painted from the cached
     `flatGlobalLeaves` re-projected by `projectQ16` (preview≡ship, §4).
   - **X/Y axis** single-tap cycle buttons (`CellActionButton`) over
     `GridAxis.allCases`; READOUT (`CellText`) names active axes + grabbed object.
   - **Action** `CellActionButton ×3`: `Export 16³` / `Export 64³` call the
     **existing** `exportRung(_:)` (`ReviewPhaseField.swift:232`) which already
     reads `settings.paletteBranching`; `Done` clears `paletteOpen`.
3. **Entry** — add a `Palette` `CellActionButton` to `actionRow`
   (`ReviewPhaseField.swift:214` Atlas-button pattern), gated on
   `settings.paletteControlEnabled`; sets `paletteOpen = true`. Branch into
   `PaletteControlField` in `body` exactly where `atlasCurationField` branches
   (`:71-75`).
4. **Instant-radix cache** — compute `flatGlobalLeaves` once via
   `Task.detached(.userInitiated)` on sub-state entry (it is the ~seconds step),
   cache `[OKLabQ16]`; every face/axis tap re-projects cheaply
   (`projectQ16`/`layoutN`). Ghost-fill until it lands.
5. **Brush + σ-dual-light** — thread a `(col,row)` brush callback through
   `CellSprite` (math inside the primitive, lint-exempt); extend
   `PaletteGridView`'s opaque `darkenStep` to light the brushed band, and on `.b2`
   also light the σ-partner `2i↔2i+1`.

> Phase A is a **complete, byte-honest creation tool**: choose the genome (reaches
> GIFB), read it in any LAB rank pair, export at that genome. No fake levers.

### Phase B — δ generators (spec-first; ships the δ row)

6. **`Spec.LeafOverride`** (new Haskell module + `Map` entry + Haddock) — define
   the **generator-space** override: for `.b2`, a `Δgenerator` on even cᵢ with the
   σ-lock `(ΔL free, Δa→−Δa, Δb→−Δb on partner)` applied **before** Haar
   reconstruct; for `.b4`, a `(δ₁,δ₂)` push at an addressed node. Laws:
   `lawSigmaLockPreservesSymmetry`, `lawQuad4PushPreservesOpponentCross`,
   `lawOverrideIdentityIsNoOp` (zero δ ⇒ byte-unchanged GIFB). Golden vectors;
   `cabal test` gate; `cabal run spec-codegen`.
7. **Swift port** — extend `BranchedPalette.projectQ16` to accept an optional
   generator-override, byte-exact vs the new golden. **Thread the override into
   BOTH** `makeURL(…, override:)` and the preview projection (the single shared
   input — §4).
8. **δ row UI** — render the gated `AXIS [ΔL][Δa][Δb]` `CellSelector` + one
   `CellSlider` bipolar knob (center = 0). Brush scopes WHICH generators; slider
   is HOW MUCH; preview re-projects live.

### Phase C — cut-lever (separate workflow, NOT this panel)

9. The Axis-B cut is a **new SplitTree-backed collapse path** (`Spec.CollapseLever`
   wiring). It is **explicitly out of scope** here (see §2.4 / §7) and gets its
   own spec-first build with a live 16³ preview, because it is a real new DOF over
   the producer, not a slider over the existing maximin.

---

## 7. Explicitly DEFERRED (real estate or rules forbid it)

- **The cut-lever as a panel control.** Verified no-op over today's producer
  (`collapseK` is derived from the face; no `cutLevel` is read by `makeURL`).
  Deferred to its own SplitTree-backed collapse build (Phase C). Shipping a slider
  now would be a fake lever.
- **Free leaf-space δ / "recolour any swatch".** Forbidden by construction:
  `sigmaPairProjectQ16` discards odd leaves; Haar redistributes per-leaf offsets.
  δ must be generator-space (`Spec.LeafOverride`, Phase B) — until then, **absent**.
- **A coexisting bottom band.** 256 pt surface vs 80 pt band (3.2× over); and the
  "risk-free" band is not provably disjoint because review widgets are **movable**.
  Forbidden by real estate + the movable-scene fact.
- **Six axis segments on one row.** `6·22+5 = 137 > 100` cols. Degraded to a
  single-tap **cycle** with the axis named in the READOUT.
- **A second 16×16 live-preview echo.** Another 64 cells — overflows AND is
  redundant (the surface IS the preview). Omitted.
- **Making the panel a movable `ColorWidget`.** The `ColorIdentity` alphabet is
  closed `{field64, palette16, diversityRing}`; a 4th would need
  `Spec.MovableLayout` + `MoveContract` regen and a disjointness re-proof. The
  panel is **immovable sub-state chrome** instead — no regen, no new identity.
- **A title/label to disambiguate a per-frame↔global mode swap on the existing
  grid** (the Inline failure mode). Avoided entirely: the sub-state owns its OWN
  surface, so there is no silent dual-purpose grid and no data hazard.

---

## 8. Tie to SIXFOUR-WIDGETS Family 2

This document is the **UI/UX + cell-grid projection** of `SIXFOUR-WIDGETS.md §4
(Family 2 — The Delta Control)`. It does not duplicate that family's semantics
(RGBT delta cube on the 4⁴ opponent cross; the cut-lever as Axis B; σ-mirror nudge
on the 2⁸ learn-face). It (a) confirms Family 2's stated statuses against the repo
(`quad4Analyze`/`analyzePaired` exist in spec; `BranchedPalette` routes `.b4`/
`.b2`; **no `Quad4DrillView`**; **cut-lever TO BUILD**; **mirror-nudge UI not
wired**), and (b) supplies the missing build map: the **sub-state envelope**, the
**generator-space override** that makes the structured-prior δ legal, and the
**deferral of the cut** to its own collapse path. The keystone Family-2 rule —
*"the user's deltas are a structured PRIOR on the collapse, not a free recolour"* —
is enforced here by construction: every δ moves **within** the genome
(σ-eigenspace / Quad4 opponent cross), never breaks it.
