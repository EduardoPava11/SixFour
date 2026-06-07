# SixFour — STATUS (canonical)

> **NOTES.md = history; STATUS.md = current truth.**
> The load-bearing facts in this file are gated by `scripts/verify-doc-claims.sh` — run it
> before trusting a status claim. If a claim here disagrees with another doc, this file wins;
> the other doc is stale. Last reconciled 2026-06-05 (merges the former
> SIXFOUR-ARCHITECTURE-MAP, TECH-DEBT-LEDGER, SIXFOUR-DEBT-RECONCILIATION, and the
> forward-status parts of NOTES.md, all now archived/demoted).

## What SixFour is

SixFour is an iOS 26 camera app (Swift 6.2, strict concurrency, zero third-party deps) that
captures a 64-frame burst at 20fps and renders it to a 64×64×256-colour animated GIF. The
render path is a **deterministic, integer-exact Zig core** (`s4_*` C-ABI kernels) — the same
fixed-point fold runs identically across devices and is the default (`useDeterministicCore =
true`). The architecture is "one cube projected honestly": a 64³ index cube is the single
source of truth, and the 2D GIF, the palette grid, and the shutter are all Haar projections of
that one state. Haskell (`spec/`) is the source of truth — every cross-language claim (Zig ≡
Swift ≡ Haskell) is pinned by a generated golden vector. A look-NN is **designed and partially
trained on the Mac but not shipped on device**; the global palette the app emits today is the
deterministic Zig collapse, not a learned genome.

## BUILT / DESIGN-ONLY / MISSING ledger

### BUILT (verified on device path / in source)
- **Deterministic Zig render core.** Per-stage kernels (widen → linear→OKLab → quantize
  (maximin+Lloyd) → dither → significance fill → palette → LZW/GIF89a assemble) drive
  `DeterministicRenderer`; default path, GPU-float `GIFRenderer` is the throw-fallback.
  Native header exports **18** `s4_*` symbols.
