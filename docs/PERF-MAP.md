# PERF MAP: the thermal-budget re-map — tick/burst/post/preview/cold/dead classification, hot-path chain, ring re-map proposal, iOS 27 adoption points

> Status: LIVING (§1–2, §5) + PROPOSAL (§3–4, pending Daniel's approval) · Created: 2026-07-08 · Owner: SixFour
> Companions: `docs/DEVICE-MODEL-MAP.md` (memory ledger), `docs/APP-MAP.md` (UI map), `docs/STATUS.md`.
> Every anchor is `file:line` from the 2026-07-08 five-scanner inventory + hot-path audit; flags read
> live from `SixFour/Settings/Feature.swift` (`v21Capture = true`, `v3SomaticTrain = true`,
> `yinYangBands = true`; `globalPaletteV2`/`metaInitW0`/`multiScaleLadder`/`liveLadder`/`opticalEV`/
> `multiScaleRender` all `false`). §4 API names are UNVERIFIED against the shipped iOS 27 SDK
> (the July 2026 research pass returned no confirmed findings) — verify in Xcode 27 headers before adopting.

## 1. The thermal budget is the product

SixFour's product is a sustained 20 fps × 3.2 s burst on an iPhone 17 Pro that can be repeated all
session without ISP frame drops, jetsam, or thermal throttle — so every file in the repo is classified
here by its **distance from the tick**: `tick` (runs per 20 fps camera frame), `burst` (runs at the
shutter seam, synchronously on the delegate queue), `post` (detached after the seam), `preview`
(~10 fps idle display), `cold` (launch/settings/export-tap), `dead` (unreachable: flag-off, test-only,
or zero-reference). The 50 ms tick budget and the shutter-seam latency are the two numbers everything
below is ranked against; RSS proximity to jetsam (the 768 MiB `v21HistBuffer`) is the third.

---

## 2. THE HOT-PATH MAP

### 2.1 Directory census (pathClass mix)

| Directory | files | tick | burst | post | preview | cold | dead | Notes |
|---|---|---|---|---|---|---|---|---|
| `SixFour/Capture/` | 8 | 2 | 2 | 0 | 0 | 1 | 3 | tick = `CaptureSession` + `ColorHead`; dead = `FrameBuffer` (zero refs), `MultiScaleLadder`, `ExposureBracketDriver` (flags off) |
| `SixFour/App/` | 1 | 0 | 0 | 0 | 0 | 1 | 0 | `SixFourApp` primes render-PSO compile off-main at first instruction |
| `SixFour/Settings/` | 2 | 0 | 0 | 0 | 0 | 2 | 0 | `Feature.swift` gates put the 768 MiB buffer + per-tick CPU colorimetry on the live path |
| `SixFour/Kernels/` | 14 | 2 | 1 | 3 | 2 | 3 | 3 | tick = `KernelsPalette16` (scalar pool loops) + `KernelsCore` (s4log); dead = `KernelsSIMT` (unwired SIMD twin), `KernelsMultiScale`, `KernelsSynth` |
| `SixFour/Native/` | 6 | 0 | 0 | 1 | 2 | 3 | 0 | `SixFourNative` facade = preview marshalling; `MaskedBandForward` = post |
| `SixFour/Generated/` | 42 | 0 | 0 | 1 | 0 | 33 | 8 | 1 post (`STBN3DContract`); 8 golden files with zero app+test refs (incl. `GenomeFixedGolden` 36 KB) |
| `SixFour/Metal/` | 13 | 3 | 0 | 6 | 1 | 2 | 1 | tick = `Pipeline` + `Shaders.metal` + `TextureCache`; dead = `PaletteLadder.metal` (test-parity twin) |
| `SixFour/Train/` | 8 | 0 | 0 | 5 | 0 | 1 | 2 | all trainers correctly detached post-seam; dead = `GatedResidual`, `MetaInit` (flag off) |
| `SixFour/Palette/` | 22 | 0 | 0 | 9 | 2 | 0 | 11 | preview = `LivePreviewAnalysis` + `LookVariant`; post stack = GPU-float FALLBACK only; half the dir is the dead explorer/ladder cluster |
| `SixFour/Encoder/` | 9 | 0 | 0 | 4 | 0 | 1 | 4 | `DeterministicRenderer` = THE default render path (detached); `LUTFile` is a main-actor hitch (cold) |
| `SixFour/Editing/` | 5 | 0 | 1 | 3 | 0 | 0 | 1 | `CaptureBundle` retains ~4–5 MB for app lifetime |
| `SixFour/Organs/` | 3 | 0 | 0 | 0 | 0 | 2 | 1 | `MetricOrgan` loader removed 2026-06-03 |
| `SixFour/RGBT4D/` | 2 | 0 | 0 | 2 | 0 | 0 | 0 | executes live via `VoxelReduce` in `Surface.buildCoarseSubstrate` (detached) |
| `SixFour/Color/` | 1 | 0 | 0 | 0 | 1 | 0 | 0 | scalar powf per pixel on the preview path |
| `SixFour/GeneLibrary/` | 9 | 0 | 0 | 0 | 0 | 1 | 8 | only `GeneStore` is live; whole swap-economy layer unwired (entitlements commented out) |
| `SixFour/UI/` | 48 | 13 | 1 | 1 | 15 | 4 | 14 | tick cluster = preview-publish fan-out + `InvertedPyramidField` (worst per-tick offender); 14-file dead cluster (palette explorers, movable widget, GridlineField…) |
| **Total** | **~193** | **20** | **5** | **35** | **23** | **54** | **56** | **~29 % of files are dead weight compiled into the shipped binary** |

### 2.2 The tick chain (20 fps burst / 10 fps idle), in execution order

1. `Capture/CaptureSession.swift` — `captureOutput` on the private delegateQueue. Burst branch:
   GPU `submitAsync` + synchronous ColorHead feed (`:1155-1157`); idle branch: preview throttled to
   10 fps by mach-time check (`:1188-1189`). One `os.Logger .debug` per burst frame (`:1111`).
2. `Metal/TextureCache.swift` — zero-copy YCbCr10 luma/chroma pair, 1–2 lookups per tick.
3. `Metal/Pipeline.swift` — `submitAsync` (`:141`): **3 fresh MTLTextures per frame, no pool**
   (`:215-233`); 3-pass command buffer (crop/linearize → OKLab → unsharp) + 4th V2.1 hist pass
   while `v21Capture` (`:164`). Non-blocking commit — verified NO `waitUntilCompleted` on the tick path.
4. `Metal/Shaders.metal` — `cropDownsampleLinearizeKernel` walks the full ~scale² (~289
   samples/output-px) crop box; `v21AccumulateHist(Soft)` RE-WALKS the same box in the same command
   buffer → ~2× per-tick GPU bandwidth while `v21Capture = true`.
5. `Capture/ColorHead.swift` — `poolSums64(fromX420:)` SYNC on delegateQueue after GPU submit:
   512×512 scalar YCbCr10→RGB10 integer loop into the retained 1.5 MB `rgb10Scratch` (`:195-218`),
   fresh 96 KB `[UInt64]` per tick (`:220`); `ingest()` = exact u64 poolSpatial2 64→32→16
   (`:242-258`) + `emitTBandPairs` every 2nd tick (1024 five-element `[Int64]` allocs, `:279-291`).
6. `Kernels/KernelsPalette16.swift` — `s4_pool_sums_linear_hlg10` (`:357`): full-frame 786 k-element
   range PRE-SCAN (`:371-373`) then the scalar LUT+sum triple loop — DOUBLE pass, zero SIMD. The
   SIMD16 twin (`KernelsSIMT.swift`) is only dispatched from `s4_pool_sums_srgb8`, which has **zero
   app callers** — the SIMT machinery is dead on device.
7. `Metal/Pipeline.swift` — `addCompletedHandler` readback (`:171-179`, `:409-434`) on the Metal
   completion thread: ~32 KB Float16 staging + ~48 KB `[SIMD3<Float>]` map per frame, then
   `delegateQueue.async` hop to append the tile (`CaptureSession.swift:1127-1137`).
8. `UI/Screens/Capture/CaptureViewModel.swift` — burst: `CoalescingFrameRenderer.submit` O(1) +
   `Task{@MainActor}` progress hop PER FRAME (`:618-628`). Idle: `previewCallback` on the Metal
   completion thread (`:435`): maximin quantize k=256 (~1 M i64 distance evals) + dither + palette
   + CGImage build (`:1135-1171`), `LivePreviewAnalysis.analyze`, then a `Task{@MainActor}` per
   frame publishing 3 observable arrays; throttled livePalette re-quantize every ~330 ms.
9. `UI/Surface/SurfaceView.swift` — `.onChange(previewIndexTile)` + `.onChange(livePalette)`:
   `settings.captureLook.apply(to:)` allocates a fresh 256-entry array per publish, 2–3 σ writes
   fan out invalidation (`:146-162`).
10. `UI/Surface/LivePhaseField.swift` — body re-eval per σ preview mutation; mounts the pyramid.
11. `UI/Surface/InvertedPyramidField.swift` — **worst per-publish offender, all on MAIN**: 96 KB
    `[UInt64]` `sums64()` alloc (`:138-149`) + `ColorHead.poolSpatial2` ×2 in body (`:73-74`) +
    THREE `CellSprite` CGContext bakes per body eval.
12. `UI/Components/CellSprite.swift` — `CellBitmap.image` (`:15-34`): cols·rows·4 buffer +
    CGContext + CGImage + UIImage on EVERY body eval, zero caching.
13. Parallel: `UI/Surface/SurfaceClock.swift` (the one 20 Hz CADisplayLink, clean/allocation-free)
    → `UI/Components/FieldMetalView.swift` — well-gated: one GPU draw per κ tick (`lastDrawnTick`,
    `:324`), pooled 4 KB tile buffer (`:356-363`), triple-buffered, no wait; small per-tick allocs
    remain in `updateUIView` (packPalette 768 B, usage arrays).

### 2.3 The burst seam (everything synchronous on delegateQueue until the continuation resumes)

1. Burst start: `Pipeline.makeV21HistBuffer` = **768 MiB** storageModeShared (`Pipeline.swift:267-271`,
   alloc at `CaptureSession.swift:749`).
2. 64th tile lands (Metal completion → delegateQueue) → `finishBurst()` (`CaptureSession.swift:850`);
   everything through `:997` is SYNC on delegateQueue.
3. `computeTiming` — trivial.
4. **`Pipeline.poolV21Counts` SYNC**: ~201 M Int32 adds over the 768 MiB buffer
   (`CaptureSession.swift:865` → `Pipeline.swift:276-285`) — the largest remaining synchronous seam cost.
5. `flowJobActive` gate (`:872-889`): a still-running previous flow encode SILENTLY skips this
   burst's flow; else `Task.detached encodeV21Flow` (~19 s device-measured, holds the 768 MiB
   buffer alive; 12.6 MiB Array copy per frame ×64).
