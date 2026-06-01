# SixFour — The Grid Is The Render Surface

**An 8-bit graphics-engine LOOK for the content layer, built atop the shipped GridLayout / Spec.GridAxis.**

Status: design (no code). Faithful to CLAUDE.md (Tier-2 zero-dep, Haskell-spec-as-source-of-truth, golden-gated, SwiftUI Canvas + simd + Metal only, build gate = `cabal test → spec-codegen → xcodegen generate → xcodebuild 'iPhone 17 Pro'`).

---

## 1. Concept: one surface, three life-stages

SixFour is an **8-bit graphics engine** whose only render surface is an *N×N grid of flat, un-shaded, indexed-colour cells*. The 64×64 GIF is literally that grid. The screen has a size; we map **screen-size → GIF-grid → cell-size**, and the grid becomes the literal render surface — no resampling, no blur, no shading.

This is not a new design language. It is the *content* half of the already-named **Lens / Grid** language (chrome = Liquid Glass lens; content = pixel grid). This document adds the one missing piece on the content side: the scattered flat-cell behaviour — re-implemented in six surfaces — is promoted into **one primitive and one integer-snapped sizing rule**.

The user always looks at the **same grid at three life-stages of the same indexed image**:

1. **CAPTURE** — the live preview is not a camera feed; it *already is* the 64×64 indexed grid the GIF will be (`makeQuantizedPreviewImage` through the deterministic Zig spine; the `AVCaptureVideoPreviewLayer` rides at opacity 0 for focus only). You compose *inside* the 64³ world. The "holy" triad {shutter, Settings gear, preview} is untouched.
2. **CREATION (the commit)** — the moment the burst becomes the indexed grid is the engine *committing* the deterministic-Zig output. The live preview's flat cells hand off into the same grid in Review, at the **same origin and cell pitch**, so the cut is continuous rather than a modal jump. The SHA-256 determinism badge is the "verified/committed" stamp on that grid (Stage 6 Zig cutover is live, default ON).
3. **REVIEW** — GIF playback and the 16×16 palette grid share **one 384pt surface**: a palette cell is exactly a 4×4 block of GIF cells. "Which colour shows up where" becomes literal, and the palette grid is *the verifier you can see* — every one of the 256 cells is a population-significant fact (`SignificantVoxelVolume`).

**Why flat is a contract, not a style.** Per-frame flatness is *intrinsic*: the residual ("shading") is shaped across the **(x, y, t) temporal-dither axis**, never within a frame's cell (temporal-dither GIF vision). And every cell is a population-significant sample of a maximin-OKLab-coverage objective — there is literally nothing to shade away. The flat indexed cell is the visual signature of the deterministic core and the diversity/significance guarantees.

---

## 2. The PixelGrid render primitive + the hard LOOK contract

Three Tier-2-pure pieces (SwiftUI Canvas + simd, zero deps), layered. **Critical scoping correction from review:** the 64×64 layer is *never* drawn as 4096 per-frame Canvas `Path` fills (81,920 path-ops/sec on the display link = jank). It stays a **bitmap** (the existing `.interpolation(.none)` UIImage path). `PixelGrid` Canvas drawing is reserved for the **256-cell palette only** (5,120 ops/sec, trivial).

### (1) `Color(srgb8:)` — one conversion
```swift
extension Color {
    init(srgb8 c: SIMD3<UInt8>) {
        self.init(.sRGB, red: Double(c.x)/255, green: Double(c.y)/255, blue: Double(c.z)/255)
    }
}
```
**Explicit `.sRGB` space** (not extended/displayP3) so on-screen colour matches the GIF's sRGB table byte-for-byte. Replaces the four copy-pasted `Double(c.x)/255` expressions (PaletteGridView:76, PaletteTreeView:91, GlobalPaletteEditor:122, and the orphaned PaletteStripView:81).

