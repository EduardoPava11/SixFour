# SixFour APP-MAP

> **Status / last refreshed 2026-06-19.** This is the LIVE orientation map of the shipped iOS
> app: what each directory/file is, how the deterministic Zig core reaches the screen, and what
> is dormant vs live. It is a **map, not a status ledger** — for built/designed/missing status,
> defer to `docs/STATUS.md` (and note STATUS itself lags: it reads 877 Haskell tests; the
> post-per-frame-merge count is 911 — see §10). For the narrative, see `docs/SIXFOUR-VISION.md`;
> for the layered proof-spine, `docs/SIXFOUR-ARCHITECTURE-MAP.md`.

<!-- SECTION 2: WHAT SIXFOUR IS -->
## 2. What SixFour is

SixFour is an iOS 26 camera app: a 64-frame, 20fps camera burst becomes a deterministic
64×64 animated GIF, produced bit-exactly across devices by an owned, dependency-free **Q16
fixed-point Zig core** (quantize → dither → significance → palette → GIF89a/LZW encode). The
entire UI is **one mounted SwiftUI view** (`SurfaceView`) whose body is the projection of a
single 8-state observable FSM driven by a 20fps clock — every "screen" (live, A/B game, export,
error) is a phase of one persistent cell-field surface, not a view swap. The defining principle
is **Haskell-verified, zero-third-party-dependency, hand-written**: the math is proven once in
the Tier-0 Haskell spec, then the hand-written Swift/Metal/Zig ports are gated bit-for-bit
against the spec's golden vectors.

<!-- SECTION 3: REPO BOUNDARY -->
## 3. Repo boundary

The repo has four code tiers. **Only `SixFour/` (the app target) ships in the iOS binary**, and
it ships with ZERO third-party dependencies (Apple system frameworks + `simd` only). The owned
Zig core builds an arm64 static lib that links into the app; everything else is Mac-side tooling.

| Top-level dir | Role | Ships in app? |
|---|---|---|
| `SixFour/` | The iOS app target — SwiftUI one-surface UI, capture engine, encoders, palette math, Atlas value-head, Generated contracts, and the `Native/` Swift facade. | **YES** (the whole shipped binary; Tier-2 zero-dep) |
| `Native/` | Owned dependency-free **Zig** Q16 fixed-point core (`src/kernels.zig` + `root.zig` + `synth.zig`) + C-ABI header + iOS/host build scripts. | **YES** as `libsixfour_native.a` (arm64-only static lib, linked via `-lsixfour_native`); the host `.dylib` it also builds is Mac-only |
| `spec/` | Tier-0 **Haskell** source-of-truth: ~150 `Spec.*` modules + QuickCheck laws + `Codegen.*` emitters. GHC-boot-only deps. | **NO** — its *influence* ships (emits `Generated/*`); the library/exes do not |
| `trainer/` | Tier-1 Mac-side **Python/MLX** ML tooling (trainers, synthetic-GIF data engine, golden checks, weights→blob serializer). | **NO** — Mac-only dev tooling (MLX/torch/coremltools) |
| `studio/` | Mac-side **Rust** research/analysis workspace (collapse-floor baselines, GMM/Bures math, the 1+1-ES "baseline-to-beat"). Third-party deps (`gif`, `rerun`, `burn`). | **NO** — standalone Cargo workspace, not wired into any project gate |

<!-- SECTION 4: APP TARGET DIRECTORY TREE -->
## 4. App target directory tree (`SixFour/`)

Census (2026-06-19): **151 Swift files, ~19,680 Swift lines, 21 directories** under `SixFour/`.

```
SixFour/
├── App/                  @main entry. SixFourApp.swift mounts exactly ONE SurfaceView().
├── UI/
│   ├── Surface/          THE one-surface FSM: SurfaceView (the only mounted view), Surface (σ),
│   │                     ABSurfaceMachine (8-phase δ), SurfaceClock (κ 20fps), PhaseField (Π router),
│   │                     Live/ABCandidate/BootstrapError/Exporting/Done phase fields, SurfaceColor,
│   │                     GeneLogView, IsometryMove.
│   ├── Components/       Cell-widget alphabet (CellSprite/CellText/CellSymbol/CellChrome/CellGlyph/…),
│   │                     StageGround/FieldMetalView (Metal influence-field ground), + a large dead
│   │                     palette-explorer + Atlas-UI island (see §9).
│   ├── Screens/Capture/  CaptureViewModel — the MainActor capture+render orchestrator.
│   ├── Theme.swift, GlobalLattice.swift, ScreenLattice.swift, CellAlgebra.swift,
│   │   MovableColorWidget.swift  (design tokens, 4pt-atom lattice facade, placement algebra)
├── Capture/              CaptureSession (AVFoundation 10-bit HDR burst engine), FrameBuffer (dormant).
├── Metal/                Shaders.metal (capture 3-pass + GPU k-means), field.metal (influence ground),
│                         NearestCentroidShaders.metal (blue-noise), Pipeline/GPUContext/TextureCache,
│                         KMeans/BlueNoise/PaletteEngines (demoted float fallback).
├── Encoder/              DeterministicRenderer (live 5-stage GIFA driver), GIFEncoder (GIF89a/LZW),
│                         GIFRenderer (float fallback), ABExport (256² chosen-look), ContactSheet,
│                         LUTFile (65³ .cube), + dormant Ladder/ABExportFamily/NetSynth256.
├── Palette/             OKLab color math: PaletteGenerator (live per-frame finish), Wu/KMeans seeding,
│                         Dither, SignificantSplitFill, FarthestPointCollapse, BranchedPalette,
│                         GenomePair/ABCandidates (live A/B), GenomeCarrier, GroupRGBT, PaletteValue.
├── RGBT4D/               Reversible Q16 Haar cube-ladder: RGBT4DLift, VoxelReduce (both dormant).
├── Color/               ColorScience (OKLab transforms — consumed app-wide).
├── Editing/             CaptureBundle (live per-capture archive), ClusterStatisticsOps (mostly dormant).
├── Atlas/               On-device Bradley-Terry value head + curation session: AtlasTrainer (MPSGraph),
│                         AtlasState (unmounted), PersonalTaste (LIVE θ), DecisionLog, GLRM, AtlasBoard,
│                         AtlasCollapse, ThetaToDelta (owned-but-unwired).
├── Organs/, GeneLibrary/ "Shareable learned look" catalog (Organ/MetricOrgan/Composition/GeneStore/
│                         AirDropHandler) — compiles, functionally dormant.
├── Settings/            AppSettings (live @Observable prefs), Feature (compile gates:
│                         globalPaletteV2=false, abCandidatePicker=true).
├── Native/              SixFourNative.swift — the Swift facade over the Zig C-ABI.
├── Generated/           DO-NOT-EDIT codegen output: Swift contracts + integer-exact golden vectors.
└── Resources/           gamma_lut.bin, stbn3d-8.bin, and other spec-emitted binaries.
```

