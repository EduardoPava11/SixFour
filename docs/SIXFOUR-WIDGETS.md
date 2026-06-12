# SixFour — WIDGETS (consolidated · form follows function)

> **THE single source of truth for widget design.** Every widget here is justified by
> one question: *how does it serve the ultimate function?* This doc **consolidates and
> supersedes the framing** of the scattered widget docs (map in §8); those remain as
> implementation detail, not as competing architectures.
> Status tags are **scout-verified 2026-06-12** (workflow `wf_c777dd6f`), not aspirational.

---

## 0. The ultimate function — what every widget must serve

SixFour turns a 64-frame burst into **a ladder of shareable GIFs**, where the user
**sees** color on a cell grid, **controls** color via deltas in RGBT space, and a
**net** transmutes statistical uncertainty into the global look they keep.

| Aspect | The function | Math ground |
|--------|-------------|-------------|
| **OUTPUT** | a ladder of **5 exportable/shareable GIFs**: `16³` · `64³-A` · `64³-B` · `256³-A` · `256³-B` | spatio-temporal (resolution = sampling rate in space×time) |
| **MEDIUM** | the **cell grid** — *how the user sees LAB color* (a cell IS a color in L/a/b) | spatio-temporal / perceptual |
| **INPUT** | the user's **overarching color deltas in RGBT space**, captured as *structure to preserve* | probability (a delta is a displacement on a measure) |
| **BRIDGE** | the **NN transmutes per-frame statistical uncertainty** → one confident global look | statistics & probability |

**Two mathematical grounds, never blurred:** *spatio-temporal analysis of pixels &
color* grounds everything the user **sees** (the cube, the ladder, the cell grid);
*statistics & probability* grounds everything the net **decides** (collapse, deltas,
uncertainty, learning). Every widget below is tagged with which ground it stands on.

---

## 1. The derivation — one object, three faces, one ladder

There is exactly **one statistical object**: the per-frame palette as a *distribution
over the 64³ voxel cube* (each frame a 256-colour measure; `Spec.Significance` /
`Spec.Coverage` give its confidence). Everything is a projection of it:

```
                       ┌─────────────────────────────────────────────┐
        sees ◀── 16²    │   ONE 256-leaf SplitTree (BranchedPalette)   │   2⁸ ──▶ learns
       (LAB grid)       │   = the per-frame palette distribution       │     (σ-pairs)
                        └───────────────────┬─────────────────────────┘
                              4⁴ ──▶ controls (R,G,B,T deltas)
                                            │
                NN transmutes uncertainty + user deltas → global genome
                                            │
                       ▼ projected, at five sampling rates, to ▼
   16³ preview · 64³-A per-frame · 64³-B global · 256³-A HD per-frame · 256³-B HD global
                       ═══════════  all GIFs, all exportable, all shareable  ═══════════
```

The radix is not a setting — it is **which face of the function you are on**:

| Radix | Face | What the user does | Preserved structure | Ground |
|-------|------|--------------------|--------------------|--------|
| **16²** | **SEE** | reads 256 colours placed by L/a/b rank | LAB rank order | spatio-temporal |
| **4⁴** | **CONTROL** | pushes deltas along **R, G, B, T** | the 4-axis opponent cross (`Quad4`, 513-DOF) | probability |
| **2⁸** | **LEARN** | (mostly the net's view) edits the symmetric genome | **σ-pairs** `σ(L,a,b)=(L,−a,−b)`, 128 generators / 384-DOF | probability |

This is the consolidation of the entire "16²/4⁴/2⁸ on a flat grid" problem: they are
**one tree rendered three ways on the same cell grid** — a grid you *read*, a delta-cube
you *push*, a pair-structure the net *keeps*. There is no "8-D widget"; there is one
object with a see-face, a control-face, and a learn-face.

---

## 2. Family 0 — THE CELL GRID (the substrate, not a widget)

*Ground: spatio-temporal.* The cell grid is **how the user sees LAB colour** and the
only render primitive. Every widget is a *configuration* of it, never a new control type.

- **Atom = 4 pt** (`Generated/LatticeContract.swift:24 gifPx = 4`, GRID v3.0) — the
  single source of truth. (The old "6 pt" lineage is dead; do not reintroduce it.)
- One cell ↔ one colour ↔ one (palette index → L/a/b). Flat, opaque, no alpha, no AA.
- Three render scopes = the three perceptual axes of the object: **space** (x,y),
  **time** (t), **colour** (L/a/b). A widget chooses a scope; the grid does the rest.
- **Status: SHIPPED + wired** — `CellSprite`, `PixelGrid`, `GridScript`, the phase
  fields (`Live/Capturing/Rendering/Review`). One 20 fps clock.

> **Form-follows-function rule:** if a widget needs a control that is *not* a cell
> (a `Slider`, `Text`, SF Symbol, glass), it is off-function. The grid renders the
> control too. (`SIXFOUR-TOTAL-PIXELATION.md` is the lint that enforces this.)

---

## 3. Family 1 — THE LADDER (output: 5 shareable GIFs)

*Ground: spatio-temporal.* The export/share surface. Each rung is the **same cube at a
different sampling rate**, rendered on the cell grid, exportable as a GIF.

| Rung | Cube | What it is | Status |
|------|------|-----------|--------|
| `16³` | 16×16 × 16f | coarse live **preview** (the see-face, cheap) | **TO BUILD** (no 16³ preview today) |
| `64³-A` | 64×64 × 64f | **per-frame** palette — max LAB diversity (**HD-free GIFA**) | **SHIPPED** (hero GIF) |
| `64³-B` | 64×64 × 64f | **global** collapsed palette (**GIFB**) | collapse exists; **B not produced** (0 callers) |
| `256³-A` | 256×256 × 256f | **per-frame** super-res (direct) | **TO BUILD** (tiled/streamed) |
| `256³-B` | 256×256 × 256f | **global** super-res, *seeded by the 64³-A↔64³-B residual* | **TO BUILD** (tiled/streamed) |

**The residual that seeds B (Decision, 2026-06-12):** reconstruct `64³-B` from the
collapsed palette, **difference it against `64³-A`** — that measured per-frame↔global
displacement *is* the "palette is motion" field and the seed for the 256³ super-res.
**All five are trainable AND shareable** — no archival-only split; the A↔B pair is
itself a training comparison (diversity-max vs coherent-global).

**The export model — one gesture, any size (Decision, 2026-06-12).** The GIF is the
product, so *getting one out is a single cheap gesture* over whatever the user is
looking at, at whatever rung. There is no per-size export flow — one gesture, the size
is just which rung. **16³ is the free "working copy"**: because it is a pure subsample of
the cube (`LadderGIF.workingCopy` — temporal 64→16 + spatial 64→16, no re-extraction),
the user can snapshot/save a 16³ GIF *any time, in any capacity*, the way you'd grab a
draft. The heavier rungs (64³, 256³) are the same gesture; they just cost more to encode.

- **Widget:** one export/share affordance reachable from any surface (a swipe/long-press
  on the hero, mirrored in the Ladder sheet). The sheet lists the five rungs as
  cell-grid thumbnails; tap a rung → encode + system share; 16³ is always instant.
- **The cut-lever (Family 2) sets where on the A↔B axis each global rung sits.**
- **Status (as-built 2026-06-12):** `64³-A` ships. The **`64³-B` / 16³ producer is
  COMPLETE end-to-end and gated**: `LadderGIF` (`globalRemap`/`reindexCubeToGlobal`,
  `workingCopy`/`spatialDownsample`/`temporalSubsample`, `paletteToSRGB8`,
  `encodeGlobalGIF`) + a new **global-color-table `GIFEncoder.encodeGlobal` mode** that
  drops the per-frame `CompleteVoxelVolume` brand (so frames may use a subset of one
  global table) and writes a valid GCT GIF — verified by ImageIO round-trip. Feed
  `collapse(...,branching:).branchedLeaves` and you get the GIFB table for any radix.
- **Export gesture WIRED (2026-06-12):** Review's action row has a **"Save" menu**
  (`LadderExport.Rung.allCases` → `16³ working copy` / `64³ global`) that produces the
  rung via `LadderExport.makeURL` (collapse by `settings.paletteBranching` → reindex →
  encode) and presents the system share sheet (`ActivityView`, mirroring the LUT path).
  One gesture, any size — 16³ is the cheap working copy. Compile-gated + a producer
  round-trip test (each rung → valid GIF with the right frame count).
  **PERF CAVEAT:** `makeURL` runs the maximin collapse **synchronously** (~seconds for
  64³ — the producer test takes 4.5 s) — must move off the main thread before ship.
  **TO BUILD next:** offload the producer to a background task; hero-gesture trigger
  (long-press is taken by widget-move, so a swipe); the 256³ tiled decode.

*Consolidates:* `FOUR-GIF-UIUX`, `PALETTE-STORY`, the export half of `COLLAPSE-LEVER`.

---

## 4. Family 2 — THE DELTA CONTROL (input: RGBT deltas, structure preserved)

*Ground: probability.* Where the user sets the **overarching deltas of colour in RGBT
space**. This is the 4⁴ control-face plus the cut-lever. The structure (the tree, the
σ-symmetry) is preserved by construction — the user moves *within* the genome, never
breaks it.

- **The RGBT delta cube (4⁴ face).** Four base-4 digits = **R, G, B, T**. The user
  pushes a delta along an axis; it applies to a whole opponent-quadrant subtree, not one
  swatch (collective verb). Preserved structure = the `Quad4` opponent cross
  (`c₀−c₁−c₂+c₃=0`, 513-DOF). **Status:** `quad4Analyze` + laws **exist in spec**;
  `BranchedPalette.swift` routes `.b4`; **no dedicated `Quad4DrillView` UI yet.**
- **The cut-lever (Axis B).** One slider = how much colour-motion folds *into* the
  static global palette vs stays as residual for super-res. Low cut → bigger A↔B gap →
  more detail for 256³-B to recover. Sets the rung positions in Family 1. **Status:
  TO BUILD** (slider + live 16³ preview).
- **σ-mirror nudge (2⁸ learn-face, when editing the genome directly).** Editing Δa/Δb on
  one leaf applies −Δa/−Δb to its σ-partner (ΔL free) — stays in the symmetric
  eigenspace. **Status:** `analyzePaired` + σ-fixed laws **exist in spec**; mirror-nudge
  UI **not wired**.

> **Critical: the user's deltas are a structured PRIOR on the collapse, not a free
> recolour.** Preserving RGBT/σ structure is *why* the net can learn from them.
> *Consolidates:* `RADIX-CONTROLS` (now the impl map for this family), `HIGHDIM-UIUX`,
> the control half of `COLLAPSE-LEVER`, `COLOR-WIDGETS`, `WIDGET-DESCRIPTOR`.

---

## 5. Family 3 — THE UNCERTAINTY SURFACE (what the NN transmutes)

*Ground: statistics & probability.* Shows the **statistical confidence** the net reads
and transmutes. This is the bridge between per-frame (rich, uncertain) and global
(collapsed, confident).

- **Per-slot confidence:** population, significance (`SignificantVoxelVolume`,
  ≥minPopulation), coverage (`Spec.Coverage` — the metric, *not* MSE). Rendered as cell
  intensity/ring on the grid, so the user *sees* which colours are well-supported.
- **The A↔B residual** (Family 1) **visualised** = what the collapse threw away = the
  motion field. This is the uncertainty made visible.
- **DiversityRing / effectiveDim** — a cheap at-a-glance "how much real colour is here."
- **Status:** significance/coverage **specs exist**; `AtlasBoardView` (16³ curation)
  **shipped, flag-gated**; a unified uncertainty overlay on the main grid **TO BUILD.**

> **Form-follows-function:** the user's choices on this surface (keep/kill/weight a
> region by confidence) are **Bradley–Terry training signal** — log them now, behind the
> Atlas flag. *Consolidates:* `Spec.Significance`/`Spec.Coverage` UI intent,
> `palette-explorer` cloud/treemap (confidence views), DiversityRing.