6. `Train/CaptureGene.train` — `Task.detached` (`:900-919`): 3 MiB volume + 786 k-px quantize loop
   → `RungDispatch.trainOnVolume` (commit + wait, acceptable off-seam) → θ_up gate.
7. ColorHead yin-yang seam work SYNC (`:930-955`): snapshot sums16/GCT, `drainTBandPairs`
   (≤8192 pairs), `haltFloor()` = 256 × `s4_certified_order` (cheap).
8. `Train/BandHeadTrainer` — `Task.detached` (`:957-978`): constructed FRESH per burst (new
   GPUContext + PSO compile), single-GPU-thread 2500-step descent, wait off-seam.
9. State reset + `continuation.resume(BurstResult)` (`:983-997`) — the shutter resumes WITHOUT
   waiting on any of the 3 detached jobs (QoL 2026-07-03 seam relief, verified).
10. Main actor resumes: `renderOnce` → `Task.detached DeterministicRenderer.render` (default path;
    `emitPartial` hops 5 × 256 KB payloads to main), `CaptureBundle` assembly (~4–5 MB retained) +
    `saveBundleAsync` (4 MB JSON, .background) + `.s4cr` CBOR write (~10 KB).
11. `.done` edge: `SurfaceView.commit` builds the 256 KB indexCube on main (`:289-300`);
    `Surface.buildCoarseSubstrate` correctly detached (262 k-px reindex + 64 kernel calls +
    2 `VoxelReduce` over a ~6.3 MB tuple cube).

