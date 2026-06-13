> **Status/built-state:** see [docs/STATUS.md](../STATUS.md) (canonical, gated by `scripts/verify-doc-claims.sh`). This document is design rationale, not a status ledger.

# SixFour — App Directory & File Map

> **Purpose.** A single orientation map of the *shipped iOS app* — its directory
> layout, the files that compose it, and how the deterministic **Zig core
> surfaces all the way up into the UI/UX**. Read this before adding UI/UX
> complexity so new work lands in the right place by default.
>
> **Scope:** stable structure only. For current *status* (built / designed / missing) defer to
> `SIXFOUR-ARCHITECTURE-MAP.md`; for the narrative, `SIXFOUR-VISION.md`.
>
> **Scope.** Map only. This document describes the structure as it is; it does
> *not* propose refactors, token consolidation, or design-law enforcement.
>
> **Verified.** Live against the tree on 2026-06-01: the shippable target
> `SixFour/` = **59 Swift files (9,117 lines) + 2 Metal shaders (572 lines) + 2
> resources**, across 22 directories.

---

## §1. Repo boundary — what ships vs. what is tooling

SixFour is a polyglot monorepo. **Only `SixFour/` compiles into the app** (Tier 2,
zero third-party dependencies per `CLAUDE.md`). Everything else is upstream
source-of-truth or Mac-side tooling. The one twist: the **Zig core (`Native/`)
is not "tooling"** — it builds to a static library that the app links and runs.

| Top-level | Role | Ships in app? |
|---|---|---|
| `SixFour/` | iOS app — Swift + Metal (Xcode target `SixFour`) | **YES** |
| `Native/` | **Zig** deterministic fixed-point core (`src/`, `include/`, `lib/`, `build.zig`) | **YES — linked static lib** |
| `SixFourTests/` | app unit tests | test target |
| `spec/` | Haskell algebraic spec — formally-verified source of truth; emits `SixFour/Generated/` | no |
| `trainer/` | Mac-side MLX training / export / gates (Python) | no |
| `studio/` | Rust analysis-core + rerun visualization dev tool | no |
| `docs/` | design docs (incl. `SIXFOUR-DESIGN-LANGUAGE.md`) — **this map lives here** | no |
| `scripts/` | build/deploy helpers | no |
| `project.yml` | **XcodeGen source of truth** for the `.xcodeproj` | — |
| `SixFour.xcodeproj/` | generated — never hand-edit; `xcodegen generate` | — |
| `CLAUDE.md`, `README.md`, `NOTES.md`, `SETUP.md` | project docs | no |

**Build facts:** iOS deployment target **26.0**, Swift **6.2**, strict
concurrency **complete**, zero third-party deps. A pre-build *spec-codegen drift
gate* regenerates `SixFour/Generated/` and fails the build if it diverges from
the committed contracts.

---

## §2. App target directory tree (`SixFour/`)

```
SixFour/
├── App/          @main entry point
├── Capture/      AVFoundation 64-frame burst capture
├── Color/        OKLab color science
├── Editing/      capture bundle + cluster-statistic ops
├── Encoder/      tile → GIF  (GPU float path + deterministic Zig path)
├── GeneLibrary/  on-disk organ catalog + AirDrop  (BundledOrgans/ empty, reserved)
├── Generated/    DO NOT EDIT — emitted from the Haskell spec
├── Metal/        GPU compute pipelines + .metal shaders
├── Native/       Zig C-ABI bridge (Swift side)
├── Organs/       learned-model loaders (metric organ)
├── Palette/      palette extraction + dithering + structure
├── Resources/    stbn3d-8.bin blue-noise mask
├── Settings/     AppSettings store
└── UI/
    ├── Theme.swift    SFTheme design tokens
    ├── Components/     reusable views (glass, cells, palette widgets)
    └── Screens/
        ├── Capture/    CaptureView + CaptureViewModel
        ├── Review/     GIFReviewView
        ├── Settings/   SettingsView
        └── State/      bootstrap / unauthorized / failure
```

---

## §3. ⭐ Zig → UI/UX trace (priority)

The deterministic Zig core is **the thing the user watches**, not a hidden
backend. It is the **default** render path (`useDeterministicCore = true`); the
GPU float path is a silent fallback only if a kernel fails. The five render
stages are literally the strings shown on the capture banner, and the SHA-256 of
the Zig output is the "byte-reproducible" proof shown in Review.

### Layer 1 — Zig source (`Native/src/`)

