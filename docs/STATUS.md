# SixFour — STATUS (canonical)

> **NOTES.md = history; STATUS.md = current truth.**
> The load-bearing facts in this file are gated by `scripts/verify-doc-claims.sh` — run it
> before trusting a status claim. If a claim here disagrees with another doc, this file wins;
> the other doc is stale. Last reconciled 2026-06-17 (state-inspection pass: verified test
> counts to **834 Haskell / 31 Zig** — both gates green; closed the Zig-export-surface debt
> by declaring the 4 `s4_cube/rgbt_lift` symbols in the header + lighting the previously-skipped
> `rgbt4d_fixture_test`; see `docs/SIXFOUR-STATE-INSPECTION-2026-06-17.md`). Prior reconcile
> 2026-06-09 (debt-cleanup pass: archived 10 docs
> superseded by the 4 pt GRID v3 atom / deleted views, recorded on-device-personalization
> feasibility, and added orphan-spec + Zig-export-surface debt rows — see
> `docs/SIXFOUR-DEBT-CLEANUP-REPORT.md`). Prior reconcile 2026-06-05 (merged the former
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
Swift ≡ Haskell) is pinned by a generated golden vector. A look-NN is **designed (forward
oracle + Zig loader code) but its supervised MLX training was ABANDONED 2026-06-17 (trained
weights deleted) and nothing runs it on device**; the global palette the app emits today is the
deterministic Zig collapse, not a learned genome. Full NN inventory + design ledger:
`docs/SIXFOUR-NN-DESIGN-CANON.md` (roster) and `docs/SIXFOUR-NETWORKS-CANONICAL-ROSTER.md`
(per-net detail).

> **Single source of DIRECTION: `docs/SIXFOUR-CANONICAL-PATH.md`** (2026-06-18). The canonical
> core = one Gumbel-AlphaZero policy+value predictor as a *bounded addition above a frozen
> Q16-idempotent maximin floor*, read at search budgets n=0/1/8–16 (which subsume the
> deterministic / residual / AlphaZero candidates; supervised MSE Look-NN rejected). v1 ships
> value-only search over a frozen policy; the calibrated taste organ + perceptual warp are
> separately-specced research bets, not settled. STATUS (this file) stays the canonical *status*
> ledger; CANONICAL-PATH is *direction*. Cited research: `docs/SIXFOUR-RESEARCH-*.md`.

## On-device personalization feasibility (A19 Pro / iOS 26) — north-star

The product north-star is **on-device personalized look-learning**: the user trains / "push-pulls"
a tiny proprietary net on the iPhone so it learns *their* look, with looks mapped in categories.
Feasibility verdict (researched 2026-06-09, iPhone 17 Pro / iOS 26):

- **Hardware: YES, comfortably.** A19 Pro's per-GPU-core **Neural Accelerators** (~8 TFLOPS FP16 /
  ~14.7 TOPS INT8, programmable + autodiff-capable) can train a ~115K-param net on-device; a
  forward+backward step over a 64-frame batch is < 1 GFLOP. The 40+ TOPS **Neural Engine is
  inference-only (no public backprop)** — this validates the "deploy on GPU, skip the ANE"
  decision. Real ceilings are 76.8 GB/s unified-memory bandwidth + kernel-launch overhead → keep
  the net small and on-chip (fuse via Metal `cooperative_tensor`).