### 2.4 Hazards, severity-ranked

| # | Sev | Where | Issue |
|---|---|---|---|
| H1 | HIGH | `ColorHead.swift:195-229` + `KernelsPalette16.swift:357-399` (per burst tick via `CaptureSession.swift:1155`) | Per-20fps-tick CPU pixel work sync on the camera delegate queue: 262 k-px scalar YCbCr→RGB10 loop + `s4_pool_sums_linear_hlg10` full-frame pre-scan then scalar LUT+sum = DOUBLE pass over 786 k u16, all scalar (SIMD16 twin unreachable: `s4_pool_sums_srgb8` has zero app callers). Biggest sustained CPU load in a burst; competes with the 50 ms tick on the frame-intake queue; drives thermals. |
| H2 | HIGH | `Pipeline.swift:267-271` (alloc `CaptureSession.swift:749`; held per `:877-889`) | 768 MiB `v21HistBuffer` per burst, held ~19 s by the detached flow encode. `flowJobActive` prevents two live buffers but by SILENTLY dropping the new burst's flow. RSS dominator / jetsam proximity driver. |
| H3 | HIGH | `CaptureSession.swift:865` → `Pipeline.swift:276-285` | `poolV21Counts` SYNC on the delegate queue inside `finishBurst`: ~201 M Int32 adds before the shutter continuation resumes. A frame arriving during the stall hits `alwaysDiscardsLateVideoFrames`. |
| H4 | HIGH | `InvertedPyramidField.swift:71-100` + `CellSprite.swift:15-34` | Every preview publish (~10 fps idle, up to ~20 fps in burst) re-runs the pyramid body ON MAIN: 96 KB sums alloc + 2 × poolSpatial2 + THREE CGContext/UIImage bakes with per-pixel Double `pow` — zero caching, exactly while capture UI must stay responsive. |
| H5 | MED | `CaptureViewModel.swift:435-469, 1135-1171` (Metal completion thread) | Per ~10 fps preview frame: maximin quantize k=256 (~1 M i64 evals) + dither + CGImage + dictionaries + a MainActor Task publishing 3 arrays; then SurfaceView's LOOK re-grade allocates another 256-array. Display-only churn. (Runs on the completion thread, NOT the delegate queue — does not directly block intake.) |
| H6 | MED | `Pipeline.swift:215-233, 409-434` + `ColorHead.swift:220, 242-297` | Per-tick allocation churn: 3 fresh MTLTextures/frame (no pool), ~80 KB readback arrays/frame, 96 KB sums/tick, ingest intermediates, 1024 five-element `[Int64]` t-band allocs every 2nd tick with O(n) `removeFirst`. Aggregate allocator traffic = power/thermals over a session. |
| H7 | MED | `KernelsCore.swift:47-52` + `SixFourNative.swift:33-54` | `s4log` formats a String + `Array(utf8)` on EVERY kernel call once logging installs at bootstrap; preview suppression is checked in the callback AFTER formatting — ~10 fps quantize/dither/palette calls still pay per-call alloc + interpolation. (The 20 fps pool kernels do not call s4log — burst path clean.) |
| H8 | MED | `Shaders.metal` v21 accumulators, dispatched `Pipeline.swift:164-166` | V2.1 hist pass re-walks the same ~289-sample crop box the box-average already read, same command buffer — ~2× per-tick GPU texture bandwidth for training data no shipped GIF byte depends on. |
| H9 | MED | `Encoder/LUTFile.swift` `makeShareItem` (called `PhaseField.swift:157`) | EXPORT LUT runs SYNC in the main-actor Button action: 65³ = 274,625-entry kernel dispatch + ~8 MB `.cube` String + file write — multi-hundred-ms Review hitch. UX-only. |
| H10 | LOW | `BandHeadTrainer.swift` init (constructed `CaptureSession.swift:969`) | Fresh GPUContext + PSO compile per burst instead of a cached singleton. Off-seam; wasted latency/power. |
| H11 | LOW | `CaptureBundle.swift` (assembled `CaptureViewModel.swift:681`) + `DeterministicRenderer.emitPartial` | ~4–5 MB retained app-lifetime; ~4 MB JSON encode concurrent with the 768 MiB flow hold; 5 × 256 KB main-actor stage hops. Post-shutter only. |
| H12 | LOW | `CaptureSession.swift:299-541` (`configure`/`selectHDRFormat`) | ~9 real ISP reconfigs (tens–hundreds of ms) inside `init`. Currently safe (off-main via `buildCaptureStack`), but the safety is a caller CONTRACT (header `:379-382`), not enforced — regression hazard. |
| H13 | LOW | `ColorHead.swift:469-531` (`ColorHeadMetal`) + `Metal/PaletteLadder.metal` | Full-frame `makeBuffer` memcpy + `waitUntilCompleted` per call — a per-tick stall TRAP with a signature identical to the live API. Verified dead (ColorHeadTests only). |
| H14 | LOW | `Kernels/KernelsLUTData.swift` | Lazy global-let init: the one-time ~250 KB base64 LUT decode fires on whichever thread first touches a table — can be the delegate queue's first burst tick (`hlg_to_linear16`). One-time hitch. |

