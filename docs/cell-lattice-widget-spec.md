# SixFour — TOTAL CELL-LATTICE UI on the LOCKED 201×437 @2pt Golden Lattice

**Status:** authoritative build plan. Supersedes the three prior pitches (cube-system-on-2pt, SFTheme-text-registers, HUD-as-cell-art) by *resolving* their three shared contradictions against the code on disk. Builds on `docs/cube-generated-uiux-system.md`, `docs/grid-is-the-render-surface.md`, `~/.claude/plans/misty-greeting-panda.md`, and the shipped primitives in `SixFour/UI/Components/PixelGrid.swift` + `CellText.swift` + `Theme.swift`.

---

## 0. The three contradictions, resolved first (per all three critiques)

Every prior pitch shipped on at least one false premise. The critiques (`latticeFaithful=false`, `perf=false`, `a11y=false`) are correct against the code I verified this session. This doc fixes them up front so every number below is real.

### RESOLUTION A — ONE pitch. The preview becomes a 128pt, 64×64 sub-region of the field at **2pt/pixel**.
The lattice header says "128pt preview" and locks it to cols 68–131 = 64 cells × 2pt = **128pt**. The shipped `gifCanvasPt = 64 × gifCellPt(6) = 384pt`. These are irreconcilable: a 64×64 grid is *either* 384pt at 6pt/pixel *or* 128pt at 2pt/pixel — not both. The "6 = 3×2, two pitches coexist" thesis is fiction (FATAL #1, critique 1).

**Decision: adopt ONE 2pt pitch everywhere.** The preview is a 64×64 PixelImage at 2pt/GIF-pixel = 128pt, living *inside* the field's coordinate system. This is what the locked lattice demands and what makes "the field IS the render surface" literally true. Consequences, stated honestly:
- **DELETE** every "native 6pt fat-pixel pitch", "its own PixelImage at 6pt", "6=3×2 boundary alignment", "carries `gifCellPt=6` forward" claim. They are false under this resolution.
- `SFTheme.gifCellPt` is **not** reused as the chrome pitch. We add `SFTheme.cellPt = 2` (the lattice cell) and migrate chrome dimensions to it (§ Primitives). `gifCellPt`/`gifCanvasPt`/`paletteCellPt` stay for the **Review/palette screens**, which are out of scope here and keep their 384pt commensurate surface.

### RESOLUTION B — the 128pt hero shrink is a PRODUCT REGRESSION the user must approve.
FATAL #2 (critique 1) is correct: today the live preview fills the width at 384pt; a 128pt preview is one third of that. "You live inside the 64³ world" degrades to a postage stamp. The 2pt lattice *forces* this — you cannot have a full-width 64-pixel preview AND 2pt-per-GIF-pixel. **This is surfaced as a hard decision, not silently shipped** (see § topRecommendation). The lattice is over-fine for the hero content; that is the price of the edge-to-edge 2pt field. The remaining design assumes the user accepts the 128pt preview; if not, the fallback is "lattice for chrome only, preview stays 384pt and spans ~192 cols" — a different layout, noted but not the recommendation.

### RESOLUTION C — ONE indexed bitmap, drawn by **CGContext**, NOT `fillCell`.
`GraphicsContext.fillCell` (PixelGrid.swift L97) issues per-rect **SwiftUI Canvas fills at render time**. Its header explicitly scopes it to the **≤256-cell palette only** — never the big surface. Every prior pitch said "composites into the ONE 201×437 indexed bitmap drawn once" *and* "drawn via `fillCell`" — internally contradictory (critique 2, perf=false).

**Decision:** the field + chrome are baked into a **CGContext-backed indexed bitmap** (`shouldInterpolate = false`) once per state change, wrapped in **one** `PixelImage(.interpolation(.none))` upscaled ×6. The cell primitives below (`CellShapes`, `CellGlyph`, `CellRing`) write **bytes into that backing store** via a tiny `setCell(col,row,srgb8)` over the buffer — they do **not** call `fillCell`. `fillCell`/`PixelGrid` stay exactly as-is for the palette screens. This keeps "drawn once, upscaled ×6" true and honours the locked perf model.

### RESOLUTION D — ghost segments get a real OPAQUE dim cell, not `mutedFill`.
`SFTheme.mutedFill = white.opacity(0.06)` is (a) an opacity-on-a-cell (violates the flat-cell contract), (b) ~1.05:1 on black = invisible / WCAG fail (critique 2, a11y=false). **Decision:** add an opaque token `ledGhost = SIMD3<UInt8>(40,40,40)` for unlit 7-seg bars. Opaque, ~1.6:1 against black ground (a deliberate dim "off-segment", not chrome text), so the LCD frame reads and the digit never reflows.

### RESOLUTION E — touch numbers corrected.
Shutter is pinned at **34 cells = 68pt** (the ladder value; the stale `gifCellPt×12 = 72pt`/36-cell box is retired). Gear = `glassIconButtonSize = 48pt = 24 cells`. **We keep shutter/gear sized in POINTS (68–72pt / 48pt), then express them in cells** — never "12 cells" (= 24pt, which would FAIL the 44pt gate). Final sizes: **shutter 34 cells = 68pt** (a clean even-34 disc; ≥44pt ✓), **gear 24 cells = 48pt** (✓). Both clear the 22-cell/44pt floor with margin.

### RESOLUTION F — secondary text does NOT use the 6×13 system-mono path.
`CellText.snap` calls `UIFont.monospacedSystemFont(ofSize: rows)`. At rows=13 with a 6-cell advance, a 13px mono cap is squeezed into ~5px ink and drops/merges stems before upscale (critique 1 LEGIBILITY, critique 2). **Decision:** the 6×13 Cozette-metric label register is a **hand-authored `CellGlyph` master**, golden-pinned — NOT the system-font snap. `CellText`'s rasterise-and-snap is retained ONLY as the Dynamic-Type AX fallback. The sampler line additionally falls back to system `Text` at ALL sizes if its measured width would overflow (§ a11y).

### RESOLUTION G — Glass RETIRED on capture (surfaced, not silent).
Glass cannot composite into the single indexed bitmap, and `GlassControls.swift`'s own header says glass is *chrome material, content never gets it* — but the whole capture chrome is now content-class flat cells. So `GlassToolbarCluster`/`GlassIconButton`/`GlassInfoChip` usage is removed **from CaptureView only**. `GlassControls.swift` **stays on disk** for Review/Settings surfaces (it is not deleted). This is a LOOK decision flagged for user confirmation, exactly like the 128pt regression.

---

## 1. The exact 201×437 band map

Lattice = **201 cols (x: 0…200) × 437 rows (y: 0…436)**; cell = 2pt = 6 device-px; ×6 upscale. Preview LOCKED at **rows 143–206 (64 rows), cols 68–131 (64 cols)** — even-start on both axes so its edges land on field cell boundaries. Golden split of the 373 chrome rows = 143 above : 230 below (230/143 ≈ 1.608 ≈ φ ✓). All bands are authored against the nominal 437-row field and **shifted at runtime** by `safeTopRows = ceil(insets.top/2)` / `safeBottomRows = floor(insets.bottom/2)` (`GlobalLattice`).

The `(air)` bands collide-check below: every interactive/glyph band is non-overlapping, and the readout sub-band collision flagged in critique 1 (13-row vs 18-row) is resolved by picking **one 18-row count band** and deleting the 13-row version.

```
ROWS      HEIGHT  ZONE                 CONTENT
────────────────────────────────────────────────────────────────────────────
0   – 30   31     TOP SAFE             Dynamic Island ≈62pt≈31 rows. Field only.
                                       Runtime: rows 0…(safeTopRows-1) reserved.
31  – 95   65     UPPER AIR (a)        Pure field. Breathing room below the DI.
96  – 115  20     TITLE band           "SixFour" 16w×20h glyph box, advance 18,
                                       7 glyphs → 124 cells. Left edge col 68
                                       (aligned to preview L) → cols 68–191.
                                       Reads as a header sitting on the preview.
116 – 142  27     UPPER AIR (b)        Field. 27-row gutter title→preview.
143 – 206  64     PREVIEW (LOCKED)     64×64 PixelImage @2pt, cols 68–131.
207 – 239  33     LOWER AIR (a)        Field. Separates preview from instrument.
240 – 300  61     DIVERSITY RING       cx = col 100.5 (2-cell center 100–101),
                                       cy = row 270, R=30 → spans rows 240–300,
                                       cols 70–130. 64 radial ticks.
253 – 286  34     SHUTTER (inside ring) 34-cell block, center col 100.5/row 270,
                                       cols 83–116, rows 253–286. Outer ring r=17,
                                       inner disc r=13. 10-cell clear annulus to
                                       the ring's inner tick radius (r=27).
301 – 305  5      LOWER AIR (b)        Field. Ring→readout gutter.
306 – 323  18     READOUT count band   ◇ + 7-seg digits + " colors", center col 100.
                                       (ONE 18-row band — supersedes the 13-row
                                       version; no collision.)
324 – 326  3      micro-air            Field.
327 – 340  14     SAMPLER tag band     6×13 Cozette line (CellGlyph), centered.
                                       Wraps to a 2nd line 342–355 if >180 cells.
341 – 419  79     LOWER AIR (c)        Field.  (Gear lives at top, not here.)
420 – 436  17     BOTTOM SAFE          Home indicator 34pt=17 rows. Field only.
                                       Runtime: floor(insets.bottom/2) reserved.
```

**Gear** is placed in the title band's right margin: **cols 173–196, rows 92–115** (24×24, right-aligned to col 196, vertically centered on the title baseline, clear of the 31-row DI). It is a peer secondary control ≥22 cells, off the busy lower band.

**Parity convention (pinned, per the radial-symmetry research):** even-cell with a 2-cell center for gear (24), shutter (34), diamond (12); the ring's center is occupied by the shutter so its parity is free. Documented in `docs/cube-generated-uiux-system.md`.

---

## 2. Per-widget table

| Widget | Cell size | Grid position (cols × rows) | Notes |
|---|---|---|---|
| **Title "SixFour"** | 16w × 20h per glyph, advance 18 → 124w × 20h block | cols 68–191 × rows 96–115 | Hand-authored 16×20 `CellGlyph` master (integer 2.5× of an 8×16 IBM-VGA master — authored *directly* at 16×20, NOT routed through CellText, which is integer-cell only and single-ink). Cap band 12–13 cells, x-height ~9, descender 2–3. Characterful '2'/'7'/'x'. `accessibilityLabel("SixFour")` + `.isHeader`; cells hidden. Decorative (no hit). |
| **Gear / Settings** | 24 × 24 (= 48pt) | cols 173–196 × rows 92–115 | `CellIcon`: midpoint-circle hub r≈5, 8 teeth as 2×2 stubs on outer r≈10 at 45° spacing, 3×3 inverted center hole, stroke 2. Even dims → 2-cell center. Hit-block = visible block, ≥22 cells. Transparent `Button` frame pinned to the cell-rect. Label "Settings"; selected (sheet open) = 1-cell border one cell outside → `.isSelected`. |
| **Readout — ◇ diamond** | 12 × 12 | cols 70–81 × rows 308–319 | `CellIcon` rotated square: 4 midpoint-line edges, 2-cell stroke, 2×2 center fill. Even dims → symmetric 2-cell tips. Brand/cube motif leading the count. Cells hidden. |
| **Readout — count "65"** | 10w × 18h per digit, advance 11 | cols 84–104 (2 digits) × rows 306–323 | Hand-authored 7-segment `CellGlyph`: 7 bars (H = 6×2, V = 2×7). Lit = white; unlit = **opaque `ledGhost` (40,40,40)** so the digit never reflows (fixed 10-cell cells + reserved colon/dp column at the leading slot for ≤256 → 3-digit growth). Driven by `vm.scene.occupiedBins` ∈ 0…256 (verify domain). NOT on the 20fps clock — re-bakes on value change only. |
| **Readout — " colors"** | 6w × 13h per glyph, advance 6 → 36w | cols 108–143 × rows 312–324 | Hand-authored 6×13 Cozette-metric `CellGlyph` master (8-cell cap, 10-cell ascent, 3-cell descent, 5-cell avg width), baseline-aligned to digit bottom. NOT the system-mono snap (drops stems). |
| **Sampler tag** | 6w × 13h, advance 6 | centered on col 100 × rows 327–340 (+ 342–355 if wrap) | 6×13 `CellGlyph`. Worst case "diffusion · FS · serpentine" ≈ 162 cells → 2-line wrap rule (both above row 420), OR system `Text` fallback if measured width > 180 cells. Only line that carries descenders ('diffusion', 'serpentine') — 6×13 honours them. |
| **Diversity ring** | R=30, ~60-cell (120pt) Ø | center col 100.5 / row 270; cols 70–130 × rows 240–300 | `CellRing`: thin axis circle (midpoint, 1-cell) + 64 radial ticks at θ=2πk/64 (k=0 top, clockwise). Active (k < floor(coverage×64)) = 3-cell stub in `accent(sceneTint)`; inactive = 1-cell dim outer stub. Ticks ~2.9 cells apart → ≥1 clear cell, no merge. coverage = `vm.sceneGauge` (Spec.Coverage). Decorative; value exposed once on shutter. Tick endpoints **precomputed as a golden table** (the only non-integer step is θ→cell). |
| **Shutter** | 34 × 34 (= 68pt) | center col 100.5 / row 270; cols 83–116 × rows 253–286 | `CellButton`: idle = 2-cell ring band (midpoint r=17) + filled disc (r=13). Pressed = invert hit-block. Busy = inner disc → rotating 3-cell rim arc at 20fps (Reduce Motion → static quadrant dots). Recording = 9-cell rounded-square stop. Disabled = 50% 2×2 checker. Even-34 → 2-cell center. Transparent `Button` (+ ButtonStyle exposing `isPressed`) pinned to the cell-rect; hit == visible. |
| **Background field** | 201 × 437 (whole screen) | cols 0–200 × rows 0–436 | One CGContext-backed indexed bitmap. Every non-preview/non-glyph cell = darkened quantized `sceneTint` (clamped, see contrast). Optional 4×4 Bayer ordered-dither shimmer over 2 adjacent tint indices (FROZEN single-phase under Reduce Motion). Seamless (no gridlines; opt-in a11y toggle). Tint regenerates at 4–8 Hz, NOT per frame. |

---

## 3. Primitives

All Tier-2 clean (SwiftUI + UIKit/CGContext + simd, zero deps). Integer-only geometry → golden-gateable byte-exact in the Haskell spec (`Spec.CellShapes` + `Spec.CellFont`), mirroring the Zig deterministic-core ethos. Each REUSES the verified disk primitives.

**`GlobalLattice`** (pure value type, golden-gateable):
```swift
struct GlobalLattice {
  let cols = 201, rows = 437
  let cellPt: CGFloat = 2      // SFTheme.cellPt
  let scale: CGFloat = 3       // device px / pt; cell = 6 device-px
  func point(col:Int,row:Int) -> CGPoint { .init(x: CGFloat(col)*cellPt, y: CGFloat(row)*cellPt) }
  func cell(at p:CGPoint) -> (col:Int,row:Int) { (Int(p.x/cellPt), Int(p.y/cellPt)) }
  func safeTopRows(_ i:EdgeInsets) -> Int { Int((i.top/cellPt).rounded(.up)) }
  func safeBottomRows(_ i:EdgeInsets) -> Int { Int((i.bottom/cellPt).rounded(.down)) }
  static func goldenSplit(_ t:Int) -> (above:Int,below:Int) { let a = Int((Double(t)/(1+1.618)).rounded()); return (a, t-a) }
  static let fib = [8,13,21,34,55,89]      // cell sizes: shutter 34, gear 24(=2×12), ring R=30
  let previewRows = 143...206, previewCols = 68...131   // LOCKED, even-start
}
```
The bitmap builder = `CGContext(width:201,height:437, ...)` with AA off → `CGImage(shouldInterpolate:false)` → wrapped in **one** `PixelImage(edge: 402pt)`. REUSES the `PixelImage` `.interpolation(.none)` discipline directly.

**`CellShapes`** (enum, pure integer, returns `[SIMD2<Int>]` cell coords — the single source for draw AND hit where shapes are interactive):
```swift
enum CellShapes {
  static func midpointCircle(cx:Int,cy:Int,r:Int) -> [SIMD2<Int>]   // E=3-2r; 8-octant; stop x<y
  static func filledDisc(cx:Int,cy:Int,r:Int) -> [SIMD2<Int>]       // midpoint per radius
  static func ringBand(cx:Int,cy:Int,r:Int,thickness:Int) -> [SIMD2<Int>]
  static func radialTick(cx:Int,cy:Int,theta:Double,rInner:Int,rOuter:Int) -> [SIMD2<Int>]  // Bresenham
  static func line(_ a:SIMD2<Int>,_ b:SIMD2<Int>) -> [SIMD2<Int>]   // diamond edges
}
```
Each returns coords; the renderer writes them into the backing buffer via `setCell(col,row,srgb8:)` (NOT `fillCell` — see Resolution C). The 64 tick endpoints are a precomputed golden table (θ→cell is the one float step). REUSES `Color(srgb8:)` for ink.

**`CellGlyph`** (View; the hand-authored 1-bit master path — distinct from `CellText`):
- Holds a 1-bit `[[Bool]]` / bit-packed `[UInt64]` master table for the three hand-authored registers: the **16×20 "SixFour" wordmark** (8 distinct glyphs S,i,x,F,o,u,r), the **6×13 Cozette label** master, the **10×18 7-segment digit** master ([Int:[Segment]] map 0–9).
- Renders via a tiny indexed CGImage + `.interpolation(.none)` ×6 — **identical render path to `PixelImage`**. Single ink for mono glyphs; the 7-seg digit writes lit (white) + unlit (`ledGhost`) cells into the backing buffer.
- `accessibilityHidden(true)`; the real string lives on the container.

**`CellFont`** = the master table feeding `CellGlyph` (the 8 wordmark glyphs + 6×13 alphabet + 7-seg digits), emitted as golden vectors by `Spec.CellFont`.

**`CellIcon`** (View): `let mask:[SIMD2<Int>]` (or 1-bit grid), `boxCols/boxRows`, `ink:Color`. Small indexed CGImage + `.interpolation(.none)` ×6 (REUSES `PixelImage` frame discipline). Used for gear + diamond. `accessibilityHidden`.

**`CellRing`** (View): `ticks=64`, `lit:Int`, `r:Int`, `activeTint/inactiveInk:Color`, `reduceMotion:Bool`, `frame:Int` (from `frameIndex`). Static ticks bake into the overlay; only the lit-tick band + busy highlight redraw via the 20fps clock. REUSES `frameIndex(at:rate:count:)` and `SFTheme.accent`.

**`CellButton`** (View): `block:CellRect`, computed states (idle/pressed/selected/disabled) from bindings, a `glyph: CellIcon`/`CellShapes` set. Applies the four affordances by transforming the painted cell set (invert / 1-cell border / 50% checker / accent border — all via `setCell`, zero new color tokens beyond `ledGhost`). Wraps a transparent `Button` + `ButtonStyle` exposing `isPressed` for the press-invert; the Button frame is pinned to the **same cell-rect** used for drawing (layout==hit, the `paletteSubdivide` discipline). Enforces ≥22 cells.

**`CellField`** (the background): builds the 201×437 indexed buffer (darkened quantized `sceneTint` + optional frozen Bayer shimmer), composites the static chrome cells in, exposes the finished CGImage as one `PixelImage`.

REUSE map (all verified on disk this session):
- `PixelImage` (PixelGrid.swift) → the field bitmap AND the 64×64 preview, both `.interpolation(.none)` + exact `.frame`.
- `Color(srgb8:)` (PixelGrid.swift) → the only sRGB8→Color conversion for tint + ink + `ledGhost`.
- `GraphicsContext.fillCell` (PixelGrid.swift) → **unchanged, palette screens only** (Resolution C).
- `frameIndex(at:rate:count:)` (PixelGrid.swift) → the single 20fps clock; drives preview tile + ring lit band + busy arc ONLY (not the count text).
- `CellText` (CellText.swift) → kept as the **AX Dynamic-Type fallback** rasteriser; not the primary glyph path.
- `SFTheme` (Theme.swift) → `accent(_:towardWhite:)`, `dimText`, `diversityTickCount=64`, `groundWashOpacity`. **ADD** `cellPt=2`, `ledGhost`, and the glyph-box tuples.

---

## 4. Font decision

**Hand-authored 1-bit pixel masters (`CellGlyph`/`CellFont`), snap-upscaled at INTEGER cell factors — NOT system-font rasterize-snap for the primary glyphs.** Rationale grounded in the research and the code:

- The whole payoff of the 2pt cell is escaping the 5×7 ceiling: at 6 device-px/cell a glyph box is many cells tall, so we get real cap/x-height/ascender/descender *bands* (the Cozette/8×16 lesson) instead of 7 rows fighting. That fidelity only materialises if the master is authored to use those bands — a system mono font rasterized tiny does the opposite (drops stems before upscale, critique-confirmed).
- `CellText` body scales by `mask.size * cell` (**integer cells only**) and applies **one ink** (`.renderingMode(.template).foregroundStyle(ink)`). So: the title's "2.5× of 8×16" cannot route through CellText (non-integer), and the 7-seg digit's two-ink lit/ghost cannot either. They MUST be `CellGlyph` masters. CellText's value is its built-in `.accessibilityLabel(Text(text))` — we keep it as the **AX fallback**.

**Glyph cell-boxes (all integer multiples of pixel masters → byte-exact, AA-off, ×6 nearest upscale):**

| Register | Cell box | pt | Master | Bands |
|---|---|---|---|---|
| TITLE "SixFour" | **16 × 20**, advance 18, line 22 | 32×40pt | integer 2.5× of an 8×16 IBM-VGA master | cap 12–13, x-height ~9, descender 2–3, counters 1–2. Characterful '2' raised stem, '7' curved. |
| READOUT / LABELS | **6 × 13**, advance 6, line 14 | 12×26pt | hand-authored Cozette-metric master | cap 8, ascent 10, descent 3 (true descenders for 'p','y','g'), avg width 5. |
| LIVE COUNT "65" | **10 × 18** per digit, advance 11 | 20×36pt | 7-segment bar stencil (H=6×2, V=2×7) | LED counter; lit=white, unlit=opaque `ledGhost`. Reads as a hardware counter, distinct from prose. |
| Micro-label FLOOR | 5 × 7 | 10×14pt | monogram-class | ONLY where no descender occurs; default to 6×13 otherwise. |

All masters golden-pinned by `Spec.CellFont` (the byte-exact claim is otherwise unverified — critique-flagged). Title alt for max personality: 24×30 (integer 3× of 8×10 caps) — deferred.

---

## 5. Single-bitmap-field perf model

The locked model, made internally consistent (Resolution C):

**Two layers, one of them static.**

- **PASS A — FIELD + STATIC CHROME (cached CGImage, re-baked on STATE change only).** A `CGContext(201×437, AA off)` UInt8-indexed (or direct sRGB8) buffer. Fill every cell with the darkened quantized `sceneTint`. Composite in the static chrome by writing cells: title, gear, shutter idle, diamond, count digits + ghosts, " colors", sampler, ring axis circle + inactive ticks. `makeImage()` → `shouldInterpolate=false` → **one** `PixelImage(.interpolation(.none))` ×6 → `.frame(402×874)`. ~88k px built ONCE per state change — **NOT 88k Canvas fills.** Re-bake triggers: `occupiedBins` delta, sampler toggle, press/disabled/settings-open, sceneTint change (throttled to **4–8 Hz**, never per frame).
- **PASS B — ANIMATED BAND (tiny separate `PixelImage` over the static overlay, 20fps).** Only the ring's lit-tick set (+ busy rim arc) re-evaluates — ~64 tick cells, cheap. Driven by `frameIndex(at:rate:20,count:64)`. The 64×64 **preview is its own PixelImage** at the locked rect, animating independently at 20fps. The count text is NOT animated (it lives in Pass A's cache).