---

## 6. The NN's place — uncertainty in, genome out, GIF down the ladder

*Ground: probability.* The net is the bridge, not a widget:

```
  per-frame palettes + their uncertainty (Family 3)            user RGBT deltas (Family 2)
                 │  (sum-pooled, permutation-invariant)              │  (structured prior)
                 └───────────────────────┬──────────────────────────┘
                          NN transmutes uncertainty → ONE global σ-pair genome (384-DOF, 2⁸ face)
                                          │
                              reconstruct into 768-leaf palette
                                          │
                    project to the ladder → 16³ / 64³-A,B / 256³-A,B  GIFs (Family 1)
```

- **Transmutes statistical uncertainty:** the net maps *which colours are well-supported
  across frames* into a confident global look — it does not invent colour, it resolves
  uncertainty. The deterministic W₂ barycenter is the floor (Lloyd-Max); the net earns
  its keep only where uncertainty/preference make the barycenter wrong.
- **Preserves user structure:** the RGBT deltas + σ-symmetry are invariants the genome
  must satisfy — so user intent survives the collapse.
- **Learns:** push/pull picks (incl. A-vs-B) train a per-user delta head on-device
  (`AtlasTrainer`/MPSGraph, **proven on hardware**).

---

## 7. Current status & the ONE unblocker (scout-verified)

