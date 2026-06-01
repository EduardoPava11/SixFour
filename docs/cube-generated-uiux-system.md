# SixFour — The Cube-Generated UI/UX System

**Status:** spec (source of truth → Haskell golden → SwiftUI/Metal)
**Target:** iPhone 17 Pro (402×874 pt @3x), iOS 26, Tier‑2 zero‑dep (Apple frameworks + simd only)
**Date:** 2026‑05‑31
**One sentence:** *The 64×64×64 GIF is not the content of the UI — it is the law of the UI. One lattice sizes every dimension, one palette colours every surface, one clock drives every frame.*

---

## 0. The clash this resolves

The content layer already obeys the cube (`gifCellPt=6 → gifCanvasPt=384`, `paletteCellPt=24`, integer‑snapped `PixelGrid`, one `Color(srgb8:)`, one `frameIndex`). The **chrome layer does not**: every control is a Liquid‑Glass circle/capsule, every size is arbitrary (84/70/44/60/49/40/14/10/4), the preview wears a hard `Rectangle().strokeBorder(white 0.5)`, and the background is inert `Color.black`. This document extends the cube's law — already proven on content — to chrome, colour, and the canvas frame, **without** breaking the flat‑cell LOOK contract or HIG/WCAG.

Three layering rules are inviolable and survive intact:
1. **Glass = chrome material only**, never on content cells (`GlassControls.swift:12‑14`).
2. **PixelGrid = content renderer only** — the 64×64 tile, the GIF, the ≤256 palette strip (`PixelGrid.swift:14‑16`).
3. **No AA/opacity/rounding on a data cell** — the golden‑gated flat‑cell contract.

The synthesis below honours all three. Where the adversarial critiques flagged violations (PixelGrid‑on‑glass, sub‑44pt glyphs, OKLab‑as‑luminance, conditional flickering frame), this spec adopts the **corrected** position, not the original design.

---

## 1. The unifying system: cube → cell pitch → modular scale

### 1.1 Two quanta, no third

The cube exposes exactly two on‑screen pitch units. **These are the only legal chrome sizing quanta. No chrome dimension may be a free point value.**

| Symbol | Token | pt | Meaning | 8pt‑grid compatible? |
|---|---|---|---|---|
| **u** | `gifCellPt` | 6 | one GIF fat‑pixel | — |
| **P** | `paletteCellPt` | 24 = 4u | one of the 256 palette cells (a 4×4 GIF block) | yes (24 = 3×8) |

`P = 24` is the keystone: it is simultaneously a cube cell, a multiple of Apple's 8pt layout grid, and `2P = 48` equals Material's 48dp comfortable target. The cube and the HIG grid **already agree** — we are not bending one to the other.

### 1.2 The modular scale (every UI dimension lives here)

Legal sizes are `n·u`, **preferring** integer multiples of `P`:

```
 6  (1u)   — gutter (decoration only), corner radius, hairline rhythm
12  (2u)   — comfortable inter-control gutter, shutter dead-zone
24  (1P)   — minimum visible secondary mark
36  (6u)   — (not used as a hit target)
48  (2P)   — SECONDARY control side (gear, toggles, selector segments) = visible AND hit
72  (3P)   — PRIMARY control side (the shutter)
84  (14u)  — DiversityRing diameter (= 72 + 2u + 2u clearance)
384 (64u)  — the canvas (the cube's edge, untouched)
```

**Off‑lattice numbers being retired:** 70, 60, 49, 40, 14, 10, 7, 4, and the floating `44`. The current `84` survives **only** re‑expressed as `14·gifCellPt` for the ring (where 84 is a coincidence of geometry, not a magic number).

### 1.3 The completeness rule (Rams §8, "nothing left to chance")

> A chrome dimension is **legal** iff it equals `n·gifCellPt` AND, if it is a hit region, `≥ 44pt`.