---

## 3. PROPOSED DIRECTORY RE-MAP (PLAN — NOT EXECUTED, pending Daniel's approval)

> **This is a proposal.** Nothing here is moved. It is ITERATIVE/additive re-organization: no file is
> deleted, no golden-gated module is removed (repo contract), and every `git mv` batch MUST land in
> the same change as its `project.yml` (xcodegen) update + any script-path references
> (`scripts/build-kernels-dylib.sh` globs `SixFour/Kernels/` — moving Kernels files breaks the Mac
> trainer dylib; `scripts/gen-lut-swift.py` writes `KernelsLUTData.swift` in place). Run
> `xcodegen generate` + full test suite after each batch; goldens must stay green.

The target layout names directories by **ring** = distance from the tick, so a future reviewer can
audit "what is allowed to allocate" by path alone:

```
SixFour/
  HotPath/        # ring 0: per-tick — allocation-audited, no logging, no float
  Shutter/        # ring 1: burst seam + detached trainers kicked from it
  Render/         # ring 2: post-shutter palette/encode/export/edit
  Surface/        # UI stays where APP-MAP puts it (UI/ unchanged this pass)
  Cold/           # settings, gene store, one-shot probes
  Attic/          # compiled-out-of-the-app-target dead weight (kept in repo, goldens intact)
```

