> **Status / last refreshed 2026-06-16, post RGBT-4D pivot.** This is the LIVE orientation map. For built/designed/missing status defer to `docs/STATUS.md` (note: STATUS.md is itself pre-pivot and stale — see §8); for the narrative, `SIXFOUR-VISION.md`; for the layered proof-spine, `SIXFOUR-ARCHITECTURE-MAP.md`.

# SixFour — App Directory & File Map

> **Purpose.** A single orientation map of the *shipped iOS app* — its directory
> layout, the files that compose it, and how the deterministic **Zig core
> surfaces all the way up into the one-surface UI/UX**. Read this before adding
> UI/UX complexity so new work lands in the right place by default.
>
> **Scope.** Map only. This document describes the structure as it is; it does
> *not* propose refactors, token consolidation, or design-law enforcement.
>
> **Verified.** Live against the tree on 2026-06-16: the shippable target
> `SixFour/` = **137 Swift files (~19,578 lines) + 4 Metal/`.metal.h` shaders +
> resources**, across 21 directories. (The archived "59 Swift / 9,117 lines /
> 22 dirs" census was 2026-06-01 and is months out of date — see §8.)

---

## §1. Repo boundary — what ships vs. what is tooling

SixFour is a polyglot monorepo. **Only `SixFour/` compiles into the app** (Tier 2,
zero third-party dependencies per `CLAUDE.md`). Everything else is upstream
source-of-truth or Mac-side tooling. The one twist: the **Zig core (`Native/`)
is not "tooling"** — it builds to `libsixfour_native.a`, which the app links and
runs.

| Top-level | Role | Ships in app? |
|---|---|---|
| `SixFour/` | iOS app — Swift + Metal (Xcode target `SixFour`) | **YES** |
| `Native/` | **Zig** deterministic Q16 fixed-point core (`src/`, `include/`, `lib/`, `build.zig`) → `libsixfour_native.a` | **YES — linked static lib** |
| `SixFourTests/` | app unit tests (incl. `RGBT4DGoldenTests`) | test target |
| `spec/` | Haskell algebraic spec — ~100 `SixFour.Spec.*` modules; formally-verified source of truth; emits `SixFour/Generated/`, `trainer/generated/`, `studio/.../generated/` | no |
| `trainer/` | Mac-side MLX training / export / gates (Python) | no |
| `studio/` | Rust `analysis-core` + `look-nn-baseline` (1+1-ES floor) + `explore` | no |
| `docs/` | design docs — **this map lives here** | no |
| `scripts/`, `project.yml`, `SixFour.xcodeproj/` | build/deploy helpers + XcodeGen source + generated project (never hand-edit) | — |
| `CLAUDE.md`, `README.md`, `NOTES.md`, `SETUP.md` | project docs | no |

**Build facts:** iOS deployment target **26.0**, Swift **6.2**, strict
concurrency **complete**, zero third-party deps. A pre-build *spec-codegen drift
gate* regenerates the contract/golden files and fails the build if they diverge
from committed. The full cross-language gate is `spec/scripts/s4.sh` (cabal test
+ `zig build test` + Swift build).

---

## §2. App target directory tree (`SixFour/`)

```
SixFour/
├── App/         @main entry point (SixFourApp.swift)
├── Atlas/       on-device value head + curation (AtlasState/Trainer/Board/Move)
├── Capture/     AVFoundation 20fps 64-frame burst capture
├── Color/       OKLab color science
├── Editing/     capture bundle + cluster-statistic ops
├── Encoder/     tile → GIF (deterministic Zig path + LZW encoder + ladder export)
├── GeneLibrary/ on-disk organ catalog + AirDrop (.sixfour-genes)
├── Generated/   DO NOT EDIT — emitted from the Haskell spec (~35 contract/golden files)
├── Metal/       GPU compute pipelines + .metal shaders (capture pre-pass + cell field)
├── Native/      Zig C-ABI facade (Swift side: SixFourNative.swift)
├── Organs/      learned-model loaders (metric organ)
├── Palette/     quantize / collapse / dither / significance / structure / branched genome
├── RGBT4D/      ★ NEW: reversible 2-D cube-ladder lift (RGBT4DLift.swift) — DORMANT (§7)
├── Resources/   stbn3d-8.bin blue-noise mask
├── Settings/    AppSettings store
└── UI/
    ├── Theme.swift / ScreenLattice.swift / GlobalLattice.swift / CellAlgebra.swift
    ├── MovableColorWidget.swift
    ├── Components/   reusable cell views (cells, palette widgets, field, atlas, glass)
    ├── Surface/      ★ the one-surface FSM: Surface + SurfaceView + per-phase *PhaseField
    └── Screens/Capture/  CaptureViewModel (the camera engine)
```

---

## §3. ⭐ Zig → one-surface UI/UX trace (priority)

The deterministic Zig core is **the thing the user watches**, not a hidden
backend. It is the **only** reproducible render path; the GPU float paths
(`GIFRenderer`/Wu/KMeans/blue-noise) are demoted to non-reproducible fallback.
The SHA-256 of the Zig output is the "byte-reproducible" proof.

### Layer 1 — Zig source (`Native/src/`)

Exported through the C ABI in `Native/include/sixfour_native.h`. The header
**documents 24 `s4_*` symbols (21 shipped + 3 tooling) and is now STALE**: it
omits the four newest RGBT-4D kernels (`s4_rgbt_lift_quad`,
`s4_rgbt_unlift_quad`, `s4_cube_lift_level`, `s4_cube_unlift_level`), which are
exported in `kernels.zig` but have no C prototype yet. Kernel bodies live chiefly
in `kernels.zig`; `root.zig` holds `s4_probe` (smoke-test stub) + `s4_load_look_net`;
`synth.zig` is Mac-only training-data synthesis. Each `*_fixture_test.zig`
byte-checks a stage against a Haskell golden (e.g. `rgbt4d_fixture_test.zig`).

| Kernel | Role |
|---|---|
| `s4_set_log_callback` | install the Swift log sink (one line per kernel call) |
| `s4_quantize_frame` | maximin (Gonzalez) seed + optional Lloyd → k=256 Q16 OKLab centroids + indices |
| `s4_dither_frame` | FS / Atkinson / STBN3D / frozen-STBN → dithered indices |
| `s4_significance_fill` | split-fill so every slot ≥ minPopulation; emit per-cell stats |
| `s4_global_collapse` | pooled-maximin **FarthestPointCollapse** (GIFA→GIFB; the P palette-scope operator) |
| `s4_palette_oklab_to_srgb8` | fixed-point gamma map → k×3 sRGB8 (the GIF colour table) |
| `s4_gif_assemble` | per-frame indices + palettes → LZW / GIF89a bytes |
| `s4_haar_*` (pair-tree) | reversible 1-D integer Haar lift (distinct from the RGBT lift) |
| `s4_zone_profile_q16` / `s4_look_transfer_q16` / `s4_build_cube_q16` | zone/look/`.cube` LUT path |
| `s4_rgbt_lift_quad` / `s4_rgbt_unlift_quad` / `s4_cube_lift_level` / `s4_cube_unlift_level` | ★ NEW reversible 2×2↔1 RGBT cube-ladder lift — **no Swift facade yet (§7)** |
| `s4_load_look_net` | parse an MLX-trained look-NN blob (aliasing, no copy) — **deploy path, no render consumer** |
| `s4_probe` | FFI smoke-test stub |
| `s4_synth_burst` | **Mac-only** deterministic training-burst generator |
| `s4_gif_encode_burst` (+ helpers) | monolithic whole-burst path — returns `S4_RC_NOT_IMPLEMENTED` (shipped path uses per-stage kernels) |

Compiled to `Native/lib/{iphoneos,iphonesimulator}/libsixfour_native.a`.

### Layer 2 — Swift facade (`SixFour/Native/SixFourNative.swift`)

The entire Swift→Zig C-ABI surface: one enum wrapping every `s4_*` kernel,
marshalling arrays via `withUnsafeBufferPointer` + a caller scratch arena, and
checking `rc == S4_RC_OK`. **Swift owns all memory, Zig only fills buffers.**
Wrappers: `oklabToQ16`, `quantizeFrame`, `ditherFrame`, `significanceFill`,
`globalCollapse`, `paletteToSRGB8`, `gifAssemble`, the zone/look/cube LUT calls,
plus `loadLookNet`. The four RGBT-4D kernels are **not yet surfaced here** (§7).
C decls import via `Native/SixFour-Bridging-Header.h`.

### Layer 3 — Consumer (`SixFour/Encoder/DeterministicRenderer.swift`)

Drives the deterministic pipeline one stage at a time. Two entry points:
- `render(...)` = **per-frame GIFA**: per frame `quantizeFrame` →
  `ditherFrame` → `significanceFill` → `paletteToSRGB8` → `gifAssemble`.
- `renderGlobalPalette(...)` = **GIFB**: same per-frame quantize, then
  `globalCollapse` (≡ `Spec.Collapse.globalCollapseQ16` ≡ `FarthestPointCollapse`
  over pooled 64·256 centroids) → optional Atlas curation → `BranchedPalette`
  projection → whole-GIF significance fill → one GCT.

Branch selected in `CaptureViewModel` on `AppSettings.paletteScope` (`.perFrame`
vs `.global`). **GIFB is wired in production** — the long-standing "collapse has
zero callers" claim is FALSE. `sha256Hex` of the GIF bytes is the reproducibility
fingerprint.

### Layer 4 — UI/UX surfaces (the one-surface FSM)

`SixFourApp` mounts exactly ONE view: `SurfaceView`. `Surface` (σ) is a single
10-phase FSM whose `surfaceStep δ` mirrors `Generated/DisplayContract.swift`;
`PhaseField` (Π) routes each phase to a `*PhaseField` cell renderer; one
`SurfaceClock` (κ) ticks at 20fps. The UI atom is the **GIF pixel = 4pt (`gifPx`)
on a 100×218 lattice**; chrome emits CELLS only — no `Text`/glass/SF-Symbol.

| Phase | PhaseField | Zig link |
|---|---|---|
| `.live` | `LivePhaseField` | hero + 16×16 palette-as-shutter; live quantize preview |
| `.locking` / `.capturing` | `CapturingPhaseField` | burst capture (no recorded-frame drops) |
| `.rendering` | `RenderingPhaseField` | drives `DeterministicRenderer` stages |
| `.browsing` | `BrowsingPhaseField` | Act III scrub + pick-four anchors |
| `.review` | `ReviewPhaseField` | flat 2D `gifCell` heroes + `LadderExport` + LOOK/`.cube` |
| `.settings` | `SettingsPhaseField` | sampler/dither/engine prefs over `AppSettings` |
| bootstrap/error | `BootstrapErrorPhaseField` | auth/failure fallbacks |

Every tick, σ(tile+palette) feeds `FieldMetalView` → `field.metal`, which colours
each 4pt cell on the GPU ground.

**Takeaway.** Adding UI/UX complexity here is largely about *surfacing more of
this pipeline*. New widgets should read fields already on `CaptureOutput` /
`DeterministicRenderer.Result` rather than recomputing.

---

## §4. File-by-file map (load-bearing files)

**App** — `App/SixFourApp.swift` `@main`; mounts the single `SurfaceView`.

**UI / Surface** (the one-surface FSM — where flow logic lands)
- `UI/Surface/Surface.swift` — σ: the 10-phase FSM (`surfaceStep`, cursor, picks, `indexCube`, `bakeCube`, `gifCell(x,y,t)`).
- `UI/Surface/SurfaceView.swift` — the only mounted view; holds `pendingOutput`.
- `UI/Surface/SurfaceClock.swift` — κ, single 20fps clock.
- `UI/Surface/PhaseField.swift` + the eight `*PhaseField.swift` — Π phase → cell renderer.
- `UI/Surface/SurfaceColor.swift` — surface colour algebra.

**Capture** (the camera ENGINE, not a router)
- `UI/Screens/Capture/CaptureViewModel.swift` — `bootstrap()` builds `MetalPipeline(64)` + `CaptureSession(20fps,64)` + `GeneStore`; runs `renderDeterministic[Global]`; emits `CaptureOutput`.
- `Capture/CaptureSession.swift` — `AVCaptureVideoDataOutput` 20fps×64-frame burst (x420 10-bit HDR) orchestrator.

**Metal**
- `Metal/Shaders.metal` — capture pixel pipeline (crop/downsample/linearize → OKLab → unsharp) + GPU k-means.
- `Metal/field.metal` — per-tick cell-field GPU ground.
- `Metal/Pipeline.swift` — `MetalPipeline` → `OKLabTile`; `Metal/{KMeans,BlueNoise}PalettePipeline.swift`, `GPUContext.swift`, `TextureCache.swift` (demoted float path).

**Encoder**
- `Encoder/DeterministicRenderer.swift` — the Zig deterministic path (§3 Layer 3).
- `Encoder/GIFEncoder.swift` — hand-written LZW GIF89a (LCT per-frame / one GCT for GIFB).
- `Encoder/LadderExport.swift` / `LadderGIF.swift` — 16³ working / 64³-B rung export.
- `Encoder/LUTFile.swift` — `.cube` writer; `GIFRenderer.swift` — demoted GPU float path; `ContactSheet.swift`.

**Palette**
- `Palette/PaletteCollapse.swift` — the `PaletteCollapse` protocol (the NN-injection seam) backed by `FarthestPointCollapse` (pooled-maximin Q16). The designed trained `LookNetCollapse` does NOT exist on device (§7).
- `Palette/BranchedPalette.swift` — radix genome projection (`.b16`=Flat768 / `.b4`=Quad4-513 / `.b2`=σ-pair-384).
- `Palette/GroupRGBT.swift` — masks which of 16 RGBT groups feed the collapse; `circularWindows` is the stride-1 width-4 rotation-equivariant SELECT lever (it SELECTS, never POOLS — see gap G1).
- `Palette/PaletteHaarTree.swift`, `QuartetDelta.swift`, `SignificantSplitFill.swift`, `WuQuantizer.swift`, `NearestCentroid.swift`, `KMeansLab.swift`, `SplitTree.swift`, `GridLayout.swift`, `Dither.swift`, `PaletteValue.swift`, `LookVariant.swift`, `BrushSet.swift`.

**RGBT4D** (★ NEW, dormant)
- `RGBT4D/RGBT4DLift.swift` — zero-dep Swift port of `Spec.RGBTLift` (the reversible 2×2↔1 integer Haar lift; `floorDiv` hazard fixed). **ZERO production callers** (only `RGBT4DGoldenTests` + `AppSettings` reference it).

**Atlas** (on-device value head — infrastructure ahead of a shipped organ)
- `Atlas/AtlasTrainer.swift` — MPSGraph Bradley-Terry value training (proven on device); does NOT yet feed palette generation.
- `Atlas/AtlasState.swift` / `AtlasCollapse.swift` / `AtlasBoard.swift` / `AtlasMove.swift` / `AtlasTrainingSession.swift` / `DecisionLog.swift` — curation seam (Swift stubs; `Spec.AtlasState/Board/Move` planned-not-built).

**Generated — DO NOT HAND-EDIT** (emitted by `cabal run spec-codegen`; ~35 files)
- Integer-exact goldens gated `==` (no tolerance): `CollapseGolden`, `RGBT4DGolden` (★), `GenomeFixedGolden`, `PairTreeGolden`, `GridAxisGolden`, `QuartetDeltaGolden`, `CloudProjectionGolden`, `FrontProjectionGolden`, `VoxelFitContract`.
- Contracts: `StageContract`, `NetContract`, `DisplayContract`, `MoveContract`, `CellMechanicsContract`, `LatticeContract`, `BoundaryContract`, `OwnershipContract`, `ExportContract`, `GlobalVolumeContract`, `PlaybackClockContract`, `SignificanceContract`, `STBN3DContract`, plus `FieldTuning.metal.h`.

**Settings** — `Settings/AppSettings.swift`: persisted prefs (`@Observable`); the hook every toggle hangs off. Holds `paletteScope` and the dormant `rgbt4dEnabled` (key `sixfour.rgbt4d.v1`, default OFF, read nowhere but its own `didSet`).

**UI — Theme / lattice** — `UI/Theme.swift`, `ScreenLattice.swift`, `GlobalLattice.swift`, `CellAlgebra.swift`, `MovableColorWidget.swift` (the closed movable-widget alphabet; `ColorIdentity.diversityRing` is in the alphabet but never rendered).

**UI — Components** (where new shared cell-widgets land)
- Cell primitives: `CellSprite`, `CellText`, `CellChrome`, `CellControls`, `CellDetent`, `CellEase`, `CellGlyph`, `CellShapes`, `CellOwnershipOverlay`.
- Field/render: `FieldMetalView` (drives `field.metal`), `StageField`, `InfluenceField`, `GridlineField`, `GridScript`, `PixelGrid`, `HaarShutterView`.
- Palette/atlas views: `PaletteCloudView`, `PaletteGridView`, `PaletteTreeView`, `AtlasBoardView`, `AtlasGalleryView`, `AtlasTrainingField`, `ContestedCellGridView`.
- Misc: `CameraPreview`, `Haptics`, `GlassControls` (Liquid Glass primitives, retired on HUD), `PlaybackClock`, `Boundary`, `DemoScene`.

**Organs** — `Organs/{Composition,MetricOrgan,Organ}.swift` (only `.metric` ships; `PaletteGenerator.refinementMetric` is dormant/unreachable).

**GeneLibrary** — `GeneLibrary/GeneStore.swift` (on-disk `.sixfour-genes` catalog; `loadMetric` removed) + `AirDropHandler.swift`.

**Resources** — `Resources/stbn3d-8.bin` (8³ blue-noise mask, tiled to 64³; true 64³ FFT-void mask deferred), `Info.plist`.

---

## §5. Navigation & state model

Single-window, **one mounted view** — no `NavigationStack`, no `TabView`, no
sheets/covers. `SixFourApp` → `SurfaceView`; `Surface` (σ), a single 10-phase
FSM, IS the router. Review is reachable only via `.committed`. State is pure
Observation: an `@Observable` engine (`CaptureViewModel`) owns an `@Observable`
`AppSettings`, injected top-down. One `SurfaceClock` (κ) ticks the whole UI at
20fps. No Redux/Flux — direct mutation via Observation.

---

## §6. Where new UI/UX complexity lands

| Incoming work | Lands in | Pairs with |
|---|---|---|
| New flow / phase | a new `*PhaseField` in `UI/Surface/` + a σ phase in `Surface.swift` (mirror `Generated/DisplayContract`) | the FSM `surfaceStep δ` |
| Richer palette tools | `UI/Components/` (cell-widget) + `Palette/` (math) | read `DeterministicRenderer.Result` / `CaptureOutput` |
| More capture / settings controls | `SettingsPhaseField` + new prefs in `Settings/AppSettings.swift` | tokens from `UI/Theme.swift` / lattice files |
| New deterministic kernel | spec `Spec.*` → `Codegen.*` golden → Zig `kernels.zig` → `SixFourNative.swift` facade | the `s4.sh` gate |
| Surfacing more Zig telemetry | a `*PhaseField` cell line / `StatsFooterView`-style chip | fields already on `CaptureOutput` |
| Atlas / value-head curation | `Atlas/` + `UI/Components/Atlas*View.swift` | `AtlasTrainer` (MPSGraph) |

---

## §7. ★ RGBT-4D cube-ladder pivot (2026-06-16) — landed but DORMANT

The pivot reframes the product from one 64³ GIF into a **three-rung 16³/64³/256³
cube ladder** = two orthogonal operators: Axis A **resolution R** (×4 ladder) ⟂
Axis B **palette scope P** (per-frame↔global). Reversibility is a lossless
(2×2)↔1 integer Haar **RGBT lift**: a 2×2 block (a,b,c,d) → sub-bands
(R,G,B,T)=(LL,LH,HL,HH).

**Landed, fully tested:**
- Spec cluster: `Spec.RGBTLift`, `Spec.CubeLadder` (`lawLadderBijective`:
  Distill∘Synthesize=id within capture; loss isolated to NN super-res strictly
  above captured resolution), `Spec.RGBTFeature`, `Spec.GroupRGBT.circularWindows`,
  `Spec.Upscale256`, `Spec.Entropy` (Phase 0), `Spec.CanonicalPhase`.
- New emitter `Codegen.RGBT4D` → `Generated/RGBT4DGolden.swift`.
- Zig: `s4_rgbt_lift_quad`/`s4_rgbt_unlift_quad`/`s4_cube_lift_level`/`s4_cube_unlift_level`
  (`kernels.zig`, gated by `rgbt4d_fixture_test.zig` vs the RGBT-4D golden).
- Swift: `RGBT4D/RGBT4DLift.swift` (zero-dep, `floorDiv` hazard fixed).
- 834 Haskell spec tests on master.

**Dormant end-to-end (do not assume it runs):**
- `AppSettings.rgbt4dEnabled` defaults OFF; no Settings UI toggle.
- `RGBT4DLift.swift` has ZERO production callers.
- The four Zig `s4_rgbt_*`/`s4_cube_*` exports have **no `SixFourNative` facade
  method** and **no C prototype** in the stale header.
- The Phase-5b Metal `simd_shuffle` circular-stencil kernel does not exist.
- The three-GIF {16³,64³,256³} export action is absent (gap **G6**).
- **Shipped render bytes are byte-identical to the pre-pivot app while the flag
  is false — the app still emits ONE 64³ GIF.**
- Device-unverified: no simulator + arm64-only prebuilt lib link-fails against
  forced x86_64; `RGBT4DGoldenTests` must run on iPhone 17 Pro hardware.

---

## §8. Corrections since archival (read before trusting older docs)

The archived APP-MAP and several memory/NOTES claims are stale. Current truth:

- **GIFB is wired in production.** `CaptureViewModel.renderDeterministicGlobal`
  → `DeterministicRenderer.renderGlobalPalette` → `SixFourNative.globalCollapse`
  (`s4_global_collapse`), gated by `paletteScope==.global`. The "collapse has
  zero callers" claim is FALSE.
- **File census** is now ~137 Swift / ~19,578 lines / 21 dirs (was 59/9,117/22).
  New `SixFour/RGBT4D/`, `SixFour/Atlas/`, and `SixFour/UI/Surface/` did not
  exist at archival.
- **One-surface UI replaced the multi-screen router.** `CaptureView`/`GIFReviewView`/
  `SettingsView`/`StateScreens` + `.sheet`/`.fullScreenCover` are gone; `Surface`
  σ-FSM + `*PhaseField` cell renderers are the navigation. `VoxelCubeView` and the
  `voxel_raymarch` kernel were DELETED 2026-06-07 (heroes are flat 2D `gifCell`).
- **Native header is stale** at 24 symbols and omits the four RGBT-4D exports;
  the archived "14 `s4_*` symbols" is older still.
- **The product is three GIFs** (16³/64³/256³ ladder), with the 64³ GIF as the
  native middle rung — *but* the three-GIF export action does not yet exist
  (G6), so the shipped app still emits one GIF.
- **Decoder is 384-DOF** (σ-pair genome); 768 is the flat leaf space. The
  supervised MLX trainer (`trainer/train_look_net_mlx.py`) was ABANDONED in the
  2026-06-17 AlphaZero reframe and its trained outputs (`look_net_trained.s4ln`,
  `atlas_net_trained.npz`) were DELETED; only the regenerable GOLDEN loader
  fixture `out/look_net.s4ln` and the Zig loader CODE remain. The core is reframed
  AlphaZero-shaped (policy+value over the LAB-collapse state machine, Bradley-Terry
  A/B reward). (Drift: `studio/look-nn-baseline/lib.rs` still runs the OLD 768-flat
  genome via 1+1-ES despite `contract.rs` exposing `SIGMA_PAIR_DOF=384`.)
- **Maximin is canon** for the deterministic path (the "maximin ≠ Wu bug" note is
  DISPROVEN); Wu/KMeans/Octree live only on the demoted float fallback.
- **No barycenter on device.** Post-ADR-014, full discrete `buresBarycenter` is
  gone (only `buresBarycenterCov` Rust golden remains); the shipped collapse is
  the deterministic pooled-maximin `FarthestPointCollapse`.
- **`docs/STATUS.md` is itself pre-pivot/stale** — still says "595 tests pass",
  has no RGBT-4D/cube-ladder/three-GIF row, and predates 2026-06-16. Master is at
  834 Haskell spec tests. STATUS.md needs a refresh to regain canon.

---

## §9. Open gaps (orientation, not a status ledger)

- **RGBT-4D dormant** end-to-end (§7): no callers, no facade, no Metal stencil,
  no toggle, no three-GIF export (G6).
- **Cube-ladder is spec-ahead-of-code:** G1 temporal-distill 64→16 (`Spec.TemporalPool
  quartetPool`) designed-not-built (`GroupRGBT` only SELECTS); G3 `Spec.Upscale256`
  golden-proven but no Swift port (256 output is spatial replicate2D, time held at
  64); G2/G4 R and P not yet factored as composable operators (`renderGlobalPalette`
  is a ~150-line parallel path, no `render(tier,scope)=encode(R(P(cube)))`).
- **Trained `LookNetCollapse` not on device:** the `PaletteCollapse` seam is always
  `FarthestPointCollapse`; the trained blob is loaded by `s4_load_look_net` (aliasing
  parse) with no render-path consumer.
- **Trainer learns L only** (a=b=0); chroma deferred; canonical `Spec.Loss` unused
  by the running trainer.
- **Determinism knob open:** Lloyd-iteration count diverges per path (shipped
  capture/collapse `lloyd_iters=0` vs GPU/gif-fixtures 15); byte-exactness needs
  identical counts across Zig/Swift/Metal per path (NOTES Q4). STBN3D ships an 8³
  tile tiled to 64³.
- **Facade/contract debt:** stale header (§8); `s4_gif_encode_burst` →
  `S4_RC_NOT_IMPLEMENTED`; `probe()` is a stub; `s4_palette_oklab_to_srgb8` has a
  vestigial ignored scratch param.
- **Atlas seam is infra ahead of a shipped organ:** `AtlasTrainer` is proven on
  device but does not feed palette generation (`candidateB` is a deterministic
  placeholder, no MCTS); Atlas Swift files have no generated contract; `GeneStore`
  is unpopulated (`loadMetric` removed); `train_metric.py` needs an absent
  `data/reference_gifs/`.
- **Browse picks are cosmetic:** `surface.picks` (4 Act-III anchors) do NOT shape
  GIF bytes (deterministic render runs autonomously from `.shutterTap`); they feed
  only the Review `QuartetDelta` motion outline.

---

## Appendix — quick recount

```sh
find SixFour -name '*.swift' | wc -l                              # 137
find SixFour -name '*.swift' -print0 | xargs -0 wc -l | tail -1   # ~19578 total
find SixFour -type d | wc -l                                      # 21
grep -hoE 's4_[a-z_0-9]+' Native/include/sixfour_native.h | sort -u  # exported kernels (STALE: omits s4_rgbt_*/s4_cube_*)
grep -hoE 's4_[a-z_0-9]+' Native/src/kernels.zig | sort -u           # true export set
bash spec/scripts/s4.sh                                           # cross-language gate
```
