# SixFour — the N×M cell-widget language (and the part that's actually new)

> Utility widgets are **N×M blocks of GIF-pixel cells** — a toggle is a `12×12`, a
> slider a `M×11`, the hero a `64×64`. That vocabulary is **old**: tile-grid layout
> systems, LED-button instruments, and 1-bit pixel UIs have all done it. What is
> **new** here is that every widget's *felt detent* is **frame-locked to the 20 fps
> cell-field refresh** — one cell crossed = one frame = one haptic = one repaint.

Companion to `docs/SIXFOUR-WIDGETS.md` (the *data* widgets: 16²/4⁴/2⁸) and the GRID
v3 lattice. This doc is the *chrome / utility* widget language + its timing.

---

## 1. Prior art — the N×M cell widget is not new

Three independent lineages already treat "a widget = an N×M region of equal cells":

1. **Modular / tile grid layout systems.** A grid panel arranges widgets by
   `row × column` slots, each child carrying a **row-span / column-span** so it
   stretches across cells; tile grids use square modules and a power-of-base unit
   (the classic 8 pt grid). This is exactly our footprint algebra — only our base
   unit is the **GIF pixel (4 pt)**, not 8.
   ([UXPin grids guide](https://www.uxpin.com/studio/blog/ui-grids-how-to-guide/),
   [Smashing — layout grids](https://www.smashingmagazine.com/2017/12/building-better-ui-designs-layout-grids/),
   [UE5 Grid Panel span/offset](https://rambod.net/tutorial/ue5-grid-panel-ui))

2. **LED-button grid instruments** — the closest ancestor. monome (16×8),
   Tenori-on (16×16), Novation Launchpad: a **responsive grid of backlit buttons
   that is simultaneously the display and the input**. monome's defining property
   is *feeding data back to the LEDs* — without it "the system is inherently dumb."
   That is verbatim our **"the grid IS the render surface"** law: each cell is both
   a data-coloured pixel and a touch target, and a widget is a labelled sub-grid.
   ([monome grid docs](https://monome.org/docs/grid/),
   [Yamaha Tenori-on](https://en.wikipedia.org/wiki/Yamaha_Tenori-on),
   [Novation on grid controllers](https://novationmusic.com/en/news/if-we-build-it-they-will-come))

3. **1-bit / low-res pixel UI** — Playdate (Teenage Engineering): tile-based
   layouts, **tile sizes a power of 2**, "constraint breeds clarity." Maps to our
   radix ladder (16² / 4⁴ / 2⁸) and the square-cell pitch.
   ([Designing for Playdate](https://help.play.date/developer/designing-for-playdate/),
   [pixel art as a UI language](https://www.filereadynow.com/blog/pixel-art-for-ui-design-icons-amp-micro-graphics))

**Takeaway:** the *spatial* language (author widgets as N×M cells, span across the
lattice, power-of-2 radix) is settled craft. We adopt it wholesale and stop
describing chrome in free points.

---

## 2. The lattice (the unit every N×M is counted in)

From `SixFour/UI/GlobalLattice.swift` — the atom is the **GIF pixel**:

| Token | Value | Meaning |
|---|---|---|
| `gifPx` (the ATOM) | **4 pt** = 12 device-px @3× | one cell; the content/instrument unit |
| `subPt` | 2 pt = `gifPx/2` | half-atom for fine gutters + text only |
| touch floor | **11 cells** = 44 pt | HIG minimum hit target (exact at 4 pt) |
| secondary square control | **12 cells** = 48 pt | gear / selector segment |
| shutter / palette-as-shutter | **16 cells** = 64 pt | clears the floor |
| hero preview | **64 cells** = 256 pt | 1 GIF pixel per cell (the cube law) |
| gauge ring | **20 cells** = 80 pt | radius fixed in cells for gap-free ticks |

Rule: **a governed widget's footprint is a whole-cell `N×M`, and any interactive
widget is at least `11×11`** (the touch floor). 4 pt was chosen over 6 precisely
because `11·4 = 44` lands the HIG floor on a whole-cell boundary.

---

## 3. The widget REGISTRY — every current widget, in N×M

Surveyed 2026-06-15 against the live app. **Every interactive widget is now
cell-authored** (the lone point-literal holdout, `PaletteCloudView` plane buttons
`minHeight: 44`, was migrated to `gif(touchFloorCells)`). Footprint = `W × H` cells
at the 4 pt atom; `detent` = does dragging it cross cell boundaries that should fire
a frame-locked `CellTick` (§4).

### Chrome / utility widgets (`Components/CellChrome.swift`, `CellControls.swift`)
| Widget | File | Footprint (cells) | Gesture | Detent |
|---|---|---|---|---|
| `CellActionButton` | CellChrome.swift:77 | **11 H × N W** | tap | — |
| `CellSlider` | CellChrome.swift:123 | **M W × 11 H**, knob = 1 lit cell | **drag** | **yes** (caller-flushed today) |
| `CellSelector` (segmented) | CellControls.swift:14 | **N · (segW × 11 H)** | tap | — |
| `CellToggle` | CellControls.swift:51 | **11 H × N W** | tap | — |
| `CellSymbol` / `CellIcon` | CellChrome.swift:10 / CellSprite.swift:124 | **12 × 12** (gear 24×24 @ subPt) | — | — |
| `CellButton` (shutter) | CellSprite.swift:84 | **34 × 34** (`shutterCells`) | tap | — |
| `CellText` / `CellDigits` / `CellRing` | CellText/CellGlyph/CellSprite | content-sized in cells | — | — |
| `GlassIconButton` | GlassControls.swift:26 | **11 × 11** (44 pt, `glassIconButtonSize`) | tap | — |

### Surface widgets (`UI/Surface/*PhaseField.swift`, `MovableColorWidget`)
| Widget | File | Footprint (cells) | Gesture | Detent |
|---|---|---|---|---|
| Motion toggle | ReviewPhaseField.swift:332 | **11 H × N W** (`CellActionButton`) | tap | — |
| **Motion threshold slider** | ReviewPhaseField.swift:353 | **16 W × 11 H** (`CellSlider`) | **drag** | **yes — frame-locked ✓** (the reference impl) |
| `MovableColorWidget` (Field64/Palette16) | MovableColorWidget.swift | **64²** / **16²** footprint | long-press → **drag** | **yes — per `cellsCrossed`, NOT yet frame-locked** |
| group-pick macro-grid | ReviewPhaseField groupPickField | **16 cells** (4×4 of 2×2 quads) | tap | — |

### Selectors built on `CellSelector` (all cell-authored, 11 H)
`RepresentationSelector`, `BranchingSelector`, `ScopeSelector`, `CloudProjection`
selector — each `N · (segW × 11 H)`, tap.

### Data surfaces (the picture, not chrome — see `SIXFOUR-WIDGETS.md`)
`PaletteGridView` 16² · `PaletteTreeView` 16² treemap · `PaletteCloudView` 256-dot
3D (orbit drag, *not* cell-quantised — a continuous 3-D rotation, deliberately
outside the detent contract) · the 64² GIFA hero.

### Detent consistency gap (the next build-on)
Three widgets cross cells on drag, but only ONE is frame-locked:
- **Motion threshold slider** — frame-locked ✓ (flushes on `clock.tick`, §4).
- **`CellSlider`** (generic) — supports the drag + `step` quantisation, but detent
  firing is **caller-added**; it should frame-lock natively so every slider inherits
  the contract.
- **`MovableColorWidget`** — fires `Haptics.play(1)` per `cellsCrossed` boundary
  *directly*, gated only by `tickEvery`, **not coalesced to the 20 fps frame**. It
  predates the contract and should be brought under `lawTicksFrameMonotone`.

So "defining the widgets in this framework" is footprint-complete; the open work is
**unifying the detent**: factor the slider's frame-locked flush into one reusable
mechanism (a `.cellDetent(on: clock)` modifier or native `CellSlider` flush) and route
`MovableColorWidget` through it — then every drag widget obeys one cell = one frame =
one tick.

---

## 4. What's new — the 20 fps frame-locked detent

The interaction algebra already exists: `Spec.CellMechanics` owns the lifetime FSM
(`Resting → Pressed → Lifted → Settling`), the **detent** (each cell boundary a
lifted widget crosses is *one felt* `CellTick`; `cellsCrossed` counts them,
`lawTickConservation` proves none are lost), and the **reactive pulse** (colour/tint
tokens). `Spec.Display` drives the surface at **20 fps** ("every cell I/O @ 20 fps").
Both emit *tokens*; the impure leaves (play a haptic, animate a tint) are Swift-side.

**The novel synthesis: quantise the detent, the pulse, and the repaint to the same
20 fps frame boundary.** Prior art only goes part-way — Apple's Watch crown fires a
detent haptic *synchronised to display/animation events* over a low-latency path,
and VSync-locked haptic rates are known; even small visual↔haptic lag "feels
unnatural."
([Apple crown-detent patent](https://image-ppubs.uspto.gov/dirsearch-public/print/downloadPdf/11797110),
[haptic↔visual sync patent](https://image-ppubs.uspto.gov/dirsearch-public/print/downloadPdf/12340021),
[2025 haptics UX guide](https://saropa-contacts.medium.com/2025-guide-to-haptics-enhancing-mobile-ux-with-tactile-feedback-676dd5937774))
Nobody makes that the **universal contract for an entire grid-cell UI**: here *every*
widget, not one crown, obeys

> **one cell crossed ⇒ one 20 fps frame ⇒ one `CellTick` haptic ⇒ one cell repaint**,
> all on the *same* frame tick.

### Why frame-locking is a feature, not a limitation
At 20 fps a frame is **50 ms**. A detent can fire at most once per frame, so a drag's
felt ticks are **capped at ≤ 20 detents/s** and every tick coincides with a visible
cell-state change. That makes ticks **countable and legible** — you *feel* the same
event you *see*, never a blur of sub-frame buzzes. It also makes the haptic stream
**deterministic**: `cellsCrossed` per frame is integer and golden-pinned, so the
felt output is reproducible across devices, the same way the visual output is.

### The contract (to spec next)
A small extension to `Spec.CellMechanics` / `Spec.Display`, not new geometry:

- **Frame-quantised ticks.** Accumulate `cellsCrossed` within a frame; emit *one*
  `CellTick` token per crossed boundary, but **scheduled on frame ticks** (≤ 1 per
  50 ms slot). Law: tick tokens are conserved (`lawTickConservation` already) *and*
  monotonic in frame index (new: `lawTicksFrameMonotone`).
- **Coincident triad.** The haptic token, the pulse/colour token, and the cell's
  repaint for a given boundary carry the **same frame index** (new:
  `lawDetentTriadCoincident`) — the on-screen change can never disagree with the
  felt tick, the frame-locked sibling of the existing `lawDropColorMatchesMove`.
- **Swift leaf.** A single 20 fps scheduler (the existing `PlaybackClock` /
  display clock) flushes the frame's tick token to `UIImpactFeedbackGenerator`
  and the repaint in the same `CADisplayLink` callback — no per-touch async haptic.

This is the one genuinely proprietary layer: a **provably frame-locked,
device-reproducible haptic detent for an N×M cell-grid UI**, built on the same
20 fps clock and the same golden-pinned cell math as the picture.

---

## 5. Status & next steps
**Done:** (1) chrome authored in cells — `CellActionButton`/`CellSlider`/`CellSelector`/
`CellToggle` carry explicit `N×M` footprint params; the last point-literal holdout
(`PaletteCloudView` plane buttons) is migrated. (2) The frame-locked detent is spec'd
(`lawTicksFrameMonotone` + `lawDetentTriadCoincident` on `Spec.CellMechanics`,
golden-pinned). (3) The QuartetDelta threshold slider is the first frame-locked widget.

**Open — unify the detent (the registry's §3 gap):**
1. **Factor one reusable flush.** Extract the Motion slider's `clock.tick` flush into a
   `.cellDetent(on:clock, cellsCrossed:)` modifier (or a native `CellSlider` flush) so
   detent firing is not re-hand-rolled per call site.
2. **Frame-lock `MovableColorWidget`.** Route its per-`cellsCrossed` `Haptics.play(1)`
   through that mechanism so the drag haptic is coalesced to ≤1/frame — bringing the
   oldest detent widget under `lawTicksFrameMonotone`. Device-feel-verify on iPhone.
3. **Lint.** A grep lint that flags any new `minHeight:`/point literal on an interactive
   widget (keep the registry footprint-complete as the app grows).

Sources: [UXPin](https://www.uxpin.com/studio/blog/ui-grids-how-to-guide/) ·
[Smashing](https://www.smashingmagazine.com/2017/12/building-better-ui-designs-layout-grids/) ·
[UE5 Grid Panel](https://rambod.net/tutorial/ue5-grid-panel-ui) ·
[monome](https://monome.org/docs/grid/) ·
[Tenori-on](https://en.wikipedia.org/wiki/Yamaha_Tenori-on) ·
[Novation](https://novationmusic.com/en/news/if-we-build-it-they-will-come) ·
[Playdate](https://help.play.date/developer/designing-for-playdate/) ·
[pixel-art UI](https://www.filereadynow.com/blog/pixel-art-for-ui-design-icons-amp-micro-graphics) ·
[crown detent patent](https://image-ppubs.uspto.gov/dirsearch-public/print/downloadPdf/11797110) ·
[haptic-visual sync patent](https://image-ppubs.uspto.gov/dirsearch-public/print/downloadPdf/12340021) ·
[2025 haptics guide](https://saropa-contacts.medium.com/2025-guide-to-haptics-enhancing-mobile-ux-with-tactile-feedback-676dd5937774)