### 3.1 HotPath ring (ring 0 — the 50 ms tick)

| Move | From → To |
|---|---|
| `git mv` | `SixFour/Capture/CaptureSession.swift` → `SixFour/HotPath/CaptureSession.swift` |
| `git mv` | `SixFour/Capture/ColorHead.swift` → `SixFour/HotPath/ColorHead.swift` (SPLIT FIRST: extract the dead `ColorHeadMetal` class `:469-531` into `Attic/ColorHeadMetal.swift` with `PaletteLadder.metal` so the stall trap stops sitting next to the live API) |
| `git mv` | `SixFour/Metal/Pipeline.swift`, `Shaders.metal`, `TextureCache.swift` → `SixFour/HotPath/Metal/` |
| stay | `SixFour/Kernels/` DOES NOT MOVE (dylib script + ABI header + Mac trainer bind to this path). Instead add a `// RING: tick` header comment to `KernelsPalette16.swift`/`KernelsCore.swift` and enforce by lint. |

### 3.2 Shutter ring (ring 1 — finishBurst + detached trainers)

| Move | From → To |
|---|---|
| `git mv` | `SixFour/Capture/CaptureRecord.swift`, `HaltDepthBridge.swift`, `CaptureExposureProbe.swift` → `SixFour/Shutter/` |
| `git mv` | `SixFour/Train/RungDispatch.swift`, `CaptureGene.swift`, `BandHeadTrainer.swift`, `OctantCube.swift` → `SixFour/Shutter/Train/` (+ `Metal/BandHeadShaders.metal`, `Metal/DeviceTrainShaders.metal`) |
| SPLIT | `SixFour/Train/DeviceTrainer.swift` — do NOT move whole: `DeviceTrainStepCPU` helpers are LIVE on post paths → `Shutter/Train/DeviceTrainStepCPU.swift`; the MPSGraph `DeviceTrainer` class + `DeviceTrainGoldenCheck` (golden-harness only) → `Attic/DeviceTrainerHarness.swift` (kept: golden-gated). |

### 3.3 Render ring (ring 2 — post-shutter)

| Move | From → To |
|---|---|
| `git mv` | `SixFour/Encoder/{DeterministicRenderer,GIFEncoder,GIFRenderer,ContactSheet,LUTFile}.swift` → `SixFour/Render/` |
| `git mv` | live `SixFour/Palette/` files (`LivePreviewAnalysis`, `LookVariant`, `PaletteGenerator`, `Dither`, `NearestCentroid`, `SignificantSplitFill`, `WuQuantizer`, `KMeansExtractor`, `ClusterStatistics`, `PaletteExtractor`, `DistanceMetric`) → `SixFour/Render/Palette/` |
| SPLIT | `SixFour/Palette/PaletteCollapse.swift` — the `OKLabQ16` typealias IS load-bearing on live paths: extract it to `SixFour/Render/OKLabQ16.swift` FIRST, then the collapse code (globalPaletteV2-gated) → `Attic/`. |
| `git mv` | `SixFour/Metal/{KMeansPalettePipeline,BlueNoisePalettePipeline,NearestCentroidShaders.metal,PaletteEngines,PalettePipeline}.swift` → `SixFour/Render/Metal/`; `SixFour/Editing/` + `SixFour/RGBT4D/` → `SixFour/Render/Editing/`, `SixFour/Render/RGBT4D/` |

### 3.4 Cold ring + Attic