Load-bearing assumptions (measure on device, per the build gate): (1) the 88k-px re-bake stays off the 20fps path (throttled tint); (2) Pass B touches only the tick band. `fillCell` is **never** used on the big surface — it is contractually the palette-only Canvas path. The single cell-rect table feeds both draw and hit (layout==hit, `paletteSubdivide` precedent).

---

## 6. Accessibility (HARD gate)

Honoured cell-by-cell, matching the patterns already in CaptureView (which I read):

- **Every interactive hit-block is a real transparent `Button`** with frame pinned to its cell-rect; painted cells are `accessibilityHidden(true)` (decorative).
- **Title:** `accessibilityLabel("SixFour")` + `.accessibilityAddTraits(.isHeader)`; cells hidden. (The one non-hidden decorative element, since it is a wordmark/heading.)
- **Shutter:** label "Capture 64-frame burst"; `accessibilityValue("Scene diversity \(round(gauge*100)) percent")`; hint "Holds focus and exposure, captures sixty-four frames at twenty fps". Busy/disabled via `.disabled()` so VoiceOver announces dimmed (replaces ProgressView semantics).
- **Gear:** label "Settings"; `.accessibilityAddTraits(.isSelected)` when the sheet is open.
- **Diversity ring:** the 64 tick cells are `accessibilityHidden` — **NOT 64 AX nodes**. Coverage is exposed ONCE, as the shutter's `accessibilityValue` (single owner, no double-speak).
- **Count + labels:** cells hidden; a single combined element labelled `"\(occupiedBins) colors, sampler \(spokenSamplerTag)"` (abbreviations expanded for speech, e.g. "blue noise, 3D").
- **Dynamic Type fallback:** at standard sizes the `CellGlyph` masters ARE the type (integer cell-scale). At `@Environment(\.dynamicTypeSize) >= .accessibility1`, ALL text registers (title/count/label/sampler) fall back to system `Text` (`SFTheme.titleMono`/`captionMono`) with the same string + ink — via the retained `CellText` AX path. **The AX-fallback container is constrained with a `maxHeight`/bottom safe-area inset** so flowing Text cannot cross the row-420 home-indicator floor (critique-flagged). The instruments (ring/shutter/gear) stay cell-art (controls, not text). The sampler line additionally falls back to system `Text` whenever its measured width would overflow, at any size.
- **Reduce Motion:** freezes the field shimmer (single Bayer phase), the ring tick transition (snap to value), the tint cross-fade, AND the busy spinner (rotation → static quadrant dots — the spinner guard the prior pitches forgot).
- **Touch:** shutter 34 cells = 68pt, gear 24 cells = 48pt — both > 22-cell/44pt. Visible == hit (no invisible slugs).
- **Contrast (HARD number, not "darken to budget"):** the field's max luminance is computed from `accent()`'s `towardWhite` clamp on the brightest allowed `sceneTint`; the white chrome AND the ring/border indicator must hold **≥ 3:1 (WCAG SC 1.4.11)** against it. The ring/border outline is **luminance-flipped** (dark outline on bright field) as a *tested invariant*, not a "should". `ledGhost(40,40,40)` is opaque and ~1.6:1 vs black ground — a deliberate off-segment, never load-bearing text. The contrast clamp + flipped outline are asserted in the layout golden.

