# NOTES — design decisions, session log

> NOTES.md is a chronological session log (history), NOT current status. For current build-state see docs/STATUS.md (canonical), gated by scripts/verify-doc-claims.sh.

Running notes on architectural pivots and their tensor evidence. Entries are
newest first.

---

## 2026-06-10 — Swipe-to-LOOK + R3D `.cube` LUT extraction (one transform, two projections)

> **Session theme:** "a look IS a LUT." Brought the GIF→LUT idea from
> `~/lut-generator/src/python/gif_palette_lut.py` into SixFour as ONE data-driven OKLab
> palette→palette transform with two projections: the live capture screen recolours on a
> horizontal **swipe**, and Review exports the SAME transform as a 65³ `.cube` for grading R3D
> in DaVinci Resolve. Spec-first, byte-exact, golden-gated. **750 Haskell tests + 28 Zig tests
> green; drift gate 24 symbols; iOS BUILD SUCCEEDED** (compile-only per the camera-app rule).

### Design decisions
- **OKLab, not CIELAB.** The python analyses in CIELAB; we port to OKLab so the whole transform
  reuses the existing byte-exact Q16 colour core (`Spec.ColorFixed`). A primaries coincidence
  (sRGB ≡ Rec.709 primaries, differing only in gamma) makes OKLab→linear land exactly in linear
  Rec.709 — so the Rec.709 output is correct. The cost: every zone edge/threshold is in OKLab L
  ∈ [0,1] units (NOT the python's L\* ∈ [0,100]); the luminance-preservation law pins this.
- **Transcendentals as spec-generated embedded 1-D LUTs.** Log3G10 decode + filmic `exp` would
  break integer determinism, so the Haskell spec generates `log3g10_decode_lut.bin` /
  `filmic_tonemap_lut.bin` (+ a Q16 `srgb_encode_lut.bin` for 6-decimal output) and Zig
  `@embedFile`s them — the `gamma_lut.bin` pattern. No float on the core path.
- **Q16 6-decimal `.cube`** (not 8-bit) for banding-free R3D; golden stays exact (Q16 ints).
- **Swipe = render param only.** The look recolours the palette; the index tile is untouched, so
  the 4 pt cell grid is structurally intact. The swipe is a clear background layer behind the
  widgets (the hero is `allowsHitTesting(false)`), so it never contends with the palette's
  tap-to-shoot / hold-to-move.

### Keystone laws (the feature pivots on these)
- ★ **luminance preservation** — the transform is chrominance-only (output L == input L).
- ★ **preview ≡ cube** — the live 256-colour preview and the 65³ voxel call a byte-identical
  `transferOklabQ16`; a regression there breaks the build.
- ★ **.cube grid ordering** (R fastest) — prevents an R/B-swapped LUT.

### Where it lives
Spec `Spec.{ZoneProfile,LookTransfer,RedFrontEnd,CubeLut}` + `Properties.*` (laws) +
`Fixtures.hs` (blobs + `lut_golden.json`). Zig `s4_zone_profile_q16` / `s4_look_transfer_q16` /
`s4_build_cube_q16` + `lut_fixture_test.zig`. Bridge `SixFourNative.{srgb8ToOklab,lookZoneProfile,
lookTransfer,extractLUT}`. UI `LookVariant`, `AppSettings.captureLook`, `LivePhaseField.lookSwipe`
+ look-name `CellText`, `SurfaceView` palette re-grade, `ReviewPhaseField` Export LUT + `LUTFile`.
Full design: `docs/SIXFOUR-LOOK-LUT-WORKFLOW.md`.

---

## 2026-06-07 — The GIFA cube becomes CELLS; capture→GIFA morph wired; raymarcher deleted

> **Session theme:** "render the cell grid EVERY time." The whole capture→GIFA experience now
> renders through the ONE cell-grid path — live preview, loading sweep, and the GIFA review cube
> are each a `cellColor(at:)` population function over `CellSprite`/`CellBitmap`. The Metal voxel
> raymarcher is **deleted**. Spec **584 green**; iOS build SUCCEEDED; 166 Swift tests pass except
> one **pre-existing** `FrontProjectionTests` ImageIO-decode failure (confirmed failing on the
> clean branch with this work stashed — not introduced here).

### How it was built (workflow-driven, riskiest-first)
Three multi-agent workflows (review → broad UI/UX design → cell-grid design), each with an
adversarial-verify stage that caught load-bearing bugs **before** code:
- **The orbit raymarcher is only pixel-exact when flat** — its √2/2 basis lands ~1.76 art-px/voxel
  at the hero. Proven (`Spec.VoxelFit.lawOrbitHeroNotPixelExact`) and retired in favour of an
  integer shear table. 8-bit cubes are *dimetric* (integer slopes), never rotated cameras.
- **`halfSpan` is the wrong window divisor** (the shear isn't centred on 0) → a centered `cubeBox`
  `(cu,cv,h)`, re-verified inverse≡forward-scatter to 0 mismatches across all 9 rungs.
- **`artPerVoxel=2` would gap the flat face** → the rasterizer is **cell-scale (1 voxel = 1 cell)**,
  so flat is a solid 64×64 byte-identical to the GIF (`lawRasterizeFrontIsGif`).

### What shipped (on `grid/ownership`, this session)
- **`Spec.VoxelFit`** (NEW, 584 tests): the discrete integer projection ladder + per-cell rasterizer
  (`cubeBox`, `cellProject`, `cubeRasterMap`) with laws: front == 2D GIF ∀ rung, box clips nothing,
  flat = 4096 cells, rotation reveals side faces. Codegen → `VoxelFitContract.swift` (+golden box /
  cell-count tables, `selfCheck`) + `VoxelFitContractTests`.
- **The cube AS cells** — `Surface.bakeCube` forward-scatter z-buffer → `CubeRaster` → `CellSprite`
  (same path as the preview). Near face plays the cursor frame; X/Y **discrete rung sliders** shear
  depth to reveal the (x,t)/(y,t) faces; integer pitch keeps it crisp as it shrinks-to-fit.
- **Live hero = the REAL camera** (`σ.previewTile` index cells, replacing a synthetic palette scroll).
- **Loading = REAL streamed partials** — `DeterministicRenderer.onPartial` surfaces the true
  `quantize→dither→significance→palette` buffers into `σ.indexCube` (the discarded quantize indices
  are now retained); the serpentine sweep shows the GIFA actually forming, in true colour.
- **Review = the TRUE per-frame GIFA** (`σ.palettesPerFrame`, 64×256, not frame-0 replicated).
- **One addressing function** `Surface.cellGlobal(x,y,t)` backs every cube reader.
- **DELETED (aggressive cleanup):** `VoxelCubeView.swift` (708L), `GIFPlayer`/`PlayerTransport`
  (dead legacy player + `GIFCanvas`), the `voxel_raymarch` Metal kernel (~200L), AppSettings
  `voxel*`/`playerMode` keys, `VoxelRestPoseIdentityTests`. Stale `6pt/384` comments fixed; the
  `SIXFOUR-CAPTURE-GIFA-FLOW` doc marked superseded by the `Surface` architecture.
- **Correction to the plans (kept):** the collapse/GIFB path is **NOT** dead — it's the look-NN's
  output target, reachable via `paletteScope == .global` (STATUS.md already recorded this). Left intact.

### Open / next
- Flat-cube on-screen size (~195pt) vs preview 256pt — slight morph shrink, easy to tune.
- Rung-stop count (`flat → quarter → iso`) — confirm the granularity feels right.
- The review **Share** button is still a placeholder (`accessibilityHidden`); wire `gifURL` through σ.

---

## 2026-06-05 — SUNSET / handoff: ethos-debt cleanup + display-FSM proven

> **Entry point for the next session.** This session ran a workflow-audited ethos &
> technical-debt sweep, then fixed/proved the high-value items. Everything is committed
> and pushed to `origin/master` (HEAD `73c530f`); working tree clean; `cabal test` =
> **517 green**, iOS **BUILD/TEST SUCCEEDED**, drift gate + GRID lint pass.

### What shipped (6 commits, newest first)
- `73c530f` — resolution log in `docs/SIXFOUR-DEBT-RECONCILIATION.md` **§0** (the live
  status table — read this first; it maps each of the 18 live findings → fixed/open).
- `8c560e7` — FrontProjection **golden** (`SixFourFrontProjection`) + `FrontProjectionGoldenTests`
  + a **runtime DEBUG log** in `GIFPlayer.frontProjectedFrames` (os.Logger category
  `frontprojection`) that checks RULE-CUBE-2D-IDENTITY on device.
- `176186d` — `Spec.FrontProjection` proves the 2D-GIF == cube-near-face identity
  (reuses `PlaybackClock threeDFrontFace == twoDFrame`).
- `98a032a` — `DisplayContractTests`: **cross-contract** parity (Display ↔ PlaybackClock ↔
  Lattice agree — the seam per-file selfCheck/drift-gate miss).
- `6dabded` — `DisplayContract.swift` codegen (FSM constants + `goldenCursorTrace`).
- `a4532a8` — **`Spec.Display`** proves the FSM `M=(Σ,ι,δ,λ,Π,κ)`, **T1–T9 + composition**
  (`spec/src/SixFour/Spec/Display.hs`, `spec/test/Properties/Display.hs`).
- `81dadd2` — Tier 1 cleanup: lattice-govern bare point dims, delete dead
  `GlassOverContent.swift`, rewrite DISPLAY-FSM §2.4.2 (glass retired), and a **codegen
  Sendable fix** (`CellContract.Golden`) that unblocked the contested-cell build.

### Hard constraint learned (do not forget)
- **The simulator has NO camera**, so the capture flow can't be driven there. Verify via
  **unit tests** (they run fine — contract tests don't touch the capture path) and
  **logs** (os.Logger / `print` in tests). A final **device A/B** is the only way to
  confirm visuals.

### Open / next steps (priority order)
Open/next-steps are tracked in docs/STATUS.md (Open debt table) as of 2026-06-05.

The full audit (ethos restatement, all 18 live + 15 dismissed findings, exact fixes) is in
`docs/SIXFOUR-DEBT-RECONCILIATION.md` (now archived under `docs/archive/`); the audit workflow
is `scripts/wf-ethos-debt-audit.js`.

---

## 2026-05-29 — Next session: FULL GIF creation in Zig (per-frame LAB palette, 20 fps)

> **Entry point for the next session.** The owned Zig core (`Native/`) currently ships
> exactly one kernel — `s4_load_look_net` (blob parser, `Native/src/root.zig:64`). This
> brief scopes the next real kernel: the **full GIF-creation pipeline in fixed-point Zig**,
> driven by the existing Swift capture/Metal/display layer. Decision lineage:
> [[sixfour-zig-quantized-core]] (integerize the palette pipeline with a deterministic
> argmin tie-break so GIF↔tensor round-trips are bit-exact MLX↔device). **Reproduce the
> existing algorithms faithfully — do NOT invent new ones.** The Haskell spec (`spec/`)
> is the verified source of truth and emits the contracts + golden vectors we gate against.

### 1. GOAL + acceptance
Product flow: **Swift/AVFoundation capture → 64 frames → per-frame 256-colour OKLab
palette that BALANCES the camera input (max LAB diversity/coverage, NOT MSE) → 64×64 GIF
frames → shown to the user @ 20 fps gold standard.** Zig owns the deterministic quantized
core; Swift keeps capture + Metal decode + display.

- **Accept (quality):** GIF quality ≈ current float Swift/Metal path — negligible loss.
  Per-frame palette is **surjective** (all 256 colours used) and **significant** (every
  slot ≥ `minPopulation` pixels). Coverage metric (not MSE) is the objective.
- **Accept (timing):** capture @ 20 fps (`activeVideo{Min,Max}FrameDuration = 1/20`),
  display @ 20 fps (5 centiseconds/frame in the GIF + a 20 fps `Timer`), nearest-neighbor
  upscale. Extraction+encode run **post-burst, offline** (no real-time deadline on Zig).
- **Accept (bit-exact):** once integerized, Zig output is bit-identical to the Haskell
  golden vectors (goldens shift from tolerance → EXACT) and reproducible Python/Swift↔Zig.

### 2. ALGORITHM MAP (concrete algo · canonical file:line to read · how verified)

**A. Per-frame palette extraction (cluster → select → nearest-centroid → significance)**
- **Wu variance-cut seeding** — 32³ moment histogram (hist + 9 moment tables), cumulate
  along L,a,b, greedily split highest-WCSS box on highest-variance axis until K=256.
  Read `SixFour/Palette/WuQuantizer.swift:99` (quantize), `:256` (bestSplit), `:233`
  (WCSS); CPU wrapper `Metal/KMeansPalettePipeline.swift:378`. Spec: `spec/src/SixFour/Spec/StageA.hs:77`.
  Verified: `SixFourTests/WuQuantizerTests.swift`, `Properties/Significance.hs`.
- **Lloyd K-means** — assign to nearest centroid (squared OKLab L2, strict `<` tie→idx0),
  accumulate linear+outer-product sums, divide by count (keep old centroid if count==0).
  15 iters GPU / 3 iters CPU+spec. Read Metal `Shaders.metal:375` (assign+accumulate,
  tie-break `:402`), `:443` (finalize), `:489` (finalize-stats covariance). Spec
  `StageA.hs:96` (lloydStep). Verified: `MetalKMeansTests.swift`, Haskell `varianceCutReference`.
- **Farthest-point (maximin) seeding** — diversity objective: seed0 = argmax dist-from-mean,
  then iteratively argmax min-dist-to-chosen. Read `KMeansPalettePipeline.swift:402`;
  spec `Significance.hs:269`. Verified: `lawSigMaximinVariety`.
- **Nearest-centroid assignment** — argmin squared OKLab L2 with **strict `<`, lowest
  index wins**. SIMD8 path `Palette/NearestCentroid.swift:67` (mask replace + horizontal
  reduction `:91`); scalar oracle `:165`; GPU `Shaders.metal:402`. Spec `Significance.hs:245`.
  Verified: `NearestCentroidTests.swift:46`.
- **Significance split-fill (rebalance)** — every slot count ≥ `minPopulation`; for each
  deficient slot pull the pixel NEAREST to palette[k] from a surplus slot (count > min).
  Terminates since 4096 ≥ 256·2. Read `Palette/SignificantSplitFill.swift:34` (rescue),
  `:78` (cells: mean/σ/count/provenance). Spec `Significance.hs:304`. Verified:
  `lawSigAllSignificant`, `lawSigMassConservation`, `SignificantSplitFillTests.swift`.
- **Covariance** — E[xxᵀ]−μμᵀ, upper triangle (LL,La,Lb,aa,ab,bb), empty→(1e-6,0,0,1e-6,0,1e-6).
  Read `Shaders.metal:489`/`:420`; assembly `KMeansPalettePipeline.swift:232`; spec `Significance.hs:193`.

**B. LAB/OKLab transforms + diversity/coverage objective**
- **OKLab transform** — sRGB↔linear (piecewise gamma) · M1 (lin→LMS) · cbrt · M2 (→OKLab);
  inverse uses M2⁻¹, cube, M1⁻¹. 18 bit-exact Ottosson constants. Read
  `spec/src/SixFour/Spec/Color.hs:45`, Swift `Color/ColorScience.swift:34`. Verified:
  `Properties/Color.hs` round-trip ≤1e-5 over 33³ grid, `ColorScienceTests.swift`.
- **Gamut coverage (16³ voxel grid)** — bin OKLab into 4096 voxels (`floor((v+0.5)·n)`),
  coverage = occupied/4096; this is the diversity objective maximized by farthest-point.
  Read `Spec/Coverage.hs:40`, `Spec/Bottleneck16.hs:44`, Swift `Editing/ClusterStatisticsOps.swift:306`.
  Verified: `Properties/Coverage.hs` (∈[0,1], monotone-under-union).
- **Diversity measures** — weighted covariance → Gaussian entropy ½ln((2πe)³|Σ|),
  effective-dim (trΣ)²/tr(Σ²)∈[0,3]. Read `Spec/Diversity.hs:38`, Swift `ClusterStatisticsOps.swift:288`.

**C. GIF encoder (LZW + per-frame palette table + STBN3D dither + 64×64 + timing)**
- **LZW (8-bit alphabet, variable code size, LSB-first)** — dict init [0..255], clearCode=256,
  endCode=257, first new=258; code size 9→12, increment when nextCode==(1<<codeSize); sub-blocks
  ≤255 bytes, 0x00 terminator. Read `Encoder/GIFEncoder.swift:190`; spec `gen/SixFour/Gen/GifWire.hs:203`.
  Verified: `GIFEncoderTests.swift` round-trip via `decodeLZWBlocks():274`.
- **GIF89a frame builder (per-frame Local Color Tables, no GCT)** — header 'GIF89a',
  LSD (packed 0x70), NETSCAPE2.0 loop, then 64× {GCE 0x04+delay, Image Descriptor 0x2C…0x87,
  768-byte LCT, LZW data}, trailer 0x3B. Read `GIFEncoder.swift:32`; spec `GifWire.hs:73`.
  Verified: byte-level structure tests in `GIFEncoderTests.swift:15`.
- **OKLab→8-bit sRGB** — `byte = clamp(round(x*255),0,255)` per channel after `okLabToSRGB`.
  Read `GifWire.hs:177`; Swift via `simd` + `okLabToSRGB`.
- **STBN3D blue-noise dither** — pre-computed 8³ mask (void-and-cluster, toroidal Gaussian
  σ²=1.5), tiled 8×8×8→64³; threshold picks nearest2 farther centroid. **Load
  `SixFour/Resources/stbn3d-8.bin` (512 bytes) — never regenerate.** Read
  `Generated/STBN3DContract.swift:28` (loadTiled), `Palette/Dither.swift:291` (blueNoiseSIMD);
  spec `Spec/STBN3D.hs:76`. Error-diffusion (Floyd–Steinberg/Atkinson) `Dither.swift:148`/`:334`,
  spec `Spec/Dither.hs:22`.
- **Brands gating the encode** — `CompleteVoxelVolume` (per-frame surjectivity, `Spec/Indices.hs:59`,
  Swift `SignificantVoxelVolume.swift`) + `SignificantSplitFill.rescue`. Encode consumes the
  witness at `GIFEncoder.swift:56`.

**D. Capture → frame → display + 20 fps timing**
- **20 fps burst** — `AVCaptureVideoDataOutput` delegate (x420 10-bit YCbCr), frame-rate
  clamped 1/20. Read `Capture/CaptureSession.swift:382` (clamp), `:499` (captureBurst),
  `:651` (delegate).
- **Metal YCbCr10→OKLab** — crop/downsample/linearize (colorSpaceTag OETF) → linear→OKLab →
  unsharp-L (0.6). Read `Metal/Pipeline.swift:25`/`:243` (readback OKLabTile). Stays Swift/Metal.
- **GIF display @ 20 fps** — `Timer` interval 1/20, `Image(...).interpolation(.none)`
  nearest-neighbor; reduceMotion freezes frame 0. Read `UI/Screens/Review/GIFReviewView.swift:115`,
  per-frame status `TimelineView(.animation(1/20))` `:54`. Encode delay 5cs `GIFEncoder.swift:40`.

### 3. ZIG INTEGERIZATION BOUNDARY

**Becomes fixed-point Zig (the owned quantized core):**
1. **Wu histogram + variance-cut seeding** (32³ moment tables → greedy split → centroids).
2. **Lloyd K-means** (fixed-point atomic-style accumulation; keep-old-on-empty; matched scale).
3. **Nearest-centroid argmin** — i32 squared distance, **DETERMINISTIC tie-break: strict
   `<`, lowest index wins** (mirror Swift/Haskell exactly). Output UInt16 indices [0,256).
4. **Split-fill rebalance** — distance-based donor pull (nearest-to-palette[k] from surplus).
5. **LZW + GIF89a serialization** — byte-for-byte port of `GIFEncoder.swift:190`/`GifWire.hs:203`
   (LSB-first, sub-block chunking, little-endian fields, minCodeSize=8).
- Fixed-point: Q16/Q24; `toFixedPoint(f32)→i32`, `distanceFixed→i64`. OKLab cube-root via
  Newton-Raphson if conversion is done Zig-side (or accept float centroids from Swift and
  convert). Fixed-point accumulation scale must match Metal's ×2^16 / ÷65536 (`Shaders.metal:460`/`:507`).

**Stays Swift/Metal (the seam):**
- AVFoundation capture + 20 fps timing (`CaptureSession`), Metal YCbCr→OKLab + unsharp
  (`Pipeline.swift`), live 10 fps preview, GIF display `Timer` (`GIFReviewView`).
- **STBN3D mask generation** — load the pre-computed `stbn3d-8.bin`; Zig tiles it, never regenerates.
- Blue-noise GPU dither path (`BlueNoisePalettePipeline.swift`) stays Metal. (Error-diffusion
  CPU dither MAY be ported but is optional — it is a Swift-only refinement, not in the spec.)
- `CompleteVoxelVolume` + `SignificantSplitFill` type-safe gates orchestration in Swift.

**Reuse the established C-ABI + bridge pattern** (cite `s4_load_look_net`):
- Static lib: `Native/build-ios.sh` → `zig build-lib src/root.zig -target {aarch64-ios,
  aarch64-ios-simulator} -O{ReleaseFast,ReleaseSafe}` → `libsixfour_native.a`.
- Header: `Native/include/sixfour_native.h` (C signatures). Bridge:
  `SixFour-Bridging-Header.h`. Swift wrapper: `SixFour/Native/SixFourNative.swift`.
  Link wired in `project.yml` (`preBuildScript` → build-ios.sh, `LIBRARY_SEARCH_PATHS`,
  `OTHER_LDFLAGS=-lsixfour_native`). Proposed new exports (caller-allocated outputs, no
  alloc crosses FFI):
  - `s4_quantize_frame(pixels[4096*3] f32, centroids[K*3] f32, K, out_indices[*]u16) i32`
  - `s4_gif_encode(frames u8*, frames_len, palettes (RGB8) , palette_count, out_path) i32`
- **Zig 0.16 facts:** `pub const panic = std.debug.no_panic` (no stack-trace symbols in the
  host binary); `align(1)` ptrs OK for scalar f32 loads on arm64 (SIMD/Metal consumers must
  re-pack); default integer wraparound `+%` (argmin comparisons are naturally checked);
  `zig build-lib` arm64-ios + simulator both green (s4_load_look_net shipped & tested).

### 4. REPRODUCTION RISKS / bit-exactness watch-list
- **Tie-break = strict `<`, lowest-index-wins** everywhere (scalar, SIMD8 lane-scan, GPU,
  Zig). Any `>` / `≤` / lazy handling flips indices on exact ties. (`NearestCentroid.swift:91`.)
- **Fixed-point scale parity** with Metal ×2^16/÷65536 (`Shaders.metal:460`,`:507`).
- **Lloyd iteration count** (15 GPU / 3 CPU+spec) — pick a mode and match it.
- **Empty-cluster = keep old centroid** (`Shaders.metal:454`, `StageA.hs:106`).
- **Covariance order** = (LL,La,Lb,aa,ab,bb); population divisor /n (NOT n−1).
- **Voxel bin** = `floor((v+0.5)·n)` truncation-as-floor; mixed round/floor misaligns coverage.
- **OKLab→sRGB = round (not truncate)**, then clamp; 18 M1/M2 constants bit-exact (1 ULP compounds).
- **LZW edge cases:** LSB-first bit order; code-size increment threshold `nextCode==(1<<codeSize)`
  (off-by-one corrupts); sub-blocks ≤255 bytes + 0x00 terminator; all multi-byte fields little-endian.
- **STBN3D determinism** — load `stbn3d-8.bin`, never regenerate (Euclidean ≠ toroidal mask).
- **Surjectivity check is PER-FRAME** (set cardinality == K for each frame), not global union.
- **Constants from contract, not hardcoded** — `minPopulation=2`, confidence Z=1.959963984540054,
  binsPerAxis=32 flow from `Significance.hs` codegen → Swift `SignificanceContract.swift`.
- **Order-of-eval** in fixed-point Lloyd accumulation — enforce row-major pixel scan
  (rounding makes addition order-dependent).
- **Cross-frame remap** not implemented; if introduced it must compose with quantization in
  Zig to keep commuting at fixed-point precision.

### 5. VERIFICATION STRATEGY (how to gate the Zig port)
- **Golden vectors from the Haskell spec** — `cabal run spec-codegen` already emits forward
  goldens (`trainer/generated/look_net_golden.json`, `Generated/*Contract.swift`). Add
  quantization + LZW + GIF-bytes goldens via `Codegen.Golden`. **Once integerized, flip the
  Swift↔spec goldens from tolerance (≤5e-3 / 1e-5) to EXACT byte/index equality.**
- **Cross-language fixture test** (mirror `Native/src/fixture_test.zig`, which checks the
  S4LN blob byte-exactly): Python/Swift writes a synthetic frame + centroids (+ expected
  indices/GIF bytes) as a fixture; Zig reproduces bit-exactly; `zig build test` gates it
  (skip-if-absent like the current fixture). Then an iOS integration test feeds Zig's
  quantize output into `PaletteGenerator.generate()` → dither → encode and asserts the GIF
  is byte-identical to the Swift path (`GIFEncoderTests.swift` round-trip on all 64 frames).
- **On-phone benchmark (iPhone 17 Pro, iOS 26)** — confirm 20 fps capture + 20 fps display
  hold, and measure quality (coverage, per-frame MSE diagnostics already surfaced in
  `GIFReviewView` perFrameStatus) ≈ current float path. Extraction+encode are offline, so
  only correctness/quality is gated here, not latency.

### 6. OPEN QUESTIONS for the user
1. **Fixed-point width:** Q16 or Q24 for OKLab? (Q16 cheaper; Q24 safer on the cbrt cube-root
   round-trip near gamut edges.) Need a target last-bit tolerance that does NOT flip indices.
2. **OKLab conversion locus:** does Zig do sRGB→OKLab (needs Newton-Raphson cbrt) or does
   Swift/Metal hand Zig float OKLab pixels + centroids and Zig only does integer argmin/LZW?
   (The capture survey says OKLab pixels already exist post-Metal — leaning toward the latter.)
3. **LZW in Zig now, or later?** It is the highest-risk byte-exact port but has no float
   nondeterminism. Port it together with quantization, or land quantize first and keep the
   Swift encoder until goldens are EXACT?
4. **Lloyd iteration count to standardize** for the device path: 15 (GPU parity) or 3 (spec)?
5. **Seeder of record:** Wu variance-cut vs farthest-point as the shipped default for the
   "balances the camera input / max diversity" objective (the 3-way selector currently
   picks K-means/Wu/Octree — which one is the Zig core's primary)?

---

## 2026-05-29 — Haskell→MLX alignment audit: open gaps (flags only)

> **Closure status (2026-05-29, branch `feat/haskell-mlx-alignment`, 6 commits, 289 spec
> tests green + golden/loss gates pass).** CLOSED: #2 Spec.Loss→MLX port, #3 loss golden
> (float64-CPU gate @1e-6 — MLX is f32, Haskell f64; reduced in f64 to hold 1e-6),
> #5 decoder→384 SigmaPairHead, #6 option4Theorem, #7 SIGMA_PAIR pins, #8 MLX smoke-test
> arm, #9 MLX↔torch check, #10 non-finite guards, #11 PonderNet halting loss, #14
> NetSlot.LOOK, #15 deploy-blob serializer (writer+format+round-trip; producer
> `trainer/export_look_net_blob.py`). PARTIAL: #1 — loss *target* ported+gated, but the MLX
> training *loop* script isn't written (also blocked by #4). BLOCKED: #4 training data empty
> (`trainer/data/*` = 0 files → can't actually train). DEFERRED (research-gated): #12/#13
> GRAM stochastic core + `spec-measure` on real captures. NEW FOLLOW-UP: the native loader
> `s4_load_look_net` is a declared C ABI contract (`Native/include/sixfour_native.h` +
> Swift seam) but NOT yet implemented in Zig nor wired into `project.yml` (bridging header +
> link) — this is the "first real kernel" of the owned Zig core ([[sixfour-zig-quantized-core]]).

Audit of the **MLX training** and **NN-design** seams. No code changed — this is a
flag log (the repo keeps deferred work as prose here, not as inline markers). Each item
is phrased to double as a **work-list for a follow-on dynamic workflow**: locus
(`file:line`), acceptance criterion, and dependency edges. Verified firsthand 2026-05-29.

**Healthy baseline (not gaps).** The *forward* path is bit-exact: `Codegen.MLX`
(`spec/src/SixFour/Codegen/MLX.hs`) is the real, primary 194-line `mlx.nn` emitter (NOT a
numpy stub); the golden gate (`trainer/check_golden.py`) matches MLX & PyTorch to the
Haskell oracle at 1e-6; σ-equivariance is proven in Haskell and verified bit-exact. Every
gap below is on the **training** and **design-pivot-wiring** side, never the forward math.

### A. Training pipeline — the core hole
1. **No look-NN trainer exists.** `trainer/` has only `train_metric.py` (Stage-A PSD
   metric); there is no `train_look_net_mlx.py`. The "MLX is the primary trainer"
   contract (`CLAUDE.md:23`) is currently true only for the metric organ, not the look-NN.
   *Accept:* an MLX training loop produces look-NN weights. *Dep:* needs B (decoder dims) + #2.
2. **`Spec.Loss` not ported to MLX/Python.** `spec/src/SixFour/Spec/Loss.hs` defines
   fidelity (Bures-W) + coverage + Ou-Luo beauty; no fidelity/coverage/beauty/bures/
   `lookNetLoss` anywhere in `trainer/*.py` (outside `generated/`). *Accept:* MLX loss fn
   matches `Spec.Loss` within tol on a golden case. *Dep:* needs loss golden vectors (#3).
3. **No loss/gradient golden vectors.** `trainer/generated/look_net_golden.json` +
   `check_golden.py` cover the **forward pass only** (`check_golden.py:77` is
   `torch.no_grad()`; no loss/backward/grad). Training numerics are unverifiable against
   Haskell. *Accept:* `Codegen.Golden` emits loss (and ideally grad) reference cases.
4. **Training data empty.** `trainer/data/captured_frames/` and `…/reference_gifs/` are
   both 0 files; the metric trainer `SystemExit`s with no GIFs. *Accept:* a documented
   data-acquisition path (real captures from the on-device session dir, or synthetic).

### B. SigmaPairHead design pivot — spec is ahead of codegen (the long pole)
5. **Decoder emits the committed 384-DOF SigmaPairTree.** CLOSED: `look_net_mlx.py:33`
   and `look_net_torch.py:33` read `DECODER_OUT_DIM = 384 # = SIGMA_PAIR_DOF` and reconstruct
   the 256-leaf σ-pair palette. The spec derives it at LookNetD.hs:117/315 (== 384).
6. **`option4Theorem` dead-ends at `Quad4ReconAchroma`.** The `Spec.Pipeline` composition
   theorem is not re-instantiated at `SigmaPairHead` (see NOTES 2026-05-28 open Q#2 +
   "Risks"). *Accept:* a `SigmaPairHead` instance proves conditional σ-equivariance.
7. **`SIGMA_PAIR_*` codegen pins emitted everywhere.** CLOSED: `SIGMA_PAIR_DOF=384 / DEPTH=7
   / LEAVES=256` emitted at look_net_mlx.py:40-42, look_net_torch.py:40-42, net_shape.py:37,
   NetContract.swift:48, contract.rs:23-25. Sources: Burn.hs:58-61, Shapes.hs, CoreML.hs:89-98,
   MLX.hs, Swift.hs:319.

### C. MLX-specific verification gaps
8. **MLX σ-equivariance is verified in `smoke_test.py` Step 3b** (smoke_test.py:73-106:
   imports mlx.core + look_net_mlx, transfers torch state_dict, asserts mlx_delta == 0). CLOSED.
9. **Direct MLX-vs-PyTorch forward comparison present** — smoke_test.py Step 3c (:108-123)
   is a same-weights MLX↔torch allclose at rtol 1e-5. CLOSED.
10. **NaN / non-finite guard implemented in `run_torch` and `run_mlx`** (check_golden.py:101-103
    and :132-134 append (name+":nonfinite", inf) on non-finite output). CLOSED.
11. **PonderNet halting loss trained via KL(halting-dist ‖ geometric-prior)** in
    Spec.Loss.haltingLoss (Loss.hs:343), mirrored in look_net_loss_mlx.py and actively trained
    in train_look_net_mlx.py:103 (total += lam_halt·halt). CLOSED.

### D. GRAM stochastic core — design-only, research-gated (defer)
12. **Stochastic L4 core deferred** (`spec/GRAM_MAPPING.md`); VI target `y` unresolved
    (2026-05-28 open Q#5). Current `LookNetR` core is deterministic Mixture-of-Recursions.
13. **`spec-measure` on real captures still pending** (2026-05-28 open Q#1) —
    `sigmaSymFraction` measured only on synthetic palettes, so the SigmaPairHead decision
    (and B above) lacks on-device evidence. *This gates B and D; do it first if data exists.*

### E. Extra missing threads (beyond the four categories)
14. **The look-NN is not a first-class `NetSlot`.** `trainer/generated/net_shape.py` /
    `Spec.Net.hs` register only `NetSlot.METRIC`; look-NN dims (`MODEL_DIM`, `CORE_DEPTH`,
    `DECODER_OUT_DIM`, `MAX_TOKENS`) live only inside the model files via
    `CoreML.emitLookNetConstants`, not in the shape-contract registry. *Accept:* a
    `NetSlot.LOOK` (or similar) with a `NetIOSpec`, pinned like the metric.
15. **No deploy-blob serializer.** `MLX.hs:13` intentionally omits a `build_mlpackage`
    analog (MLX weights → plain binary blob for the hand-written Swift forward pass), but
    nothing yet *writes* that blob. It is the unwritten second half of the missing
    `train_look_net_mlx.py` (#1). *Accept:* a documented MLX-weights→blob format + writer.

### Dependency order for the closure (Phase 2 dynamic workflow)
```
B (SigmaPairHead 384-DOF) ─► regen golden (Codegen.Golden) ─► A (trainer + Spec.Loss port)
                                                                      │
C (MLX verify arm, NaN guard) ── mostly independent ──────────────────┘
D (GRAM core) ── research-gated on #13 ── defer
```
Plan with full Phase-2 workflow sketch: `~/.claude/plans/snug-zooming-dewdrop.md`.

---

## 2026-05-28 — σ-pair decoder pivot (Quad4 rejected → SigmaPairHead adopted)

**Session goal.** Unify three new spec primitives — the 16³ OKLab histogram
bottleneck (`Spec.Bottleneck16`), the σ-eigenspace split (`Spec.SigmaDecomp`),
and a 4-ary opponent-quadrant decoder (`Spec.Quad4`) — into one coherent
look-NN pipeline, and decide between binary PairTree and 4-ary Quad4 for the
L6 reconstruction stage.

**What the session committed.** Seven commits on top of `80b9843`:

| Commit | Lines | What |
|---|---|---|
| `3cb1be5` | +1198 | Substrate: GMM + Bures (W₂ on Gaussians) |
| `e09c791` | +3376 | Look-NN spec: 9-layer pipeline (L1…L9), 768-coeff PairTree |
| `c4f8e8e` | +2361 | Tooling: spec-tui, spec-gif, spec-gen |
| `a96d1c5` | +848  | Bottleneck16 + SigmaDecomp + Quad4 (the redesign primitives) |
| `ab27a16` | +548  | Spec.Pipeline (Stage / SigmaEquivariant type-class framework) |
| `06f8746` | +519  | LinAlg + Quad4Fit (tensor measurement on Quad4) |
| `f7667b8` | +341  | SigmaPairHead (σ-pair-symmetric decoder, tensor-verified) |

Net **+10,497 / -701** across 100 files. **191 spec tests pass.**

### The pivot in one paragraph

`ab27a16` encoded the σ-equivariance claim of the plan addendum (§A) as a
Haskell type-class framework. The composition theorem `option4Theorem`
typechecks — proving that *if* every stage is `SigmaEquivariant`, the whole
pipeline is. The user noted this proof is **structural only**: it certifies
shapes commute, not that the architecture has the right representational
power. The follow-up commit `06f8746` built the Quad4 design matrix
`B ∈ ℝ^{768 × 511}` explicitly and measured its image via Modified
Gram-Schmidt. **Finding:** Quad4's residual on σ-symmetric synthetic palettes
was *indistinguishable* from its residual on random palettes (median ≈ 6 %
both, contrast ratio ≈ 1). Quad4's image cuts ℝ⁷⁶⁸ at some generic angle
that captures concentrated palette content equally well regardless of σ
structure — it is **not** preferentially σ-aligned. The plan's claim "Option
4's Quad4 decoder yields σ-symmetric output by construction" was false at
the tensor level.

`f7667b8` introduced **`Spec.SigmaPairHead`** to fix this: instead of
freely-parameterised 256 leaves, emit only **128 σ-pair GENERATORS** via a
depth-7 binary Haar pyramid, and define the 256-leaf palette as
`[c_0, σ(c_0), c_1, σ(c_1), …]`. The σ-pair structure is now algebraic; every
odd leaf is the σ-reflection of its even predecessor for *any* genome. The
design matrix `B ∈ ℝ^{768 × 384}` is full rank (384) — exactly the dimension
of the σ-symmetric palette subspace — and the empirical residuals are:

| | SigmaPairHead | Quad4 |
|---|---|---|
| Rank | 384 (full) | 511 (full) |
| σ-symmetric residual (median) | **0.0** (≈ 1e-15) | 0.06 |
| Random palette residual (median) | 0.09 | 0.06 |
| **Contrast (random / σ-symmetric)** | **≈ 10²⁸** | ≈ 1 |

The contrast ratio is the architectural signature. SigmaPairHead is **10²⁸×
better** at fitting σ-symmetric content than random palettes; Quad4 has no
σ-preference at all.

### Why this matters

The "128 σ-balanced pairs" headline of `LOOK_NN.md` was always aspirational.
A free-parameter tree (binary or 4-ary) achieves σ-symmetric output only via
a learning signal — the architecture itself provides no guarantee.
SigmaPairHead is the structural inhabitant the headline required. Its DOF
(384) is exactly the σ-symmetric subspace dimension — **zero wasted DOF on
σ-antisymmetric content the constraint forbids**.

### Open questions left for the next session

1. **`spec-measure` exe on real captures.** The σ-symmetric / random
   distinction was measured on synthetic palettes drawn from a [0.2, 0.8] ×
   [-0.2, 0.2]² box. The decision-relevant question — what does the
   `sigmaSymFraction` distribution look like on on-device captures from
   `~/Library/Application Support/SixFour/sessions/` — is still pending
   (Tasks #3, #4 in the TaskList).

2. **Re-instantiate `option4Theorem` at `SigmaPairHead`.** The Pipeline
   composition theorem in `Spec.Pipeline` is currently parameterised over
   `Quad4ReconAchroma`. Should be straightforward to add a
   `SigmaPairHead`-instance and prove the conditional σ-equivariance for the
   updated pipeline.

3. **The L5 decoder.** The encoder L3 → L4 → L5 → L6 chain needs to emit a
   384-coefficient `SigmaPairTree` instead of a 768-coefficient
   `HaarPalette`. Cheap: drop the lowest Haar level.

4. **Codegen pin for the new dimensions.** `Spec.Codegen.Burn` should emit
   `SIGMA_PAIR_DOF = 384`, `SIGMA_PAIR_DEPTH = 7`, `SIGMA_PAIR_LEAVES = 256`
   into `studio/look-nn/src/generated/contract.rs`. One commit (Task #2).

5. **Stochastic core (GRAM-style, `spec/GRAM_MAPPING.md`).** Still design-
   only, still deferred. The VI target `y` open question is unresolved.

### Architectural diagram (post-session)

```
L1 Pool      :  CyclicStack → samples                                (Det)
L2 GMM       :  samples → tokens (μ, Σ, w)                           (Det)
L3 Encoder E :  10 → dM = 64                                         (Learn)
L4 Core R    :  dM → dM   (PonderNet over Mixture-of-Recursions)     (Learn)
L5 Decoder D :  dM → 384  (SigmaPairTree genome — was 768 PairTree)  (Learn)
L6 Reconstruct: SigmaPairTree → 256-leaf σ-pair palette              (Det,  NEW)
L7 Remap     :  per-frame K → K                                      (Det)
L8 GlobalIdx :  T·H·W + remap → T·H·W ∈ [0, K)                       (Det)
L9 Dither    :  index field + STBN3D → GIF index field               (Learn/Det)
```

Genome budget: **dM = 64** (encoder bottleneck) → **384** (decoder output) →
256 σ-pair-structured leaves. Both PairTree (768) and Quad4 (511) are
retained in the spec library as documented alternatives — they're not wired
into the pipeline, but their spec modules and tensor measurements are kept
as evidence of why SigmaPairHead won.

---

## Review summary (this session)

**Code added (Haskell):** 9 new modules in `spec/src/SixFour/Spec/`:
`Bottleneck16`, `SigmaDecomp`, `Quad4`, `Pipeline`, `LinAlg`, `Quad4Fit`,
`SigmaPairHead`, plus extensions to `Indices` (`GlobalSurjective` brand),
`Cyclic` (constant-trajectory AC-power fix), `Codegen.Burn` (Rust contract
emit). Total ~2.6 k LoC of spec, ~1.3 k LoC of property tests.

**Code added (Rust):** `studio/look-nn/` crate (272 LoC), `analysis-core`
extensions for Bures + GMM (~480 LoC). Golden-checked against Haskell spec.

**Tooling added:** Three executables (`spec-tui`, `spec-gif`, `spec-gen`)
with their own gen/viz/gen-test source dirs (~1.7 k LoC), plus a `gen-tests`
test-suite (9 tests green).

**Tests added:** 191 spec tests total (was 79 before commit `3cb1be5`).
Highlights: 16-law layer report at production 64³ × 3 seeds; Bures iteration
convergence; σ-eigenspace orthogonality / Parseval; PairTree round-trip;
Quad4 σ-equivariance; SigmaPairHead structural σ-pair guarantee; tensor
residual reports printed live with `§A.4` verdicts.

**Risks / things to watch.**
- Modified Gram-Schmidt is not the most numerically stable QR; if matrix
  conditioning degrades in a future variant, may need to upgrade to
  Householder QR or pull in a BLAS-backed LA library (license-gated).
- The `option4Theorem` proof in `Spec.Pipeline` is currently dead-end at
  Quad4ReconAchroma — needs the SigmaPairHead update before the
  type-class framework actually points at the new decoder.
- `spec/dist-newstyle/` is sometimes 300 MB; `.gitignore` covers it but
  watch out for `spec/analysis/dist-newstyle/` (covered by the
  `spec/**/dist-newstyle/` rule added in commit `3cb1be5`).
- The branch name `feat/significance-settings-instrument` is stale —
  significantly outscoped its original purpose.

**Verification performed.**
- `cabal test spec-tests` → 191 / 191 green.
- `cargo build -p analysis-core -p look-nn` in `studio/` → clean.
- `cabal run spec-codegen` → 8 files + 1 resource, no diffs against the
  shipped Swift / Python / Rust contracts.
- Manual review of every commit's diff against the plan's named files
  (`~/.claude/plans/flickering-dazzling-dewdrop.md`).