| Move | From → To |
|---|---|
| stay | `SixFour/Settings/`, `SixFour/Generated/` (codegen writes here), `SixFour/App/` — path churn buys nothing. |
| `git mv` | `SixFour/GeneLibrary/GeneStore.swift` stays (the one live file); the other 8 (`AirDropHandler`, `CarrierWire`, `GenomeCarrier`, `SwapCarrier`, `CreatorIdentity`, `GeneCloudSchema`, `GeneExchange`, `Governance`) → `Attic/GeneLibrary/` — golden-gated (`SwapCarrierGolden` etc.), so KEPT and still compiled into the TEST target, removed from the APP target via `project.yml` source excludes. |
| `git mv` | Flag-off modules → `Attic/Gated/`, gates intact: `MultiScaleLadder.swift`, `ExposureBracketDriver.swift`, `KernelsMultiScale.swift` (breaks the Kernels-stays rule — alternative: leave in place, exclude from app target), `MultiScaleRender.swift`, `MetaInit.swift` (keep the `CaptureSession.swift:903` gate reference compiling — move needs a stub or the reference travels), `OpticalTileFolds.swift`. These are ITERATIVE roadmap modules (optical-EV ladder, multiscale render) — attic'd, not deleted. |
| `git mv` | Zero-reference dead → `Attic/`: `FrameBuffer.swift`, `KernelsSynth.swift` (Mac tooling — better: move under `trainer/`), `KernelsSIMT.swift` (KEEP NEAR KERNELS if H1 fix wires it live — see §3.6), `LadderExport.swift`, `LadderGIF.swift`, `NetSynth256.swift`, `ModelFloor.swift`, `GatedResidual.swift`, `KMeansLab.swift`, `MetricOrgan.swift`, the 9-file Palette explorer cluster, the 14-file UI dead cluster (`MovableColorWidget`+`CellDetent`, `PaletteCloud/Grid/TreeView`, `ContestedCellGridView`+`CellAlgebra`, `PlaybackClock`, `GlassControls`, `GridlineField`, `CellGlyph`, `DemoScene` DEBUG-only). |
| APP-target exclude | 8 zero-ref Generated goldens (`DerivationLogGolden`, `Ed25519Golden`, `FrontProjectionGolden`, `GeneHashGolden`, `GenomeFixedGolden` 36 KB, `GridAxisGolden` 16 KB, `Sha512Golden`, `SigChainGolden`) — files stay in `Generated/` (codegen owns the dir), excluded from the app target only. |

### 3.5 Sequencing (each batch = one PR, xcodegen + tests green)

1. **Batch 0 (no moves):** app-target source excludes for Attic candidates — measures binary-size win
   with zero path churn, reversible by deleting one `project.yml` line.
2. **Batch 1:** file SPLITS (`DeviceTrainer`, `PaletteCollapse` typealias, `ColorHeadMetal`) — these
   unblock every later move.
3. **Batch 2:** Attic moves (dead + gated), test target keeps compiling everything golden-gated.
4. **Batch 3:** HotPath/Shutter/Render ring moves.

### 3.6 What the re-map does NOT do

It does not fix H1–H8 — those are code changes, not moves. The map's value is that after it, "a PR
touches `HotPath/`" is a reviewable event. The single highest-value CODE follow-up remains: wire the
`KernelsSIMT` SIMD16 pool twin into the bgra8/hlg10 variants (or move pooling to the existing GPU
pass) and delete the hlg10 pre-scan double pass (H1).

---

## 4. iOS 27 ADOPTION POINTS (UNVERIFIED against shipped SDK — confirm in Xcode 27 headers first)

The July 2026 research pass returned no confirmed findings, so every API name below is a candidate
to verify, not a fact. Each is tied to the file that would adopt it.

1. **Deferred session start** (`isDeferredStartEnabled` on `AVCaptureVideoDataOutput` /
   `automaticallyRunsDeferredStart`) — `SixFour/Capture/CaptureSession.swift` (`configure()` at
   `:299-541`, `startPreview` `:597-605`). The ~9-reconfig `selectHDRFormat` probe loop is today kept
   off the first frame only by the off-main caller contract (H12); deferred start would let the OS
   overlap session bring-up with first render and turn the contract into construction. Launch-to-preview
   is the metric.
2. **`hardwareCost` + `systemPressureState.frameRateOverride` monitoring** —
   `SixFour/Capture/CaptureSession.swift`. The 20 fps × 3.2 s product IS a thermal contract: observe
   `AVCaptureDevice.systemPressureState` (KVO) and any iOS 27 frame-rate override, surface it into the
   burst gate so a thermally-throttled burst REFUSES (matches the KinematicHaltPrior refuse-don't-lie
   ethos) instead of silently delivering a 13 fps GIF timed as 20.
3. **`AVProVideoStorage` (or the iOS 27 external/pro storage write path)** —
   `SixFour/Capture/CaptureRecord.swift` (`:118` atomic write) + `CaptureViewModel.swift` GIF/bundle
   writes (`:521-531`, `:745`). Move `.s4cr` training records, the 4 MB CaptureBundle JSON, and the
   accumulating `Documents/sixfour_*.gif` files (no GC today, per DEVICE-MODEL-MAP D1) onto the
   deferred/pro storage path so disk I/O never shares the post-burst window with the 768 MiB flow hold.
