# DEVICE MODEL MAP: memory ledger, on-device model census, colour seam, 20fps sync, S/K/I comp packets

> Status: LIVING · Created: 2026-07-02 · Owner: SixFour
> Companions: `docs/V3-BUILD-WORKFLOW.md`, `docs/LAUNCH-BUILD-WORKFLOW.md`, `SIXFOUR-MODEL.md`.
> Spec wins on any disagreement. Every anchor below is `file:line` verified against source
> at HEAD c2cf8d4 unless tagged UNVERIFIED. Flags read live from `Feature.swift`
> (`v21Capture = true`, `v3SomaticTrain = true`, `globalPaletteV2 = false`).

## Verdict first

1. **Peak RSS is dominated by one buffer.** `v21HistBuffer` is 768 MiB (0.75 GiB) and is
   pinned ~19 s past burst end by the detached flow encode. One capture cycle momentary
   peak is ~1.0-1.2 GB at 1080p-class format; two overlapping flow encodes would be ~1.8 GB,
   and the `flowJobActive` skip (`CaptureSession.swift:60-64`) is the only jetsam guard.
2. **One live on-device learner:** the 21-param somatic θ_up SIMT trainer runs for EVERY
   burst (`CaptureSession.swift:792-794`). Everything else learned is DORMANT or UNBUILT.
3. **Colour seam is honored in the Zig core and Metal interior, but leaks in four places.**
   The designed contract is Lab-model-over-sRGB8-GIF-carrier (Opt-1 sRGB8-canonical); the
   real defect is a live linear/gamma fork inside the V2.1 field tensor.
4. **20 fps is synced by convention, not by construction.** Display 20 Hz comes from the
   spec; the GIF 5 cs delay is a hardcoded literal in three independent places. Changing one
   compiles clean against the other.
5. **The S/K/I structure is real but unmapped.** I-boundaries (lift/unlift, gif assemble,
   transport+disp) are free replayable fault seams; K commits destroy info; the single S
   site (θ_up mint) needs a weight blob. No `Spec.SkiLedger` exists yet.

---

## 1. MEMORY PIPELINE: the end-to-end buffer ledger

Shape constants: T=64 frames, side=64, K=256, nLevels=256, Q16 = Int32<<16
(`Native/src/kernels.zig:63-67`).

### 1.1 Buffer ledger

