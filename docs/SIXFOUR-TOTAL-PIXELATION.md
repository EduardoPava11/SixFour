# SixFour — Total Pixelation (the screen grid IS the UI)

> **Atom-size reconciliation (2026-06-12).** The authoritative atom is **`gifPx = 4 pt`**
> (`= 12 device-px @3x`), and the **single source of truth is the code, not any prose doc**:
> `SixFour/Generated/LatticeContract.swift` (`gifPx = 4`, codegen'd from `Spec.Lattice`),
> mirrored by `SixFour/UI/ScreenLattice.swift` + `SixFour/UI/GlobalLattice.swift`
> (`SixFourLattice.gifPx`, GRID v3.0). This document already states 4 pt — it is **correct**.
> The gap report's §6 row that labels the (now-deleted) `SIXFOUR-DESIGN-LANGUAGE.md` v2.0 / 6 pt
> as "authoritative" is **mislabeled**: that doc was the stale one (6 pt is GRID-v2.0 lineage)
> and is no longer in the repo. When in doubt, read `ScreenLattice.swift`, not a markdown doc.

> Goal (user): the WHOLE app pixelated. Map the iPhone 17 Pro screen → a cell grid →
> that grid is the UI surface. No anti-aliased system text, no glass, no SF Symbols on
> our chrome. Source: `sixfour-total-pixelation` workflow (audit → design → critique), 2026-06-04.

## The grid (v3.0 — ONE 4pt atom)

> **v3.0 amendment (2026-06-06, commit `9a8d319`).** The 2pt-master / 6pt-content two-pitch
> model originally described here was unified away. There is now ONE atom. The text below is
> corrected; the structure and narrative of the document are unchanged.

`Spec.Lattice` maps the iPhone 17 Pro and emits `Generated/LatticeContract.swift` (mirrored in
`GlobalLattice.swift`). THE ATOM is `gifPx = 4 pt = 12 device-px @3x` — chosen (not `gcd`-forced)
because it lands on integer device pixels AND expresses the 44 pt HIG touch floor exactly
(`11·4 = 44`). The screen tiles to a **100 col × 218 row** lattice, with a 2 pt per-axis bleed
absorbed off-lattice at the safe edges. Every widget is an integer cell-rect on this ONE grid.

**One pitch, one atom (the v2.0 two-pitch tension is retired).** Content and chrome both live on
the single 4pt atom; widgets grow by using MORE atoms, never a bigger atom. The half-atom
`subPt = 2 pt = gifPx/2` is a commensurate sub-atom used only for fine spacing/gutters and text
legibility — it is NOT a second master grid. `scripts/lint-grid.sh` hard-fails any element that
introduces its own point size ("one pitch").

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

## STATUS: Phases 0–2 COMPLETE; Phases 3–5 PENDING (2026-06-06) — build + GRID lint + 547 Haskell tests green

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

- **Phase 0 — spec (DONE 2026-06-06, commit `9a8d319` — GRID v3.0):** unified on ONE 4pt atom.
  `Spec.Lattice` emits `gifPx = reviewPitchPt = 4` into `LatticeContract.swift`; the old 3×
  commensurate pitch (`reviewPitchPt = 3*cellPt`) is RETIRED in favour of single-pitch. `subPt
  = 2` is the half-atom for text/spacing only. The Lattice law gates the geometry as a theorem.
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
- **Phase 4 — the missed Review subviews:** `AddressPickerView`, `Quad4DrillView`, and
  `GlobalPaletteEditorView` were **DELETED** (not converted) in the cell-field cleanup
  (`cleanup/cell-field-law`, 2026-06-06) — they were non-cell chrome reachable only from the
  suspended palette-explorer scaffold (`gridFirstReview = true`). The remaining work is on the
  render-mode views that ARE kept: `PaletteCloudView` still carries glass buttons
  (`GlassIconButton`/`GlassToolbarCluster`) → convert to `CellActionButton`/`CellSelector`
  before reactivation; `VoxelCubeView` (the 3D iso GIF mode) needs its iso-angle control
  surfaced as `CellSlider`s. Tracked as §3b of the cell-field demolition plan.
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