| Thing | Status |
|-------|--------|
| Cell grid, 16² see-grid, AddressPicker, treemap, AtlasBoard, on-device trainer | **SHIPPED** (AtlasBoard flag-gated) |
| `analyzePaired`, `quad4Analyze`, their laws, `BranchedPalette.swift` | **EXIST** (spec + Swift routing) |
| `CollapsedPalette` carries `branching`/genome; collapse is branch-aware | **NO** — only `{leaves, chosenIndices}` |
| Voxel cube view (`VoxelCubeView`, `.voxel3D` route) | **DOES NOT EXIST** (feature build) |
| `64³-B` global GIF produced; `16³`/`256³` rungs; A↔B residual; cut-lever; uncertainty overlay | **TO BUILD** |

**The one unblocker = branch-parameterize the collapse** so a face-choice (16²/4⁴/2⁸)
reaches the *genome*, not just the display. The analysers already exist — this is **pure
integration** (extend `CollapsedPalette`, add the protocol param, wire cube/re-index/
editor/Atlas in concert), not new spec. Until then every face is display-only and no
user delta reaches a GIF. *(RADIX-CONTROLS §4 Step 1.)*

---

## 8. Consolidation map (what each prior doc now is)

This doc is the **architecture**; the others are **implementation detail under a family**,
not competing designs. Read them *through* the family they serve.

| Family | Authoritative here; detail in |
|--------|------------------------------|
| 0 Cell grid | `SIXFOUR-TOTAL-PIXELATION` (lint), `LatticeContract.swift` (atom) |
| 1 Ladder | `SIXFOUR-FOUR-GIF-UIUX`, `SIXFOUR-PALETTE-STORY`, `SIXFOUR-JEPA-256-SUPERRES` (256³ decode) |
| 2 Delta control | `SIXFOUR-RADIX-CONTROLS` (file:line map), `SIXFOUR-HIGHDIM-UIUX`, `SIXFOUR-COLLAPSE-LEVER-UIUX`, `SIXFOUR-COLOR-WIDGETS`, `SIXFOUR-WIDGET-DESCRIPTOR` |
| 3 Uncertainty | `Spec.Significance`/`Spec.Coverage`, `palette-explorer-2d-3d-4d-design`, `COLOR-ATLAS` |
| bridge NN | `SIXFOUR-MLX-DEPLOYMENT`, `ON-DEVICE-TRAINING`, `COLOR-ATLAS` |
| context/plan | `SIXFOUR-APP-WIDGET-GAP-REPORT` (the gap report this distils) |

Those docs keep their detail; **if any contradicts this one on architecture, this one
wins** and the other gets a pointer header.