- **Zero-dep training path (ranked by fit to the Tier 2 contract):** (1) **hand-written SGD on a
  small look-delta head** in Swift or the **Zig core** (byte-exact, cross-device — matches the
  `s4_*` philosophy), optionally BNNS; (2) **MPSGraph custom training loop** (first-party GPU
  autodiff + arbitrary W2/OT losses Core ML can't express); (3) **Core ML `MLUpdateTask` / kNN**
  (sanctioned, MSE/cross-entropy + innerProduct/conv only; kNN maps onto per-user look categories).
- **Ruled OUT on the shipped path:** `mlx-swift` (Tier 1 Mac-only — Swift.org says research, not
  production; the old "deploy to mlx-swift" note is STALE for Tier 2), Foundation Models LoRA
  (Mac-only training, language model, per-OS adapter lock), Metal 4 ML encoder (inference-only).
- **Spine:** Tier 1 (Mac/MLX) pre-trains the base net; the iPhone trains only a small per-user
  **delta head** from push/pull signals; the Haskell spec golden-gates both.
- **Spec gap (open debt below):** no look-CATEGORY taxonomy survives, no per-user delta/adapter
  spec, and no on-device trainer/gradient spec — the north-star has **zero spec footprint** today.

**UPDATE 2026-06-12 — the MPSGraph path is PROVEN on hardware and the Color Atlas gives the
north-star its first spec footprint.** Future Claude Code sessions: work ON TOP of this state —
do not re-research or re-derive it.

- **On-device training proven** (commit `ef0344e`, `SixFour/Atlas/AtlasTrainer.swift` +
  `SixFourTests/AtlasTrainerTests.swift`): MPSGraph `gradients(of:with:)` + SGD trained a
  29,249-param value net on the physical iPhone 17 Pro — Bradley–Terry loss 0.7154 → 0.00075
  over 300 steps, **12.4 ms/step steady, 6.3 s total**. The on-device run is real, but
  cross-language bit-identity Mac ↔ iPhone is UNPROVEN (no parity harness; folded from the
  state-inspection §2 C11 into `docs/SIXFOUR-GATE-COVERAGE-TABLE.md §5`). Gotchas (encoded in
  code): MPSGraph cannot EXECUTE in the simulator
  (uncatchable ObjC exception) and `MPSSupportsMTLDevice()` falsely returns true there —
  gate with `#if targetEnvironment(simulator)`. Device tests need signing overrides
  (`DEVELOPMENT_TEAM` + Apple Development identity; project.yml pins ad-hoc).
- **VALUE NET SPEC & IMPLEMENTATION STATE (single source of truth):** Spec (v1) = a LINEAR
  utility over the 770-D atlasEmbedding → scalar (`docs/SIXFOUR-ALPHAZERO-COLLAPSE-DESIGN.md
  §4.1`), which is literally `btUpdate` (`Spec.PreferenceUpdate`, dims=770) so the three spec
  laws hold for free. Device spike (PROVEN, current) = a NONLINEAR MLP over the 384-D genome
  + 128-D board context → scalar (`AtlasTrainer.swift`; 29,249 params pinned at
  `AtlasTrainingSession.swift:76`; 12.4 ms/step, train-only, never selects a palette). These
  are DIFFERENT heads over DIFFERENT inputs; cross-language bit-identity is UNPROVEN. Alignment
  work (debt `atlas-value-spec-drift`): rewrite AtlasTrainer to the v1 linear-770 head over
  atlasEmbedding, add the `-η·λ·θ` L2 decay, delete the 384-genome MLP, re-measure. Detail:
  `docs/SIXFOUR-NETWORKS-CANONICAL-ROSTER.md §4`.
- **Curated research**: `docs/ON-DEVICE-TRAINING.md` (adversarially verified, cited) — MPSGraph
  is the recommended first-party training API; `MLUpdateTask` legacy-only; `mlx-swift` stays
  Tier 1. Federated bootstrap design: single-message Prio split-trust aggregation, central DP
  at the aggregator, preference clustering for non-IID taste.
- **Federation thresholds measured** (`trainer/fed_sim.py`, findings in
  `trainer/fed_sim_results.md`): FedAvg beats local at K≥4 users for shared taste, K≥16–64 at
  moderate heterogeneity, never at the strong-non-IID worst case; the **β = n/(n+50) blend is
  the dominant cold-start policy**; oracle-vs-self cluster assignment gap (8–9 pts) is the
  high-leverage research item.
- **Spec footprint now exists**: `Spec/AtlasBoard|AtlasMove|AtlasState|DeltaCodebook|AtlasOracle|
  PreferenceUpdate|DecisionLog|AtlasCascade|Upscale256` (74 properties, all green) — the Move
  ADT, replay-record wire format, and on-device preference-update rule the north-star lacked.
  Remaining gaps: look-CATEGORY taxonomy, MPSGraph trainer spec/golden-gating, `.s4ln` v2.
- **Canonical design + continuation plan**: `docs/COLOR-ATLAS.md` — §8 lists the implementation
  phases and seams; the disclosed stub limits (true Q16 centroids through CaptureOutput, MCTS
  gallery for candidate B, binary SF64 decision log, brand-gate preflight) are the next units
  of work.

## BUILT / DESIGN-ONLY / MISSING ledger

### BUILT (verified on device path / in source)
- **Global-palette BACKEND + shareable GIF ladder + Save export (Family 2, 2026-06-12).**
  The byte-exact machinery to create + ship the ONE global palette (GIFA→GIFB): branch-aware
  collapse (`CollapsedPalette` carries `branching`+`branchedLeaves`; `BranchedPalette.projectQ16`
  for 16²/4⁴/2⁸); the **σ-locked generator-space δ** (`Spec.LeafOverride` — 8 Haskell laws + 11
  Swift byte-exact tests, adversarially verified HIGH assurance, release-`precondition` on the
  power-of-two contract; `projectQ16(_, override:)`); and the **Save** export (a cell-menu →
  any ladder rung GIF: 16³ working copy / 64³-B global) via a global-color-table
  `GIFEncoder.encodeGlobal` (drops the per-frame completeness brand), collapse off-thread.
  `preview ≡ ship` by construction. All cell-grid-native (`lint-grid` PASS). **The creation
  CONTROL UI was a `.review` VStack FORM (radix selector + axis buttons + display grid + δ
  slider) — REJECTED + DELETED** (a form ≠ the cell-grid medium). Being rebuilt as
  gesture-grid tools (Act III `.browsing`: 64 frames = 16 RGBT groups, swipe-pick) per
  `docs/SIXFOUR-GESTURE-GRID-TOOLS.md`. **Not yet:** the gesture tools, Act III `.browsing`
  phase, the picks→global `Spec.GroupRGBT` path, 256³ tiled rungs.
- **Deterministic Zig render core.** Per-stage kernels (widen → linear→OKLab → quantize
  (maximin+Lloyd) → dither → significance fill → palette → LZW/GIF89a assemble) drive
  `DeterministicRenderer`; default path, GPU-float `GIFRenderer` is the throw-fallback.
  Native header now **declares all 31** `s4_*` exports (28 shipped + 3 tooling-only:
  `s4_gif_decode`, `s4_gif_decode_scratch_bytes`, `s4_srgb8_to_oklab_q16`); the gate asserts the
  header symbol set ≡ the Zig export set (drift-proof). **RESOLVED:** `s4_quantize_frame`'s
  maximin (Gonzalez 1985 farthest-first) **IS** the `Spec.QuantFixed`/`Spec.Collapse` canon and
  Zig matches byte-for-byte — it was never a "maximin ≠ Wu" bug; do not re-flag.
- **Swipe-to-LOOK + R3D `.cube` LUT export (2026-06-10).** A "look" is ONE data-driven OKLab
  palette→palette transform derived from the captured palette's luminance-zone chroma profile
  (an OKLab port of `~/lut-generator/.../gif_palette_lut.py`). Two projections of the same
  transform: the live capture screen recolours the 64×64 hero + 16×16 palette on a horizontal
  **swipe** (`LivePhaseField.lookSwipe` cycles `AppSettings.captureLook: LookVariant`; index tile
  untouched ⇒ cell-grid law intact; transient `CellText` look name), and Review **Export LUT**
  bakes a 65³ `.cube` (`LUTFile`, Q16 6-decimal, Log3G10/RWGRGB→Rec.709) for grading R3D in
  Resolve. Spec source of truth: `Spec.{ZoneProfile,LookTransfer,RedFrontEnd,CubeLut}` (★ laws:
  luminance-preservation, preview≡cube, .cube grid ordering; 834 Haskell tests). Zig kernels
  `s4_zone_profile_q16`/`s4_look_transfer_q16`/`s4_build_cube_q16` are byte-exact to the spec
  (`lut_fixture_test.zig`, 31 Zig tests); transcendentals (Log3G10 decode, filmic exp) +sRGB
  encode are spec-generated embedded 1-D LUTs (`{log3g10_decode,filmic_tonemap,srgb_encode}_lut.bin`).
  Swift bridge `SixFourNative.{lookZoneProfile,lookTransfer,extractLUT}`. iOS build SUCCEEDED
  (compile-checked; on-device swipe/look + Resolve LUT verification is the user's step).
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
  CloudProjection, VoxelFit, RGBT-4D cube-ladder goldens green; spec suite **834 tests pass**
  (Haskell), **31 Zig tests pass** (incl. the now-live `rgbt4d_fixture_test` cross-language gate).
- **Capture→GIFA morph on the one surface (2026-06-07).** The live hero paints the REAL
  camera (`σ.previewTile` index cells, not a synthetic scroll); the loading sweep streams the
  REAL deterministic partials (`raw→quantize→dither→palette`) in true colour via
  `DeterministicRenderer.onPartial` → `σ.indexCube`; review renders the TRUE per-frame GIFA
  (`σ.palettesPerFrame`, 64×256, not one global palette replicated). One addressing function
  `Surface.cellGlobal(x,y,t)` backs every cube reader. Review tilt is DISCRETE rung sliders
  (`SixFourVoxelFit` ladder, flat = the GIF).
- **The GIFA review cube is RENDERED AS CELLS — the Metal raymarcher is DELETED (2026-06-07).**
  Per-cell rasterizer `Surface.bakeCube` (forward-scatter z-buffer, 1 voxel = 1 cell) bakes the
  64³ GIFA to an `N×N` cell raster, drawn through the SAME `CellSprite`/`CellBitmap` as the live
  preview — pure Swift+simd, no Metal, no AA. Geometry proven in `Spec.VoxelFit`: `cubeBox`
  (centered box), `lawCubeBoxContainsSilhouette`, `lawRasterizeFrontIsGif` (front face byte ==
  2D GIF at every rung), golden box + cell-count tables. The near face plays the cursor frame
  (`frontFaceFrame`); rungs shear depth to reveal the (x,t)/(y,t) side faces, the cube
  shrinking-to-fit at integer pitch. **DELETED:** `VoxelCubeView.swift` (708 lines),
  `GIFPlayer`/`PlayerTransport` (dead legacy player), the `voxel_raymarch` Metal kernel
  (~200 lines), AppSettings `voxel*`/`playerMode` keys, `VoxelRestPoseIdentityTests`.
- **Movable ColorWidgets — three identities, ONE shared layout (2026-06-07).** A ColorWidget
  is a widget whose cells project the one cube; movability is a property of being one (chrome
  has no placement state → immovable by construction). The closed alphabet `ColorIdentity =
  Field64 | Palette16 | DiversityRing` is the only movable set. Each holds ONE global,
  phase-independent position (`AppSettings.widgetPlacement`, three versioned `*Position.v1`
  keys) that SLIDES across every phase dock (live / rendering / review all `.place(region(for:
  at:))`). Long-press LIFTS, drag moves, release SNAPS to the 4 pt atom via
  `MoveContract.move` — accepted iff in-bounds AND `GridLayoutContract.isDisjoint`, else exact
  snap-back; a clean tap still fires the shutter (`.movable` on the inner grid, not the
  Button). Source of truth `Spec.MovableLayout` (8 laws: disjoint-preservation, bounds-clamp,
  snap-idempotence, reject-is-identity, …) golden-pinned in `MoveContract.goldenAfter` and
  re-folded in `Surface.assertSpecParity` (DEBUG). **DiversityRing re-introduced** (the
  `CellRing` gauge had no caller) fed by `Surface.diversityGauge`. 834 Haskell tests + 11
  Swift `MovableLayoutTests` (move laws + persistence round-trip + corrupt-store fallback).
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
- **Supervised MLX look-net ABANDONED (2026-06-17).** The grayscale-L training did not converge
  to a usable look; the trained outputs (`look_net_trained.s4ln`, `atlas_net_trained.npz`,
  `synth_looknet_grayscale.gif`) were DELETED. The Zig `s4_load_look_net` loader CODE is kept and
  still fixture-verified against the regenerable golden `look_net.s4ln` (not a trained artifact).
  The core is reframing AlphaZero-shaped: a policy+value net over the reversible 2x2->1 LAB-collapse
  turn-based state machine (Atlas board/move/state), Bradley-Terry A/B preference as the reward,
  built bare-metal SIMT+Metal. Design: `docs/SIXFOUR-ALPHAZERO-COLLAPSE-DESIGN.md`; consolidated
  NN ledger + roster: `docs/SIXFOUR-NN-DESIGN-CANON.md` + `docs/SIXFOUR-NETWORKS-CANONICAL-ROSTER.md`;
  what-is-gated: `docs/SIXFOUR-GATE-COVERAGE-TABLE.md`. The
  sigma-pair / sigma-equivariant trunk ideas are ported, the MLX weights are not.

### DESIGN-ONLY (spec'd / written, not on the live render or UI path)
- **Learned global palette (the NN genome).** No on-device Swift forward pass; `loadLookNet`
  has **zero production callers**. The genome path is unreached. Full per-net inventory (all 7
  slots, spec status, param counts pinned-vs-est., trainers, consumers) lives in
  `docs/SIXFOUR-NETWORKS-CANONICAL-ROSTER.md`.
- **Atlas policy / value nets — NO spec-pinned NetIOSpec.** Only METRIC and LOOK have a
  `NetIOSpec` (Net.hs → net_shape.py → NetContract.swift). The Atlas policy (13-D tokens →
  1,524 logits) and the Mac/spec-v1 linear-770 value head carry NO cross-tier contract; the
  only proven value net is the device spike. See roster doc + debt rows `atlas-nets-unpinned`,
  `board-q16-unported`.
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
| atom-pitch-violations | `Spec.Lattice` call-site lint not yet enforced; re-scan live call sites for off-atom point literals (old `AddressPickerView.swift:173` cite is DEAD — that view + `GlobalPaletteEditorView` are deleted) | `scripts/lint-grid.sh` (planned) | low | open (cite refreshed 2026-06-09) |
| ledger-self-drift | TECH-DEBT-LEDGER §A1 (#5–#8) audits NOTES phrases already annotated CLOSED inline | `docs/TECH-DEBT-LEDGER.md:177` | low | resolved-by-archival |
| glasscontrols-dead | ~~`GlassControls.swift` orphaned~~ — **INVALID**: it defines `GlassIconButton`/`GlassToolbarCluster`/`GlassInfoChip`, all used by `PaletteCloudView`. NOT dead; the "0 refs" check grepped the type name, not the exported components. Kept. | `SixFour/UI/Components/GlassControls.swift` | — | **closed-invalid 2026-06-09** |
| haarribbon-orphan | `Spec.HaarRibbon` (Act III 2⁸ ribbon) — **resolved 2026-06-10**: wrote `Properties.HaarRibbon` (6 laws), wired into the suite; the header's parity-gate claim is now true (un-orphaned). | `spec/test/Properties/HaarRibbon.hs` | — | **resolved** |
| quartetdelta-orphan | `Spec.QuartetDelta` (Act II 4⁴ quartet) — **resolved 2026-06-10**: wrote `Properties.QuartetDelta` (6 laws), wired in; parity-gate claim now true (un-orphaned). | `spec/test/Properties/QuartetDelta.hs` | — | **resolved** |
| spec-quad4fit-dangling | `Spec.Map` cited retired `SixFour.Spec.Quad4Fit` (ADR-014) — dangling Haddock cross-ref | `spec/src/SixFour/Spec/Map.hs:46` | low | **resolved 2026-06-09 (removed)** |
| golden-drift-cloudgrid | **RESOLVED 2026-06-09/10.** All three hand-ports now golden-pinned: `Codegen.CloudProjection`→`CloudProjectionGolden` (`CloudWorld.map`); `Codegen.GridAxis`→`GridAxisGolden` pins `GridLayout.layout` AND the end-to-end `GridScript.surfaceColors` (layout→`Order.fromGrid`→surface). 4 golden tests RUN-pass in the sim (dyadic fixture ⇒ Float/Double precision-independent). | `Generated/{CloudProjection,GridAxis}Golden.swift` | — | **resolved** |
| s4-synth-burst-header-drift | `sixfour_native.h` declared `s4_synth_burst` with 5 params; Zig fn takes 8 | `Native/include/sixfour_native.h` | med | **resolved 2026-06-09 (8-param prototype)** |
| zig-undeclared-exports | 3 Zig exports lacked header decls (`s4_gif_decode`, `s4_gif_decode_scratch_bytes`, `s4_srgb8_to_oklab_q16`) | `Native/include/sixfour_native.h` | low | **resolved 2026-06-09 (declared + set-equality gate)** |
| gif-encode-burst-golden-skip | **RESOLVED 2026-06-10.** `spec-fixtures` now emits `golden_input.halfs` + `golden.gif` from a COMPOSED Haskell fold (widen→oklab→quantize→dither(FS)→palette→assemble, K=256/32²/2f, exact dyadic halfs); `gif_fixture_test` runs `s4_gif_encode_burst` on it and asserts byte-equality. Monolithic entrypoint now pinned to the spec (was composition-tested only). | `spec/app/Fixtures.hs` + `Native/src/gif_fixture_test.zig` | — | **resolved** |
| no-look-category-taxonomy | North-star "looks mapped in categories" has no spec — the Berlin-Kay/`Spec.Competition` grid was deleted when `Spec.Preference` went category-free | `spec/src/SixFour/Spec/Preference.hs` | high | open |
| no-ondevice-trainer-spec | No Spec/Codegen for an on-device gradient/weight-update step over the 384-DOF σ-pair delta head; `Spec.Preference` (Bradley-Terry) is orphaned (no Swift port/codegen/consumer) | `spec/src/SixFour/Spec/Preference.hs` | high | open |
| palette-value-unused | `PaletteValue.swift` search value head has zero iOS consumers (part of the unwired learned/search spine) | `SixFour/Palette/PaletteValue.swift` | med | open |
| glrm-wired-but-unused | `Spec.GLRM` OLS kill-switch ported to `GLRM.swift` (byte-exact, golden vs Haskell) and WIRED: `AtlasTrainingSession.makeBatch` regresses win/loss on `[coverage, beauty, ‖chroma‖²]` and BLOCKS real-data training (falls back to synthetic, `.blockedByKillSwitch`) when `R² < r2Floor`. | `SixFour/Atlas/GLRM.swift`, `SixFour/Atlas/AtlasTrainingSession.swift` | med | DONE 2026-06-18 |
| board-q16-unported | `Spec.BoardQ16` ported to owned Zig (`s4_board_mass_q16`/`s4_board_counts_to_mass_q16`); `AtlasBoard16.base` now uses it (mass = round-half-up `count·2¹⁶/total`, stored `/65536` = exact dyadic) so the policy/value board input is cross-device bit-identical. Golden-gated Haskell≡Zig≡Swift (`board_q16` Zig test + `BoardQ16GoldenTests.swift`). | `Native/src/kernels.zig`, `SixFour/Atlas/AtlasBoard.swift` | high | DONE 2026-06-18 |
| no-metal-golden-gate | No Metal kernel gated byte-exact vs a Zig golden; `field.metal` is float-tolerance vs a CPU reference; `s4_cube_lift_level` (`kernels.zig:684`) has no Metal port | `SixFour/Metal/field.metal` / `Native/src/kernels.zig:684` | high | open (blocker) |
| atlas-nets-unpinned | Atlas policy+value have no spec-pinned `NetIOSpec`; dims live only in trainer Python (`ATLAS_TOKEN_DIM=13`, `N_VOCAB=1524`); no `Codegen.Atlas*` | `trainer/atlas_net_mlx.py` / `spec/src/SixFour/Codegen/` | high | open (blocker) |
| atlas-value-spec-drift | Device value spike (nonlinear MLP, 384 genome + 128 board ctx, 29,249 params) ≠ spec v1 (linear-770 over atlasEmbedding); rewrite AtlasTrainer to spec | `SixFour/Atlas/AtlasTrainer.swift` | high | open |
| ab-perturb-stub | A/B device path uses `perturb()` fixed-delta stub (±0.04 a-axis, Q16 2621), not spec'd `sampleOrthogonalPair`/`GenomePair` | `SixFour/Atlas/AtlasState.swift` / `spec/src/SixFour/Spec/GenomePair.hs:270` | high | open |
| gan-framing-contradiction | `regimen.py` calls Stage 2 "ε-annealed GAN"; `look_net_loss_mlx.py` implements 3 non-GAN terms (Bures/coverage/beauty); `Spec.Loss`/`Map.hs:25` says "GAN dropped" — strike vestigial GAN framing + dead lam_adv/dlr/eps_* from regimen.py (Tier-1, no gate) | `trainer/regimen.py:14,54` | med | open |
| looknet-param-count-est | Look-NN ~115K param count is an unsourced design estimate; no literal in look_net_mlx.py, no law in Spec.LookNet | `docs/COLOR-ATLAS.md` | low | open |
| genome-blend-carrier-export-design-only | `Spec.{GenomeBlend,GenomeCarrier,ExportFamily}` spec'd, no on-device consumer (federated import, v2+) | `spec/src/SixFour/Spec/Map.hs` (§4) | low | open |
| app-widget-gap-plan | App-only widget plan (radix 16²/4⁴/2⁸ as one `SplitTree` at 3 branching factors, the compression/cut-level lever P5, and the P6 train-the-iPhone seam). 5 decisions resolved 2026-06-12: (1) three radix screens = perspectives of one widget; (2) picking on Capture+Review; (3) log picks as Bradley–Terry NOW behind the Atlas flag; (4) **TWO 256³ products** — A=per-frame (HD GIFA) + B=global (residual-seeded by the 64³ per-frame↔global comparison, HD GIFB); (5) both 256³ products are **trainable AND shareable**. §7 sequences the build (steps 1–2 = zero-NN plumbing). | `docs/SIXFOUR-APP-WIDGET-GAP-REPORT.md` | — | plan (2026-06-12) |

## Ethos pillars

1. **One cube, projected honestly** — the 64³ index cube is the only state; GIF/grid/shutter are Haar projections of it.
2. **Deterministic, integer-exact** — the Zig fold is byte-exact cross-device; float is the off-path "lying layer" (mint ≠ apply).
3. **Haskell is the source of truth** — Zig and Swift mirror the spec; every cross-language claim is golden-pinned.
4. **Scaffold, not automate** — the NN proposes, SEARCH generates options, the user authors and owns the look; no auto-collapse button.
5. **Rigor only where failure is "pager-on-fire"** — stay at golden vectors + Layers 0–2; escalate to type-level proofs only when a shape theorem is load-bearing.
