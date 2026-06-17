# SixFour — Architecture Map

> **Status — last refreshed 2026-06-16, post RGBT-4D pivot.** This is the CONCEPTUAL
> map: the Swift / Zig / Metal / Haskell / MLX boundary RULES, the NN core, the
> cross-language byte-alignment contract, the end-to-end data flow, and the CRITICAL
> current-state callouts. `docs/STATUS.md` owns the built/design/missing ledger (and is
> itself pre-pivot stale — see §6); `SIXFOUR-VISION.md` owns the narrative; the cube-ladder
> pivot is detailed in `docs/SIXFOUR-CUBE-LADDER-GAP-ANALYSIS.md`. This doc owns the shape
> of the machine.

## 0. The product, in one paragraph

SixFour is a zero-third-party-dependency iOS 26 camera app that folds a **64-frame burst**
into a deterministic, Haskell-verified **64×64×256-colour GIF89a** — and is now pivoting
that single cube into a three-rung **16³ / 64³ / 256³ cube ladder**. The architecture is a
**five-tier proof spine**: a ~100-module Haskell algebraic spec (`spec/`) is the single
source of truth that codegens (a) byte-exact integer goldens (Swift `==`, no tolerance) for
the Zig native core (`Native/`, `libsixfour_native.a`, Q16 fixed-point `s4_*` kernels) AND a
hand-written Swift port; (b) shape/enum contracts and the cell-mechanics / display FSMs for
the SwiftUI app (`SixFour/`); (c) hex-IEEE754 float goldens (1e-6 tolerance) plus
MLX / PyTorch / Rust-burn modules for the Mac-only trainer (`trainer/`) and Rust studio
(`studio/`). On device: **Metal** owns the float capture pre-pass, **Zig** owns all
reproducible integer GIF math (SHA256-pinned), **Swift** owns UI as a single phase-FSM
"surface". **The RGBT-4D cube-ladder pivot (2026-06-16) is fully landed in spec + Zig + Swift
+ golden but is flag-gated OFF with zero runtime consumers** — the shipped app still emits
one 64³ GIF (see §5).

## 1. The five-tier proof spine — Swift WHERE vs Zig WHERE vs …

| Capability | Zig | Swift | Metal | Haskell-spec | MLX | Why |
|---|---|---|---|---|---|---|
| Capture transfer + primaries + linear→OKLab + unsharp | — | — | `Shaders.metal` | — | — | GPU-native, float OK at capture, no determinism needed |
| Per-tick cell-field ground | — | `FieldMetalView/Core` | `field.metal` | `FieldTuning.metal.h` | — | One frame per κ tick; float, presentational |
| OKLab float → Q16 int32 | — | `SixFourNative.swift` | — | — | — | One-time deterministic hand-off; Zig owns everything after |
| Quantize (maximin Gonzalez + Lloyd + nearest) | `kernels.zig` | (parity oracle) | — | `Spec.Collapse` | — | Integer-exact, byte-gated cross-device |
| Dither (FS / Atkinson / STBN3D blue-noise) | `kernels.zig` | — | — | `Spec.Dither` | — | Sequential integer error buffer; sole shipped path |
| Significance split-fill | `kernels.zig` | (parity oracle) | — | `Spec.Significance` | — | Min-population enforcement, integer distance |
| OKLab Q16 → sRGB8 | `kernels.zig` | — | — | reference | — | Ottosson M1/M2 i64 + integer `icbrtQ16`, byte-exact |
| Global collapse (P operator, GIFA→GIFB) | `kernels.zig` `s4_global_collapse` | `FarthestPointCollapse` | — | `Spec.Collapse.globalCollapseQ16` | — | Integer-exact pooled maximin; the NN-injection seam |
| 1-D Haar pair-tree | `kernels.zig` `s4_haar_*` | `PaletteHaarTree` (oracle) | — | `PairTreeFixed` | — | Reversible integer lifting (distinct family from RGBT) |
| **RGBT 2-D cube-ladder lift (R operator)** | `kernels.zig` `s4_rgbt_lift_quad`/`s4_rgbt_unlift_quad`/`s4_cube_lift_level`/`s4_cube_unlift_level` | `RGBT4DLift.swift` | (Phase-5b kernel **absent**) | `Spec.RGBTLift` / `Spec.CubeLadder` | — | Lossless (2×2)↔1 integer S-transform; the pivot core |
| LZW + GIF89a assemble / encode / decode | `kernels.zig` `s4_gif_assemble` | `GIFEncoder` (preview/B fallback) | — | reference | — | Byte-faithful encoder, SHA256-pinned |
| Zone / look / 65³ `.cube` LUT | `kernels.zig` `s4_zone_profile_q16`/`s4_look_transfer_q16`/`s4_build_cube_q16` | facade | — | `Spec.{ZoneProfile,LookTransfer,CubeLut}` | — | Integer-exact LUT export |
| Pipeline orchestration / telemetry | — | `DeterministicRenderer` | — | — | — | Holds state, calls C-ABI, no determinism needed |
| Value head (Bradley-Terry beauty) | — | `AtlasTrainer` (MPSGraph) | — | `PaletteOracle` | — | Float aesthetic reward; on-device, proven |
| Look-NN forward (future) | (`s4_load_look_net` aliasing) | hand-written (NOT wired) | maybe | `LookNetE/R/D`, `LookNetEval` | `look_net_mlx.py` | Trainable weights, float; verified vs golden |
| Float K-means extraction (preview) | — | `Pipeline.swift` | `Shaders.metal` | — | — | Interactive speed; explicitly NOT bit-exact |