4. **Responsive capture / `captureReadiness`** — `SixFour/Capture/ExposureBracketDriver.swift` +
   `SixFour/Capture/MultiScaleLadder.swift` (both flag-off, Attic'd by §3 but ROADMAP modules): the
   interleaved 0/+1/+2-stop EV ladder is exactly the workload readiness coordination exists for —
   the driver's `setExposureModeCustom` every ~4 frames (`ExposureBracketDriver.swift:110-125`) needs
   a readiness signal to avoid banding the ladder against ISP settle time. Adopt when `opticalEV` flips on.
5. **Quad-pixel sensor binning = the HARDWARE rung of the K-ladder** —
   `SixFour/Capture/CaptureSession.swift` (`selectHDRFormat`, format enumeration `:459`) +
   `SixFour/Capture/ColorHead.swift`. 2×2 same-colour binning is analog pooling BEFORE readout noise:
   one binned read has the photon sum of 4 photosites but ONE read-noise draw, so the coarse rung's
   SNR beats digital pooling after the ISP (which sums 4 already-noised samples). If iOS 27 exposes a
   binned x420 video format, the 16-cube rung should prefer it: it is the same K (pool) operator as
   §5, executed in silicon. Probe for it in `CaptureExposureProbe.swift`.
6. **Core Image RAW 9** — photo path only. SixFour's live path is x420 video (no CIRAWFilter
   involvement); RAW 9 matters only if a ProRAW still path ever lands (cf. the 6teen3/GIFtok
   lessons). No current file adopts it; note kept so nobody burns a session investigating.

---

## 5. PURE THREE-RESOLUTION SIGNAL: the pooling ladder is the S/K/I record

The current purest continuous path is already live: **x420 10-bit HLG BT.2020, linearized BEFORE
pooling** (`s4_pool_sums_linear_hlg10`, `KernelsPalette16.swift:357` — inverse-EOTF LUT per sample,
then exact u64 sums). Linear-light sums are photon-count arithmetic: pooling after linearization is
the only order in which the 32/16 rungs are radiometrically true area means (`Spec.RadiometricRealize`
realizes them through `s4_sums_bt2020_to_srgb8`).

The ladder IS the short exact sequence:

- **K = pool.** `ColorHead.ingest` derives 32/16 from 64 by exact u64 2×2×2 adds
  (`ColorHead.swift:242-258`) — K keeps mass, kills detail. The 16-cube is the GCT basis.
- **ker K = the Walsh detail bands.** What pooling destroys is exactly the 2×2×2 mixed-derivative
  octant grading (`Spec.OctantViews`, 1+3+3+1) — and those bands are **S's training target**: the
  t-band pairs `emitTBandPairs` accumulates (`:279-291`) and `BandHeadTrainer` fits are the
  reversal-odd cargo K cannot see (the colour-momentum law: K kills momentum, S invents it).
- **I = exact reconstruction.** Sums are the transitive carrier (rounded means do not compose —
  teeth-tested); keep the sums and the lift is invertible (`KernelsLattice` Haar/octant lifts,
  `VoxelReduce` keeps `spatialDetail`+`temporalDetail` for exact inversion).

Per-voxel sample counts across the rungs are **1 : 8 : 64** (64-rung = 1 pooled sample, 32-rung =
2×2 spatial × 2 temporal = 8, 16-rung = 64), i.e. 0/3/6 bits of pooling — so **32 is the geometric
(log-domain) midpoint**, not an arbitrary middle child: each rung step is exactly +3 bits of SNR
bought with ×8 fewer voxels, at the GIF-exact cadences 20/10/5 Hz forced by the centisecond delay
law (`s4_ladder_delay_cs`).

The **optical EV ladder rides the same k axis**: `ExposureBracketDriver`'s 0/+1/+2-stop assignment
to the 64/32/16 rungs adds one photographic stop per rung step on top of the +3-bit pooling gain —
optical exposure, analog binning (§4.5), and digital pooling are three implementations of the ONE
coarsening operator k (`sixfour-colortime` law: one k = coarsen/pool/stops/norm/bits). The hardware
rung (quad-pixel binning) slots under the digital rung with strictly less read noise; the optical
rung slots above it with strictly more photons. Purity ordering per coarse voxel:
**optical EV > analog binning > digital linear-light pooling > anything post-ISP-gamma** — and the
live path today already sits at rung three of four.

---

## 6. LANDED 2026-07-08 (the same session, post-audit)

All gates green after each item: `xcodebuild test` (full suite) + GRID lint + BUILD SUCCEEDED.

- **H1** — `s4_pool_sums_linear_hlg10` pre-scan is now a SIMD16 lane-max sweep (same
  refuse-before-write contract, pinned by `ZigPortPalette16Tests`); the x420 loop in
  `ColorHead.poolSums64(fromX420:)` computes chroma offsets once per 4:2:0 pixel pair
  (cache keyed on `ci`, reset per row). Byte-identical outputs.