This single predicate is golden‑gateable in Haskell exactly like the flat‑cell LOOK contract: enumerate every SFTheme chrome token, assert each `% 6 == 0` and (for hit regions) `≥ 44`. The build fails on any arbitrary point value. **This is the operational meaning of "64×64×64 == GIF is the seed of the whole UI."**

---

## 2. Per‑element sizing — the answer table

See the structured `sizingTable` for the machine‑readable version. Headlines:

- **Capture button: 72pt = 12u = 3P.** A 12×12‑GIF‑cell square. (Full justification §3.)
- **Settings gear / any secondary icon button: 48pt = 8u = 2P**, visible **and** hit (no sub‑44 glyphs — adversarial fix adopted).
- **DiversityRing diameter: 84pt = 14u**, re‑derived as `shutter(72) + 2u clearance per side`. The 64 ticks still map 1:1 to the 64 frames; ring geometry need not shrink (this is the critique‑endorsed reconciliation — 72→84 keeps today's tick legibility).
- **Selector segment (Review): 48pt square**, replacing capsules.
- **Inter‑control gutter: 12pt (2u) minimum between interactive controls** (adversarial fix — the 6pt min is decoration‑only); 6pt for control‑to‑decoration.
- **Corner radius on square glass controls: 0pt (true cell) preferred; 6pt (1u) tested fallback.** Decision §4.3.
- **Background:** palette‑derived wash, not `Color.black` (§5).
- **Preview frame:** removed; replaced by a static, contrast‑adaptive 1px edge over a palette‑matched gutter (§5).

---

## 3. Capture button — the principled answer

> **The capture button is 72pt on a side: a 12×12 grid of the cube's own cells (12·`gifCellPt`), exactly 3 palette cells, 216 device px @3x. Stated in the cube's voice: "twelve cells of the cube on a side."**

### Why 72, not 84, not 48

- **84 is off‑lattice.** `84/24 = 3.5` palette cells — a non‑integer. It was never declared as a cube quantity; it is the arbitrary number the user's literal question ("what is the size of the capture button?!") targets. `70` (inner) is equally arbitrary. **72 is the largest exact palette‑cell integer (3P) at or below today's footprint.**
- **48 is the *secondary* size.** It is correct for the gear and toggles (clears 44pt HIG, equals Material 48dp, sits in the MIT 45–57px finger range). But the shutter is the **one unmissable primary action**: thumb‑zone research (Hoober: 49% one‑handed, 67% right thumb, 75% of touches thumb‑driven) says the single primary action belongs bottom‑center and should be the **largest** target. The adversarial critique on the 48pt design was explicit: *"48pt for the primary, frequently‑tapped, one‑handed trigger under hand motion is below comfortable even though it clears the 44pt floor; 72pt stays exactly on‑grid and preserves shutter primacy."* **72 it is.**
- **72 sits in the best‑in‑class comfort band.** Halide and Apple's stock shutter read ~70–90pt visually; 72 ≈ Material's 76dp "gloves/driving" generous tier. Above the 44pt floor with wide margin, on‑lattice, thumb‑reachable.

### Shape and behaviour

- **Square, corner radius 0** (a true cell), not a circle — the shutter *is* the cube's footprint. (Round‑vs‑square decision §4.4.)
- **Solid fill, not a PixelGrid.** The critiques unanimously reject rendering a second flat grid stacked under the live 64×64 canvas ("two flat-cell grids stacked… breaks the I/O‑appliance rule that the canvas is the only grid surface"). The shutter expresses its cube‑ness through its **72 = 12u dimension**, not through a competing mini‑grid. Idle = solid (palette‑accent or white, contrast‑clamped); **busy = the square recolours (red‑band fill) and exposes an `accessibilityValue` for progress** (replacing the current `ProgressView` semantics).
- **Position unchanged:** bottom‑center thumb green zone. This is already best‑in‑class; do not relocate.
- **Gesture:** single tap fires the 64‑frame burst. Press‑and‑hold is **reserved and documented**, never overloaded — the whole product *is* the burst, so a single deliberate tap is the clearest mental model.
- **Ring:** the 64‑tick DiversityRing (84pt = 14u) survives as the one signature round gauge, justified because **64 is a cube count** (frames). Ticks become square (1u) rather than capsules, so the lattice is total (§4.4).

---

## 4. Buttons as square grids, reconciled with Liquid Glass + 44pt

### 4.1 Separate MATERIAL from SHAPE

`.glassEffect(_, in:)` and `.buttonStyle` accept any `Shape` — `.circle`/`.capsule` are **defaults, not rules**. A square glass control is sanctioned iOS 26 chrome (Conor Luddy Liquid Glass reference). Therefore:

> **Glass = how a control is lit. The cube = how it is shaped. The palette = how it is tinted.**

Every control becomes a square glass **material** frame whose shape is `RoundedRectangle(cornerRadius: 0…6)`. The mark inside stays a **centered SF Symbol** (for legibility, Dynamic Type, and VoiceOver) — **not** a PixelGrid (critique §LOOK, adopted: PixelGrid is the *content* primitive; putting it on glass inverts the documented split and 8×8 auto‑rasterised symbols are illegible blobs).

### 4.2 Hit target = visible target (no invisible slugs)

Adversarial fix adopted in full: **the visible square must equal the tappable square.** No sub‑44pt glyph with a 48pt invisible hit region (an HIG anti‑pattern — users aim at what they see, and oversized slugs steal neighbour taps). Every interactive square is **≥48pt, visible and hit**. A 6pt/24pt single cell is never tappable alone; aggregate cells until ≥48pt.

### 4.3 Corner radius decision

Binary and testable: **ship `cornerRadius = 0` (true cell)** for the cube LOOK. If the `.regular.interactive()` specular highlight on a 0‑radius glass square reads as a rendering bug on device, fall back to **exactly `1u = 6pt`** and document the measured result. Do **not** leave 6pt as an untested default (the card‑vs‑cell ambiguity flagged by every critique). Retire `pillCorner=14`/`cardCorner=10`/`stripCorner=4`; any non‑square chrome strip quantizes to 6pt multiples.

### 4.4 The round‑vs‑square seam (resolved, not left half‑done)

The critiques' single most‑repeated LOOK objection: a square shutter inside a round ring is "a leftover." **Resolution: commit fully.** The DiversityRing stays *round* (its roundness encodes the 64‑frame cycle — a justified signature), but its **64 ticks become square 1u marks** instead of `Capsule()`s, so the only curvature in the whole UI is the gauge's circular *path*, and every *mark* on screen is a cube cell. No half‑state ships.

### 4.5 One container, concentric corners

All square controls share **one `GlassEffectContainer`** (glass cannot sample glass) for correct shared sampling and morph transitions. Use `.containerConcentric` corners so nested squares stay aligned (parent radius − padding). `glassClusterSpacing: 10 → 12` (2u).

### 4.6 Review action row is the one exception

`Share / contact‑sheet / Retake` (`GIFReviewView.swift:165‑186`) **stay Apple `.glass`/`.glassProminent` text+symbol buttons.** Pixelating text‑bearing buttons wrecks legibility and abandons Dynamic Type (critique, adopted). The square‑grid language governs **icon‑only chrome**; document this scope boundary explicitly.

---

## 5. Preview blends into the background

### 5.1 The technique (blend lives OUTSIDE the tile)

The content tile is **untouched**: `PixelImage` keeps `.interpolation(.none)`, integer `edge = canvasEdge(forAvailable:cells:64) = floor(w/64)*64`, hard square fat‑pixels. The LOOK contract forbids AA/opacity on cells, so **blend is achieved in chrome painted around the tile**, never by softening it. Three layers, all on the lattice:

1. **Delete the hard frame.** Remove `Rectangle().strokeBorder(white 0.5)` (`CaptureView.swift:82‑85`). For Review, **parameterise** `pixelFrame(bordered:)` rather than deleting globally (critique fix: Review is a *document* in a scrolling stack and needs separation; Capture is an *immersive canvas* and does not).
2. **Palette‑matched gutter, not a stroke.** A 1‑cell (6pt) ring of the palette‑derived ground surrounds the 384pt canvas. Figure/ground is held by a **deliberate modular gap** (Swiss gutter), so the outermost fat‑pixels meet a near‑matching field and dissolve. This is Halide's "nothing obstructs the viewfinder" + iOS 26's see‑through chrome — generated from the cube, not from fixed black.
3. **No soft feather.** The critiques converged: a continuous alpha falloff abutting discrete cells reads as photographic bloom — the opposite of the 8‑bit idiom. **Drop the feather; use the hard modular gutter only.** If a transition is wanted, it must be a **stair‑stepped band of N discrete cell‑wide flat fills** (each a flat colour), so the blend stays on the 6pt grid.

### 5.2 The legibility safeguard (a flat cell against a near‑equal ground has zero guaranteed contrast)

A **static, always‑on, contrast‑adaptive 1px edge**:
- Compute **one** frame colour (light or dark, luminance‑flipped) **once per scene‑settle**, from the canvas‑edge mean luminance — **not** per‑20fps‑frame, **not** per‑edge‑cell.
- This kills three things the critiques flagged: the partial/broken frame ("3 sides, gap on one — reads as a bug"), the per‑frame **flicker/photosensitivity hazard** (WCAG 2.3.1), and the main‑thread per‑frame contrast scan.
- It is chrome over the invisible `canvasEdge` layout frame (PixelGrid contract untouched). Pin "the canvas can never visually vanish" as a **verified spec invariant**, not a runtime hope.

---

## 6. Palette‑driven background & chrome colour

### 6.1 The cube colours the room

Replace `Color.black.ignoresSafeArea()` (`CaptureView.swift:50`, `GIFReviewView.swift:18`) with a **palette‑derived ambient wash**. The hook is already partly wired: `SFTheme.accent(SIMD3<UInt8>, towardWhite:0.45)` + `vm.sceneTint` already tint the gear icon and lit diversity ticks. Extend the **same deterministic 256‑colour table** to paint:
- **Background** = the palette's low‑chroma OKLab summary (darkest population‑significant cell), chroma scaled ~25%, **L clamped to a dark band** so the room is a recognisably‑hued near‑black (deep maroon on a red scene, deep green on a forest scene) — never a bright distraction.
- **Chrome accent / selection** = `vm.sceneTint` (existing), extended from gear‑only to every square control.

This answers *"what about the colours that make up the preview?"*: the chrome is **literally sampled from the cube, every frame, on the one clock** (Rams: colour is functional, not decorative).

### 6.2 Four mandatory accessibility guards (the Apple Music shipped‑then‑fixed bug)

1. **TRUE WCAG luminance, not OKLab L.** *(Blocking correctness fix from the critiques.)* OKLab L is perceptual lightness, **not** WCAG relative luminance. Build `relativeLuminance(_ srgb8)` from linearised sRGB (`Y = 0.2126·R_lin + 0.7152·G_lin + 0.0722·B_lin`, reusing `okLabToLinearSRGB`), then `contrast = (max+0.05)/(min+0.05)`. Clamp every text pairing to **4.5:1** and every non‑text boundary to **3:1**. A gate built on OKLab L passes/fails the wrong colours and *re‑ships* the exact bug it claims to prevent. **Build and golden‑test this function FIRST; do not bind any surface to the palette until it exists.**
2. **Honour Increase Contrast / Reduce Transparency** → fall back to `Color.black` + **solid (non‑glass) chrome** (drop the material, not just the tint). The palette tint is an *enhancement layer*, never the sole contrast source. Document this as intended degradation: the headline effect is invisible to these users by design.
3. **Honour Reduce Motion** → freeze the wash to a single static summary colour; no 20fps recompute. *(Omitted by two designs; adopted here.)*
4. **Clamp chroma/L** to a low‑saturation dark ground as in 6.1, and **EMA‑smooth** the wash (critique: accents are currently passed RAW at the VM layer — smooth them or derive from the already‑smoothed `sceneTint`, animate `.easeInOut(0.3)` matching the ring).

### 6.3 Cost

The summary is a **256‑entry reduction**, computed **off the render path** on the existing deterministic index buffer, memoised per capture frame. Never scan 4096 px/frame. Verify <1ms on iPhone 17 Pro before wiring.

---

## 7. Layout & thumb zone (already correct — formalise it)

- **Primary (shutter): bottom‑center green zone** (Hoober 1,333‑observation data). Do not move.
- **Secondary (gear, toggles): bottom corners / bottom cluster**, thumb‑reachable.
- **Forbidden: any primary action in the top corners** (red zone — requires grip shift). Encode as an SFTheme layout rule.
- **Idle chrome recedes** toward translucency (Halide dials fade; iOS 26 see‑through) — but **never the shutter**.
- **Dynamic Type preserved** *(critique fix):* keep semantic fonts (`.caption`/`.footnote`/`.title2`) for all user‑read text; apply the cube lattice to control **geometry** only, never to type metrics. Add a layout test at AX5 so a 72pt shutter + scaled readouts don't collide in the bottom cluster.

---

## 8. Device fit (iPhone 17 Pro, 402×874 pt)

384pt canvas (64u) + 6pt gutters fits within 402pt with margin. 72pt shutter + 84pt ring + 48pt gear + readout fit the bottom safe‑area cluster (re‑verify on device before merge per critique). 48pt and 72pt both clear the 44pt floor on this exact target.

---

## 9. SFTheme token rewrite (zero‑dep, golden‑gated)

```
// RETIRE (arbitrary): 84, 70, 60, 49, 40, pillCorner=14, cardCorner=10,
//                     stripCorner=4, glassIconButtonSize=44, glassClusterSpacing=10
// ADD (cube-derived; every value = n * gifCellPt):
shutterSidePt        = 12 * gifCellPt   // 72  (3P) — primary, visible == hit
iconButtonPt         =  8 * gifCellPt   // 48  (2P) — secondary, visible == hit
selectorSegmentPt    =  8 * gifCellPt   // 48
diversityRingDiameter = 14 * gifCellPt  // 84  (= shutter + 2u clearance/side)
controlCorner        = 0                // (tested fallback: gifCellPt = 6)
gutterPt             =  1 * gifCellPt   // 6  — control-to-decoration only
comfortableGutterPt  =  2 * gifCellPt   // 12 — interactive minimum
glassClusterSpacing  =  2 * gifCellPt   // 12
shutterDeadZonePt    =  2 * gifCellPt   // 12
// NEW palette-chrome surface:
func relativeLuminance(_ c: SIMD3<UInt8>) -> Double   // TRUE WCAG, not OKLab L
func meetsContrast(_ fg:, on bg:, ratio:) -> Bool
func ambientWash(_ accents: [SIMD3<UInt8>]) -> Color  // clamped dark low-chroma
```

Golden gate (Haskell): every chrome token `% 6 == 0`; every hit region `≥ 44`; `meetsContrast` proven over the 256‑entry table; the static adaptive‑edge invariant ("canvas never vanishes").

---

## 10. Adversarial critiques — how each was folded in

| Critique finding | Resolution in this spec |
|---|---|
| Sub‑44pt visible glyph + invisible slug = HIG anti‑pattern | **Rejected.** Visible == hit, all ≥48pt (§4.2). |
| PixelGrid fills on glass / shutter as 12×12 grid violate the content/chrome split & stack two grids | **Rejected.** SF Symbols on chrome; shutter is a solid square; cube‑ness via size (§3, §4.1). |
| Conditional per‑frame gridline flickers → photosensitivity, partial‑frame bug | **Rejected.** Static, scene‑settle, single‑colour adaptive 1px edge (§5.2). |
| OKLab L used as WCAG luminance = ships the contrast bug | **Fixed.** True relative luminance, built & golden‑tested FIRST (§6.2.1). |
| 6pt inter‑control gutter too tight | **Fixed.** 12pt min between interactive controls (§2.2, §9). |
| Soft 24pt feather fights the 8‑bit aesthetic | **Dropped.** Hard modular gutter only (§5.1). |
| 48pt shutter under‑weights the primary one‑handed target | **Fixed.** Default 72pt; 48pt is secondary‑only (§3). |
| Square shutter inside round ring = leftover seam | **Fixed.** Square ticks; ring path round only as 64‑frame signature (§4.4). |
| Reduce Motion unaddressed | **Added** as a mandatory guard (§6.2.3). |
| Dynamic Type regressed by fixed type metrics | **Fixed.** Semantic fonts kept; lattice governs geometry only (§7). |
| Removing `pixelFrame()` globally degrades Review document | **Fixed.** `pixelFrame(bordered:)` parameterised (§5.1). |
| 6pt corner left untested | **Fixed.** Binary decision: 0 default, 6 measured fallback (§4.3). |
| Review action row pixelated | **Rejected.** Stays system glass buttons (§4.6). |
| Glass material at low corner radius unverified | **Flagged** as on‑device gate before merge (§4.3, §8). |

---

## 11. Research citations

- **Apple HIG — Layout / Buttons / Immersive / Camera Control:** 44×44pt floor; 4/8pt grid; "avoid clutter that diminishes the immersive experience"; single dominant unmissable shutter.
- **iOS 26 Camera (MacRumors):** dropped the bright white shutter ring for a subtle Liquid Glass ring; opened space around the shutter; made behind‑controls "a touch more see‑through" — Apple itself dissolves chrome into the viewfinder.
- **Halide 1.5 (Lux):** "nothing obstructs the viewfinder"; controls within thumb's reach; dials fade when idle — the canonical "preview blends, controls recede."
- **Obscura 2 (9to5Mac):** one‑hand full‑screen viewfinder for tall iPhones.
- **Hoober (UXmatters) / Smashing — Thumb Zone:** 49% one‑handed (67% right thumb), 75% thumb touches; bottom‑center green zone for primary actions; ≥45px hit areas.
- **WCAG 1.4.11 / 2.5.8 / 2.3.1:** 3:1 non‑text contrast; 24px target+spacing (44 best practice); flash/seizure threshold.
- **LogRocket / LukeW / Material:** 44pt Apple, 48dp Material, 76dp gloves tier; MIT 45–57px finger contact.
- **Conor Luddy Liquid Glass reference:** glass = chrome only; cannot sample glass (shared `GlassEffectContainer`); shape is a parameter (square sanctioned); tints from surrounding content.
- **Apple Music adaptive‑colour (9to5Mac):** palette‑driven chrome shipped a dark‑mode legibility bug; fix = honour Increase Contrast → black. **The mandate for §6.2.**
- **Mike Vardy (DEV):** a random extracted colour has no contrast guarantee; verify to 4.5:1.
- **Playdate dev docs:** 8×8 auto‑raster causes eye strain; stroke ≥2px — **why glyphs stay SF Symbols, not fat‑pixels.**
- **Rams 10 Commandments:** "as little design as possible"; honest; "nothing arbitrary or left to chance" — the completeness rule (§1.3).
- **Müller‑Brockmann / Swiss Style:** one modular unit generating all layout reads as rigour, not gimmick.
- **Teenage Engineering OP‑1:** a square‑grid control surface + restrained palette reads as a premium instrument.
- **Monospace Web (Wickström):** total grid‑snap, nothing floats off the cell lattice.
- **Use Your Loaf — iPhone 17 sizes:** 402×874 @3x confirms 384pt canvas fits.

---

## 12. Build plan

See `buildPhases` for the ordered list. Spec‑first, each phase golden‑gated, building atop the shipped `PixelGrid`/`SFTheme`, zero‑dep throughout.