---

## 7. Spec-first ordered build plan (atop shipped work)

Each phase is spec-first: the Haskell spec + golden vectors land before the Swift, per CLAUDE.md (`cabal test` is the gate; never hand-edit `SixFour/Generated/`).

1. **Decisions gate (no code).** Get user sign-off on (a) the 128pt preview regression (Resolution B) and (b) Glass retirement on capture (Resolution G). Both are visible product changes; do not proceed silently.
2. **`Spec.CellShapes` (Haskell) + goldens.** midpointCircle parity, filledDisc/ringBand, Bresenham radialTick, the precomputed 64-tick endpoint table (θ→cell pinned). `cabal test` green. Codegen emits golden vectors.
3. **`CellShapes.swift` (Swift) verified byte-exact vs goldens.** Pure integer; returns `[SIMD2<Int>]`. No view yet.
4. **`Spec.CellFont` + goldens.** The 8 wordmark glyph rows (16×20), the 6×13 Cozette alphabet, the 10×18 7-seg digit table. Emitted + pinned. (Without this the byte-exact claim is unverified — critique-flagged.)
5. **`SFTheme` migration.** Add `cellPt=2`, `ledGhost=SIMD3(40,40,40)`, glyph-box tuples (`titleGlyph`, `labelGlyph`, `digitGlyph`). Scope `cellPt` to the new chrome; leave `gifCellPt`/`gifCanvasPt`/`paletteCellPt` for Review/palette. Audit no chrome consumer mixes the two pitches.
6. **`CellGlyph` + `CellIcon` (Swift).** Hand-authored master render via indexed CGImage + `.interpolation(.none)` (PixelImage path). Verify title/label/7-seg/diamond/gear render byte-exact vs the §4 masters.
7. **`CellField` builder.** The 201×437 CGContext bitmap: field tint + Bayer shimmer + static chrome composite → one PixelImage. Throttle tint to 4–8 Hz. Contrast clamp asserted.
8. **`CellRing` + `CellButton`.** Ring static/animated split (Pass B, `frameIndex`), the four affordances, transparent Button + isPressed ButtonStyle, cell-rect table shared with hit-test.
9. **`GlobalLattice` + runtime safe-area band shift.** Wire `safeTopRows`/`safeBottomRows`; verify bands never collide with DI/home indicator across real insets.
10. **CaptureView integration.** Delete `GlassToolbarCluster`/`GlassIconButton` usage in `topBar`, the SwiftUI-Rectangle `DiversityRing`, the stroked-RoundedRectangle `shutterButton`. Replace with the cached overlay `PixelImage` + `CellRing` animated layer + two `CellButton`s positioned by the shared cell-rect table. Keep `vm.capture()`/`focus()`/Haptics behaviour. Keep `GlassControls.swift` on disk for Review/Settings.
11. **A11y wiring.** Labels/values/hidden per §6; AX Dynamic-Type fallback with `maxHeight` floor guard; Reduce Motion freezes field + ring + busy spinner.
12. **LAYOUT GOLDEN (build gate, was a "risk" — now a gate).** On-device snapshot across **idle / pressed / busy / disabled / settings-open** at **default + AX Dynamic Type**, asserting: (a) preview pixel pitch is integer; (b) no chrome glyph below the legibility floor; (c) field max-luminance contrast ≥ 3:1; (d) AX fallback text stays above row 420. Nothing ships until this passes.