| Buffer | Type | Size math | Alloc site | Lifetime | Copies |
|---|---|---|---|---|---|
| A1 CVPixelBuffer pool | x420 10-bit biplanar YCbCr | 720p ~2.7 MB/buf, 1080p ~6.2 MB/buf, ~3-6 bufs | OS pool, `CaptureSession.swift:338-455` | per-frame, AVF-owned | n/a |
| A2 CVMetalTexture | r16Unorm + rg16Unorm | 0 bytes (zero-copy wrap of A1) | `TextureCache.swift:39-62` | per-frame | 0 |
| A3 Tile intermediates | 3× RGBA16F 64×64 | 3×32 KiB (2 private + 1 shared) | `Pipeline.swift:148,215-233` PER submitAsync | per-call | 64 allocs/burst, no pool (churn) |
| A4 Readback | halfPixels SIMD4<Float16> → pixels SIMD3<Float> | 32 KiB → 64 KiB | `Pipeline.swift:409-434` | transient | f16→f32 + stride-16 pad, ~75% waste |
| A5 OKLabTile burst | [OKLabTile] | 64×64 KiB = 4 MiB | `CaptureSession.swift:33,639-641,929` | per-capture COW | 1 storage / 4 refs |
| **A6 v21HistBuffer ★HOTSPOT** | Int32 shared MTLBuffer | 64·64²·3·256 = 201,326,592 el ×4B = **768 MiB** | alloc `CaptureSession.swift:649-651`, use `Pipeline.swift:267-271` | per-burst, EXTENDED ~19 s by detached flow encode | GPU soft-splat per frame same cmd buf |
| B1 poolV21Counts | [Int32] | 4096·3·256 = 12 MiB | `Pipeline.swift:276-285` | COW into V21FieldData | 1 storage |
| B2 Flow encode (detached) | anchor + per-frame slice + disp | anchor 12 MiB + 64× 12 MiB slice COPY + disp 95 MiB(720p)/192 MiB(1080p)/frame | `Pipeline.swift:305,314`; mass `Pipeline.swift:67` | 19 s, retained anchor 12 MiB | per-frame slice `Array(UnsafeBufferPointer)` copies (churn) |
| B3 CaptureGene (v3SomaticTrain) | volume + GPU buffers | volume 3 MiB + blocks 1 MiB + pairs 1 MiB + scratch 1.25 MiB + theta/committed/loss bytes | `CaptureGene.swift:45`, `RungDispatch.swift:247-282` | per-capture, freed on return | ThetaUp 84 B retained |
| C1 q16Frames | 64× [Int32]4096·3 | 3 MiB | `DeterministicRenderer.swift:103` | per-render | 2nd float→int copy of tiles |
| C2 centroidsPerFrame | Int32 | 64×256·3·4B = 192 KiB | `SixFourNative.swift:144-154` | per-render | n/a |
| C3 quantIndices + indices | UInt8 | 2× 64×4096 = 512 KiB | `:145,161` | per-render | n/a |
| C4 kernel scratches | quantize ~40 KiB, dither 48 KiB | malloc/free PER FRAME ×64 | `SixFourNative.swift:165-166,205-206` | per-frame | churn |
| C5 STBN mask | UInt8 | 64×4096 = 256 KiB (from 512 B 8³) | `STBN3DContract.swift:11,28` | blue-noise mode | tiled |
| C6 StagePartial stream | flatten | 256 KiB ×4 stage emissions = 1 MiB | `:131-139` | UI-only | copies to MainActor σ |
| C7 Export replicate | [UInt8] | 64×256² = 4 MiB | `DeterministicRenderer.swift:246-250`, `ExportContract.swift:12-35` | per-export | 1→4×4 index replicate; shipped 256² is fake 64²×4 |
| C8 gifAssemble out | [UInt8] | bound ~8.45 MB | `kernels.zig:74-91`, `SixFourNative.swift:547-549` | per-export | `Data(out[0..outLen])` SECOND copy `:565` |
| D1 GIF file | file | Documents/sixfour_<ISO>.gif | `CaptureViewModel.swift:745` | app-lifetime, **NO GC** | files accumulate forever |
| D3 CaptureBundle | JSON | 64 tiles as JSON floats → est. 8-15 MB text | `CaptureBundle.swift:79-103` | overwrite, reparsed EVERY bootstrap | heaviest disk inflation (doc's "~4 MB" `:94` assumes binary) |
| D5 V21 AirDrop export | .npy + maps.bin | field 12 MiB (+12 MiB Data copy) + contested 48 KiB + anchor 12 MiB | `V21CaptureField.swift:79-364` | per-export transient | n/a |
| E3 FieldMetalView drawables | BGRA8 | 3× screen ≈ 3×12.6 = ~38 MiB, maxDrawable=3 | `FieldMetalView.swift:302` | OS pool | tileBuffer 4096 B pooled once `:356-360` |
| F1 θ_up somatic gene | 21 Float | 84 B + 7 Int committed | `CaptureGene.swift:18-33` | rides σ.thetaUp | n/a |
| F2 θ_B | 63-param forward | bytes-scale | `MaskedBandForward.swift`, CLAUDE.md:111-112 | n/a | n/a |
| F3 DeviceTrainer MPSGraph | placeholders [N,3]+[N,7] fp32 | small | `DeviceTrainer.swift:144-210` | self-check only | NOT on capture path |
| F4 NetSynth256 | 0 weights | n/a | `NetSynth256.swift:15` | identity on floor | n/a |
| F5 FrameBuffer actor | n/a | n/a | `Capture/FrameBuffer.swift:5` | ORPHAN, 0 callers | n/a |

### 1.2 Peak-RSS estimate (one capture cycle, flags ON, 1080p-class)

```
baseline app+SwiftUI+AVF pool+Metal        ~150-250 MB
v21HistBuffer (pinned through flow encode)  768 MiB
flow transients (anchor+slice+disp)         ~120-220 MB momentary
render+tiles+export+somatic (A5,C1-C8,B3)   ~30 MB
≈ 1.0-1.2 GB momentary peak during the burst-end overlap window (B4)
steady-state post-capture ~200-300 MB
Without Feature.v21Capture: peak ~200-300 MB
Two overlapping flow encodes ≈ 1.8 GB → flowJobActive skip is the jetsam guard
                                        (CaptureSession.swift:60-64,770-772)
```

### 1.3 Redundant-copy / churn findings (ranked)

1. **B2 per-frame slice Array copies:** 64× 12 MiB alloc/free inside a 19 s loop while
   768 MiB is pinned (`Pipeline.swift:314`). The inline doc says "reads IN PLACE" but
   `Array(UnsafeBufferPointer)` COPIES each slice.
2. **D3 CaptureBundle JSON:** float tiles as text, rewritten per capture, reparsed per
   launch off-main (`CaptureViewModel.swift:352-355`).
3. **A4/C1 quadruple representation of one tile:** f16 texture → f16 array → f32 SIMD3
   stride-16 → Int32 Q16, ~4 copies of the same 4096 px.
4. **C8 GIF bound buffer** 8.45 MB → `Data` slice copy (could write into `Data` directly).
5. **A3 per-frame texture allocation** (no heap/pool); **C4 per-frame scratch mallocs**.
6. **D1 unbounded GIF accumulation** in Documents (no `removeItem` anywhere).

---

## 2. ON-DEVICE MODEL MAP: every learned object

Contract governing everything: CLAUDE.md:29-43 (Tier-2 = zero third-party deps; on-device
NN = hand-written forward loading MLX-trained plain blob; "Never `mlx-swift`. Never a CoreML
black box"), CLAUDE.md:96-104 (train spine: base MLX on Mac, on-device per-user MPSGraph,
sim-gate via `targetEnvironment(simulator)`). **Violation scan clean:** no `import MLX` /
`import CoreML` / `import CoreAI` in `SixFour/` (grep); CoreAI seam DELETED 2026-06-26
(CLAUDE.md:70-73). Only planned resurrection risk is `docs/V21-HJEPA-COREAI-WORKFLOW.md`
(roadmap, not code).

| Object | Params | Precision | Weights from | Train/Infer | Status | Anchor |
|---|---|---|---|---|---|---|
| θ_up somatic (SIMT Metal) | 21 | fp32 desc / Q16 commit | trained per capture ON DEVICE | both | **BUILT+WIRED** | `CaptureSession.swift:792-794` |
| θ_up MPSGraph backend | 21 | fp32 | on device | train | BUILT+DORMANT (golden only, sim-excluded) | `DeviceTrainer.swift:125-273` |
| Frozen lift / tokenizer | 0 | int32 Q16 | none, frozen by law | infer | **BUILT+WIRED** (Zig+Swift+Metal twins) | `SixFourNative.swift:266-304`, `DeviceTrainShaders.metal:90,99` |
| θ_B masked band | 63 | Double→Q16 | fixed fixture (MLX blob UNBUILT) | infer | BUILT+DORMANT (tests only, no prod caller) | `MaskedBandForward.swift:20-67` |
| NetSynth256 | 0 loaded | n/a | UNBUILT | infer | BUILT+DORMANT scaffold (returns floor) | `NetSynth256.swift:12-25` |
| MetricOrgan | ≤9 | fp32 JSON | Mac | infer | BUILT+DORMANT (no setter; `refinementMetric = nil`) | `MetricOrgan.swift:7-41` |
| AtlasTrainer / value-pref | 29,249 | fp32 | on device | train | DELETED 1e0837b; resurrection PLANNED | gone; precedent CLAUDE.md:99-104 |
| σ-look genome | 384 | Q16 | curated | infer | DORMANT (`globalPaletteV2 = false`) | `Feature.swift:21` |
| Context MLP up-rung | ~6K | fp32 | Mac/device | mixed | UNBUILT | V3 doc:59 |
| 9-θ cell conditioner | 9 | fp32 | device | train | UNBUILT | V3 doc:60,80 |
| Temporal rung MLP | 5,772 | fp32 | device | train | UNBUILT | V3 doc:61,81 |
| Preference head (Bradley-Terry) | tiny | fp32 | device | train | UNBUILT (needs Atlas resurrection) | V3 doc:62,84 |
| V3 field encoder | ≤1M | fp32→quantized | Mac MLX | infer | UNBUILT both sides | V3 doc:58,83 |

### 2.1 The one live learner (θ_up somatic, V3 B2.4)

Runs at `finishBurst` for EVERY burst, gated `Feature.v3SomaticTrain = true`
(`Feature.swift:45`). Factory `CaptureGene.train(tiles:)` (`CaptureGene.swift:62-82`): burst
OKLab float tiles → Q16 int32 volume (round-half-to-even ×2¹⁶, the single sanctioned
float→device crossing, `CaptureGene.swift:45-56`) → `RungDispatch.trainOnVolume`
(`:203-220`). ONE command buffer: `captureOctantsKernel` (`DeviceTrainShaders.metal:264`) →
`deviceTrainSimtKernel` (`:317`, 256-thread single threadgroup, fixed-order tree-reduced
mean-gradient fp32 SGD, bitwise-reproducible) → Q16 commit. 21 params (7 bands × φ=[1,ṽ,ṽ²]);
η=0.2, 600 steps (`DeviceTrainGolden.swift:12-13`); ~200 ms for 32,768 pairs (V3 doc:146-147).
Supervision manufactured by the exact lift on device, no corpus crosses to the phone
(`DeviceTrainer.swift:9-13`). Sim-gating NONE needed (plain Metal runs in simulator,
`RungDispatch.swift:11-13`). Physical-device run on a REAL burst still unvalidated
(V3 doc:155-156, UNVERIFIED on hardware). Output `CaptureGene.ThetaUp` on
`BurstResult.thetaUp` (`CaptureSession.swift:125`); absence == deterministic floor.

Inference of the trained gene: `OctantCube.expandProposal` (`OctantCube.swift:92`, CPU up-rung
gated vs Zig `s4_octant_lift`) in Decide preview (`DecideSurface.swift:87-102`); curate/export
ladder via GPU `cubeExpandRungKernel` (`DeviceTrainShaders.metal:124`) with the cascade
sandwich (θ float layer committed OUTSIDE the kernel via `DeviceTrainStepCPU.predictCommitted`,
`CurateBuilder.swift:37-41`, only integers enter the dispatch).

### 2.2 Fold rule and unbuilt frontier

A gene trains inside the rung dispatch iff weights+grads fit the 32 KiB threadgroup
(V3 doc:98-101); measured SIMT working set 21.6 KiB (V3 doc:135). B3 go/no-go
(`lawAboveFloorMarginMeasured`, does adapted θ_up beat floor on held-out cells) NOT YET RUN
(V3 doc:159-161, UNVERIFIED). `docs/MODEL-BUILD-WORKFLOW.md` W2.2 "paint tool next" is STALE:
`NudgePaintView.swift` exists and V3 training is already wired.

---

## 3. COLOUR SEAM VERDICT

The designed contract is **Lab-model-over-sRGB8-GIF-carrier (Opt-1 sRGB8-canonical):** the
model interior is OKLab Q16 Latent→Latent, and the GIF wire carrier is canonical sRGB8. sRGB
is meant to appear ONLY at `encodeBoundary` (camera/linear → OKLab) and `decodeBoundary`
(OKLab → sRGB8 GIF bytes). Interior kernels must never touch sRGB.

**Verdict: the device honors "interior = Latent→Latent" in the Zig core and Metal interior
kernels, and every sRGB touchpoint it KNOWS about is at a boundary. It fails the seam law in
four ways.**

### 3.1 What HOLDS
- Zig interior fully Latent→Latent: no kernel between `s4_linear_to_oklab_q16`
  (`kernels.zig:305`) and `s4_palette_oklab_to_srgb8` (`kernels.zig:1685`) touches sRGB
  (quantize `:344`, dither `:1519`, Haar `:1036`, board `:1162`, transport, energy `:3146`
  all consume oklab_q16 or counts).
- On-device training operates on OKLab Q16 volumes only (`CaptureGene.swift:35-39`,
  `RungDispatch.swift:199`, `DeviceTrainShaders.metal:251`).
- Q16 gamma decodeBoundary triple-implemented byte-exact: Zig LUT (`kernels.zig:1685`), Swift
  port (`SurfaceColor.swift:86-108`), spec golden (`color_fixture_test.zig:28-82`).
- Single display conversion site with explicit `.sRGB` (`PixelGrid.swift:24`); HLG path
  documents and avoids double-gamma (`Shaders.metal:37-41`); Look/LUT export boundary-perfect
  and integer-exact end to end (`kernels.zig:2698-2721`).

### 3.2 Violations (most severe first)

1. **V2.1 field: two sources, two colour encodings, one tensor format (LIVE fork).** GPU
   `camera_box` deposits **linear-sRGB** levels (`Shaders.metal:319-321`, comment `:234`
   "V2.1 is sRGB-native, NO OKLab"); the fallback `temporal_proxy` counts **gamma sRGB8** GIF
   palette bytes (`V21CaptureField.swift:44-48` reads `pal[idx]`). Same `[y,x,3,level]` npy,
   distinguished only by manifest `field_source` (`V21CaptureField.swift:62-68`). The spec
   seam (`V21Field.hs:13-14`, "collapse == the sRGB byte the boundary consumes") holds ONLY
   for temporal_proxy; for camera_box the level axis is a different (linear) alphabet. Any
   consumer comparing field argmin to GIF bytes is comparing gamma to linear.
2. **Shipped-path duplicate float Lab→sRGB8.** `GIFRenderer` emits colour tables via FLOAT
   `ColorScience.okLabToSRGB8` (`GIFRenderer.swift:167`, pow-based, not the gamma LUT). Live:
   silent fallback whenever the deterministic core throws, and primary when
   `settings.useDeterministicCore` is false (`CaptureViewModel.swift:628-652`). Same OKLab
   centroid can round to different sRGB8 bytes vs the Zig LUT path. Not gamma-twice: a
   divergent double implementation at the decodeBoundary.
3. **The fixed-point encodeBoundary is bypassed on device.** Shipped chain: Metal FLOAT
   linearize + FLOAT OKLab (`Shaders.metal:6-104`) → Swift float→Q16 rounding
   (`SixFourNative.swift:147-155`) → Zig integer core. Zig's own golden-gated
   `s4_linear_to_oklab_q16` and single-call `s4_burst_to_gif` (`kernels.zig:157-239`) have
   ZERO Swift caller (grep). Byte-determinism begins only AFTER GPU float OKLab.
4. **`contractQ16NotRecoverableAcrossGif` has no device counterpart.** Grep hits only spec/
   (`CaptureFormat.hs:150`). `CaptureFormatContract.swift` is index-domain only. Device does
   the right thing by convention (`Surface.swift:193-215` re-derives Q16 via canonical Zig
   `srgb8ToOklab`) but nothing device-side asserts or type-brands re-derived Q16 ≠ original.

Minor / dormant: import decodeBoundary UNBUILT (`s4_gif_decode` `kernels.zig:2117` has no
Swift caller); UI-only interior-in-gamma ops (`CellMechanicsContract.swift:115-122` tint lerp,
`V21FieldView.swift:72-77` level rescale, self-declared diagnostic). `PaletteCollapse.swift:161`
+ `LadderGIF.swift:87-90` float Lab→sRGB8 into a GIFB table are on the V2-deferred global path
(dormant, but would repeat violation 2 if `globalPaletteV2` flips).

**No Lab→sRGB→Lab double conversion on the shipped hot path; no gamma-applied-twice found;
one gamma-never (camera_box levels).**

---

## 4. 20FPS SYNC + INTERACTION

### 4.1 GIF GCE delay → display cadence chain

**Write side (Zig):** per-frame GCE `s4_gif_assemble` writes `{0x21,0xF9,0x04,0x04}` +
u16 LE centiseconds, disposal=1 (`kernels.zig:1914-1917`); param `frame_delay_cs`
(`kernels.zig:1867`); fixture pins 5 cs = 20 fps (`gif_fixture_test.zig:78`). Swift callers
hardcode the literal `delayCs: 5` at both `DeterministicRenderer.swift:253,466`; the Swift twin
`GIFEncoder.swift:44-49` derives `cs = max(1, 100/fps)` with default `fps: 20`. Spec twin
`GifWire.hs:61-64` parameterizes fps, no constant pins 20.

**Display side (Swift):** ONE clock, a single `CADisplayLink` with
`preferredFrameRateRange` min=max=preferred=`SixFourDisplay.logicRateHz`
(`SurfaceClock.swift:51-55`); every Timer/TimelineView removed. Rate is GENERATED from spec:
`DisplayContract.swift:13 logicRateHz = 20` (spec `Display.hs`, theorems T1-T9). ProMotion
divisibility is a PINNED invariant: `panelRates = [60,120]` `:21`, `holdCounts = [3,6]` `:23`,
`selfCheck()` `:47-52` asserts `panelRates[i] % logicRateHz == 0`. **So 3 vsyncs/GIF-frame at
60 Hz, 6 at 120 Hz, exact integer holds, zero beat-frequency drift BY CONSTRUCTION** (20
divides both). Tick → frame index: `advanceCursor()` = `SixFourPlaybackClock.frameAfter(cursor,
count: 64)` (`Surface.swift:126-129`, spec-pinned Z₆₄).

**Is display rate derived from the GIF delay? NO. SYNCED BY CONVENTION, NOT CONSTRUCTION.**
Display 20 Hz comes from `Spec.Display`; the GIF 5 cs comes from a hardcoded literal in three
independent places; no code references `logicRateHz` when choosing the delay (grep: zero hits
in `Encoder/` or `Native/`). Changing one side compiles clean against the other. The 100/20=5
identity holds today in 4 places by human convention only. **Drift risk is cross-file, not a
ProMotion beat-frequency risk** (that is closed by construction). Capture side also pinned to
20 (`captureRateHz = 20`, `DisplayContract.swift:15`). Live camera preview is NOT on this clock
(its own ~10 fps, `LivePhaseField.swift:115`).

### 4.2 Per-tick playback cost
Review tile: `CapturedReviewPhaseField` re-evaluates each κ tick → `CellSprite` →
`CellBitmap.image` (`CellSprite.swift:15-57`) allocates a fresh 64×64×4 = 16 KB `[UInt8]` +
CGContext + CGImage + UIImage EVERY 50 ms. 20 UIImages/s heap churn is the steady playback
cost, CPU bake, no texture reuse. The GPU ground `FieldMetalView` is better: 4096 B tile
through a POOLED MTLBuffer, memcpy per draw (`FieldMetalView.swift:355-361`).

### 4.3 Draw-mechanic path (NudgePaintView, 16³×9 CellBudget)
`DragGesture(minimumDistance: 0).onChanged` (`NudgePaintView.swift:163-171`): pixel→cell,
bounds guard, `model.paint(x,y,z,channel,value)` → `mortonIndex` (12 bitops, 4-bit/axis) →
`budget[cell][channel] = max(0,value)` → `objectWillChange.send()`. **Double-invalidation bug:**
writing `@Published var budget` already fires `objectWillChange`; the explicit `.send()` at
`:70` fires it TWICE per touch-move (same in `reset()` `:74`). Per touch-move recompute: whole
16×16=256 `NudgeCellView` rebuilt; header `paintedCellCount` `:77` scans 4096 cells × 9-channel
`contains`. No CGImage (pure SwiftUI diffing, value-type churn). No early-out for unchanged
value. NudgePaintView renders NUDGE FIELD ONLY; live invented preview UNBUILT until
`Upscale256` floor + weights land (`:15-18`). Live consumer `DecidePaintWidget`
(`DecideSurface.swift:326-372`) shares `NudgePaintModel.paint`, underpaints via
`model.proposalSRGB8` (256 cells × `ModelRender.displaySRGB8`/invalidation); reconstruction is
built ONCE off-main (`buildReconstructions` `:84-108`, cached), NOT per stroke.

### 4.4 Swipe-scrub paths (gesture → frame index → render)
- **Path A, Decide preview scrub** (`DecideSurface.swift:252-297`): `onChanged` sets
  `model.frame = Int(x/width * tiles.count)`. Per touch-move: `reconstructionSlice` fresh
  64×64×4 = 16 KB + 4096 `displaySRGB8`, `rgbaImage` `Data(rgba)` COPY + CGImage. **~32 KB
  fresh heap + one CGImage per event, up to 120 Hz on ProMotion, NO frame-bucket caching**
  (recomputed even when the drag stays in one frame). Side effect: drives `paintLayer` so the
  paint grid z-slice + `DecidePaintWidget` re-derive too.
- **Path B, Curate hero scrub** (`CurateSurface.swift:243-249`): same shape, 16 KB rgba +
  4096 `displaySRGB8` + Data copy + CGImage per touch-move. Volume cached once.
- **Path C, Review playback** is NOT swipe-driven (no DragGesture; frame from κ only).
- **Path D, LOOK swipe on live** (`LivePhaseField.swift:97-107`): one swipe = one discrete
  look step + haptic, re-grades palette only, index tile untouched.

Cross-cutting: every `CellSprite` consumer re-bakes UIImage+CGImage per invalidation; only
`FieldMetalView` uses a pooled GPU buffer; all interactive scrub/paint surfaces are CPU CGImage
pipelines with per-event allocation. Per-touch-event haptics already treated as a hazard and
replaced with a frame-locked detent (`CellDetent.swift:14`).

---

## 5. S/K/I LATENT-OP LEDGER + COMP PACKETS

### 5.1 The reading (spec anchors)
S=expand/invent, K=contract/pool, I=reversible floor; "S barred on the floor" DERIVED from
linearity=bijection (`V2-SKI-EXPAND-CONTRACT.md:13-33`). Referents: K=`scalarCollapseLossy`
(`OctreeCell.hs:235-236`), I=`unliftOct.liftOct==id` (`OctreeCell.hs:203`), S=`liftKeyed`
(`PairedResidual.hs:90`). K-with-a-receipt = `octantDistill` (`V2-SKI-EXPAND-CONTRACT.md:54`).
Ring: no field, no recip, `unitInverse` partial (`RefinementSystem.hs:5-13`); detail = A7 root
lattice (`RootLatticeDetail.hs:3-5`). /3 blocker: index-3 sublattice Λ={l≡a+b mod 3}, det M=3,
exact inverse on Λ (`V2-SKI-PONDER-DIGEST.md:37-39`), **NOT-FOUND in any Zig/Metal kernel**.
Float→int law: `reenterQ16` idempotent retraction (`RingReduction.hs:3`).

### 5.2 Division-site census (`Native/src/kernels.zig`)
- **/2 dyadic floor-div** (the ONLY division on the reversible floor, reversible because high
  band carried): sLift64/sUnlift64 `:766-771`; Metal twin `fdiv2` `DeviceTrainShaders.metal:24-28`
  (explicit floor, NOT C truncation).
- **/2¹⁶ truncating** (boundary K, remainder discarded): OKLab matmuls `:315-323,:1703-1711`;
  cube `:1674`.
- **/n non-unit** (genuine K weakening): Lloyd means `:377-379,:444-446`; zone means `:1607`;
  cell std isqrt `:1639`; board mass `:1146`; dither `:1435,:1485`.
- **/3: ZERO sites in device code.** `s4_v21_opponent_delta` is forward-only integer-linear
  (L=R+G+B, a=R−G, b=R+G−2B, NO division, `:3123-3134`); inverse needs /3 and is UNBUILT (the Λ
  hazard, dodged by never inverting on device).
- **Totality wall:** SUBSTRATE_BOUND B=2²⁹−1, quad worst case 4B tight (`:96-109`); every
  kernel refuses `RC_OUT_OF_RANGE` instead of wrapping.

### 5.3 The ledger (kernel → S/K/I → exactness → division → checkpoint class)
Legend: EXACT=byte-exact golden-gated integer; DET=deterministic lossy; FLOAT=not cross-device
bit-exact. CKPT: I=replayable boundary, K=commit point, S=needs θ blob.

| Kernel (file:line) | S/K/I | exact | division | CKPT |
|---|---|---|---|---|
| s4_octant_lift/_unlift (`:857/887`) | I pair (floor unit) | EXACT | /2 floor | I |
| s4_rgbt_lift/_unlift_quad (`:816/836`) | I pair | EXACT | /2 floor | I |
| s4_cube_lift/_unlift_level (`:973/1012`) | I pair (K-with-receipt view) | EXACT | /2 floor | I |
| s4_haar_analyze/_reconstruct (`:595/649`) | I pair | EXACT | /2 floor | I |
| s4_haar_split/_join_level (`:1044/1076`) | I pair (temporal) | EXACT | /2 floor | I |
| s4_cube_expand_rung (`:924`) | I / **S-SITE** if details from θ_up / floor-I if null | EXACT (float θ stays outside, sandwich) | /2 floor | I if logged, S if θ-minted |
| s4_quantize_frame (`:343`) | **K** (p→k pool) | DET | /n Lloyd | K commit |
| s4_dither_frame (`:1395`) | **K** (Q16→index) | DET | /16,/8,/denom trunc | K commit |
| s4_significance_fill (`:1518`) | **K** (rebalance) | DET | /n, isqrt | K commit |
| s4_leaf_override (`:1270`) | **S_dup** (taste channel) | EXACT | none | S (log δ) |
| s4_linear_to_oklab_q16 (`:305`) | boundary K | DET golden, not invertible | /2¹⁶ trunc | K edge |
| s4_palette_oklab_to_srgb8 (`:1685`) | boundary K | DET golden | /2¹⁶,/2³² | K commit (GIF bytes) |
| s4_srgb8_to_oklab_q16 (`:1962`) | boundary (lossy inverse) | DET | /2¹⁶ | re-entry |
| s4_gif_assemble/_decode (`:1861/2122`) | I pair at byte tier (LZW lossless) | EXACT | none | I |
| s4_v21_collapse (`:2878`) | **K par excellence** (argmin curve→byte) | EXACT (order-only) | none | K commit |
| s4_v21_transport/_pushforward (`:2913/2971`) | **I pair** (1-D OT, negate disp = inverse) | EXACT, equal-mass guarded | none | I (disp = the packet) |
| s4_v21_counts_to_energy (`:3146`) | I (affine, total recoverable) | EXACT | none | I |
| s4_v21_opponent_delta (`:3110`) | I-forward, inverse UNBUILT (/3 Λ hazard) | EXACT fwd | none (÷3 avoided) | fwd-only |
| s4_v21_accumulate_hist/_soft (`:3178/3373`) | **K** pool (soft keeps 1st moment receipt) | EXACT int | /box floor | K |
| deviceTrainFused/SimtKernel (`DeviceTrainShaders.metal:191/317`) | **S** (mints θ_up 21p) sandwich [int lift I]→[fp32 GD]→[Q16 commit] | int EXACT; GD FLOAT but order-pinned ⇒ bitwise-repro; gate = post-commit bytes | n/a | S (log θ hash) |
| kmeansSeed/Assign/Finalize (`Shaders.metal:523-685`) | **K** family | FLOAT, NOT bit-exact (atomics) | n/a | UN-checkpointable, gate at Zig oracle |
| v21AccumulateHistKernel (`Shaders.metal:269`) | K pool, integer twin of Zig | EXACT int (Metal==Zig==Haskell) | n/a | K |

### 5.4 Safe fault/checkpoint boundaries
- **I (safe replayable packet seams):** octant/RGBT/cube/haar lift-unlift pairs,
  cube_expand_rung with logged details, gif_assemble/decode, v21 transport+disp,
  counts_to_energy, mode_relative+anchor_at pair. Fault localization is free: round-trip
  (unlift∘lift==id) is a self-test per packet; `RC_*` totality codes name the failing kernel.
- **K (commit points, info destroyed, need checkpoint input or receipt):** quantize_frame,
  dither_frame, significance_fill, v21_collapse, accumulate_hist, board mass, colour-boundary
  maps. Receipts that upgrade K→reversible exist in-kind (octantDistill detail channel, GIF
  byte as anchor receipt, soft-splat first moment).
- **S (need θ blob hash in the ledger entry):** deviceTrainFused/Simt, cube_expand_rung's
  θ-minted details, leaf_override's δ. Determinism = SIMT fixed-order reduction + rint commit;
  gate is always post-commit bytes.
- **Un-checkpointable today:** Metal kmeans/blueNoise/crop float path (atomic-order
  nondeterminism), treat the whole GPU preview as ONE opaque packet gated by the Zig oracle at
  the palette boundary.

### 5.5 Packets of allowable comp (proposal)

Define a **comp packet** as a contiguous run of kernels bounded on both ends by an I-seam or a
K-commit, with a fixed per-packet compute budget. The ledger yields a natural packetization:

| Packet | Boundary in → out | Class | Budget basis | Fault policy |
|---|---|---|---|---|
| P0 GPU-preview | camera texture → palette bytes | opaque K (kmeans float) | wall-clock only, statistical parity | no fault replay; gate at Zig oracle |
| P1 encodeBoundary | linear-sRGB half → OKLab Q16 | boundary K | bytes moved (4 MiB tile) | replay from A5 tiles |
| P2 quantize+dither | q16Frames → indices | K∘K commit | per-frame FLOP budget ×64 | checkpoint input = q16Frames (C1) |
| P3 lift/unlift ladder | cube ↔ octant bands | I | /2 op count, RC guard | **fault allowed, round-trip self-test** |
| P4 θ_up mint (SIMT) | volume → 21 θ + commit bytes | S | 21.6 KiB working set, 600 steps | checkpoint = θ hash + post-commit bytes |
| P5 v21 flow | counts → anchor + disp maps | I | mass budget (`Pipeline.swift:67`) | **fault allowed, negate-disp inverse** |
| P6 assemble | indices+palettes → GIF bytes | I (LZW) | out bound 8.45 MB | replayable from indices |

**Enforcement:** wrap each packet in an `os_signpost` interval (Section 6) and a
`MTL4CounterHeap.timestamp` pair (iOS 26, `writeTimestampIntoHeap` / `resolveCounterHeap`, GPU
Counters docs; legacy `MTLCounterSampleBuffer` for non-MTL4 buffers). Per-packet budget = a
hard cap on the resolved GPU-time delta plus a byte-moved ceiling; a packet that overruns its
budget is logged with its packet id. **Faulting is allowed ONLY at I-boundaries (P3, P5, P6):**
a fault there re-runs the packet from its logged input, verified by the round-trip self-test.
K-commits (P2) and the S mint (P4) cannot be faulted-and-replayed for free: they need their
checkpoint input (P2: q16Frames) or their θ-blob hash (P4) recorded first. P0 is a single
opaque non-replayable packet.

---

## 6. LOGGING PLAN

Minimal `os_signpost` + `Logger` scheme keyed to the S/K/I packet boundaries so every fault is
attributable to ONE packet. Rationale: `os_signpost` intervals line up with Metal System Trace
on one Instruments timeline (min/max/avg/σ per interval), and pair cleanly with GPU-counter
timestamps for the budget assertions in 5.5.

```
subsystem = "com.sixfour.device"
categories (one per packet class, so faults sort by S/K/I):
  "packet.I"   : lift/unlift, flow, assemble        (replayable)
  "packet.K"   : quantize, dither, hist, boundary    (commit; log checkpoint input id)
  "packet.S"   : theta_up mint                        (log theta blob hash + commit bytes)
  "packet.P0"  : GPU preview                          (opaque; wall-clock only)

per packet:
  os_signpost(.begin, category, name: "<packetId>", "in=%{public}@ bytes=%d", srcId, nBytes)
  ... encode / dispatch ...
  os_signpost(.end,   category, name: "<packetId>", "rc=%d gpu_us=%d", rcCode, resolvedUs)
```

- Every packet id is stable and matches the ledger (P0–P6). A fault surfaces as an `.end`
  event with `rc != RC_OK`; because the id is one packet, the fault is attributable to exactly
  one kernel run and one S/K/I class.
- **I packets** additionally emit a `roundtrip=%d` field (0/1) from the unlift∘lift self-test,
  so a silent corruption (not an `RC_*`) is still caught at the packet boundary.
- **K packets** log the checkpoint-input buffer id (e.g. q16Frames storage id) so replay can
  find its source; **S packets** log the θ-blob hash + the 7 committed bytes so the mint is
  reproducible.
- The GPU-time field (`gpu_us`) is the resolved `MTL4CounterHeap` delta; a packet over its 5.5
  budget is logged at `Logger.warning` with the same packet id, so budget overruns and faults
  share one attribution key.
- Keep the whole scheme behind a `Feature.signpostPackets` flag (UNBUILT; add alongside the
  existing flags in `Feature.swift`) so it is a zero-cost `os_signpost` no-op in release.

---

## 7. RESEARCH DIGEST

### 7.1 MPS / Metal iOS 26 vs 27
- **iOS 26 (deployment target) already has everything V3 needs:** Metal 4 core + `MTLTensor` +
  `MTL4MachineLearningCommandEncoder` + shader `tensor_ops` (A14+); MPSGraph incl. autodiff +
  optimizers + bf16; 4/8-bit **integer** quantized tensor types; `MTL4CounterHeap` timestamps;
  legacy `MTLCounterSampleBuffer`; ML network debugger; Neural Accelerator auto-use via
  TensorOps on A19-class (framework side iOS-26-era, exact minor version UNVERIFIED)
  ([WWDC26-330](https://developer.apple.com/videos/play/wwdc2026/330/)).
- **iOS 27 / Metal 4.1 buys only:** 4/8-bit FLOATING-point (fp8/fp4) + 2-bit int tensor types;
  FP8 E8M0 block-scale planes / MXFP4; cooperative tensors as direct matmul inputs (no
  threadgroup round-trip); Metal 4.1 MPP tensor path
  ([WWDC26-330](https://developer.apple.com/videos/play/wwdc2026/330/),
  [Rigel arXiv 2606.12765](https://arxiv.org/pdf/2606.12765)).
- **MPSGraph is NOT deprecated but is stagnating** (zero WWDC26 mentions across 330/324/359);
  new investment flows to MTLTensor/TensorOps/Core AI. Formal iOS-27 SDK deprecation
  UNVERIFIED. **Core AI** ships iOS 27 (press; Apple session says only "all Apple Silicon",
  min OS UNVERIFIED), is **inference-only**, positioned as Core ML successor
  ([WWDC26-324](https://developer.apple.com/videos/play/wwdc2026/324/),
  [byteiota](https://byteiota.com/apple-core-ai-replaces-core-ml-ios-27/)).
- **On-device training:** MPSGraph autodiff is the only Apple-framework autodiff on iOS
  (`gradient(of:with:)`, since WWDC20). WWDC26-359 explicitly endorses **hand-rolled
  training for tiny nets** ("a few thousand parameters or less... trained online every few
  frames"; the same TensorOps building blocks do the backprop, no autodiff). This is exactly
  the θ_up SIMT path.
- **Determinism:** no vendor bit-exactness guarantee for MPSGraph or Metal 4 tensor ops
  (UNVERIFIED as a contract). Measured: fixed call = identical bits run-to-run, but
  cross-device/cross-chunking fails via float non-associativity
  ([arXiv 2606.00279](https://arxiv.org/pdf/2606.00279)). **Integer MSL is exact and
  order-independent**, so the byte-exact integer floor in hand-written kernels is deterministic
  by construction. MSL fast-math is ON by default; disable via `MTLMathMode.safe` /
  `-fno-fast-math` / `metal::precise::`. **Ruling: keep the floor in hand-written integer Metal;
  treat MPSGraph/Core AI as the float-above-floor layer only.**
- **Profiling:** `MTL4CounterHeap.timestamp` (iOS 26) for MTL4 packets; legacy
  `MTLCounterSampleBuffer` otherwise; `os_signpost` for CPU-side interval budgets; WWDC26-388
  StateReporting API + Control Center trace capture on iOS.

### 7.2 CNN construction + higher-accuracy model spec (Q16 / QAT / interval bounds)
- **Architecture at 63p–20M for 64³ voxels:** factorized **(2+1)D beats full 3D at fixed
  budget** (halves params/block, doubles nonlinearities, lower train+test loss,
  [R(2+1)D arXiv 1711.11248](https://arxiv.org/pdf/1711.11248)); since Z=time in the GIF voxel,
  2D+t is the literature default. Tiny-regime templates: X3D depthwise/channel-separated
  ([CVPR 2020](https://arxiv.org/pdf/2004.04730)), CSN, MoViNets causal stream buffers.
  **JEPA predictor stays deliberately small/fixed** (V-JEPA 2 holds predictor at ViT-S while
  encoder scales 300M→1B, [arXiv 2506.09985](https://arxiv.org/pdf/2506.09985)); a linear /
  1-layer predictor over pooled latents is defensible: capacity belongs in the encoder.
- **Q16 fixed-point:** canonical inference recipe = Jacob et al. int8 operands, **int32
  accumulator**, rescale via integer multiplier + right shift, QAT recovers accuracy
  ([CVPR 2018](https://openaccess.thecvf.com/content_cvpr_2018/papers/Jacob_Quantization_and_Training_CVPR_2018_paper.pdf)).
  **Accumulator width is a provable budget:** dot product of N a-bit×w-bit terms needs
  ⌈log₂N⌉+a+w bits; **A2Q** constrains the weight L1-norm to guarantee overflow-freedom in
  narrow accumulators ([ICCV 2023](https://arxiv.org/abs/2308.13504)). For Q16 with int64
  accumulation there is 32 bits of log₂N slack; with int32 you must A2Q-bound or pre-shift.
  Integer-only *training* exists (PocketNN via direct feedback alignment,
  [arXiv 2201.02863](https://arxiv.org/pdf/2201.02863)), but fully integer gradients cost a few
  points, and **the "float rides above the Q16 floor" split matches what the literature says is
  safe.** Determinism = impose ONE binary-tree reduction topology everywhere (TBIK,
  [arXiv 2511.17826](https://arxiv.org/html/2511.17826)); matches the SIMT fixed-order rule.
- **Tight spec for accuracy:** golden-vector gating (TFLite reference-kernel-as-spec pattern;
  formalized as "Kernel Contracts" [arXiv 2604.22032](https://arxiv.org/pdf/2604.22032)): this
  IS the Haskell-golden discipline. **Interval bound propagation** pushes input intervals
  through affine+monotone layers (loose, weakens with depth, fine for shallow nets);
  **QA-IBP** does quantization-aware IBP to certify float-vs-fixed divergence layer by layer
  ([AAAI 2023](https://dl.acm.org/doi/10.1609/aaai.v37i12.26747)); tighter option = Bernstein
  bounds (BERN-NN). **Metamorphic relations** (shift/permutation equivariance, palette-gauge
  invariance, additivity of linear stages) become EXACT equalities on an integer floor,
  strictly stronger than the float literature's tolerance tests.
- **Per-layer budgeting:** roofline: latency ≈ FLOPs / min(peak, BW×AI). At 63p–100k params
  everything is **activation-bandwidth-bound** (weights fit in registers/threadgroup), so budget
  **bytes of 64³ activations, not FLOPs**; depthwise/(2+1)D convs have low arithmetic intensity
  (save FLOPs, not necessarily latency). This directly justifies the byte-moved budget basis in
  the comp-packet table (5.5).

### 7.3 MAP-Elites gene-economy mapping
- **Archive = the mint ledger + browse gallery.** MAP-Elites keeps the single highest-fitness
  elite per behavior-descriptor cell (Mouret & Clune 2015,
  [arXiv 1504.04909](https://arxiv.org/abs/1504.04909)); QD *illuminates* the whole trade map
  (coverage + quality), exactly what a "browse the space of looks" catalog wants. CVT-MAP-Elites
  scales to high-D descriptors at fixed cell budget.
- **Descriptor = what makes a gene browsable + valuable.** Start with 2-6 hand-designed
  colour/temporal axes read straight off the exported GIF (mean hue angle, chroma spread,
  luminance contrast, warm-cool balance, palette entropy, temporal flicker), which ties directly to
  the OKLab / V2.1 palette-basis work. Graduate to **AURORA / VQ-Elites** learned descriptors
  from the JEPA embedding so the map self-organizes ([AURORA arXiv 2106.05648](https://arxiv.org/pdf/2106.05648),
  [VQ-Elites arXiv 2504.08057](https://arxiv.org/html/2504.08057v1)); **JEPA energy doubles as
  fitness** (one model supplies both QD signals). A discrete VQ codebook cell-id fits a
  codec-native indexed-GIF-palette app naturally.
- **Swap = island migration.** The **decentralised MAP-Elites for swarms** precedent (Hart/Steyven
  2018, [arXiv 1804.07655](https://arxiv.org/abs/1804.07655)) is most on-point: each robot keeps
  a LOCAL archive and shares with peers it physically contacts, functional diversity emerges
  WITHOUT geographic isolation, exactly the phone-to-phone / AirDrop model. Study its **four
  archive-merge strategies** before fixing the swap protocol; merge policy decides whether the
  economy converges (monoculture) or stays diverse.
- **On-device training = per-island emitter.** Tiny per-capture nets (21p–6K) make full
  **CMA-MAE** affordable on-device ([arXiv 2205.10752](https://arxiv.org/pdf/2205.10752)); if
  palette loss + descriptors are differentiable, **CMA-MEGA/MAEGA** (gradient arborescence) is
  the sample-efficient fast path. `pyribs` = deploy-side reference.
- **Anti-collapse:** learned descriptors drift (AURORA failure mode) and island migration can
  converge the pool. Anneal encoder updates, periodically re-index the archive, and keep a
  **neutral-net stash** of behaviorally-equivalent but genetically-diverse variants beneath each
  elite to bank evolvability. Mirrors the project's own "shared data-manufactured target, no
  co-evolving predictor" anti-collapse stance.
- **The four Hart 2018 merge strategies, read in full (paper: EDQD, GECCO'18,
  [arXiv 1804.07655](https://arxiv.org/abs/1804.07655); code
  [github.com/asteyven/EDQD-GECCO2018](https://github.com/asteyven/EDQD-GECCO2018)).** Setup:
  each robot broadcasts its whole **LocalMap** (a 15x15 MAP-Elites archive) to peers in range;
  receivers stack copies in a **ReceivedMapList**; at end of lifetime each robot condenses that
  list into a **SelectMap** and draws a random genome from it. Merge = cell-wise argmax fitness
  (Algorithm 3), so coverage is monotone non-decreasing by construction. Variants:
  **EDQD-R** SelectMap = ONE random received map (baseline, least spread).
  **EDQD-M1** SelectMap = merge(everything received this lifetime).
  **EDQD-M2** adds a persistent **MemoryMap** merged across ALL generations ever;
  SelectMap = merge(received, memory).
  **EDQD-M3** SelectMap = merge(received, own LocalMap) AND the LocalMap itself absorbs
  received elites, so the robot RE-BROADCASTS others' genes (transitive gossip).
  Findings: all four beat the non-QD baseline (mEDEA), whose diversity DECAYS toward
  monoculture while EDQD diversity RISES over time; R is the weakest variant (random pick
  throttles information spread); M1/M2/M3 tie on diversity (~91-94 unique behaviours vs R's
  ~86); **M3 significantly wins on local-map precision** (opt-in reliability) and M2/M3 win on
  swarm-map precision. The mechanism: merging never deletes a cell, it only upgrades per-cell
  champions, so MORE sharing = more selection pressure on quality with NO diversity cost. The
  monoculture risk lives elsewhere: a single global fitness scalar or drifting learned
  descriptors, not the merge itself.
- **S4GX protocol ruling implied:** adopt M2's persistent MemoryMap on-device (AirDrop contact
  is sparse, so memory across encounters does the work robot density did in the paper), and
  treat M3's re-broadcast as the economy question: transitively re-sharing a received gene is
  what makes quality spread fastest, but it requires provenance (the mint ledger must credit
  the original minter when a re-shared gene lands, or carriage=memehood inflates). Per-cell
  argmax replacement + the neutral-net stash is the anti-monoculture guard.

---

## 8. PRIORITIZED TODOS (dependency-ordered)

1. **Land the θ_up hardware validation** (`lawAboveFloorMarginMeasured`, V3 doc:159-161): run
   the SIMT trainer on a REAL burst on the iPhone 17 Pro and confirm adapted θ_up beats floor on
   held-out cells. UNVERIFIED today; gates every downstream V3 net. (Depends on nothing.)
2. **Fix the V2.1 field colour fork (colour violation 1).** Decide one alphabet for the
   `[y,x,3,level]` tensor: either linearize `temporal_proxy` or gamma-encode `camera_box`, and
   brand the axis. Until then no consumer may compare field argmin to GIF bytes.
   (`Shaders.metal:319-321` vs `V21CaptureField.swift:44-48`.) Blocks any field-encoder training.
3. **Kill the shipped-path float Lab→sRGB8 duplicate (colour violation 2):** route
   `GIFRenderer.swift:167` through the Zig gamma LUT so the fallback render path cannot ship
   divergent bytes. (Depends on nothing; independent of 2.)
4. **Cut the B2 per-frame slice copies** (`Pipeline.swift:314`): read the 768 MiB hist buffer in
   place instead of `Array(UnsafeBufferPointer)` per frame, shrinking the 19 s pinned window's
   transient churn. Top memory win. (Depends on nothing.)
5. **Remove the NudgePaintView double-invalidation** (`NudgePaintView.swift:70,74`): drop the
   redundant `objectWillChange.send()`; add an unchanged-value early-out in `paint`. Cheap
   interaction win. (Depends on nothing.)
6. **Cache scrub renders by frame bucket** (Paths A/B, `DecideSurface.swift:293-297`,
   `CurateSurface.swift:253-261`): skip the 16 KB + CGImage rebuild when the drag stays in one
   frame; the dominant per-gesture cost at 120 Hz. (Depends on nothing.)
7. **Bound the Documents GIF store** (`CaptureViewModel.swift:745`, D1): add a GC / cap; and
   switch CaptureBundle (D3) from JSON floats to a binary tile format. (Depends on nothing.)
8. **Build the packet logging scheme (Section 6)** behind `Feature.signpostPackets`: wrap P0–P6
   in `os_signpost` intervals + `MTL4CounterHeap` timestamps; emit `roundtrip` on I packets.
   (Depends on 1 for meaningful S-packet budgets.)
9. **Author `Spec.SkiLedger`** (File 1 of the SKI build plan, `V2-SKI-EXPAND-CONTRACT.md:146`):
   pin the kernel→S/K/I table + the I/K/S checkpoint classes as a spec contract so the packet
   boundaries are gate-enforced, not doc-only. Then `lawRefineFactorsThroughOctantLift`
   (weight-tying keystone, NOT-FOUND in spec/src). (Depends on 8 for the runtime evidence.)
10. **Add the device-side `contractQ16NotRecoverableAcrossGif` counterpart (colour violation 4):**
    type-brand re-derived Q16 ≠ original in `CaptureFormatContract.swift`. (Depends on 2.)
11. **Wire the import decodeBoundary** (`s4_gif_decode`, `kernels.zig:2117`, no Swift caller):
    needed for the GIF-gene swap economy to re-enter OKLab from wire bytes. (Depends on 10.)
12. **Prototype the MAP-Elites archive (7.3):** 2-6 hand-designed GIF descriptors + `pyribs`
    off-device first, JEPA-embedding descriptors + CMA-MAE per-island later; study Hart 2018
    merge strategies before fixing the AirDrop swap protocol. (Depends on 1, 11.)