Exported through the C ABI in `Native/include/sixfour_native.h` (14 `s4_*`
symbols). Kernel implementations live across `Native/src/*.zig` (chiefly
`kernels.zig`; `root.zig` holds `s4_probe` + `s4_load_look_net`; `synth.zig` is
Mac-only training-data synthesis). Each `*_fixture_test.zig` byte-checks a stage
against a Haskell golden.

| Kernel | Role |
|---|---|
| `s4_set_log_callback` | install the Swift log sink (one line per kernel call) |
| `s4_quantize_frame` | maximin seed + optional Lloyd → k=256 Q16 OKLab centroids + indices |
| `s4_dither_frame` | 4 modes (Floyd-Steinberg / Atkinson / STBN / frozen-STBN) → dithered indices |
| `s4_significance_fill` | rebalance so every slot ≥ minPopulation; emit k×7 cell stats |
| `s4_palette_oklab_to_srgb8` | fixed-point gamma map → k×3 sRGB8 (the GIF local colour table) |
| `s4_gif_assemble` | per-frame indices + palettes → LZW / GIF89a bytes |
| `s4_load_look_net` | parse an MLX-trained look-NN weight blob (deploy path; not yet on the render path) |
| `s4_probe` | FFI smoke test (`x + 1`) |
| `s4_synth_burst` | **Mac-only** deterministic training-burst generator |
| `s4_gif_encode_burst` (+ `_bound`), `s4_widen_half_to_q16`, `s4_linear_to_oklab_q16`, `s4_burst_scratch_bytes` | monolithic whole-burst path + helpers — **stubbed / unused on device** (see §7) |

Compiled to `Native/lib/{iphoneos,iphonesimulator}/libsixfour_native.a` and
linked into the app target.

### Layer 2 — Swift bridge (`SixFour/Native/SixFourNative.swift`, 318 lines)

- C declarations imported via `Native/SixFour-Bridging-Header.h`.
- `installLogging()` → `s4_set_log_callback`; routes every kernel line to
  `Logger(subsystem: "com.sixfour.SixFour", category: "native.zig")`.
- `withZigLogsSuppressed(_:)` mutes the sink during the ~10 Hz live preview
  (which calls kernels every frame).
- Per-stage wrappers; **Swift owns all memory, Zig only fills buffers**:
  `oklabToQ16`, `quantizeFrame`, `ditherFrame`, `significanceFill`,
  `paletteToSRGB8`, `gifAssemble`, plus `loadLookNet`.

### Layer 3 — Consumer (`SixFour/Encoder/DeterministicRenderer.swift`, 248 lines)

- `render(tiles:comment:onStage:)` drives the five kernels **one stage at a
  time**, firing `onStage(.quantize / .dither / .significance / .palette /
  .encode)` between each so the UI can show which kernel is running.
- Computes per-frame MSE + 16³ OKLab coverage in the *same* Q16 integer domain
  (lines 170–198), so the Review numbers match the bytes.
- `sha256Hex` = SHA-256 of the GIF bytes (line 209) — the reproducibility
  fingerprint. A `.notice` headline log (line 216) records per-stage timings.
- **Path selection** in `CaptureViewModel.renderOnce()`:
  `if settings.useDeterministicCore { renderDeterministic … }` — on throw it logs
  and falls back to `GIFRenderer` (GPU float).

### Layer 4 — UI/UX surfaces (what the user sees & controls)

| Surface | Location | Visible label | Zig link |
|---|---|---|---|
| **Engine toggle** | `SettingsView.swift:92` (section `"Engine"`, line 94); `AppSettings.useDeterministicCore`, key `sixfour.useDeterministicCore.v1`, default **true** (`AppSettings.swift:30,94,150`) | **"Deterministic core"** + footer explaining reproducible vs. GPU-float bytes | chooses Zig vs. GPU path |
| **Live stage banner** | `CaptureView.swift` phaseBanner ← `CaptureViewModel.deterministicStage` | "Quantizing — maximin palette…" → "Dithering — shaping the residual…" → "Significance — backing every colour…" → "Palette — OKLab → sRGB…" → "Encoding — LZW / GIF89a…" | each string = one Zig kernel running now (`DeterministicRenderer.Stage`, lines 22–27) |
| **Reproducibility badge** | `GIFReviewView.swift:138–163` (shown iff `deterministic && sha256`) | green seal **"Deterministic core · byte-reproducible"**, pipeline trace `quantize → dither → significance → palette → encode`, selectable **`sha256 ……`** | proves the GIF came from the verified Zig kernels |
| **Per-frame status** | `GIFReviewView.swift:114–132` | e.g. `255/256 ✓ · frame 1/64 · 48 bins · mse 0.0042` | significance count from `s4_significance_fill`; MSE/coverage in Q16 |
| **Stats footer** | `StatsFooterView.swift` | `Diffusion · 2.4 MB · 342 ms · ✓` / `MSE 0.0042 · κ ∞ · χ² 0%` | MSE from Zig quantization; **κ/χ² are GPU-only → render as ∞/0% on this path (see §7)** |
| **Console telemetry** | categories `native.zig` (per kernel) + `deterministic` headline (`DeterministicRenderer.swift:216`) | per-kernel lines + `[deterministic] 64f → NB in Tms […] sha256 …` | one log line per kernel; persisted at `.notice` |