- **H3** — `poolV21Counts` left the shutter seam: it runs first inside the detached flow task,
  delivered via the new `v21CountsCallback` (epoch-guarded, the `flowCallback` pattern);
  `BurstResult.v21Counts` is nil by design. BEHAVIOR NOTE: the rare flow-skip branch now drops
  the field too (memory over completeness; review bench falls back to the proxy).
- **H4** — `InvertedPyramidField` bakes moved to @State keyed by a pixel fingerprint + a
  filled-cell-quantized shutter key: pixel change = one rebake of all three, progress tick =
  256-cell vertex only. Colour math verbatim. DEVICE-UNVERIFIED (visual).
- **H7** — new `s4_set_log_gate` C-ABI hook (KernelsCore + ABI header): suppression is checked
  BEFORE the line formats; the app wires the preview thread-local into it (`installLogging`).
- **H6/H10** — `MetalPipeline` per-frame texture triple now recycles through a checked-out/checked-in
  pool (cap 4, recycle after readback in the completed handler); `BandHeadTrainer.shared` replaces
  the per-burst GPUContext + PSO compile (`@unchecked Sendable`: immutable after init).
- **Batch 0 (§3.5)** — app-target excludes for the files that mechanically verified ZERO-REF across
  app + tests (type AND top-level decls): 5 Generated goldens (`DerivationLog/Ed25519/GeneHash/
  Sha512/SigChain`), `FrameBuffer`, `NetSynth256`, `CellGlyph`. The §3.4 list was optimistic:
  `FrontProjection/GenomeFixed/GridAxis` goldens + `GatedResidual` are TEST-referenced (hosted
  @testable — an app exclude breaks them; needs the Batch-2 test-target-sources pattern),
  `KernelsSynth` is app-referenced via `SixFourNative.synthBurst`, the Palette/UI "dead clusters"
  are interconnected (transitive-closure work), `DemoScene` is live in DEBUG #Previews.

Still open (medium tier): V2.1 hist pass double-walks the crop box per tick (fold into the
box-average pass); `LUTFile.makeShareItem` main-actor hitch on the Review screen; per-burst
`os.Logger` debug line per frame; the H1 deep cut (fuse conversion+pool into one pass).

### 6.1 Round 2 (same day, later): LUT deprecation + troubleshooting logs + churn

- **LUT export DEPRECATED** (Daniel's call): new `Feature.lutExport = false` gates the
  EXPORT LUT button in `PhaseField` — the main-actor 65³ `build_cube` hitch is statically
  unreachable. `LUTFile` + kernels stay compiled and golden-gated (gate, don't delete).
- **Troubleshooting logs (aggregate, never per-tick):** `[perf] yin-yang tick CPU` — per-burst
  mean/max ms of the delegate-queue ladder tick vs the 50 ms budget, logged once at finishBurst
  (the first number to read when frames drop); `[tick] LATE frame` — per-frame timing log
  replaced by anomaly-only (gap ≥ 1.5× target period), the routine cadence lives in the burst
  summary; `[perf] texture pool miss #N` — healthy = 2–3 at warmup then silence, climbing =
  leaked sets or in-flight depth > cap. Existing V2.1 field/flow + θ_up + band-head logs unchanged.
- **`ColorHead` t-band churn:** `[[Int64]]` → flat stride-4 `[Int64]` (bias synthesized at drain):
  no more 1024 heap arrays per pair-tick, cap drop is one memmove; capacity reserved at init.
  Behavior pinned by `YinYangCircuitTests` (green).

### 6.2 Round 3: H2 — the hist buffer halved (768 → 384 MiB)

The V2.1 burst histogram buffer's counts are now **u16** end-to-end (was i32): both Metal
kernels (`v21AccumulateHist`/`Soft` — no atomics needed, one thread owns its cells, so the
narrow type is free), `makeV21HistBuffer` (+ a `[perf]` MiB log at allocation), `poolV21Counts`
and `encodeV21Flow` (widen u16 → Int32 at the read; the exact-integer transport domain is
unchanged), and `V21MetalParityTests` (green on the sim GPU). Capacity proof: a cell holds
≤ scale²·wBudget = scale²·16, inside u16 for every scale ≤ 63 (4K crop = scale 33 → 17,424);
`submitAsync` GUARDS scale > 63 (8K-class, no shipping format) — skips the pass and logs
`[perf] v21 hist SKIPPED` once instead of accumulating corrupt counts. The 19 s detached-encode
hold still exists but now pins half the RSS; H2's remaining half is shortening that hold.