<!-- SECTION 5: ZIG -> ONE-SURFACE UI/UX RENDER TRACE -->
## 5. Priority trace: Zig core -> one-surface UI/UX render

**The deterministic Zig core IS what the user watches.** The live preview calls the integer
kernels every preview frame, and BOTH cell renderers (the SwiftUI `CellSprite` hero and the
`field.metal` GPU ground) paint that exact quantized tile. The committed GIFA's index cube — from
the 5 verified kernels — is what the A/B review heroes replay. There is **no break** in the chain.

### Layer 1 — Zig source kernels (`Native/src/kernels.zig`, owned, Q16, golden-gated)

The C header `Native/include/sixfour_native.h` is **current**: it prototypes all 31
self-described exports (28 shipped + 3 tooling), including the four RGBT-4D kernels (lines
170–178). The Swift facade `SixFour/Native/SixFourNative.swift` wraps 22 distinct kernels;
caller owns all memory.

| Zig kernel | What it does | On live render path? |
|---|---|---|
| `s4_quantize_frame` (:332) | maximin/farthest-first seed + optional Lloyd + nearest-centroid (K=256/frame). The coverage objective. | **YES** (preview + GIFA) |
| `s4_dither_frame` (:1053) | Floyd-Steinberg/Atkinson error diffusion + blue-noise via STBN3D. | **YES** |
| `s4_significance_fill` | split-fill so every slot ≥ minPopulation px. | **YES** (GIFA stage) |
| `s4_palette_oklab_to_srgb8` (:1343) | OKLab Q16 → sRGB8 via inverse matrices + embedded 65537-byte gamma LUT. | **YES** |
| `s4_gif_assemble` (:1519) | byte-faithful GIF89a + variable-code-size LZW encoder. | **YES** (GIFA encode stage) |
| `s4_gif_encode_burst` (:162) | **IMPLEMENTED** monolithic whole-burst path — composes the per-stage kernels, returns `s4_gif_assemble` at :229. Exported for host round-trip tests; **not called by the app** (the app drives the per-stage kernels). *(SixFourNative's doc-comment claiming `NOT_IMPLEMENTED` is STALE.)* | no (test-only) |
| `s4_linear_to_oklab_q16`, `s4_widen_half_to_q16`, `s4_srgb8_to_oklab_q16` | color edge kernels; reached transitively. | partial |
| `s4_global_collapse` | GIFA→GIFB pooled maximin collapse. **⚠️ V2-DEFERRED** behind `Feature.globalPaletteV2=false`. | no (statically unreachable) |
| `s4_haar_*`, `s4_rgbt_lift_quad/unlift_quad`, `s4_cube_lift_level/unlift_level` | reversible Haar + RGBT-4D cube-ladder. ~31 prototyped in the header; golden-tested, **no Swift caller**. | no (dormant) |
| `s4_board_mass_q16`, `s4_leaf_override` | Atlas Q16 board mass + σ-pair taste tint. | source-reachable (`board_mass`→Atlas; `leaf_override`→`Palette/ABCandidates.swift:44`) |
| `s4_zone_profile_q16` / `s4_look_transfer_q16` / `s4_build_cube_q16` | luminance-zone + 65³ `.cube` LUT builder. | YES (LUT export) |

### Layer 2 — Swift facade & render driver

- **`SixFour/Native/SixFourNative.swift`** — thin FFI: `quantizeFrame` (:217), `ditherFrame`
  (:238), `paletteToSRGB8` (:492), `gifAssemble` (:618), `globalCollapse` (V2-gated). `rc==S4_RC_OK`
  or `nil`.
- **`SixFour/Encoder/DeterministicRenderer.swift`** — the live 5-stage spine: `render()` (:90)
  runs quantize→dither→significance→palette→encode, each `onStage` label = the kernel running,
  `onPartial` streams true-colour buffers, computes the **SHA-256** reproducibility fingerprint.
  `renderGlobalPalette()` (:321) = GIFB, V2-deferred.

### Layer 3 — Consumer (capture engine)

- **`SixFour/UI/Screens/Capture/CaptureViewModel.swift`** — `makeQuantizedPreviewImage` (:905)
  drives the live preview directly through the Zig kernels every preview frame → `PreviewFrame`
  (64×64 indices + palette). `renderDeterministic` (:592) drives the committed GIFA →
  `CaptureOutput` (:10) carrying `gifURL`, `palettesForDisplay` (64×256),
  `frameIndicesForVoxels` (64×4096), `sha256Hex`. Emits a `Phase` the surface maps onto σ.

### Layer 4 — UI surfaces / phase fields (the screen)

Everything is `PhaseField.field(for: σ.phase)` (Π router) over the one `SurfaceView`. The two
live cell renderers both read `surface.previewTile` + `surface.previewPalette`:

| Phase | Phase field | What it renders from the Zig tile |
|---|---|---|
| `.live` | `LivePhaseField` | `previewHero` `CellSprite(64×64 @4pt)` (:118) reads `previewTile` indexed through `previewPalette` — one 4pt cell per GIF pixel (cube law). 16×16 `paletteShutter` (:144) IS the capture button. |
| (ground, all phases) | `StageGround` → `FieldMetalView` → `field.metal:90 fieldFragment` | one GPU draw per 20fps κ tick; floors each pixel to a 4pt cell and bleeds `previewTile` through `paletteColor()`. The SwiftUI hero draws opaque ON TOP of this GPU ground. |
| `.captured`/`.picked` | `ABCandidatePhaseField` | two 64×64 GIF heroes as `CellSprite`s at σ.cursor, via `Surface.gifCell` (:118) projecting σ.indexCube (Zig-produced) through per-frame palettes. Tap = A/B pick. |
| `.bootstrap`/`.unauthorized`/`.error` | `BootstrapErrorPhaseField` | κ-paced skeleton / Settings deep-link / Try-Again. |
| `.exporting`/`.done` | `ExportingPhaseField` / `DonePhaseField` | re-encode via `ABExport`; SHARE GIF / EXPORT LUT / GENES / NEW SHOT. |

<!-- SECTION 6: FILE-BY-FILE MAP -->
## 6. File-by-file map (load-bearing files)

### Surface / FSM (`App/`, `UI/Surface/`)
| File | Role |
|---|---|
| `App/SixFourApp.swift` | `@main`; WindowGroup mounts the single `SurfaceView()` (no router). |
| `UI/Surface/SurfaceView.swift` | THE single mounted view; owns σ/κ/engine; `body = StageGround + PhaseField`; `mapEnginePhase`/`commit` bridge engine→σ. |
| `UI/Surface/Surface.swift` | σ — `@Observable` state (palette, palettesPerFrame, indexCube, framePixelsQ16, cursor, chosenLookPalettes). `step(_:)` sole phase writer; `gifCell(x,y,t)` THE cube reader. |
| `UI/Surface/ABSurfaceMachine.swift` | The FSM: 8-phase `ABPhase`, 11-event `ABEvent`, `abStep` δ; golden-pinned vs `Generated/ABSurfaceContract.swift`. |
| `UI/Surface/PhaseField.swift` | Π router `field(for:)`; defines `ExportingPhaseField` + `DonePhaseField`. |
| `UI/Surface/SurfaceClock.swift` | κ — single 20Hz `CADisplayLink` via weak proxy; per tick flips heartbeat + `onTick`. |
| `UI/Surface/LivePhaseField.swift` | Π for `.live`: 64-cell preview hero + 16×16 palette-shutter + swipe LOOK cycler. |
| `UI/Surface/ABCandidatePhaseField.swift` | Π for `.captured`/`.picked`: the orthogonal A/B game; pick → Bradley-Terry θ fold + decision-log record. |
| `UI/Surface/BootstrapErrorPhaseField.swift` | Π for `.bootstrap`/`.unauthorized`/`.error`. |
| `UI/Surface/SurfaceColor.swift` | Float-free SIMD Q16 OKLab→sRGB8 ladder (mirror of the Zig kernel + `gamma_lut.bin`). |
| `UI/Surface/GeneLogView.swift` | Cells-only A/B decision-log readout (the "GeneInspector"; no file by that name exists). |
| `UI/Surface/IsometryMove.swift` | delta-preserving OKLab isometry move (spec `Spec.IsometryMove`/`MoveRadiusSchedule`). |

### UI components / design system (`UI/`, `UI/Components/`)
| File | Role |
|---|---|
| `UI/Theme.swift`, `GlobalLattice.swift`, `ScreenLattice.swift` | SFTheme tokens + 4pt-`gifPx` lattice facade over `Generated/LatticeContract.swift` + `View.place()` placement. |
| `UI/Components/CellSprite.swift` | THE no-AA cell-bitmap atom + HUD widgets (CellButton/CellShutter/CellIcon/CellRing). |
| `UI/Components/CellChrome.swift`, `CellText.swift`, `CellGlyph.swift`, `CellControls.swift` | CellSymbol/CellActionButton/CellSlider; CellText (pixel font, most-used); CellDigits; CellSelector/Toggle. |
| `UI/CellAlgebra.swift`, `MovableColorWidget.swift` | no-blend cell join-semilattice; `.movable` placement algebra. |
| `UI/Components/FieldMetalView.swift` | `StageGround` — the persistent Metal influence-field ground (GPU + CPU twins). |

### Capture engine (`Capture/`, `UI/Screens/Capture/`)
| File | Role |
|---|---|
| `UI/Screens/Capture/CaptureViewModel.swift` | MainActor `@Observable` orchestrator: `bootstrap()`, `capture()` (lock/burst/render), emits CaptureOutput. |
| `Capture/CaptureSession.swift` | AVFoundation camera engine: x420 10-bit HDR probe, 20fps clamp, AE/AWB lock, 64-frame burst. |
| `Capture/FrameBuffer.swift` | Bounded 64-cap accumulator — **DORMANT** (zero callers; session uses a plain array). |

### Metal / GPU (`Metal/`)
| File | Role |
|---|---|
| `Metal/Shaders.metal` | LIVE capture kernels (YCbCr10→linear→OKLab→unsharp) + fallback-only GPU k-means kernels. |
| `Metal/field.metal` | LIVE influence-field ground fragment shader (once/20fps κ tick). |
| `Metal/NearestCentroidShaders.metal` | `blueNoiseAssignKernel` (misnamed — no nearest-centroid kernel here); fallback-only. |
| `Metal/Pipeline.swift` | LIVE per-frame capture pipeline → `OKLabTile`. |
| `Metal/KMeansPalettePipeline.swift`, `BlueNoisePalettePipeline.swift`, `PaletteEngines.swift` | GPU float palette stack — DEMOTED to silent fallback (only if `useDeterministicCore` off or Zig throws). |
| `Metal/GPUContext.swift`, `TextureCache.swift`, `PalettePipeline.swift` | shared plumbing; `textureBGRA` dead; PalettePipeline doc claims Wu/Octree pipelines that don't exist. |

### Encoder (`Encoder/`)
| File | Role |
|---|---|
| `Encoder/DeterministicRenderer.swift` | LIVE 5-stage GIFA driver + SHA-256; `renderGlobalPalette` = GIFB (V2-deferred). |
| `Encoder/GIFEncoder.swift` | hand-written GIF89a + LZW; `encode` (per-frame LCT, live), `encodeGlobal` (GCT, dormant). |
| `Encoder/GIFRenderer.swift` | demoted float path (Wu+KM GPU → CPU refine); silent fallback only. |
| `Encoder/ABExport.swift` | `encodeChosenLook` — re-encodes base cube through chosen A/B look at 256² (Swift encoder). LIVE. |
| `Encoder/LUTFile.swift` | 65³ `.cube` LUT via `s4_build_cube_q16` + share bridge. LIVE. |
| `Encoder/ContactSheet.swift` | 8×8 raw-OKLab→sRGB PNG written alongside every GIF. LIVE. |
| `Encoder/ABExportFamily.swift`, `LadderExport.swift`, `LadderGIF.swift`, `NetSynth256.swift` | {16³,64³,256³} genome ladder + 256³ super-res scaffold — all DORMANT (no live callers). |

### Palette math (`Palette/`)
| File | Role |
|---|---|
| `Palette/PaletteGenerator.swift` | CANON per-frame finish: refine → dither → SignificantSplitFill. The only Palette file on the live render path. |
| `Palette/PaletteCollapse.swift` | `FarthestPointCollapse` (Q16 maximin coverage floor); GIFB slot (V2) but `nearestQ16` reused live by Atlas/Ladder. |
| `Palette/BranchedPalette.swift` | radix-genome projections (.b16/.b4/.b2 σ-pair); reached only from the deferred global path. |
| `Palette/Dither.swift`, `SignificantSplitFill.swift`, `NearestCentroid.swift`, `WuQuantizer.swift` | error-diffusion/blue-noise; population rescue; SIMD8 nearest; Wu = the k-means SEED (not a standalone extractor). |
| `Palette/ABCandidates.swift`, `GenomePair.swift` | LIVE A/B: `deltaPreservingPair` + `sampleOrthogonalPair` (EXACT-orthogonal `genomeInner==0`). Reachable (`abCandidatePicker=true`). |
| `Palette/GenomeCarrier.swift`, `GroupRGBT.swift`, `PaletteValue.swift`, `PaletteExtractor.swift` | S4GN GIF genome codec; 16 RGBT groups; value-head objective (mostly dormant); extractor protocol (only KMeansExtractor exists). |

### RGBT-4D substrate (`RGBT4D/`)
| File | Role |
|---|---|
| `RGBT4D/RGBT4DLift.swift` | reversible Q16 Haar lift (`liftQuad`/`distill`/`synthBeyond`). Consumed by VoxelReduce; no production caller of its own. |
| `RGBT4D/VoxelReduce.swift` | composes RGBT4DLift + temporal Haar into lossless 64³↔16³ reduce/expand. Consumes RGBT4DLift; **only its golden test calls it** (dormancy is here, one level up). |

### Color / editing (`Color/`, `Editing/`)
| File | Role |
|---|---|
| `Color/ColorScience.swift` | OKLab transforms + `okLabDistanceSquared`. Consumed by ~25 files app-wide. |
| `Editing/CaptureBundle.swift` | LIVE per-capture archive (raw OKLab tiles); built/saved/restored; tiles feed A/B re-quantization. |
| `Editing/ClusterStatisticsOps.swift` | eigendecomp/χ²-admission/PCA-split math — only ~4 of ~10 entry points reached; rest spec-ahead-of-code. |

### Atlas value-head (`Atlas/`)
| File | Role |
|---|---|
| `Atlas/PersonalTaste.swift` | **LIVE n=0 organ**: 770-D Bradley-Terry θ (`btUpdate`) + leaf tint, called by ABCandidatePhaseField. |
| `Atlas/DecisionLog.swift`, `AtlasMove.swift`, `AtlasBoard.swift` | LIVE A/B pick log (Codable); `AtlasDecisionRecord` (live); Q16 16³ board via `s4_board_mass_q16`. |
| `Atlas/AtlasTrainer.swift`, `AtlasTrainingSession.swift` | MPSGraph Bradley-Terry value head — verified, but only consumer is the unmounted training widget. |
| `Atlas/AtlasState.swift`, `AtlasCollapse.swift`, `GLRM.swift`, `ThetaToDelta.swift` | curation session (unmounted); curated-leaf render seam (doubly-gated dead); OLS kill-switch (never fires in-app); θ→δ map (owned-but-unwired). |

### Organs / genes / settings (`Organs/`, `GeneLibrary/`, `Settings/`)
| File | Role |
|---|---|
| `Settings/AppSettings.swift` | **LIVE** `@Observable` UserDefaults prefs (~21 keys; ditherConfig/captureLook/useDeterministicCore read every capture). |
| `Settings/Feature.swift` | **The MVP1/V2 compile-gate**: `globalPaletteV2=false`, `abCandidatePicker=true`. |
| `Organs/Organ.swift`, `MetricOrgan.swift`, `Composition.swift` | metric-organ "learned look" — compiles, functionally dormant (no caller constructs MetricOrgan). |
| `GeneLibrary/GeneStore.swift`, `AirDropHandler.swift` | on-disk gene catalog (instantiated, never read) + `.sixfour-genes` import/export (zero callers). |

### Native facade & generated contracts (`Native/`, `Generated/`)
| File | Role |
|---|---|
| `Native/SixFourNative.swift` | the C-ABI facade (wraps 22 distinct `s4_*` kernels; caller owns all memory). |
| `../Native/include/sixfour_native.h` | the real C ABI contract (current; all ~31 exports prototyped incl. RGBT-4D). |
| `Generated/NetContract.swift`, `CellMechanicsContract.swift`, `FieldTuning.metal.h`, `*Golden.swift` | DO-NOT-EDIT codegen: NN/UI/Metal contracts + integer-exact golden vectors. |

<!-- SECTION 7: NAVIGATION & STATE MODEL -->
## 7. Navigation & state model

The app mounts **exactly one view** (`SurfaceView`) — no `NavigationStack`, no modals, no view
swaps. `SurfaceView` owns three `@State` objects:

- **σ = `Surface`** — the `@Observable` FSM state + out-of-band data (palette, palettesPerFrame,
  indexCube, framePixelsQ16, cursor, chosenLookPalettes). `step(_:)` is the sole phase writer.
- **κ = `SurfaceClock`** — one 20Hz `CADisplayLink` advancing a Z₆₄ playback cursor.
- **engine = `CaptureViewModel`** — the AVCaptureSession + burst + render driver.

The lifecycle is the **8-state `ABPhase`** machine (`ABSurfaceMachine.swift`), a Swift port of
`Spec.ABSurface`, gated bit-for-bit by `Generated/ABSurfaceContract.swift` via
`ABPhase.assertSpecParity()` on first appear.

**States (Σ):** `bootstrap` | `unauthorized` | `live` | `captured` | `picked` | `exporting` |
`done` | `error`. **δ = `abStep(phase, event)`** (pure, total, catch-all self-loop;
`.fault → .error` from anywhere; repeated `pickA`/`pickB` self-loop in `.picked` = the "infinite
game"). **Events (ABEvent, 11):** `sessionReady`, `authDenied`, `shutterTap`, `lockComplete`,
`burstComplete`, `pickA`, `pickB`, `exportFamily`, `exportDone`, `retake`, `fault`.

`PhaseField.field(for:)` (the Π router) maps each phase to its renderer — only **7 renderers**
exist (Bootstrap/Unauthorized/Live/ABCandidate/Exporting/Done/Error). Settings/Browsing/Rendering/
Capturing/Review phase fields were **DELETED** (refactor `5389493`); doc-comments that still call
them "left in place" are stale.

**Engine → σ bridge.** `CaptureViewModel` walks its own internal `Phase`
(`unauthorized/configuring/idle/locking/capturing/renderingStageA/renderingEncode/done/failed`),
but **lock + burst + the entire 5-stage render are INTERNAL to `.live`** — there are no
observable sub-phases. `mapEnginePhase` explicitly `break`s on `.locking`/`.capturing`/render;
only the terminal `.done` matters: it calls `commit(out)` (folds `palettesPerFrame`, `gifURL`,
the flat 64³ `indexCube`, `framePixelsQ16`) then `surface.step(.burstComplete)` → `.captured`.

**Known FSM gaps:** `abStep` has **no recovery edge out of `.error`** — the Try-Again button
dispatches `.sessionReady` which self-loops in `.error` (a wired-ahead button with no transition).
There is **no "browse / pick-four" phase** — the `sixfour-acts` "browse & pick-four" notion was
collapsed to capture → A/B taste game → export.

<!-- SECTION 8: CROSS-CUTTING FLOWS -->
## 8. Cross-cutting flows

### 8a. Capture → GIF → A/B pick → export (the user flow)

1. **Mount.** `SixFourApp` mounts only `SurfaceView()`, owning σ/κ/engine.
2. **Bootstrap → live.** `engine.bootstrap()` requests camera auth, builds MetalPipeline +
   CaptureSession + GeneStore + PaletteEngines, wires the live preview; `.idle → .sessionReady`
   drives `bootstrap → live`.
3. **Live preview.** Camera feeds `engine.previewIndexTile`/`previewPalette` (Zig-quantized every
   preview frame). SurfaceView folds them into σ only while `.live`, applying
   `captureLook.apply(...)` (swipe-to-cycle LOOK regrades the palette; the index tile is untouched
   so the 16×16 shutter recolours in place). `StageGround` GPU ground renders once per app lifetime.
4. **Shutter.** Tap → `onShutter` → `engine.capture()`. σ stays `.live` through lock + burst +
   render (internal, not visible sub-phases).
5. **Lock + burst.** AE/AWB lock (400ms timeout), then 64 frames streamed off-queue via a
   `CoalescingFrameRenderer` (camera delegate queue does only O(1) submit + progress, so
   back-pressure cannot drop recorded frames).
6. **Render (GIFA, MVP1 default).** `renderOnce` picks the deterministic Zig core when
   `useDeterministicCore == true` (default). `DeterministicRenderer.render` runs the 5 verified
   kernels: quantize → dither → significance → palette → LZW/GIF89a encode. Output is 256²
   (each 64² index replicated 4×4); **SHA-256 of the GIF bytes is the reproducibility fingerprint**.
   Brand gates `CompleteVoxelVolume` + `SignificantVoxelVolume` must pass or it throws → GPU
   fallback (`GIFRenderer`).
7. **Commit → captured.** `.done` → `commit(out)` folds CaptureOutput into σ →
   `surface.step(.burstComplete)` → `.captured`.
8. **A/B pick.** `ABCandidatePhaseField` shows two competing looks A and B as real 64×64 looping
   GIFs read through σ.indexCube at the κ cursor. A/B are **delta-preserving isometry moves**
   (`ABCandidates.deltaPreservingPair`, `IsoMove.translate`) over the SAME index cube — recolours,
   not re-quantizations. Tapping a hero IS the pick.
9. **Taste fold.** Each pick folds Bradley-Terry θ (`PersonalTaste.btUpdate`, persisted), drifts a
   bounded `centerShift`, sets `surface.chosenLookPalettes`, and appends to a persisted
   `AtlasDecisionLog`. `pickA`/`pickB` self-loop in `.picked`.
10. **Export.** `EXPORT ▸` → `.exporting` → `ABExport.encodeChosenLook` re-encodes the base index
    cube through the chosen look's per-frame palettes at 256² (the **Swift** `GIFEncoder`,
    upscale 4 — so this GIF does **not** carry the Zig render's SHA-256). → `.done`.
11. **Done / share.** `DonePhaseField`: SHARE GIF / GENES (`GeneLogView`) / NEW SHOT (`.retake`) /
    EXPORT LUT (65³ `.cube` via `s4_build_cube_q16`, only when `captureLook != .off`).

### 8b. Verification spine: Spec → Codegen → golden → consumer → `s4.sh` gate

1. **Author once (Tier 0):** pure/fixed-point Haskell `Spec.*` modules encode every algorithm.
2. **Prove (`verify` = `cabal test`):** ~110 `Properties.*` QuickCheck/tasty modules assert
   Haskell-internal self-consistency. `cabal test` does **not** diff any `Generated/*` file.
3. **Emit contracts (`codegen` = `spec-codegen`):** renders 36 `Generated/*.swift` + 7
   `trainer/generated/*` + `contract.rs` + `stbn3d-8.bin`.
4. **Emit Zig fixtures (SEPARATE exe `spec-fixtures` — NOT run by any gate verb):** writes
   JSON+binary goldens into `trainer/out/` + LUT binaries into `Native/src/`.
5. **Port + verify, Zig (`native` = `zig build test`):** `kernels.zig` is the integer twin;
   `*_fixture_test.zig` read the spec-fixtures goldens and assert bit-exact — but **skip-if-absent**.
6. **Port + verify, Swift:** hand ports gated by `*GoldenTests.swift` (+ `ZigCollapseGoldenTests`
   pinning Haskell ≡ Swift ≡ Zig). These run only if a human runs the test scheme.
7. **Cross-check Python + Rust:** `trainer/check_golden.py` (MLX+torch vs golden, 1e-6); studio
   burn `contract.rs`.
8. **Fail on drift (`build` preBuildScript):** regenerates spec-codegen to a scratch dir and
   `diff -q` every `swift/*.swift` against `Generated/*` (+ 3 explicit non-Swift pairs).
9. **Orchestrate (`scripts/s4.sh all`):** codegen → doc → verify → native → lint → gen → build.
   CI runs only the checkout-safe subset (spec-codegen + cabal test + lint).

> **Gate gaps (orientation):** Zig fixtures come from `spec-fixtures`, which **no gate verb runs**,
> and the fixture tests are **skip-if-absent** (a missing golden PASSES) — so the cross-language Zig
> proof is opt-in. Swift golden tests are never run by the gate (`xcodebuild build`, not `test`).
> The non-Swift drift coverage is a hardcoded 3-entry list, so new trainer/Rust/Zig contracts can
> silently drift. (See §9/§11.)

<!-- SECTION 9: DORMANT / DEAD / SPEC-AHEAD-OF-CODE -->
## 9. Dormant / dead / spec-ahead-of-code

A large fraction of the codebase compiles + golden-gates but has no live caller. Grouped below
with `file:symbol`. "V2-deferred" = behind `Feature.globalPaletteV2=false` (statically unreachable
in MVP1, kept TAG-not-delete).

### Global / GIFB palette path (V2-deferred — the biggest dormant body)
- `Settings/Feature.swift:globalPaletteV2 = false` — the single gate. `CaptureViewModel.swift:607`
  coerces `paletteScope` to `.perFrame`, making `.global` statically unreachable.
- `Encoder/DeterministicRenderer.swift:renderGlobalPalette` (:321) and its only call site
  `CaptureViewModel.renderDeterministicGlobal` (:708).
- `Native/src/kernels.zig:s4_global_collapse` + `SixFourNative.globalCollapse`.
- `Palette/BranchedPalette.swift:projectQ16`, `FarthestPointCollapse.collapse` (as full producer),
  `collapseForDisplay`.
- `Encoder/GIFEncoder.swift:encodeGlobal` (GCT mode), `Encoder/LadderExport.swift` (entire — zero
  non-self callers), `Encoder/LadderGIF.swift` (entire).
- `Palette/GroupRGBT.swift` — wired only into `LadderExport` (itself V2-deferred).

### Float GPU palette fallback (demoted; not byte-reproducible vs Zig)
- `Metal/KMeansPalettePipeline.swift`, `BlueNoisePalettePipeline.swift`, `Shaders.metal` `kmeans*`
  kernels — run only if `useDeterministicCore` off OR the Zig core throws. The whole per-cluster
  Σ/covariance machinery (`kmeansFinalizeStatsKernel`, `farthestPointSeedCentroids`) is dormant in
  shipping config.
- `Encoder/GIFRenderer.swift` — silent fallback only; `benchmarkSeed = true` still runs an extra
  FPS extraction per capture (a dev aid left on).
- `Metal/TextureCache.swift:textureBGRA` — zero callers (capture is YCbCr10-only).

### Atlas value head + curation (infra-ahead-of-organ)
- `Atlas/AtlasTrainer.swift` (MPSGraph value head) — trains/evaluates correctly but its ONLY
  consumer is the unmounted `AtlasTrainingField`; **never feeds palette generation**.
- `UI/Components/AtlasTrainingField.swift`, `AtlasBoardView.swift`, `AtlasGalleryView.swift` —
  zero mount sites anywhere.
- `Atlas/AtlasState.swift` — zero instantiations; `choose()`/`perturb()` (the `±0.04` OKLab
  placeholder for an unbuilt MCTS gallery) unreachable. Only its static `fnv1a32`/`srgb8` reused.
- `Atlas/AtlasCollapse.swift` + `AtlasPaletteStore` — **doubly dead**: writer unmounted, reader
  gated `colorAtlasEnabled && globalPaletteV2` (both false).
- `Atlas/ThetaToDelta.swift` — self-tagged `⚠️ OWNED-BUT-UNWIRED`; `Atlas/GLRM.swift` kill-switch
  is wired only into the never-started training session.

### RGBT-4D substrate (spec-ahead-of-code, no live consumer)
- `RGBT4D/RGBT4DLift.swift` — zero production callers; consumed only by `VoxelReduce`.
- `RGBT4D/VoxelReduce.swift` — consumes RGBT4DLift but is itself called only by its golden test.
- `Settings/AppSettings.swift:rgbt4dEnabled` — **dead flag**: written in didSet/init, getter never
  read; no branch consults it.
- Zig `s4_rgbt_lift_quad`/`unlift_quad`/`s4_cube_lift_level`/`unlift_level`/`s4_haar_split/join_level`
  — golden-tested, **no Swift facade method** (11 Zig exports have no facade).
- *Stale claim corrected:* RGBT4DLift's header alleges a Metal `simd_shuffle` hot-path kernel —
  no such kernel exists.

### Organs / genes "shareable look" (complete but disconnected facade)
- `GeneLibrary/GeneStore.swift` — instantiated in `CaptureViewModel:297`, stored to `self.store`,
  **never read again**. `AirDropHandler` import/export — zero callsites.
- `Organs/MetricOrgan.swift` — nothing constructs it; its only sink
  `PaletteGenerator.refinementMetric` stays nil (loader deleted 2026-06-03).
- `GIFRenderer.swift:6-10` doc describes a `composition.makeExtractor` flow that **does not exist**.

### Editing / diagnostics (dead-end results)
- `Editing/ClusterStatisticsOps.swift:splitAlongPrincipalAxis`/`gamutEllipsoidVolume`/
  `mahalanobisSquared` — zero external callers.
- `CaptureOutput.meanCentroidConditionNumber`/`meanAdmissionRateAt05` — computed every render,
  **no readers** (the χ²/condition-number machinery runs but nothing displays its output).

### Look-NN deploy path (abandoned/unwired)
- `Native/SixFourNative.swift:loadLookNet` + Zig `s4_load_look_net` + `trainer/export_look_net_blob.py`
  — a complete blob parser, but **no trained look-net to load** (supervised MLX look-net abandoned
  2026-06-17); zero Swift callers, no `.s4ln` bundled.
- `Encoder/NetSynth256.swift` — `hasLearnedWeights == false`; `synthesize()` always returns the
  replicate-4× floor (honest no-op scaffold).
- `SixFourNative.encodeBurst` doc claims `s4_gif_encode_burst` returns `NOT_IMPLEMENTED` — **STALE**;
  the kernel is implemented (the doc, not the kernel, is wrong).

### UI components dead island
- `UI/Components/PaletteCloudView.swift`/`PaletteGridView.swift`/`PaletteTreeView.swift`/
  `PixelGrid.swift`/`ContestedCellGridView.swift`/`PlaybackClock.swift` — palette-explorer +
  Canvas-grid island; zero render callers (the Review screen that hosted them is cut).
- `UI/Components/GlassControls.swift` — zero callers and gutted (flat cells, no GlassEffectContainer).
- `Capture/FrameBuffer.swift` — zero callers.

### Generated contracts with no consumer
- `Generated/FrontProjectionGolden.swift`, `InfluenceFieldGolden.swift` (Swift twin),
  `STBN3DContract.swift` — emitted, referenced nowhere (app or test). `SixFourNetSlot` enum:
  zero refs.

> **Contradictions to flag (not papered over):** (a) the header `sixfour_native.h:298` says "31
> symbols total" while a `grep` of `export fn s4_*` finds 33 — **the header tally is stale** (the
> ~31-prototyped figure is the header's self-description, the true export count is 33). (b)
> `leafOverride` has exactly **1** live caller — `Palette/ABCandidates.swift:44` (the A/B candidate
> σ-pair path); `ThetaToDelta` names it only in doc-comments and never invokes it, so the
> `OWNED-BUT-UNWIRED` banner on `ThetaToDelta` is correct. (c) Multiple Surface headers
> cite deleted `surfaceStep`/`bakeCube`/`CubeRaster` machinery.

<!-- SECTION 10: CORRECTIONS SINCE THE 2026-06-16 MAP -->
## 10. Corrections since the 2026-06-16 map

**Current census (`find SixFour -name '*.swift'`): 151 Swift files / 19,680 lines / 21 dirs.**
The old map said ~137 Swift / ~19.5k LOC / 21 dirs — Swift file count is now **+14** (151), LOC
~19.7k, dirs unchanged.

### What changed in this window (2026-06-17 → 06-19)
- **2026-06-17:** the supervised MLX look-net was **ABANDONED** (trained weights deleted); the
  core reframed AlphaZero-shaped (policy+value over the reversible collapse + cube ladder,
  Bradley-Terry A/B reward).
- **2026-06-18:** canonical path decided = one Gumbel-AlphaZero predictor above a frozen Q16
  maximin floor. Built `s4_board_mass_q16`, `GLRM.swift` kill-switch, `s4_leaf_override` +
  `ThetaToDelta` (owned-but-unwired), DECN v2 embeddings, and the n=0 taste loop.
- **2026-06-18 (late):** the **per-frame pivot** — global-palette collapse retired from MVP1
  behind `Feature.globalPaletteV2 = false` (one gate, five guarded entry points, TAG-not-delete).
  `VoxelReduce` (64³↔16³) owned in all 4 languages.
- **The A/B game shipped (G1–G7):** `DivergenceSchedule`, `GenomePair` (EXACT-orthogonal
  `genomeInner==0`), `ABCandidates`, `ABExportFamily`, `GenomeCarrier` (S4GN codec), `GeneArchive`,
  `NetSynth256` scaffold, and the 8-phase `ABSurface` FSM (was an orphan stub). Spec 877 → 911.
- **A/B-genome shift (P1–P5):** the live FSM re-pointed to `ABSurface`; A/B re-quantize moved off
  the main actor; the genome now shapes the bytes (A and B are genuinely different); delta-preserving
  `IsometryMove` replaced a lossy re-center.
- **P4 refactor (`5389493`) PRUNED the old multi-screen flow:** DELETED `ReviewPhaseField`
  (745 LOC), `BrowsingPhaseField`, `RenderingPhaseField`, `CapturingPhaseField`,
  `SettingsPhaseField`, `CandidatePickView`, `HaarShutterView` (~2277 deletions).
- **256×256 export** (`ABExport.swift`) shipped; **A/B pick log** shipped (`GeneLogView.swift`);
  34 `os.Logger` bench timings demoted to `.debug`.

### What now contradicts the old (2026-06-16) map — INVERSIONS
- **GIFB / global collapse is NOT produced at runtime.** The old map's headline "GIFB IS produced
  (`renderDeterministicGlobal → s4_global_collapse`)" is **INVERTED**. MVP1 emits **per-frame
  palettes ONLY**; the global path is fully implemented + golden-gated but **DEFERRED TO V2**
  behind `Feature.globalPaletteV2 = false` (every entry point guarded ⇒ unreachable). The old map's
  "collapse-has-zero-callers is FALSE" claim is itself now false for the live path.
- **The nav/FSM is no longer multi-screen.** The old map described Review/Browsing/Rendering/
  Capturing/Settings phase fields — those files are **DELETED**. The live FSM is the single
  **8-phase `ABSurface`** (capture → A/B pick → export); `PhaseField` collapses `captured`+`picked`
  into one render branch.
- **A live A/B-candidate subsystem exists** that the old map omitted entirely:
  `Palette/ABCandidates.swift`, `Palette/GenomePair.swift`, `UI/Surface/ABCandidatePhaseField.swift`,
  `Generated/GenomePairGolden`, gated by `Feature.abCandidatePicker = true`. The A/B pick is **not
  cosmetic** — `chosenLookPalettes` is what `ABExport` re-encodes into the shipped bytes (a
  delta-preserving recolour over the same index structure).
- **The C header is current, not stale.** `Native/include/sixfour_native.h` prototypes all four
  RGBT-4D kernels (lines 170–178) and self-describes ~31 exports. Any "header omits RGBT-4D / no C
  prototype yet" claim is wrong.
- **`s4_gif_encode_burst` is implemented** (`kernels.zig:162 → :229`), not `NOT_IMPLEMENTED`. It is
  a whole-burst monolith exported for host round-trip tests, not called by the app.
- **`RGBT4DLift` is not zero-caller** — `VoxelReduce.swift` consumes it; the dormancy is one level
  up (`VoxelReduce` has no production caller).
- **Metal has THREE `.metal` shaders:** `field.metal`, `Shaders.metal`, `NearestCentroidShaders.metal`
  (the old map omitted the last).

### Naming / status notes
- There is **no "GeneInspector" file** — the implemented artifact is `UI/Surface/GeneLogView.swift`.
- **STATUS.md is stale on the test count:** it reads 877 Haskell tests (reconciled pre-merge);
  NOTES records 877 → 911 after the A/B-game merge. Trust **911**.
- The 256×256 export is plain **4×4 index replication** (thick pixels), NOT learned super-res;
  `NetSynth256` (the learned 256³ path) is an honest no-op scaffold. Two different things that
  share the "256" name.

<!-- SECTION 11: OPEN GAPS -->
## 11. Open gaps (orientation, not a status ledger)

These are structural seams worth knowing when adding code. They are observations, not a to-do list
(for status, see `docs/STATUS.md`).

- **Two parallel render engines, no shared facade.** The live deterministic Zig path
  (`DeterministicRenderer`) and the float GPU k-means path (`GIFRenderer`) diverge in math
  (Q16 vs float), so the silent fallback is **not byte-reproducible** — a fallback render would
  produce a different GIF with no UI signal.
- **Two GIF encoders in play.** Capture (GIFA) uses the Zig `s4_gif_assemble` (carries SHA-256);
  the A/B export (`ABExport.encodeChosenLook`) uses the Swift `GIFEncoder(upscale:4)` — the shipped
  chosen-look GIF does **not** carry the deterministic fingerprint.
- **Two preference models.** The MPSGraph `AtlasTrainer` value head V(board,genome) is verified but
  consumed by nothing; the live ranking organ is the separate linear `PersonalTaste` θ in
  `ABCandidatePhaseField`. Only the linear one ships.
- **Export ladder is spec-ahead-of-code.** `ABExportFamily` / `NetSynth256` / the {16³,64³,256³}
  genome ladder compile but nothing calls them; `ExportingPhaseField` only invokes
  `encodeChosenLook` (256² flat). The family export is an explicit follow-on.
- **Verification gate gaps (§8b):** Zig fixtures come from an un-gated exe; fixture tests are
  skip-if-absent; Swift golden tests aren't run by the gate; the non-Swift drift list is a hardcoded
  3 entries (so new trainer/Rust/Zig contracts can drift). The Rust `studio/` workspace is wired
  into no project gate at all.
- **Pervasive stale doc-comments.** Surface headers cite deleted `surfaceStep`/`bakeCube`; Cell*
  comments describe a retired 2pt/6pt lattice (the atom is now 4pt); `PalettePipeline`/`GIFRenderer`
  reference nonexistent Wu/Octree pipelines and a `makeExtractor` flow; `kernels.zig` still calls
  itself a "Stage 0 scaffold." Code is correct; comments lag the per-frame-genome-A/B pivot.
- **No SettingsView.** ~6 `AppSettings` keys (`openInPixelatedPreview`, `autoSaveToPhotos`,
  `showPaletteTree`, `paletteRepresentation`, `gridAxisX/Y`) are write-only — no in-app Settings
  screen binds them.
- **Editing tooling is the missing top half.** `ClusterStatisticsOps` documents a full
  chi²-admission → PCA-split editing workflow with no UI/controller wiring it together.

<!-- SECTION 12: APPENDIX -->
## 12. Appendix: recount commands

Run from the repo root (`/Users/daniel/SixFour`). These reproduce the census in §4/§10
(verified 2026-06-19: 151 / 19,680 / 21 / 3 / 33).

```bash
# Swift file count
find SixFour -name '*.swift' | wc -l                       # -> 151

# Total Swift lines
find SixFour -name '*.swift' -exec cat {} + | wc -l        # -> 19680

# Directory count under the app target
find SixFour -type d | wc -l                               # -> 21

# Metal shaders (field.metal, Shaders.metal, NearestCentroidShaders.metal)
find SixFour -name '*.metal' | wc -l                       # -> 3

# Zig exported symbols (kernels + root + synth)
grep -rh 'export fn s4_' Native/src/*.zig | wc -l          # -> 33

# Generated contracts/goldens emitted into the app target
ls SixFour/Generated/*.swift | wc -l

# The two MVP1/V2 compile gates
grep -n 'globalPaletteV2\|abCandidatePicker' SixFour/Settings/Feature.swift

# Confirm the per-frame coercion (global statically unreachable)
grep -n 'paletteScope' SixFour/UI/Screens/Capture/CaptureViewModel.swift

# RGBT-4D kernel prototypes in the C header (lines ~170-178)
grep -n 's4_rgbt_lift_quad\|s4_cube_lift_level' Native/include/sixfour_native.h
```