**Takeaway.** Adding UI/UX complexity here is largely about *surfacing more of
this pipeline*. New capture/Review widgets should read the fields already
produced on `CaptureOutput` / `DeterministicRenderer.Result` — `perFrameMSE`,
`perFrameCoverage`, `cells`, `srgbPalettes`, `sha256Hex` — rather than
recomputing.

---

## §4. File-by-file map

Every file in §2's tree appears once, with line count and a one-line purpose.
*Largest files flagged.*

**App**
- `App/SixFourApp.swift` (12) — `@main`; WindowGroup → `CaptureView()`, dark mode, status bar hidden.

**Capture**
- `Capture/CaptureSession.swift` (851 — **largest**) — AVCaptureVideoDataOutput 20fps burst orchestrator; session lifecycle, frame delivery, timing.
- `Capture/FrameBuffer.swift` (28) — bounded actor accumulating the 64-frame OKLabTile burst.

**Color**
- `Color/ColorScience.swift` (96) — OKLab struct + sRGB↔OKLab conversions.

**Editing**
- `Editing/CaptureBundle.swift` (113) — in-memory archive of one capture's raw + extracted state; re-process for editing.
- `Editing/ClusterStatisticsOps.swift` (384) — pure math over ClusterStatistics (χ² admission, PCA, multicollinearity).

**Encoder**
- `Encoder/GIFRenderer.swift` (271) — GPU float render path (K-means + blue-noise).
- `Encoder/DeterministicRenderer.swift` (248) — **Zig deterministic path** (see §3 Layer 3).
- `Encoder/GIFEncoder.swift` (274) — 64 OKLab tiles → animated GIF89a format encoder.
- `Encoder/ContactSheet.swift` (66) — 64 tiles → 8×8 grid PNG (raw-capture validation).

**GeneLibrary**
- `GeneLibrary/GeneStore.swift` (110) — on-disk organ catalog under `<appSupport>/genes/<slot>/`.
- `GeneLibrary/AirDropHandler.swift` (84) — import/export `.sixfour-genes` bundles.
- `GeneLibrary/BundledOrgans/` — empty, intentionally reserved.

**Generated — DO NOT HAND-EDIT** (emitted by `cabal run spec-codegen`)
- `Generated/NetContract.swift` (30) — NN slot identifiers; mirrors `Spec/Net.hs`.
- `Generated/SignificanceContract.swift` (103) — per-frame palette significance constants; mirrors `Spec/Significance.hs`.
- `Generated/StageContract.swift` (75) — shape constants (64, 256 colours, 4 frames); mirrors `Spec/Shape.hs` + `Spec/Color.hs`.
- `Generated/STBN3DContract.swift` (39) — loader for the 8×8×8 blue-noise mask; mirrors `Spec/STBN3D.hs`.

**Metal**
- `Metal/KMeansPalettePipeline.swift` (439) — all-GPU Lloyd k-means palette extraction.
- `Metal/Pipeline.swift` (286) — per-frame OKLab tile producer (camera frame → OKLab pixels).
- `Metal/BlueNoisePalettePipeline.swift` (150) — GPU blue-noise ordered-dither assignment.
- `Metal/TextureCache.swift` (67) — CVMetalTextureCache wrapper (capture-queue bound).
- `Metal/GPUContext.swift` (44) — shared device / queue / shader-library plumbing.
- `Metal/PalettePipeline.swift` (19) — per-frame extraction protocol.
- `Metal/PaletteEngines.swift` (16) — pipeline factory (single Wu-init K-means).
- `Metal/Shaders.metal` (523) — capture + k-means compute kernels.
- `Metal/NearestCentroidShaders.metal` (49) — blue-noise assignment kernel.

