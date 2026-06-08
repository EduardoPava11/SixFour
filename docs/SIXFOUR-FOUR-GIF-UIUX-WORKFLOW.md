# SixFour — The Four-GIF Preview→Commit UI/UX (GIFA→GIFC→GIFB+GIFD)

> Keywords: GIFA/GIFB/GIFC/GIFD, 4pt atom, GIFD exception, 16²/4⁴/2⁸ widgets, quartet, 4-frame delta,
> R,G,B,T, tap-to-inspect, spatio-temporal color deltas, SIMD, collapse lever.

**Status:** UI/UX workflow (2026-06-08). Companion to `SIXFOUR-COLLAPSE-LEVER-UIUX.md` (the lever),
`SIXFOUR-PALETTE-IS-MOTION-WORKFLOW.md` (the math), `Spec.CollapseLever` (compiles, laws green).
**SixFour owns all code; determinism is the decision — the user steers via cell widgets, not an NN.**

---

## 0. The four GIFs (locked naming)

| GIF | Size | What it is | When |
|---|---|---|---|
| **GIFA** | 64×64 × 64f | capture: **per-frame** palettes (64 diverse palettes) | after burst |
| **GIFC** | 16×16 × 16f | **collapse preview**: the global palette, coarse | before commit |
| **GIFB** | 64×64 × 64f | commit: the **global** palette applied | on commit |
| **GIFD** | 256×256 × 256f | super-res render from the global palette | on commit/export |

Flow: **capture GIFA → inspect frames + palettes + deltas → mark what matters (2⁸/4⁴/16² widgets) →
preview GIFC → commit → render GIFB + GIFD.**

---

## 1. The pt law + the GIFD exception (decided)

**Standard atom = 4pt** (grid-v3). One pt size everywhere. At 4pt the cube ladder is an honest physical
size ladder:

```
GIFC  16²  @ 4pt = 64pt     ✓ fits
GIFA  64²  @ 4pt = 256pt    ✓ fits (today's hero)
GIFB  64²  @ 4pt = 256pt    ✓ fits
GIFD  256² @ 4pt = 1024pt   ✗ ≈4× the 402pt screen
```

**GIFD is the ONE sanctioned exception.** It does NOT obey the 4pt atom; it renders **fit-to-screen**
(its own pt — ~1.5pt/cell ⇒ ~384pt square within the 402pt width, or 1pt ⇒ 256pt with margin). This is a
deliberate, documented carve-out — *not* a per-level pitch trick. Everything else (`16²/4⁴/2⁸`, GIFA, GIFB,
GIFC, all chrome) stays pure 4pt. The 256 frames scrub through the one `PlaybackClock`.

> Rule of the exception: GIFD is the only surface allowed off-atom, and only because `256² @ 4pt` exceeds
> the device. It is rendered, not paned. Lint allows GIFD; forbids off-atom anywhere else.

---

## 2. The three widgets — tappable grids over the 256 palette

Three honest views of the same 256 colors, all on the 4pt atom, all **tappable**:

| Widget | On-screen | Order / structure | Tap reveals |
|---|---|---|---|
| **16²** | 16×16 grid (64pt² @4pt) | rank (color identity) — the palette | color OKLab + slot + stats |
| **4⁴** | the **quartet**: 4 frames × (4×4) | R,G,B color × **T = 4 frames** | the color's 4-frame trajectory + Δ |
| **2⁸** | 16×16 grid, Haar 8-bit order | σ-pairs adjacent (`cᵢ, σ(cᵢ)`) | the pair + 8-bit drill path |

`2⁸` default = **Haar-ordered 16×16 grid** (consistent square, pairs adjacent). One-line switch to a
`128:2` pair-list if the mirror structure should be foregrounded.

Backing (all **byte-exact, already built**): `BranchedPalette.projectQ16` with `Branching {b16,b4,b2}`,
golden `GenomeFixedGolden`; `Spec.CollapseLever` supplies `(tree, cut) → palette + reindex`.

---

## 3. Spatio-temporal motion, as color deltas (the R,G,B,T breakdown)

A pixel event `(x,y,t) → color`; we track the palette measure, so motion splits into two color-delta kinds:

- **R,G,B (appearance):** where color mass sits in OKLab and how it transports. Shown by **16²** (static
  face). A delta = a color sliding to a new OKLab position (OT displacement).
- **T (temporal, 4 levels = 4 frames = one quartet):** how the palette evolves across the quartet. Shown
  by **4⁴**. A delta = a color's frame-to-frame change within the 4-frame window.

`4⁴ = R·G·B·T`, each at 4 levels ⇒ the 4th axis **is** time, a 4-frame quartet. So **64 frames = 16
quartets × 4 frames**, and the delta preview shows **≤ 4 frames at a time** (one quartet). Per color, a
quartet is a 4-sample trajectory; the deltas are `Δ₁=f2−f1, Δ₂=f3−f2, Δ₃=f4−f3`. Zero → static
(background); non-zero magnitude = OT motion-energy. This is the user's "important" signal.

### The preview layout
```
┌──────────────────────────────┐
│ HERO  (4pt)                   │  GIFA / GIFC / GIFB in the 256pt square
│  64²@4pt = 256pt              │  (GIFD = the fit-to-screen exception)
├──────────────────────────────┤
│ 16²  palette face  (R,G,B)    │  256 colors, static, tappable
├──────────────────────────────┤
│ 4⁴  quartet delta  (T)        │  f1 f2 f3 f4 — color motion, ≤4 frames
│   ▸ quartet 1..16 scrub       │  16 quartets span the 64 frames
└──────────────────────────────┘
```