**The ONE governing rule:** integer-exact + deterministic + cross-device-reproducible → **Zig**
(all `s4_*` kernels in `Native/src/kernels.zig`, gated byte-for-byte against Haskell golden
vectors); perceptual / float / trainable → **Swift** (+ **MLX** off-device for training);
GPU capture acceleration → **Metal**. Color-science constants (sRGB↔linear, OKLab M1/M2) are
tripled identically across Zig / Swift / Haskell on purpose.

**Two reversible-lift families now coexist.** The 1-D `s4_haar_*` pair-tree is the look-NN
coefficient space; the **RGBT (2×2)↔1 lift** (`Spec.RGBTLift` / `Spec.CubeLadder`) is the
product-facing reversible operator that builds the cube ladder. They are distinct lifting
families that share the one pinned arithmetic hazard — floor division (`@divFloor` ≡ `div` ≡
`floorDiv`). The look-NN is demoted to the **NN-guided Synthesize↑** (64³→256³ super-res)
strictly *above* a deterministic `Spec.Upscale256` floor; the deterministic tier ships first.

**Intentional duplication vs drift.** The tripled color constants, pure-Swift
`FarthestPointCollapse` (`PaletteCollapse.swift`), `PaletteHaarTree`, and the new
`RGBT4DLift` are **parity oracles** — gated against the SPEC golden (`CollapseGolden`,
`RGBT4DGolden`), exact for integer paths. The one genuine *drift* is `GIFEncoder.swift`'s
legacy float-dither encoder, kept only for the GPU-preview / GIFB-encode path and superseded
on the shipped per-frame path by Zig `s4_gif_assemble`.

## 2. How Swift + Zig + MLX serve the NN

**(a) L/a/b typing.** The net carries a 64-D hidden context split by the Hurvich-Jameson
σ-decomposition into **22 achromatic (σ-fixed, L)** + **42 chromatic (σ-negated: 21 a +
21 b)** dims (`LookNetE`). The σ-action is a fixed diagonal involution negating the chromatic
channels; L lives in the +1 eigenspace, a/b in the −1 eigenspace.

**(b) The unifying centroid-balancing core.** ONE 64×64 weight-shared block (`LookNetR`) reused
8 times (Mixture-of-Recursions / Universal Transformer) with a PonderNet halting head. Each
application amortizes one Wasserstein-2 / Bures barycenter iteration over the pooled OKLab
Gaussian mixture of the 64 input palettes. σ-equivariance forces the block block-diagonal
(45% symmetry-pruned); the halting head is σ-*invariant*.

