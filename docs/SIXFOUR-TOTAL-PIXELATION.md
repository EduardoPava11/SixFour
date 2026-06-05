# SixFour — Total Pixelation (the screen grid IS the UI)

> Goal (user): the WHOLE app pixelated. Map the iPhone 17 Pro screen → a cell grid →
> that grid is the UI surface. No anti-aliased system text, no glass, no SF Symbols on
> our chrome. Source: `sixfour-total-pixelation` workflow (audit → design → critique), 2026-06-04.

## The grid (already exists)

`Spec.Lattice` maps the iPhone 17 Pro: 402×874 pt, `cellPt = gcd(402,874) = 2pt` → a
**201×437 cell lattice** (mirrored in `GlobalLattice.swift` ← `Generated/LatticeContract.swift`).
Every widget is an integer cell-rect on it.

**Pitch decision (resolves the critic's legibility tension).** Two zoom levels of the ONE
master 2pt grid, and they may share the Review screen because they are commensurate
(`6 = 3·2`, so a 6pt cell = a 3×3 block of 2pt cells):
- **Content** (the GIF hero, frame counter, 2D/3D toggle) = **6pt** chunky pixels.
- **Chrome text** (selector labels, action labels, status) = **2pt** master pitch — because a
  word at 6pt is illegibly huge ("structure" ≈ 360pt wide). 2pt keeps words legible AND
  pixel-hard, on the same master grid. This relaxes "one pitch per screen" to "one master
  grid; commensurate sub-grids may coexist" — which is what the GIF+chrome relationship
  actually is.

## The rule

No `Text`, no `Font.system`, no `glassEffect`/`.buttonStyle(.glass)`, no `Image(systemName:)`,
no `Slider` on OUR chrome. Every label = `CellText`; every button = `CellSprite`/`CellSelector`
ground; every icon = `CellIcon` mask. (Exempt: system `Menu`/`Picker` *popovers* and
sentence-length prose per §6.8 — but their trigger labels are still `CellText`.)

## Primitives

- `CellText` — rasterises any string to hard cells (AA off, NN upscale). **+ NSCache** added
  (perf: the 20fps status line must not re-rasterise every frame).
- `CellSprite` / `CellDigits` / `CellIcon` — all now take a `cellPt` param (default 2pt).
- `CellSelector` (existing) — the segmented control the 3 word-selectors delegate to.
- `CellActionButton` (NEW, `CellChrome.swift`) — flat cell ground + `CellIcon` + `CellText`,
  touch floor pinned in **points (≥44pt)**, not cells×pitch.
- `CellIcon.share / .grid3x3 / .retake` (NEW masks). `.seal / .warn` pending (Phase 2).

## STATUS: Phases 0–5 COMPLETE (2026-06-04) — build + 149 Swift + 463 Haskell tests green

Coverage grep confirms: **zero `glassEffect` / `.buttonStyle(.glass)` / `Slider` / `Picker` /
`Stepper` calls remain on our chrome** (only doc-comments mention them); the only
`Image(systemName:)` is inside `CellSymbol`'s own rasteriser. Remaining `Text(` are
accessibility labels, `#Preview` scaffolding, the Menu-popover item labels, and the two
documented §6.8 prose blocks (SettingsView help, State-screen paragraphs).

Key addition beyond the original plan: **`CellSymbol`** — rasterises ANY SF Symbol to hard
cells (same snap+NN-upscale as `CellText`), so reimplementing `GlassIconButton` to use it
pixelated EVERY glass icon button at once (cube/cloud/editor/capture) instead of authoring
dozens of masks. New primitives: `CellSymbol`, `CellActionButton`, `CellSlider` (the discrete
cell stepper), `CellIcon.share/.grid3x3/.retake/.seal/.warn`.

## Build phases

- **Phase 0 — spec (pending):** add `reviewPitchPt = 3*cellPt` + `lawReviewPitchCommensurate`
  to `Spec.Lattice`, emit into `LatticeContract.swift`, set `SFTheme.gifCellPt =
  CGFloat(SixFourLattice.reviewPitchPt)` (kill the free `6` literal). Makes the 3× a theorem.
- **Phase 1 — the screenshot fix (DONE 2026-06-04, build+149 tests green):**
  `CellText` cache; `CellIcon` `cellPt` + share/grid3x3/retake masks; `CellActionButton`;
  converted `RepresentationSelector`, `ScopeSelector`, `BranchingSelector` → `CellSelector`;
  `GridAxisSelector` label → `CellText`; `GIFReviewView.actionRow` (Share/contact/Retake) →
  `CellActionButton`. **The structure/grid/cloud/cube · per-frame/global · 16²/4⁴/2⁸ ·
  Share/Retake surfaces are now cells.**
- **Phase 2 — Review status + badge:** `statusLine` (sig/256 → `CellDigits`, seal/warn →
  `CellIcon.seal/.warn`, frame/bins/mse → `CellText`); `determinismBadge` glass card → flat
  cell panel. Width-fit the long `pipeline`/`sha256`/"Deterministic core" lines (they exceed
  402pt at large cells — wrap or shrink rows). Mandatory `CellText.snap` dimension golden.
- **Phase 3 — status bar + capture residuals:** `.statusBarHidden(true)` + Info.plist
  `UIStatusBarHidden=YES` on every root; convert `GlassControls` (GlassIconButton/Chip) +
  `StatsFooterView`.
- **Phase 4 — the missed Review subviews (critic's coverage gaps):** `AddressPickerView`
  native `Picker(.wheel)` → a cell wheel/stepper (+ its 7 `Text` + glass); `Quad4DrillView`
  (`Text` + `.glass`); `GlobalPaletteEditorView` (glass cluster + `Text`); the omitted
  `PaletteCloudView` (247/499/504/525) and `VoxelCubeView` (300/310/315/343/347/354/398) glass
  buttons. These are ON Review — "100% pixelated" is only true once they're done.
- **Phase 5 — State screens + cleanup:** `StateScreens` (Image systemName/Text/.glassProminent);
  cell sliders/steppers for the cube/cloud study panels; retire `SFTheme.footnoteSelector/
  captionMono/dimText/hairline/glass*` + the `Glass*` components; add a grep-lint (no
  `Text`/`glassEffect`/`systemName`/`Slider` in `UI/` outside the exempt prose allow-list).

## Open from the critique (carry into later phases)

- Label register: standardize chrome words at `rows: 9` (selectors) / `11` (actions) — `rows:7`
  was too small. Pin per call site; the snap-dimension golden catches drift.
- Hit targets: every cell button asserts `minHeight: 44` (points), verified.
- `AddressPicker` wheel is VoiceOver-adjustable; its cell replacement needs
  `.accessibilityAdjustableAction` or adjustability regresses.
- Opacity→opaque conversions (`dimText`/`hairline`/`.opacity(…)`) must use the existing
  `ledGhost(40,40,40)`/`dimInk(140,140,140)` precedents, not invented shades.
