# SixFour — The Influence Field: empty cells become the link between two movable widgets

> Keywords: influence field, two-source radiation, energy/balance/gradient map, interplay ridge,
> movable ColorWidget, authored link, canonical Stage grid, whole-cell rounded rect, Spec.Boundary,
> StageField, blue-noise dither, cell-field law, form-follows-function, future-widget birth map.

**Status:** UI/UX + spec-first build plan (2026-06-09). Companion to `SIXFOUR-ACTS-WORKFLOW.md`
(the five acts; this re-skins Act I's "empty cells" §4 fill plan), `SIXFOUR-DISPLAY-FSM.md`
(the FSM), and the GRID v3.0 lattice (`Spec.Lattice` → `Generated/LatticeContract.swift`).
**SixFour owns all code**; Haskell spec is the source of truth, codegen-pinned.

House style: terse, law-citing, `file:line`-grounded, copy-pasteable seams.

This plan answers two coupled questions, both under form-follows-function:
**(1)** the black-and-white checker "empty space" becomes a **function of the interaction between
the two movable widgets** — color radiating out of Palette16 and Field64, muted where they meet;
**(2)** the cell grid is fixed so **every cell is a whole square that fits the physical screen
(rounded corners included)**, one canonical grid for all five acts.

---

## 0. The problem (as-built, `file:line`)

Act I = `LivePhaseField` (`SixFour/UI/Surface/LivePhaseField.swift:29`). Its ground is
`TintedCheckerField` (`:142`) — a full-screen checker whose two inks are the palette's tonal
extremes (`:192 inks`), inverting at 20 fps (`:153`). It proves *liveness* and nothing else:
the empty cells carry **no information about the two widgets' relationship**.

Two movable heroes sit on it (`Spec.MovableLayout` → `Generated/MoveContract.swift`):
- **Field64** — 64×64 live preview, `previewTile[r·64+c]` through `previewPalette`
  (`LivePhaseField.swift:81`). The colors *arranged in space*. `cwInteractive = False`.
- **Palette16** — 16×16 = the 256-color set AND the shutter (tap → `.shutterTap`)
  (`LivePhaseField.swift:107`). The color *set*. `cwInteractive = True`.

Positions live in `settings.widgetPlacement : [ColorIdentity:(col,row)]`, re-read every `body`
(`LivePhaseField.swift:37`), moved by the long-press-lift FSM (`MovableColorWidget.swift:59`),
committed by `MoveContract.move` (disjoint + in-bounds, `MoveContract.swift:98`).

**Grid mis-fit.** The ground is baked `100×218` and pinned top-leading at physical `(0,0)` with
`.ignoresSafeArea()` (`GridlineField.swift:89`, `LivePhaseField.swift:46/67`). The physical
iPhone 17 Pro screen is a **rounded rect (≈56 pt radius)** with a Dynamic Island, so the four
corner cells + top rows render *under the bezel/island*. Safe-top = 62 pt = **row 15.5** (a
half-cell) — the "top row not fully developed." `act1-live.svg` confirms it: the checker is drawn
with `rx="56"` and labels safe-top at row 15.5.

---

## 1. The functional link (the form, derived from the function)

The data already encodes the link: `previewTile` is **indices into** `previewPalette` /
`surface.palette`. **Palette16 is the color set; Field64 is that set arranged in space.** So the
"influence of the palette onto the preview" is literal and measurable: *which palette colors,
and how much, the live preview is built from.*

> **DECISION 1 (2026-06-09) → USAGE-WEIGHTED INFLUENCE.** Each palette color radiates outward
> from Palette16 with strength = **its usage count in the live `previewTile`**. Dominant scene
> colors radiate brightest/furthest; unused swatches stay dark. Field64 radiates its **edge
> colors** outward in each direction (the preview "bleeds"). You *see* the palette's influence on
> the preview. (Alternatives considered: set↔arrangement flow currents; symmetric two-source
> spray — both rejected as less honest to "influence".)

---

## 2. The MOVABLE link — the user authors it

The widgets move, so **the link is not fixed geometry — the user authors it by dragging.** The
field is a **pure function of `(R_F, R_P, palette, usage)`** where `R_F`/`R_P` are the live cell
rects from `region(for:.field64/.palette16, at: placement)` (`MovableColorWidget.swift:45`).

- Drag them **apart** → a long gradient corridor; the interplay ridge is a wide calm band.
- Drag them **close** → tight, intense interplay; the ridge is a sharp seam.
- Drag one to a **corner** → the field reshapes around the new geometry.

Recompute triggers: a **committed drag detent** (the move FSM already snaps to whole atoms and
fires one `CellTick` per cell crossed — `MovableColorWidget.swift:80`), a palette change, a
preview-usage change. Movability invariance is a field **law** (§5): translating both sources by
the same delta translates the field by that delta; the ridge is always the equal-weight locus.

---

## 3. The field math = THE MAP (energy · balance · gradient)

For each stage cell `p` (inside the Stage §4, not occluded by a widget):

1. **Edge distances** (radiate from the widget *edges*, so color emanates from the widget, not a
   point): `d_F(p)` = cells from `p` to nearest cell of `R_F`; `d_P(p)` = same for `R_P`.
   Reuse `CellGeom.dist` (`CellSprite.swift:64`); clamp to a max reach `R`.
2. **Source weights**, falloff → 0 at reach `R` (far cells go calm/dark):
   `w_F = falloff(d_F)`, `w_P = falloff(d_P)`, quantized Q16 (integer-exact, spec-portable).
3. **THE MAP — three quantities per cell:**
   - **energy** `E = w_F + w_P ∈ [0,1]` — high near either widget, ≈0 in the far calm.
   - **balance** `b = (w_P − w_F)/(w_P + w_F) ∈ [−1,+1]` — −1 pure preview, +1 pure palette,
     **`b = 0` = the interplay ridge** (the equal-weight locus = the literal *link line* between
     the two widgets). It slides as they move.
   - **gradient** `∇E`, `∇b` per cell — the **motion map**: a future widget is born at a source
     and animates *downhill along ∇E* (flow outward) or *travels the `b=0` ridge* from Palette16
     to Field64. **This is the reason the feature exists** — the colors' movement is mapped so the
     birth/animation of future widgets has a defined field to follow.
4. **Color of each source at `p`** (Decision 1): Palette16 → the usage-ranked palette color for
   `p`'s angular/radial address about `R_P`'s center (strong colors reach further); Field64 → the
   preview edge color in `p`'s direction.
5. **Compose:** mix the two source colors by `b` (near a source = its color at full chroma); at
   the ridge (`b≈0`) **mute** toward a dark neutral (the muted interplay the user asked for);
   multiply by `E` so the far field fades to near-black.

> **DECISION 2 (2026-06-09) → HYBRID TEXTURE (potential × blue-noise dither).** `(E,b)` set
> per-cell strength + muting; an **ordered blue-noise dither** picks the discrete sRGB8 per cell.
> Reads as pixel-noise radiating (matches the app's dither ethos / `sixfour-palette-accel`
> blue-noise infra), not a flat gradient. The 20 fps heartbeat advances the noise phase, so the
> field *breathes* riding the link instead of a flat parity invert.

---

## 3a. Universal across acts + never-pause (2026-06-09 amendment)

The field is no longer Act I only — it is **the ONE universal ground for every act**, and it
**never pauses**. Two generalisations, both as-built:

**(a) The rule generalises to N sources (a Voronoi of order).** "The widgets, whatever they are,
are ORDER; every other cell is CHAOS radiating out of them." With two widgets the seam was the
`b=0` ridge; with *any* number it is wherever the **top-two** sources' weights are comparable:
`energy = Σ_s w_s`, the **dominant** source colours the cell, and the **runner-up ratio**
`w₂/w₁ → 1` mutes toward the neutral (the chaos seam). Each source is a `FieldSource {rect, kind}`
— `.arrangement` bleeds a tile (the preview / GIFA frame), `.set` radiates the usage-weighted
palette wheel. Add a widget in any act → pass it in `InfluenceField(extraSources:)` and it simply
becomes another radiating source. Today the two persistent movables are the sources in every phase;
the per-act widgets (filmstrip, scrub rail, gate, collapse lever …) register as extras as they land.

**(b) Each act feeds its own real data.** `InfluenceField.arrangement(of:)` picks the best 64×64
tile + palette for the phase — the **live camera** in `.live`/`.capturing`, the **GIFA frame at the
cursor** (through its per-frame palette) in `.rendering`/`.review`. Empty ⇒ arrangement sources fall
back to radiating the palette, so the ground is never blank.

**(c) Never-pause = driven by the monotonic `tick`, not the 0/1 heartbeat.** The breathing cycles
`tick % phases` over an N-frame (`FieldTuning.phases`) noise ring; `SurfaceClock.tick` advances
every κ fire while the window is active, so the field keeps breathing through data gaps, phase
changes, and drags — as basic as the cell grid itself. (`heartbeat` was a 0/1 parity that a static
canvas pins; it only ever flipped two baked frames.) Bakes happen on `bakeKey` change only (NOT
`tick`), so cycling pre-baked frames is the cheap, always-on motion.

**Wiring:** `LivePhaseField`, `CapturingPhaseField`, `RenderingPhaseField`, `ReviewPhaseField` all
ground on `InfluenceField(surface:placement:tick: clock.tick)`. Bootstrap / unauthorized / error /
settings keep the masked B/W checker (`GridRefreshFieldView`) — they are not acts and carry no
widgets/data. Tunables live in the nonisolated `FieldTuning` enum.

---

## 4. The canonical Stage grid (whole cells, rounded, all acts)

The fix is 90% built: `Boundary` (`SixFour/UI/Components/Boundary.swift:13`) already encodes an
inset rounded rect stepped in **whole cells** — `insetTop=16` (64 pt clears the island),
`insetBottom=10` (clears home), `insetX=3`, `cornerCells=14` (56 pt = device radius), integer
Euclidean corner test (`:37 inside`). Today it is only the movable-widget fence
(`footprintFits`, `:47`) + a thin cyan outline (`BoundaryView`, `:66`).

> **DECISION 3 (2026-06-09) → PROMOTE Boundary TO THE FIELD EXTENT (the "Stage").** Render cells
> only where `Boundary.inside(c,r)`; outside → `nil` (transparent) → `.background(Color.black)`
> (= the bezel). The field becomes a **rounded rect of whole 4 pt squares floating on black** — no
> clipped corners, no half-row, nothing under the island. It is a property of *the surface* (not a
> phase), so **all five acts** inherit it. Coordinate space stays `100×218`; the Stage is a *mask
> predicate*, not a new lattice. Move-bounds already use `footprintFits`, so widgets are already
> confined to the rounded interior — consistent.

**Spec-pin it.** `Boundary.swift`'s own doc says "promote to a golden-pinned spec module when the
boundary phase lands." That is now: new **`Spec.Boundary`** (Haskell) → `Generated/BoundaryContract.swift`
(`StageContract` is taken by `SixFourShape`). Laws: `inside ⊆ lattice`, `footprintFits ⇒ 4
corners inside`, corner is the mirrored quarter-disc, `isOutline ⊂ inside`, all insets/radius are
whole cells. Golden vector = a sampled `inside`/`isOutline` bitmap digest.

---

## 5. The spec (Phase 3, after the look is approved) — `Spec.InfluenceField`

A pure, integer/Q16 field over the Stage, codegen-pinned, with laws:
- **falloff-monotone:** `d ≤ d' ⇒ w(d) ≥ w(d')`; `w(d≥R) = 0`.
- **ridge:** `w_F(p) = w_P(p) ⇒ b(p) = 0`; `b` strictly increases as `w_P/w_F` grows.
- **far-calm:** `E(p) → 0` as `min(d_F,d_P) → R` (the field never lights the whole screen).
- **movability-invariance:** translate both sources by `δ` ⇒ field translates by `δ` (the map is
  geometry, not pixel-anchored).
- **occlusion:** a cell under a widget footprint is not in the field domain.
- **conservation (texture):** the blue-noise dither over a region reproduces the region's mean
  `(E,b)` color (no DC drift) — the standard dither golden.
Golden vectors pin the `(E,b)` map + a dithered swatch for a fixed `(R_F,R_P,palette,usage)` case.
Document the **animation-map contract**: the exact `(E,b,∇)` a future widget reads to be born +
animated (the durable artifact).

---

## 6. Performance (movability-aware)

Field depends on `(R_F, R_P, palette inks, bucketed usage histogram)` — positions change only on a
committed drag detent; palette/usage ~10 fps. Bake the `100×218` bitmap **on change** (same cache
discipline as `TintedCheckerField.ensure`, `LivePhaseField.swift:172`); re-bake per committed
cell-tick during a drag. 20 fps breathing = pre-bake a small ring of **N noise-phase frames** and
swap (the O(1)-flip discipline, `GridlineField.swift:74`). Measure on device; Metal compute is
contract-allowed (CLAUDE.md) if the CPU bake is too slow — **prototype CPU-first**.

**Shared ground.** Refactor the per-phase grounds (`TintedCheckerField`,
`GridRefreshFieldView`) into ONE `StageField` (`SixFour/UI/Components/StageField.swift`, new)
masked to the Stage and parameterized by "the active sources for this phase" (default
Field64+Palette16). One ground, one grid, every act.

---

## 7. Build plan (gated by `scripts/s4.sh all`)

- **Phase 0 — this doc.** Add the `Spec.Map`-adjacent index entry per the maintenance contract.
- **Phase 1 — Stage grid fix (§4), spec-pinned.** `Spec.Boundary` + golden + `Codegen.Swift` →
  `Generated/BoundaryContract.swift`; `Boundary.swift` becomes the typed facade; new `StageField`
  masks the cell closure to `Boundary.inside`; refactor `LivePhaseField` + sibling phase fields.
  Gate: `s4 verify` (boundary golden) + `s4 lint` (GRID) + `s4 build`. On-device: rounded
  whole-cell field, clean corners/top.
- **Phase 2 — Influence field prototype (§§1–3) in Swift.** New `InfluenceField.swift` computing
  per-cell `(E,b,color)` (usage-weighted + hybrid texture), on-change bake + N-phase noise ring;
  wire into `StageField` for `.live`/`.capturing`. Gate: `s4 build` + on-device tuning; **confirm
  the look with the user.**
- **Phase 3 — Formalize (§5).** `Spec.InfluenceField` + golden + codegen → port Swift to the
  contract, re-fold parity; document the animation-map contract.

## 8. Files

- **Phase 1:** `spec/src/SixFour/Spec/Boundary.hs` (new) · `spec.cabal` · `Spec/Map.hs` ·
  `Codegen/Swift.hs` → `SixFour/Generated/BoundaryContract.swift` · `SixFour/UI/Components/Boundary.swift`
  (facade) · `SixFour/UI/Components/StageField.swift` (new) · `LivePhaseField.swift` + sibling
  phase fields.
- **Phase 2:** `SixFour/UI/Components/InfluenceField.swift` (new); reuse `CellBitmap`/`CellSprite`,
  `CellGeom`, blue-noise infra, `region(for:at:)` + `settings.widgetPlacement`,
  `surface.previewTile`/`palette`.
- **Phase 3:** `spec/src/SixFour/Spec/InfluenceField.hs` + golden + `Codegen/Swift.hs`.
- **Never** hand-edit `SixFour/Generated/*` — edit `spec/src/SixFour/Codegen/` + regenerate.

## 9. Open questions (carried)

- Falloff shape (linear vs `1/(1+d)`) and reach `R` (cells) — tune in Phase 2, pin in Phase 3.
- Mute target (pure dark neutral vs. a desaturated blend of the two source colors) at `b=0`.
- Does the field also animate a *flow* along ∇E at rest (drifting noise), or only breathe in
  place? (Affects whether Phase 3 needs a per-frame flow term.)
- Should `.review`/`.rendering` use different sources (e.g., the collapse lever) or the same two?