---

## 8. Research citations

- **Bitmap-font ladder & glyph boxes:** Cozette 6×13 metric (cap/ascent/descent bands) — *Cozette README*, github.com/slavfox/Cozette; the 8×16/9×16 "letterforms stop being compromised" threshold and characterful '2'/'7' — *The Ultimate Oldschool PC Font Pack* (int10h.org) + *Mx437 IBM VGA 8×16 metrics* (fontinfo.opensuse.org); the 8×8 "everything in one tile" ceiling we buy out of — *GB Studio Central, Understanding Fonts*; integer-master bitmap font system — *bitbanksoftware, "Building a Better Bitmap Font System"*; monogram 5×7 floor — datagoblin (itch.io). **Counter:** the *system-mono rasterize-snap fails at 6×13* finding is confirmed against `CellText.snap`'s `UIFont.monospacedSystemFont(ofSize: rows)` on disk → drove the hand-authored-master decision.
- **7-segment numerals:** *Seven-segment display* (Wikipedia) + torinak.com 7-seg font — idiomatic LED counter, segment bars read as a gauge not prose.
- **Pixel icons & states:** *Octicons / Primer Icon Design Guidelines* (primer.style) — design per size, consistent stroke, snap outer edges, 1-cell gaps; *Icons8, A Guide to Pixel-Perfect Icons* — small-size flattening, parity rule for radial symmetry; *Pixilart / Pixel Art 101: Buttons* — invert/border/checker state affordances.
- **Ring geometry:** *Midpoint Circle Algorithm* (Wikipedia) — integer E=3-2r, 8-octant; *Radial Gauge tick configuration* (Infragistics/Syncfusion) — major/minor ticks via inner/outer radius, the 64-tick = 64 radial stubs (not arc pixels) model.
- **Contract precedents (codebase):** `docs/grid-is-the-render-surface.md` (the grid IS the render surface; gridlines = chrome toggle only), `docs/cube-generated-uiux-system.md` (cube-derived chrome lattice), `~/.claude/plans/misty-greeting-panda.md`. Zig deterministic-core byte-exact ethos → golden-gate `Spec.CellShapes`/`Spec.CellFont`. arXiv 2312.11209 (integer quantized cores) backs the golden-vector discipline.