### (2) `PixelImage` — the bitmap upscale twin (GIF + live preview)
```swift
struct PixelImage: View {   // Image(uiImage:).interpolation(.none).resizable()
    let image: UIImage      // + exact .frame(width:height:), NOT scaledToFit/scaledToFill
}
```
One fit policy, defined once. Unifies CaptureView:70-73 (drop `.scaledToFill`) and GIFReviewView:209-212 (drop `.scaledToFit`). **Honest scope:** the no-interpolation contract is *split* — `shouldInterpolate:false` lives at the CGImage layer (CaptureViewModel:604) and `.interpolation(.none)` at the view layer. `PixelImage` owns the view half only; document this, or centralise CGImage creation in the primitive. Do **not** claim "no call site can opt out."

### (3) `PixelGrid` — the 256-cell Canvas primitive
```swift
struct PixelGrid: View {                  // palette grids only — never the 64×64 GIF
    let cells: Int                        // 16
    let origin: PixelGridOrigin           // .bottomLeft (coord grid Y-up) | .topLeft
    let colorAt: (_ row: Int, _ col: Int) -> SIMD3<UInt8>?   // nil = skip
}
```
It owns: integer-snapped cell-rect math, the single `Color(srgb8:)` fill, flat `ctx.fill(Path(rect))` with no interpolation/gradient/shading, and the **configurable row-origin flip** (PaletteGridView's hidden Y-flip at :68 becomes `origin: .bottomLeft`, a configured value not a re-implementation). A `GraphicsContext.fillCell(_ rect:, srgb8:)` helper serves the treemap, whose recursive non-uniform rects **cannot** reduce to `colorAt(row,col)`.

**Treemap exemption (review-mandated honesty):** `PixelGrid` unifies 2 of 6 surfaces + a shared `fillCell`/`subdivide`. The treemap is **explicitly carved out** of the "one snapped engine" claim — its `subdivide` emits *fractional* rects today and is a recursive non-uniform surface. Either route its leaf rects through the same integer-snap, or state plainly it is exempt. Do not claim a unification the code can't deliver.

### The hard flat-cell LOOK contract
(see `lookContract` for the enforceable rule list)

---

## 3. The pinned screen → grid → cell-size math

(see `sizingRule` for the one-line pinned formula)

**Encoded once** in `SFTheme` (Theme.swift has *no* grid tokens today — natural home, matches its `diversityTickCount=64` motif):

| token | value | meaning |
|---|---|---|
| `gifCellPt` | 6 | one GIF fat-pixel in points |
| `gifCanvasPt` | 384 | 64 × 6 (= 1152 device px @3x) |
| `paletteCellPt` | 24 | 16 × 24 = 384; **= 4 × gifCellPt** |
| `canvasEdge(forAvailable:cells:)` | `floor(w/n)*n` | snap to largest integer multiple that fits |

384pt fits the iPhone 17 Pro portrait width (402pt per useyourloaf, or 393pt non-Pro — **384 fits under either**, since 393/64 = 6.14 → still 6pt) with ~18pt to spare. **Expose `canvasEdge()` as the data-driven helper** so if the container after `.padding` is < 384pt it degrades to `gifCellPt=5 → 320pt` rather than hard-coding 384. Confirm exact width on the actual simulator/device, not from the web. pt sizes are **pure UI constants — no Haskell golden, no codegen**.

---

## 4. Deepening the GIF + GIF-creation UX through the grid lens

**CAPTURE** — holy triad untouched. The preview is explicitly the 64×64 indexed grid, now snapped to the 384pt integer canvas so live fat-pixels are perfectly *even* (today: uneven 6/7px @3x because `side = min(w,h)` at CaptureView:45 isn't a multiple of 64). The shutter's 64-tick `DiversityRing` reads as the engine's live OKLab-coverage gauge (glass chrome, off-content).

**CREATION (commit)** — the burst → indexed-grid handoff reads as the *same surface settling*, not a modal jump (same primitive, origin, cell pitch into Review). The SHA-256 badge is the committed/verified stamp.

**REVIEW** — GIF playback (`PixelImage`) and `PaletteGridView` (`PixelGrid`) on the same 384pt surface. New affordance: **palette-cell → GIF-pixel highlight** ("which colour shows up where"). Because a palette cell = a 4×4 block of GIF cells, tapping a palette cell highlights every GIF pixel using that index — rendered as **ONE mask CGImage overlay, never 4096 selectable rects**, and reading the **deterministic index buffer** (not a re-derived nearest-centroid) so the highlight matches the shipped bytes. The 256/256 ✓ badge already asserts "every cell is a fact." Sampler/dither stays a *Settings* decision (no re-render in Review); Retake re-shoots, Share exports. No new capture-screen chrome.

**One 20fps clock** drives GIF + palette + status line, phase-locked.

---

## 5. Critiques folded in

- **Zero-dep (HARD RULE):** every piece is SwiftUI Canvas + simd + Apple frameworks. No SPM/Pods/Carthage. Metal correctly **rejected** — no payoff for 256 flat fills; the 64×64 layer is already a bitmap. ✓
- **Perf (the real fix, not the cosmetic one):** consolidating fills does *nothing* for the actual hotspot — PaletteGridView rebuilds `GridLayout.layout()` + 256 srgb8→OKLab conversions (PaletteGridView:58-61) **inside the TimelineView body every tick**, and PaletteTreeView rebuilds `SplitTree.build()` per tick. **Memoize per frame index:** precompute the 64 laid-out frames / 64 SplitTrees / per-frame Color arrays once when `palettes` arrives; the clock only indexes the cache.
- **One clock, one driver:** delete the `Timer` (GIFReviewView:249); drive everything from a **single parent `TimelineView(.animation)`** feeding a shared `frameIndex(at:rate:count:)` down to GIF + palette + status. Two sibling TimelineViews = two display-link subscriptions; collapse to one. `TimelineView(.animation)` quantises to 20fps internally — do not keep the Timer (not phase-locked).
- **No-shading consistency — the treemap is where flatness LEAKS:** split-planes are `ctx.stroke(.black.opacity(0.55))` — edge-centered + AA'd + opacity = the violation. Moving to an overlay does **not** fix it unless drawn as **integer-snapped FILLED inset rects (gaps), not strokes, no opacity, no `cornerRadius:3`**. opacity *is* shading by our own rule; the overlay must be opaque chrome gaps. The selection highlight must be **square, opaque, snapped**.
- **a11y:** (a) flat cells give no adjacent-contrast guarantee — add an accessibility/Settings **"cell gridlines" toggle** (1px inter-cell gap as *chrome*, never on data). (b) the new highlight affordance needs a VoiceOver `accessibilityValue` ("index 137, used by 12% of pixels") — do not leave 256 tappable-but-AX-invisible regions; keep the single-summary `children:.ignore` model + expose highlight as value. (c) selection/hover indicator must meet **SC 1.4.11 3:1** over *any* of 256 cell colours → contrast-adaptive (dual light+dark / luminance-flipped outline), not a single token. (d) **reduce-motion** must be honoured at the single clock driver, or consolidation silently re-introduces motion.
- **Corner-rounding is a deliberate LOOK call:** removing `RoundedRectangle(cardCorner=10)` clipping (4 surfaces) changes every grid's silhouette and removes the figure/ground boundary against `Color.black`. **Confirm "hard square, round only chrome" with the user before applying**; keep a visible `gridFrameStroke` border so dark-edged palettes don't bleed into black.
- **Editor narrative:** GlobalPaletteEditor draws from float `current` OKLab via `okLabToSRGB8` (the **provisional** `GlobalPaletteCollapse.maximin`, not the Q16 GIF bytes). Route it through the same `PixelGrid` for *visual* consistency but do **not** let the "same shipped indices" narrative cover it — it is a dev/be-the-NN tool over a float stand-in.

---

## 6. Look-decision the user must confirm

**Round → square/full-bleed:** all four palette/GIF surfaces currently clip to `cardCorner=10`, softening the outermost indexed cells (AA'd clip = direct "no AA on content" violation). Recommended: render full-bleed hard square, round only the chrome frame. This is a deliberate silhouette change — surface it as a decision, not a silent edit.

---

## 7. Tech-debt cleanup & build plan

See `debtCleanup` (prioritized now/soon/later) and `buildPhases` (spec-first, ordered, atop GridLayout/Spec.GridAxis). Every phase gates on `cabal test → spec-codegen → xcodegen generate → xcodebuild 'iPhone 17 Pro'` + an on-device look-check of all touched surfaces (no layout golden exists).