**(c) Data path (where each tier plugs in).**
1. **Metal** — 64 frames captured, linearized, OKLab; per-frame K-means → local 256-palettes.
2. **Swift** — float OKLab → Q16 hand-off (`SixFourNative`).
3. **Zig (integer floor)** — `s4_quantize_frame` produces the 64 per-frame Q16 centroids.
4. **Swift/MLX NN core** — pool 64 palettes → OKLab GMM tokens → encoder → barycenter
   recursion → decoder emitting a **384-DOF σ-pair genome** (3·128 generators; the 768-real
   leaf space is the *output* it reconstructs, NOT the genome — see §6).
5. **Zig (integer floor)** — `s4_global_collapse` (pooled-maximin gamut floor) expands into
   the 256-leaf global palette, byte-exact.
6. **Zig** — `s4_palette_oklab_to_srgb8` + `s4_gif_assemble` emit the final GIFB.

Zig is the integer-exact floor at steps 3, 5, 6; Swift is the host orchestrator and (future)
learned core at steps 2, 4. **CRITICAL:** the trained core does not yet consume the Zig floor —
the trained blob is *loaded* but has no render-path consumer, and the running trainer learns
**grayscale-L only** (a=b=0). Step 4 is therefore design-quality on device; step 5 ships as
the deterministic `FarthestPointCollapse`, not a learned barycenter (see §5, §6).

**(d) The trainer (Mac, never shipped).** `regimen.py` is the one-command L-NN protocol
(gates → train → quality-gate → export blob). `train_look_net_mlx.py` is the **real, run
trainer** (GAN + PonderNet halt + Bures anchor, soft-OT). `zig_native.py` is the ctypes data
engine: `s4_synth_burst` + `gif_to_tokens` produce the (16384, 10) GMM tensor-of-the-GIF the
device sees. `export_look_net_blob.py` writes the **S4LN** blob
(`out/look_net_trained.s4ln`, 133,923 bytes on disk) loaded by Zig `s4_load_look_net`.
`gates.py` demands beating the 256-level Wasserstein barycenter on EVERY SynthClass. The Rust
**studio** is a separate Mac sidecar: `analysis-core` (golden-checked 1e-6 math),
`look-nn-baseline` (gradient-free 1+1-ES = the non-NN floor), `explore` (writes FINDINGS.md).

## 3. The cube: moving in COLOR space AND FRAME space, now factored into R ⟂ P

**Two orthogonal data spaces.** COLOR space = the 256-colour palette as 3D OKLab (L,a,b).
FRAME/CUBE space = (x,y,t), 64×64 pixels over 64 frames — one voxel per address. The
(x,y,t) cube is the abstract substrate the pivot operators act on, **not** a rendered review
peer (the 3D `VoxelCubeView` was deleted 2026-06-07 — see §6).