**Native**
- `Native/SixFourNative.swift` (318) — **Zig C-ABI bridge** (see §3 Layer 2).

**Organs**
- `Organs/Composition.swift` (68) — "signature look" = optional metric organ + dither choice (JSON in bundle).
- `Organs/MetricOrgan.swift` (41) — metric organ loader (tiny PSD 6-float matrices, JSON).
- `Organs/Organ.swift` (36) — protocol + pipeline insertion points (only `.metric` ships).

**Palette** (14 files)
- `Palette/Dither.swift` (368) — error-diffusion (Floyd–Steinberg + Atkinson) on OKLab tiles.
- `Palette/WuQuantizer.swift` (322) — shared Wu quantization core (CPU + GPU histogram parity).
- `Palette/PaletteGenerator.swift` (215) — per-frame finishing pass (metric refine + dither).
- `Palette/NearestCentroid.swift` (205) — SIMD nearest-centroid hot loop.
- `Palette/ClusterStatistics.swift` (162) — per-frame extraction output (centroids + per-cluster stats).
- `Palette/SplitTree.swift` (131) — median-cut partition; Review treemap structure.
- `Palette/SignificantSplitFill.swift` (114) — significance-preserving split-fill (≥ minPopulation per slot).
- `Palette/KMeansLab.swift` (101) — Lloyd in OKLab (CPU path), generic over DistanceMetric.
- `Palette/GridLayout.swift` (96) — user-assignable 2-axis 16×16 grid; Swift port of the spec.
- `Palette/LivePreviewAnalysis.swift` (84) — ~0.1 ms/frame live preview gauge (distinct-colour + dominant hue).
- `Palette/GlobalPaletteCollapse.swift` (60) — per-frame → global MAXIMIN farthest-point collapse (provisional).
- `Palette/PaletteExtractor.swift` (54) — per-frame extraction protocol.
- `Palette/DistanceMetric.swift` (42) — Euclidean OKLab + learned PSD metric.
- `Palette/KMeansExtractor.swift` (28) — adapter: KMeansPalettePipeline → PaletteExtractor.

**Settings**
- `Settings/AppSettings.swift` (165) — centralized persisted prefs; `@Observable` + `@AppStorage`. **The hook every new toggle hangs off of.**

**UI — Theme**
- `UI/Theme.swift` (128) — `SFTheme` design tokens (spacing, grid pitches, glass sizes, type, colour roles). Ships both the 2 pt `cellPt` lattice and the 6 pt `gifCellPt` family — see §7.

**UI — Components** (11 — where new shared widgets land)
- `UI/Components/GlobalPaletteEditorView.swift` (161) — interactive palette editor (median-cut nudge).
- `UI/Components/PixelGrid.swift` (150) — 8-bit indexed render surface (no AA / interpolation).
- `UI/Components/PaletteTreeView.swift` (148) — median-cut treemap + scope/branching selectors.
- `UI/Components/PaletteGridView.swift` (142) — 16×16 coordinate grid + axis selectors.
- `UI/Components/CellSprite.swift` (137) — cell-based widget primitives (shutter, gear, diversity ring).
- `UI/Components/StatsFooterView.swift` (123) — bottom stats pill; **a Zig-metric surface** (MSE/κ/χ²).
- `UI/Components/GlassControls.swift` (96) — **Liquid Glass primitives**: GlassIconButton, GlassToolbarCluster, GlassInfoChip (+ shared GlassEffectContainer).
- `UI/Components/CellField.swift` (81) — 201×437 @2 pt background lattice (4×4 Bayer dither).
- `UI/Components/CellText.swift` (76) — cell-lattice text rasterizer.
- `UI/Components/CameraPreview.swift` (49) — AVCaptureVideoPreviewLayer wrapper + tap focus.
- `UI/Components/Haptics.swift` (31) — centralized haptic feedback.