- **GIFA→GIFB global collapse is WIRED in production.** `CaptureViewModel.renderDeterministic`
  (`:478`) → `renderDeterministicGlobal` (`:480/:555`) → `DeterministicRenderer.renderGlobalPalette`
  (`:268`) → `SixFourNative.globalCollapse` (`:314`) → Zig `s4_global_collapse`, gated by
  `settings.paletteScope == .global`. The shipped global palette is the **deterministic
  pooled-maximin collapse**, NOT a learned NN genome. (This retires the long-standing "zero
  callers / app cannot emit a global-palette GIF" claim, which was false.)
- **Single-call core entrypoint.** `s4_gif_encode_burst` is a real implementation (folds the
  per-stage kernels, returns `s4_gif_assemble`); `s4_widen_half_to_q16` and
  `s4_linear_to_oklab_q16` are implemented with golden anchors. (NOT stubs.)
- **Cross-language parity gates.** Collapse, value head, color, quantize, dither, GridAxis,
  CloudProjection goldens green; spec suite **517 tests pass**.
- **Palette explorer surfaces.** `.grid2D` (`GridLayout` + `PaletteGridView`, default review
  view), treemap (`PaletteTreeView`), AddressPicker, Quad4 drill, `PaletteCloudView`. Versioned
  AppSettings keys for representation + grid axes exist.
- **Total pixelation / no glass.** HUD de-glassed app-wide; **zero live `.glassEffect` calls**.
  Cell-rendered chrome.
- **One uniform cell across the whole capture scene (`CaptureGrid`, 4 pt).** Every cell —
  preview pixel, 16×16 palette swatch, background checker, gear — is the SAME 4 pt cell.
  Preview = 64 cells (256 pt), palette = 16 cells (64 pt, = the capture button), gear = 12
  cells (48 pt). The 4 pt capture cell is deliberately finer than the 6 pt `GlobalLattice`
  chrome atom (which still governs Review): the 64-cell preview must fit with margin to
  clear the rounded corners and rotate into the 64³ cube. Geometric law: preview = 4×
  palette (cell-count locked). (Canonical Display palette stays `blockFactor 1` = 6 pt.)
- **Grid refresh heartbeat (capture ground).** A full B/W checkerboard of the 4 pt cell
  that inverts at 20 fps (`GridHeartbeatClock` / `GridChecker` / `GridRefreshFieldView`),
  baked as one screen-sized bitmap, two-phase image swap (O(1) flip), freezes static under
  reduce-motion. The opaque heroes draw on top. Pure UI off the deterministic path.
- **Look-NN forward path proven in Haskell** (LookNetE/R/D, 384-DOF SigmaPairTree decoder,
  Obfuscation keystone, PairTree round-trip) — proven, but **nothing runs it on device**.
- **Trained grayscale-L deploy blob** `trainer/out/look_net_trained.s4ln` (133,923 B) exists
  and the Zig `s4_load_look_net` loader is fixture-verified.

### DESIGN-ONLY (spec'd / written, not on the live render or UI path)
- **Learned global palette (the NN genome).** No on-device Swift forward pass; `loadLookNet`
  has **zero production callers**. The genome path is unreached.
- **`PaletteSearch` MCTS keystone** — spec-complete (336 LOC), zero iOS consumer.
- **REVEAL axis** (`ColorBleed`/`ChromaAllocation`/`Reference`/`Bleed`/`BleedLoop`/`Incitement`)
  — spec'd in BLEED_LOOP, **not on disk**; depth-8 grey head has δ≡0 so the bleed dial is inert.
- **SigmaPairHead 384-DOF σ-equivariance instance** — the 384-DOF wiring is CLOSED, but the
  equivariance instance at SigmaPairHead is not re-instantiated.
- **`PaletteCloudView` / VoxelCubeView** — built but off the default review path
  (`gridFirstReview`/self-heal to `.structure`).
- **256³ deep export, fold/loom authoring UI, ScopeSelector-as-named-file, GCT-mode encoder** —
  not built.

### MISSING
- **Trained full-colour NN + on-device forward pass** — does not exist; trainer is
  grayscale-L-only (a=b=0 nucleus, Mac-side).
- **Training data** — `trainer/data/captured_frames` and `trainer/data/reference_gifs` are
  empty/absent (gitignored). Eval is synthetic-seed only (`eval_l_quality.py`); the
  "beats baseline 5/6 / ~3×" figure is unpinned synthetic runtime output, not a contract.
- **`Spec.Lattice` call-site enforcement** — the *module* is BUILT and law-bearing (10 laws,
  gated by `Properties.Lattice`, emits `LatticeContract.swift`); what is still `[PLANNED]` is the
  **lint that forbids off-atom point literals at call sites** — tracked as `atom-pitch-violations` below.
- **Direct LZW parity gate** (`s4_gif_assemble` ≡ `GIFEncoder.swift`) and Swift golden gates
  for dither / palette→sRGB8 / sRGB8→OKLab.

## Open debt

| id | what | where (file:line) | sev | status |
|----|------|-------------------|-----|--------|
| empty-training-data | No committed training data; trainer is synthetic-only | `trainer/data/` (absent) | high | open |
| looknet-load-unused | `loadLookNet` declared, zero production callers (NN spine unwired) | `SixFour/Native/SixFourNative.swift:82` | high | open |
| spec-lattice-callsite-enforce | `Spec.Lattice` module BUILT & gated (10 laws, `Properties.Lattice`, emits `LatticeContract.swift`); remaining gap = lint forbidding off-atom point literals at call sites | `spec/src/SixFour/Spec/Lattice.hs` + `scripts/lint-grid.sh` | med | open (was mis-filed "unbuilt") |
| reveal-axis-unbuilt | ColorBleed/ChromaAllocation reveal modules spec'd, not on disk | `spec/BLEED_LOOP.md:235` | med | open |
| palette-search-design-only | `PaletteSearch` MCTS spec-complete, no iOS consumer | `spec/src/SixFour/Spec/PaletteSearch.hs` (336 LOC) | med | open |
| gifencoder-lzw-parity | No direct `s4_gif_assemble` ≡ `GIFEncoder.swift` LZW parity gate | `Native/src/kernels.zig` | med | open |
| missing-dither-golden | `s4_dither_frame` lacks a Swift golden gate | `SixFourTests/GlobalRenderTests.swift` | med | open |
| missing-palette-srgb8-golden | `s4_palette_oklab_to_srgb8` lacks a Swift golden gate | `SixFourTests/GlobalRenderTests.swift` | low | open |
| missing-srgb8-oklab-golden | `s4_srgb8_to_oklab_q16` lacks a dedicated golden | `Native/src/kernels.zig` | low | open |
| palette-tree-unlabeled | `PaletteTreeView` split planes drawn but axis/threshold unlabelled | `SixFour/UI/Components/PaletteTreeView.swift:64` | low | open |
| atom-pitch-violations | Bare point dims bypass `GlobalLattice` (AddressPicker/GlobalPaletteEditor step buttons) | `SixFour/UI/Components/AddressPickerView.swift:173` | low | open |
| ledger-self-drift | TECH-DEBT-LEDGER §A1 (#5–#8) audits NOTES phrases already annotated CLOSED inline | `docs/TECH-DEBT-LEDGER.md:177` | low | resolved-by-archival |

## Ethos pillars

1. **One cube, projected honestly** — the 64³ index cube is the only state; GIF/grid/shutter are Haar projections of it.
2. **Deterministic, integer-exact** — the Zig fold is byte-exact cross-device; float is the off-path "lying layer" (mint ≠ apply).
3. **Haskell is the source of truth** — Zig and Swift mirror the spec; every cross-language claim is golden-pinned.
4. **Scaffold, not automate** — the NN proposes, SEARCH generates options, the user authors and owns the look; no auto-collapse button.
5. **Rigor only where failure is "pager-on-fire"** — stay at golden vectors + Layers 0–2; escalate to type-level proofs only when a shape theorem is load-bearing.