**Two orthogonal product operators (the pivot's reframe).** The three-rung ladder is the
product of two operators forking from the 64³ pivot:
- **Axis A — resolution R** (×4 ladder, 16³ ↔ 64³ ↔ 256³), supplied by the lossless RGBT
  lift. `Spec.CubeLadder` proves `Distill∘Synthesize = id` within captured resolution;
  `Synthesize∘Distill ≠ id`, with loss isolated to `synthBeyond` (NN super-res strictly
  *above* captured resolution).
- **Axis B — palette scope P** (per-frame GIFA ↔ global GIFB), supplied by `globalCollapseQ16`.

Together they are a **6-cell product matrix** that replaces the bespoke per-path code. The
reversible engine: a 2×2 block `(a,b,c,d)` maps to sub-bands `(R,G,B,T) = (LL,LH,HL,HH)` —
the semantic distinctness of the four sub-bands IS the invertibility. **GroupRGBT is no
longer just Review grouping:** `GroupRGBT.circularWindows` is the stride-1 width-4
rotation-equivariant SIMT buffer feeding `RGBTFeature → CubeLadder`, and group-**SELECT** is
now the maximin-correct collapse lever driving `globalCollapseQ16`.

**The pivot's landed spec cluster.** `Spec.RGBTLift`, `Spec.CubeLadder`, `Spec.RGBTFeature`
(completeness-preserving), `Spec.GroupRGBT.circularWindows`, `Spec.Upscale256` (256³
deterministic floor), `Spec.Entropy` (Phase-0: measures pool weights + per-tier scope via
`gaussianColorEntropy` / `sinkhornDivergence` / `gamutCoverageFraction`), `Spec.CanonicalPhase`
(necklace loop-gauge tie-break). A dedicated `Codegen.RGBT4D → RGBT4DGolden.swift` emitter
puts the Swift port on the byte-exact drift gate.

**Honesty facts.** Addressing ≠ dimensions: the 16²/4⁴/2⁸ branchings are tree depth (8 binary
splits over 3 OKLab axes), never 8D. No embedding anywhere (no t-SNE/UMAP/PCA) — all views use
true data coordinates.

## 4. End-to-end data flow

**BOOT (Swift).** `SixFourApp` → `SurfaceView.task` → `CaptureViewModel.bootstrap()` builds
`MetalPipeline(64)` + `CaptureSession(20fps,64)` + GeneStore; engine `.idle` → σ event
`.sessionReady` → σ `.live`.

**LIVE (Swift/Metal).** `CaptureSession` hands YCbCr10 frames → `Shaders.metal`
`cropDownsampleLinearizeKernel` → RGBA16F linear → `linearToOklabKernel` →
`unsharpMaskLKernel` → **`OKLabTile`** (64×64 OKLab floats) → preview callback →
`makeQuantizedPreviewImage` → σ.previewTile/previewPalette; `LivePhaseField` paints the
CellSprite hero + 16×16 palette-as-shutter; every κ tick σ(tile+palette) → `FieldMetalView` →
`field.metal` colours each 4pt cell.

**CAPTURE.** tap palette → σ.step(`.shutterTap`) → σ `.locking` → `engine.capture()` →
`lockExposureAndWhiteBalance` → `captureBurst = [OKLabTile]` (64, via `CoalescingFrameRenderer`,
no recorded-frame drops).

**RENDER (Swift→Zig, branches on `AppSettings.paletteScope`).**
- **PER-FRAME GIFA** — `DeterministicRenderer.render` → per frame `quantizeFrame`
  (`s4_quantize_frame`, maximin + Lloyd) → `centroidsPerFrame:[[Int32]]` (Q16 OKLab) →
  `ditherFrame` (`s4_dither_frame`) → `significanceFill` (`s4_significance_fill`) →
  `paletteToSRGB8` → `srgbPalettes` + `indicesPerFrame` → `SixFourExport.replicate`
  (64→256 index, 1→4×4) → `gifAssemble` (`s4_gif_assemble`) → `Result.gifData` + sha256;
  gated `CompleteVoxelVolume` + `SignificantVoxelVolume`.
- **GLOBAL GIFB** — `renderGlobalPalette` → same per-frame quantize → `globalCollapse`
  (`s4_global_collapse` ≡ `Spec.Collapse.globalCollapseQ16` ≡ `FarthestPointCollapse` over the
  pooled 64·256 centroids) → `CollapsedPalette.leaves` → optional Atlas `curatedLeavesQ16` →
  `BranchedPalette.projectQ16` (`.b16`/`.b4`/`.b2` = Flat768 / Quad4-513 / σ-pair-384) →
  whole-GIF `significanceFill` over 262,144 pixels → one GCT → `GlobalResult`; gated
  `GlobalCompleteVolume` + `GlobalSignificantVolume`.

**OUTPUT.** `CaptureOutput{ gifURL, palettesForDisplay:[64][256], frameIndicesForVoxels:[64][4096],
sha256 }`.

**BROWSE (Act III).** held in `SurfaceView.pendingOutput`; user scrubs σ.cursor + `togglePick`
→ 4 anchors → `.picked4`.

**COMMIT.** `palettesForDisplay` → σ.palettesPerFrame; frameIndices packed → σ.indexCube
(flat `t·4096 + y·64 + x`); `.committed` → σ `.review`; heroes read
`σ.gifCell(x,y,t) = palettesPerFrame[t][indexCube[…]]`.

**EXPORT.** `ReviewPhaseField` → `LadderExport` builds the 16³ working / 64³-B rungs
(`FarthestPointCollapse` + `BranchedPalette` + `GIFEncoder.encodeGlobal`); the LOOK path runs
captured palette → `s4_zone_profile_q16` → `s4_look_transfer_q16` (live preview) OR
`s4_build_cube_q16` (65³ Log3G10→Rec.709 `.cube`).

**TRAINER (Mac, offline).** seed + SynthClass → `s4_synth_burst` → `Burst.gif` →
`gif_to_tokens` (16384,10 GMM tokens) → generated LookNet → 384-DOF σ-pair genome →
`export_look_net_blob` → `look_net_trained.s4ln` (133,923 B) → on-device `s4_load_look_net`
(aliasing pointers) → hand-written Swift forward pass — **NOT YET wired into render.**

## 5. The cross-language byte-alignment contract

**Haskell is the single source of truth:** same Haskell ⇒ same emitted artifacts. Ports never
hand-copy constants; they inherit them from the `Codegen.*` emitters into `SixFour/Generated`,
`trainer/generated`, `studio`. Two transport regimes by numeric class:

1. **INTEGER-EXACT kernels** (collapse, Haar pair-tree, **RGBT cube-ladder lift**, genome
   projection, significance, color Q16) are transported as plain `Int` literals and gated with
   `==` (**NO tolerance**). These are owned **3×** and must agree byte-for-byte:
   **Haskell ≡ Swift ≡ Zig** (e.g. `globalCollapseQ16 ≡ FarthestPointCollapse ≡
   s4_global_collapse`).
2. **FLOAT behaviour** (NN forward, value head, genome float projection) is transported as
   **hex-IEEE754** (`castDoubleToWord64`) and gated within `meta.tolerance = 1e-6`, because
   cross-language matmul summation order diverges at the ULP level — bit-equality is explicitly
   NOT claimed.

**Verification topology is HUB-AND-SPOKE, never peer-to-peer.** Every port gates against the
SPEC golden; Zig vs Metal are never compared directly. Swift `RGBT4DLift` gates on
`RGBT4DGolden.swift`; Zig gates on `rgbt4d_golden.json`; both inherit from `Spec.RGBTLift`.

**The one pinned arithmetic hazard** across all three is floor division:
`@divFloor` ≡ Haskell `div` ≡ Swift `floorDiv` (with `@divTrunc` ≡ `quot` for truncating paths).

**Determinism contract.** Same burst ⇒ same GIF bytes ⇒ same SHA256, so the float GPU paths
(`GIFRenderer` / Wu / KMeans / blue-noise) are demoted to a **non-reproducible fallback**.

**The deploy blob is the only train→device artifact:** a self-describing little-endian float32
**S4LN** format (magic `S4LN` v1, fixed tensor order `phi, w1, w2, halt_w, halt_b, head0..7`)
with a `.spot.json` byte-exact assert checked by `export_look_net_blob`'s round-trip self-test
and the Zig parser `s4_load_look_net` (aliasing, no copy).

**Enforced in CI by `spec/scripts/s4.sh`:** `verb_verify` = `cabal test` (Haskell + `s4_*`
kernel laws), `verb_native` = `zig build test` (cross-lang fixtures) + the Swift build; any
drift fails the gate.

**OPEN determinism knob.** Lloyd-iteration count differs per path — shipped capture/collapse
uses `lloyd_iters = 0` (pure maximin) vs the GPU / full-pipeline + gif fixtures' 15.
Byte-exactness requires identical counts across Zig/Swift/Metal per path (NOTES Q4 unresolved).
STBN3D ships only an 8³ tile tiled to 64³ (true 64³ FFT-void mask deferred, TR-1).

## 6. CRITICAL current-state callouts (read before trusting any older doc)

**RGBT-4D is landed but DORMANT end-to-end.** Spec + Zig + Swift + golden all landed
(Zig `s4_rgbt_lift_quad`/`s4_rgbt_unlift_quad`/`s4_cube_lift_level`/`s4_cube_unlift_level` at
`kernels.zig:621-732`, gated by `rgbt4d_fixture_test.zig` vs `rgbt4d_golden.json`, commit
`e7ebf11`; Swift `RGBT4DLift.swift`, zero-dep, floorDiv hazard fixed). **But:**
`AppSettings.rgbt4dEnabled` (key `sixfour.rgbt4d.v1`) defaults **OFF** and is read nowhere but
its own `didSet` (no Settings UI toggle); `RGBT4DLift.swift` has **ZERO production callers**
(only `RGBT4DGoldenTests` + `AppSettings` + itself); the Zig RGBT exports are **NOT surfaced**
in `SixFourNative.swift`; the Phase-5b Metal `simd_shuffle` circular-stencil kernel **does not
exist**; and the three-GIF {16³,64³,256³} export action is **absent (gap G6)**. While the flag
is false, shipped render bytes are byte-IDENTICAL to the pre-pivot app — **the app still ships
ONE 64³ GIF.** Master is at **834 Haskell spec tests** post-pivot.

**GIFB IS wired in production (the "zero-callers" claim is FALSE).**
`CaptureViewModel.renderDeterministicGlobal → DeterministicRenderer.renderGlobalPalette →
SixFourNative.globalCollapse` (`s4_global_collapse`), gated by `AppSettings.paletteScope ==
.global`. The pivot reframes global collapse as the first-class **P** operator. Any "GIFA→GIFB
collapse has zero callers / the app cannot emit a global-palette GIF" text is retired.

**Decoder DOF is settled at 384.** The spec, the generated MLX net (`look_net_mlx.py`,
`net_shape.py`), and the running trainer all use the **384-DOF σ-pair genome**; **768 is the
flat leaf space** (256·3) that the genome reconstructs — do not conflate them. The *live* drift
is the opposite of the old "768 un-wired" note: `studio/look-nn-baseline/src/lib.rs` still
hand-optimizes the OLD 768-flat-coefficient genome via 1+1-ES even though its own generated
`contract.rs` exposes `SIGMA_PAIR_DOF = 384` / `DECODER_IO out_dim = 384` — **the Rust baseline
is genome-incompatible with the current MLX decoder.**

**A look-NN trainer DOES exist.** `train_look_net_mlx.py` is real and run; `out/look_net_trained.s4ln`
(133,923 B) and `out/atlas_net_trained.npz` are on disk. The trainer has produced a deploy blob.
The remaining gap: the blob has **no on-device render consumer** (`s4_load_look_net` aliasing-parses
it, nothing renders from it), and the trainer learns **grayscale-L only** (a=b=0, chroma deferred).

**`Spec.Loss` is ported but unused by the runner.** `Properties.Loss` is wired into
`test/Spec.hs`; `look_net_loss_mlx.py` is the gated MLX port. BUT it defines the training
*target* only — `train_look_net_mlx.py` minimizes its own GAN / soft-OT / Bures-anchor loss on a
grayscale-L palette, so the verified-canonical 3-term colour loss is **not** the loss actually
optimized.

**The trained `LookNetCollapse` barycenter does NOT exist on device.** The `PaletteCollapse`
protocol was designed for a learned Wasserstein/Bures collapse; the shipped global palette is
**always** the deterministic pooled-maximin `FarthestPointCollapse`. (Post-ADR-014, full discrete
`buresBarycenter` is gone; only `buresBarycenterCov` — Gaussian-approx covariance, Rust golden —
remains, with `Loss.fidelityLoss` flagging `mixtureAsGaussian` as the approximation and
`fidelityLossSinkhorn` as the multi-modal alternative. The shipped collapse is NOT a barycenter.)

**The 3D `VoxelCubeView` is gone.** `VoxelCubeView.swift` + the `voxel_raymarch` Metal kernel
were **deleted 2026-06-07**, replaced by the `Surface.bakeCube` cell rasterizer. The review hero
is the flat 2D `gifCell` animation; the (x,y,t) cube is the abstract substrate the R/P operators
act on, not a rendered peer.

**Maximin is canon, not a bug.** Maximin (Gonzalez farthest-first) IS the deterministic-path
canon — do not re-flag "maximin ≠ Wu". Wu / KMeans / Octree live only on the demoted float GPU
`GIFRenderer` fallback.

**Stale census / header figures.** The "59 Swift / 9,117 LOC / 22 dirs" APP-MAP census is months
out of date (new `SixFour/RGBT4D/`, `SixFour/Atlas/`, `SixFour/UI/Surface/` and many cell-field
files landed across June). The C header `Native/include/sixfour_native.h:253` is STALE — it
documents 24 total symbols and **omits all four RGBT prototypes** (exported in `kernels.zig:621+`
but absent from the header), so C-header callers get no prototype for the newest kernels.
`docs/STATUS.md` is itself **pre-pivot**: it still says "595 tests pass" (lines 130, 160), has no
RGBT-4D / cube-ladder / three-GIF ledger row, and needs a refresh to stay canonical (master = 834).

## 7. Build order (organized — gated tiers ship deterministic-first)

1. **Surface the RGBT-4D kernels and turn the flag on.** Add the `SixFourNative` facade methods
   for `s4_rgbt_lift_quad`/`s4_rgbt_unlift_quad`/`s4_cube_lift_level`/`s4_cube_unlift_level`, give
   `rgbt4dEnabled` a real Settings toggle and at least one production caller, and update the stale
   C header. This unblocks the pivot from "spec-ahead-of-code" to a live operator.
2. **Build the three-GIF {16³,64³,256³} export (gap G6) + the missing ladder keystones.**
   G1 temporal-distill 64→16 (`Spec.TemporalPool.quartetPool`) is designed-not-built (GroupRGBT
   only SELECTS, never POOLS); G3 `Spec.Upscale256` is golden-proven but has **no Swift port / zero
   iOS consumers** (the app's 256 output is spatial `replicate2D` with time held at 64). Then
   factor R and P (G2/G4) as **orthogonal composable operators** — `renderGlobalPalette` is today a
   ~150-line parallel path; the goal is one `Spec.CubeLadder`-driven `render(tier,scope) =
   encode(R(P(cube)))` so adding a tier is O(1), not O(rewrite).
3. **Lock the integer-floor ↔ NN seams.** Keep `SIGMA_PAIR_DOF = 384` pinned across the
   Rust/Swift generated contracts; fix the Rust baseline's 768-genome incompatibility; keep the
   MLX↔torch `allclose` arm in `check_golden.py`.
4. **Promote the trainer from grayscale-L nucleus to full colour + populate data.**
   `train_look_net_mlx.py` trains the L head against soft-OT/GAN; extend to a/b chroma + the full
   σ-pair decoder, switch its objective to the verified-canonical `Spec.Loss` port, and supply the
   absent `trainer/data/reference_gifs/` (Zig synthetic-GIF engine or real captures).
5. **Hand-write the on-device forward pass.** `s4_load_look_net` is load-only; once colour weights
   exist, add the Swift/Accelerate (or Metal) forward pass feeding the genome → Zig collapse →
   256-leaf palette, gated vs golden. This is what makes the trained blob actually render.
6. **Atlas / Organ deploy seams.** `AtlasTrainer` trains a Bradley-Terry value head on-device
   (proven) but does NOT yet feed palette generation (`candidateB` is a deterministic-perturbation
   placeholder, no MCTS/search); the Atlas Swift files are UI-track stubs with no generated contract
   (`Spec.AtlasState/Board/Move` planned-not-built). Wire only after a real collapsed palette exists
   to curate over.
7. **Deferred:** `Spec.PaletteSearch` MCTS (the GIFA→GIFB "art" layer) — spec-complete, no iOS
   consumer; the browse picks (`surface.picks`, the 4 Act-III anchors) are currently **cosmetic**
   (they feed only the Review `QuartetDelta` motion outline, never the rendered GIF bytes); the
   designed picks → `Spec.GroupRGBT` global-collapse path is not built.

## 8. Device-verification caveat

No simulator camera and the arm64-only prebuilt Native lib link-fails against a forced x86_64
build, so the Phase-5 RGBT-4D Swift logic is **standalone-verified-exact but DEVICE-UNVERIFIED** —
`RGBT4DGoldenTests` must be run on an iPhone 17 Pro sim/device. Per the compile-only contract,
the bar for camera paths is BUILD SUCCEEDED; the user runs on real hardware.