**UI — Screens** (where new screens/flows land)
- `UI/Screens/Capture/CaptureViewModel.swift` (624 — **2nd largest**) — capture orchestration: state (`phase`), session, pipeline, engines, store, render (GPU + deterministic), preview-image conversion, quality diagnostics.
- `UI/Screens/Capture/CaptureView.swift` (263) — root capture screen: camera preview + HUD + live stats; state-driven routing; presents Settings (`.sheet`) and Review (`.fullScreenCover`).
- `UI/Screens/Review/GIFReviewView.swift` (251) — post-capture review: looping GIF + palette explorer (treemap/grid/editor) + per-frame stats + the Zig reproducibility proof.
- `UI/Screens/Settings/SettingsView.swift` (145) — config form (sampler/dither, engine, visualization, capture conveniences); `@Bindable` over AppSettings.
- `UI/Screens/State/StateScreens.swift` (97) — BootstrapSkeleton / UnauthorizedView / FailureView fallbacks.

**Resources**
- `Resources/stbn3d-8.bin` — precomputed 8×8×8 scalar blue-noise mask (golden from the spec).
- `Info.plist` — explicit (not synthesized).

---

## §5. Navigation & state model

Single-window, **state-driven routing** — no `NavigationStack`, no `TabView`.
The root `CaptureView` is alive for the whole session; `CaptureViewModel.phase`
selects the scene; **Settings** is a `.sheet`, **Review** is a
`.fullScreenCover`. State is pure Observation: an `@Observable`
`CaptureViewModel` owns an `@Observable` `AppSettings`, injected top-down (no
`EnvironmentObject`), with `@State` for view-local transients (animation,
toggles, selections). No Redux/Flux — direct mutation via the Observation
framework.

---

## §6. Where new UI/UX complexity lands

Descriptive — points each incoming work type at its existing home so additions
follow the current convention. (No refactors implied.)

| Incoming work | Lands in | Pairs with |
|---|---|---|
| New screen / flow | `UI/Screens/<Name>/` | a view + (if stateful) its own `@Observable` model |
| Richer palette tools | `UI/Components/` (widget) + `Palette/` (math) | surfaced from `GIFReviewView`; read `DeterministicRenderer.Result` |
| More capture / settings controls | capture HUD or `UI/Screens/Settings/`; new prefs in `Settings/AppSettings.swift` | tokens from `UI/Theme.swift` |
| Glass / visual polish | `UI/Components/GlassControls.swift` + `UI/Theme.swift` | — |
| Surfacing more Zig telemetry | `StatsFooterView` / Review status line / a new chip | fields already on `CaptureOutput` |

---

## §7. Notes & observations

- **The Zig core is the visible spine.** The capture-banner strings *are* the
  kernel order, and the Review badge proves the Zig output via SHA-256. Treat the
  deterministic pipeline as front-of-house, not a backend detail.
- **Per-stage kernels are the live path; the monolithic `s4_gif_encode_burst` is
  a stub** (`S4_RC_NOT_IMPLEMENTED`), as are `s4_widen_half_to_q16` /
  `s4_linear_to_oklab_q16`. `DeterministicRenderer` drives the per-stage kernels
  (`quantize → dither → significance → palette → assemble`). *Verify on device:*
  a populated SHA-256 badge in Review confirms the per-stage path is live.
- **κ and χ² are GPU-path-only diagnostics.** On the default deterministic path
  they render as `κ ∞` / `χ² 0%` in `StatsFooterView` — a real UX wart: a
  newcomer will think they're broken. Noted, not fixed (out of scope).
- **Two design pitches coexist in `SFTheme`** — the 2 pt `cellPt` chrome lattice
  and the 6 pt `gifCellPt` content family. `docs/SIXFOUR-DESIGN-LANGUAGE.md`
  calls the single-pitch law "DESIGN-true, CODE-false." Relevant when adding
  chrome; enforcement is a separate effort.
- **Two large files are where complexity will concentrate.**
  `CaptureViewModel.swift` (624) mixes state + render orchestration + image
  conversion; `CaptureView.swift` (263) mixes routing + layout + gestures. Worth
  a future, separately-planned split — not done here.
- **`Generated/` is contract output** — never hand-edit. Change
  `spec/src/SixFour/Codegen/` and regenerate (`cabal run spec-codegen`); a
  pre-build gate enforces parity.
- **`GeneLibrary/BundledOrgans/` is intentionally empty** (reserved for future
  bundled organs), not dead code.

---

## Appendix — quick recount

```sh
find SixFour -name '*.swift' | wc -l                       # 59
find SixFour -name '*.swift' -print0 | xargs -0 wc -l | tail -1   # 9117 total
find SixFour -type d | wc -l                               # 22
grep -hoE 's4_[a-z_0-9]+' Native/include/sixfour_native.h | sort -u  # exported kernels
```