---

## 4. Tap-to-inspect (the grid/cell hardening)

One consistent gesture across all widgets and all four GIFs: **tap a cell → info popover** — the color's
OKLab value, slot index, its 4-frame delta / temporal signature (DC/low/mid/high band), and which
pair/quadrant it belongs to. Implemented as a cell-rendered overlay (pixelation law: no SwiftUI chrome).
Reuses the `CellSprite` hit-test + `GlobalLattice` coordinates.

---

## 5. The flow (Surface FSM)

```
.review (after burst)
  hero:    GIFA 64²@4pt           (CellSprite over surface.gifCell)        [BUILT]
  16²:     palette face, tappable                                          [BUILT — add tap-inspect]
  4⁴:      quartet delta, ≤4 frames, scrub 16 quartets                     [TO BUILD]
  2⁸:      Haar-ordered grid, tappable                                     [TO BUILD]
  lever:   tree selector + cut slider → one palette                        [Spec done; slider TO BUILD]
  marks:   tap widget cells → "important" set                              [TO BUILD]
  preview: GIFC 16²@4pt=64pt, live on lever/mark change                    [TO BUILD — small]
        │ user adjusts (tree, cut) + marks; GIFC updates live (cheap, no re-encode)
        ▼ [Commit]
  σ.step(.commit) → renderGlobalPalette(branching,cut,marks)
        → GIFB 64²@4pt (hero updates)                                      [wire FSM]
        → GIFD 256² fit-to-screen exception (+ Share)                      [TO BUILD]
```

`★ One palette, four renders:` `(tree, cut, marks)` computes ONE global palette; GIFC/GIFB/GIFD are that
palette at resolutions {16³, 64³, 256³}. GIFC is the honest coarse proxy you approve **before** paying for
GIFB/GIFD.

---

## 6. SIMD path (the requirement)

Everything on the interaction path is vector-shaped:

- **Quartet delta** = a fixed **4-frame** window → NEON 4-lane (or 4×16-byte block) per color; 256 colors
  = 16 vector rows. Cheap enough to recompute live.
- **16² face** = 256 cells = sixteen 16-byte rows (the QUAD `@Vector(16,u8)` lingua franca).
- **Collapse** (maximin / barycenter) reuses the SIMD `s4_quantize_frame` seed path; the **1D sliced-OT**
  for deltas/barycenter is sort-based (SIMD-sortable), deterministic, no tuning param (motion doc §4).
- **16³ downsample** (GIFC) = box-decimate 4× spatial + 4× temporal stride — pure SIMD.
- **GIFD super-res** = index `replicate4x` (Phase 0, byte-exact) → OT/flux super-res (Phase 1).

Compute timing: **precompute deltas + collapse candidates once when GIFA lands** (one SIMD pass, cached);
lever/mark edits re-derive from cache (instant). Live full recompute only if a future need demands it.

---

## 7. Build ledger (reuse-first)

| Piece | Reuse | New |
|---|---|---|
| Hero GIFA/B/C | `CellSprite`, `surface.gifCell`, `PlaybackClock` | — |
| **GIFD (exception)** | `GIFEncoder`, index domain | fit-to-screen render mode + `replicate4x` |
| 16² face | `PaletteGridView` (golden) | tap-inspect overlay |
| **4⁴ quartet delta** | `Quad4` genome (byte-exact) | quartet view + 4-frame delta + scrub |
| **2⁸ Haar grid** | σ-pair genome + Zig `s4_haar` | Haar-ordered 16×16 + tap-inspect |
| Cut slider | `SplitTree.view().collapse()`, `Spec.CollapseLever` | cell-rendered slider |
| "important" marks | `ColorIdentity` brushing | mark-set + collapse bias |
| GIFC live preview | `CellSprite`, `Spec.PreviewProxy` | `previewSmall16` widget |
| Tap-inspect | `CellSprite` hit-test, `GlobalLattice` | info popover (cell-rendered) |

---

## 8. Specs to write (spec-first; CollapseLever already done)

1. `Spec.QuartetDelta` — 64f → 16 quartets; per-color 4-sample trajectory + Δ + motion-energy. Laws:
   static color ⇒ zero Δ; Δ sums telescope; quartet count = 16. SIMD-shaped (4-lane).
2. `Spec.PreviewProxy` — deterministic 64³→16³ downsample through the collapsed palette (no re-quantize).
3. `Spec.Export` — 64³→256³ `replicate4x` (byte-exact) + OT/flux super-res hook.
4. `Spec.Inspect` — tap (cell) → record (color, slot, band, pair/quadrant); golden the lookup.
5. `Properties.CollapseLever` — QuickCheck `lawReindexTotal`/`lawGamutClosed` + golden vs the 3 genomes.

---

## 9. Open / honest
- `2⁸` defaulted to Haar-ordered grid; `128:2` list is a one-line switch if wanted.
- GIFD exception pt (1pt vs 1.5pt fit) — pick when wiring the render mode; both fit 402pt width.
- "important" marks bias the collapse — exact mechanism (lock vs weight vs per-branch cut) still to pick
  (see `SIXFOUR-COLLAPSE-LEVER-UIUX.md` §2.4); does not block the rest.
