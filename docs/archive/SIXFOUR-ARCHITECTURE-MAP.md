> **ARCHIVED 2026-06-05 — superseded by [docs/STATUS.md](../STATUS.md).**
> This document is retained for history only. Do NOT use it for current build-state: its
> figures, line numbers, and "zero callers / GIFB never produced" claim are stale and were
> corrected when its content was merged into the canonical STATUS.md. For current truth, read
> docs/STATUS.md and run scripts/verify-doc-claims.sh.

# SixFour — Architecture Map

> **Canonical status ledger (2026-06-05).** This doc owns the **built / design / missing**
> ledger — the single source of truth for current state (what's wired, test counts, open gaps).
> `SIXFOUR-VISION.md` owns the narrative. Other docs defer here for status rather than restating it.

## 1. Swift WHERE vs Zig WHERE

| Capability | Zig | Swift | Metal | Haskell-spec | Why |
|---|---|---|---|---|---|
| Capture transfer (sRGB/Rec709/HLG/AppleLog) + primaries + linear→OKLab | — | — | `Shaders.metal:4–104` | — | GPU-native, float OK at capture, no determinism needed |
| OKLab float → Q16 int32 | — | `SixFourNative.swift:203–212` | — | — | One-time deterministic hand-off; Zig owns everything after |
| Quantize (maximin + Lloyd + nearest) | `kernels.zig:213–328` | — | — | `Collapse.hs` | Integer-exact, byte-gated cross-device |
| Dither (FS/Atkinson/blue-noise/frozen) | `kernels.zig:519–617` | — | — | `Dither.hs` | Sequential integer error buffer; sole path |
| Significance rebalance | `kernels.zig:642–776` | — | — | `Significance.hs` | Min-population enforcement, integer distance |
| OKLab Q16 → sRGB8 | `kernels.zig:809–842` | — | — | reference | Fixed-point gamma, byte-exact |
| Global collapse (GIFA→GIFB) | `kernels.zig:340–362` | — | — | `Collapse.hs` | Integer-exact pooled maximin; reuses `s4_quantize_frame` with `lloyd_iters=0` |
| Haar analyze/reconstruct | `kernels.zig:378–518` | — | — | `PairTreeFixed.hs` | Reversible integer lifting (NN's coefficient space) |
| LZW + GIF89a assemble | `kernels.zig:985–1069` | — | — | reference | Byte-faithful encoder |
| Pipeline orchestration / telemetry | — | `DeterministicRenderer.swift` | — | — | Holds UI state, calls C ABI, no determinism needed |
| Value head (beauty + diversity) | — | `PaletteValue.swift:1–81` | — | `PaletteOracle.hs` | Float aesthetic reward; NN training ground truth |
| Look-NN forward (future) | — | hand-written (not landed) | maybe | `LookNetE/R/D.hs` | Trainable weights, float; verified vs golden |
| Float K-means extraction (preview) | — | `KMeansPalettePipeline.swift` | `Shaders.metal` | — | Interactive speed; explicitly NOT bit-exact |

**The ONE governing rule:** integer-exact + deterministic + cross-device-reproducible → **Zig** (all `s4_*` kernels in `Native/src/kernels.zig`, gated byte-for-byte against Haskell golden vectors); perceptual/float/trainable → **Swift**; GPU capture acceleration → **Metal**. Color-science constants (sRGB↔linear, OKLab M1/M2) are tripled identically across Zig/Swift/Haskell on purpose.

**Intentional duplication vs drift:** the tripled color constants, the pure-Swift `FarthestPointCollapse` (`PaletteCollapse.swift:33–134`), and `PaletteHaarTree` (`PaletteHaarTree.swift`) are **parity oracles** — test-only mirrors gated against Haskell golden (`CollapseGolden`; exact for the integer paths, within-tolerance for any Double Haar oracle since float Haar cannot be bit-exact cross-language). The one genuine *drift* is `GIFEncoder.swift`: a legacy float-dither encoder kept only for the GPU preview path, superseded on the shipped path by Zig `s4_gif_assemble`.

## 2. How Swift + Zig serve the NN

**(a) L/a/b typing.** The net carries a 64-D hidden context split by the Hurvich-Jameson σ-decomposition into **22 achromatic (σ-fixed, L)** + **42 chromatic (σ-negated: 21 red-green a + 21 blue-yellow b)** dims (`LookNetE.hs`). The σ-action is a fixed diagonal involution negating the chromatic channels; GMM input channels route σ-correctly (μL→achromatic slot 0, μa→slot 22, μb→slot 43). L lives in the +1 eigenspace, a/b in the −1 eigenspace.

**(b) The unifying centroid-balancing core.** It is the **L4 Recursive Core** (`LookNetR.hs:74–176`): ONE 64×64 weight-shared block reused 8 times (Mixture-of-Recursions / Universal Transformer) with a PonderNet halting head. Each application **amortizes one Wasserstein-2 / Bures barycenter iteration step** over the pooled OKLab Gaussian mixture of the 64 input palettes — "balancing the centroids" = matching the moments of the output measure to the pooled input measure. σ-equivariance forces the block to be block-diagonal (22×22 + 42×42 = 2248 free params, 45% symmetry-pruned); the halting head is σ-*invariant*, reading only (‖achromatic‖², ‖chromatic‖²).

**(c) Data path (where each tier plugs in).**
1. **Metal** — 64 frames captured, linearized, OKLab; per-frame K-means → 64 local 256-palettes (Stage A).
2. **Swift** — float OKLab → Q16 hand-off (`SixFourNative.oklabToQ16`, `:203`).
3. **Zig (integer floor)** — `s4_quantize_frame` produces the 64 per-frame Q16 centroids deterministically.
4. **Swift NN core (design)** — pool 64 palettes → OKLab GMM tokens → L3 encoder → **L4 barycenter recursion** → L5 decoder (**384-DOF** σ-pair coefficients = 3·128 generators).
5. **Zig (integer floor)** — `s4_global_collapse` (pooled-maximin gamut floor) and `s4_haar_reconstruct` expand the NN's Haar coefficients into the 256-leaf global palette, byte-exact.
6. **Zig** — `s4_palette_oklab_to_srgb8` + `s4_gif_assemble` emit the final GIFB.

Zig is the integer-exact floor at steps 3, 5, 6; Swift is the perceptual/host orchestrator + the (future) learned core at steps 2, 4. **Important: the "greater abstractions" cannot yet consume the Zig floor** — there is no trained full-colour NN and no on-device forward pass, so step 4 is design-only and step 5's collapse is unreached (see §4).

**(d) Built-vs-design ledger.**
- **BUILT + gated:** Zig collapse, Haar, quantize, dither, significance, palette→sRGB8, GIF; Swift+Haskell parity oracles (`CollapseGolden`, `PaletteValueGolden`); Spec reference baselines for L3/L4/L5 (encoderReference, identity-refine, σ-pair decoder); the value head (`PaletteValue.swift`); the loss + OT spec.
- **TRAINER (partial):** `trainer/train_look_net_mlx.py` **exists** but is a **grayscale-only nucleus trainer** — an AxisNet *L*-head producing a (256,) lightness-sorted palette, with an image-space `Discriminator` and the `global_palette.py` **Sinkhorn entropic-OT** differentiable renderer (uniform palette marginal = the significance/full-usage constraint). It is the a=b=0 milestone, **not the full-colour closure**; `train_metric.py` is the separate metric-learner.
- **DESIGN-ONLY:** every *trained colour* layer (no weights for the full L/a/b net), the MLX forward scaffold (`trainer/generated/look_net_mlx.py`), and the Swift/Metal on-device forward pass — `SixFourNative.loadLookNet` (`:82`) is **load-only with zero callers**.
- **MISSING:** trained colour weights; populated training data — the dirs `trainer/data/captured_frames` and `trainer/data/reference_gifs` exist but are **empty**.
- **DOF correction:** decoder is **384** (σ-pair: 3·128), confirmed at `look_net_mlx.py:33` (`DECODER_OUT_DIM = 384`) and `LookNetD.hs`. Any "768-DOF" claim (incl. CLAUDE.md's palette note) is stale.

**Subsystems not previously surfaced:** `Spec/PaletteSearch.hs` (MCTS refinement that *should* consume the collapsed global palette — spec-complete, no iOS consumer); `trainer/global_palette.py` Sinkhorn-OT substrate (the differentiable training bridge); the AxisNet *L*-head (the grayscale nucleus actually being trained).

## 3. The 64³ GIF: moving in COLOR space AND FRAME space

**Two orthogonal spaces.** COLOR space = the 256-colour palette as 3D OKLab (L,a,b) — one colour per point. FRAME/CUBE space = the GIF's (x,y,t), 64×64 pixels over 64 frames — one voxel per address. They are distinct; brushing/filtering links them.

**Existing surfaces.**
- COLOR (wired + golden-spec): **Palette Cloud** (`PaletteCloudView.swift`) — true 3D OKLab dots, orbit/scrub/brush/plane-snap, orthographic-default distance-true. **Tree** treemap (`PaletteTreeView.swift`) and **Grid** are wired but carry *truth bugs*: split planes are drawn (border thickness = depth, `:72–75`) but **unlabelled** by axis/threshold; the grid bins per-frame instead of over a fixed canonical range. **AddressPicker** (`AddressPickerView.swift`) is a wired wheel-based subtree-brushing tool, not a spatial explorer.
- FRAME (built, **SHELVED — orient-only, not a live peer**): **VoxelCubeView** (`VoxelCubeView.swift` + the `voxel_raymarch` Metal kernel) — 64³ orthographic DDA raymarch (Amanatides–Woo), rest pose byte-identical to the 2D GIF hero, orbit reveals time-as-depth, scrub/auto-rotate/luma-floor/provenance filter. **Retired as a palette-explorer peer by the full-collapse pass (#5):** `.voxel3D` is no longer a selectable representation — a persisted selection **self-heals to `.structure`** (`GIFReviewView.swift:70–102`). The view code still exists and the `case .voxel3D` branch can instantiate it (`GIFReviewView.swift:157–163`), but it is off the default path. The 2:1 dimetric ruleset / iso controls / flat-pose brushing it carries are documented in `docs/archive/SIXFOUR-VOXEL-CUBE.md` (archived, marked SHELVED).

**Honesty facts.** Addressing ≠ dimensions: the 16²/4⁴/2⁸ branchings are *tree depth* (8 binary splits over 3 OKLab axes), never 8D. No embedding anywhere (no t-SNE/UMAP/PCA) — all views use true data coordinates. GRID Law #2: selection via opaque dark-step only, never alpha — with ONE sanctioned exception, the cube's frame-isolation *analysis mode* (owner-signed-off 2026-06-03), where non-focus slices take a ghost alpha so a single frame's palette can be studied (`docs/archive/SIXFOUR-VOXEL-CUBE.md` §0.3 RULE-CUBE-ISOLATE — archived, cube shelved).

**Unified phone navigation design.** A 4-mode representation selector — [structure] [grid] [cloud] [cube] — with two link mechanisms:
1. **Cross-view brushing** via a shared `brushedIndex` (plus a new multi-index brush): tap a colour in the Cloud → cube highlights all voxels using that index; tap a voxel region in the Cube → Cloud shows only those colours. The cube's flat-pose tap-pick → `brushedIndex` (front-face pixel → palette index) is **already shipped** (`VoxelCubeView.swift`); the remaining piece is the reverse Cloud-region → cube highlight.
2. **Global air-mask filter** hoisted to a shared `PaletteFilter` (new `ReviewViewModel`): one luma-floor / provenance / depth-band control + an "N of 256 visible" readout, applied identically across all four views.

VoxelCubeView *was* positioned as the GIFB-construction view (the only surface rendering the (x,y,t) cube the global palette colours), but the full-collapse pass (#5) **retired it as a peer** — GIFB visibility now belongs to the three palette analyzers (structure/grid/cloud), with the voxel cube held in reserve as an orient-only tool. Smallest first truth-win: label the treemap split planes (e.g. `L@0.52`) at `PaletteTreeView.swift:72–75`.

## 4. Build order (organized)

1. **Wire the GIFA→GIFB collapse into the render path (the structural keystone).** `s4_global_collapse` exists in Zig *and* is wrapped in Swift (`SixFourNative.globalCollapse`, `:268`) — but has **zero callers**; `DeterministicRenderer` ships per-frame palettes only. Add the render-flow step that calls `globalCollapse` so the app actually produces GIFB. This is the single biggest organize-the-vision gap: today the app cannot emit a global-palette GIF at all.
2. **VoxelCubeView — SHELVED (orient-only), not a Review peer.** It was briefly wired as `.voxel3D` (2026-06-03) but the full-collapse pass (#5) retired it as a palette-explorer peer; `.voxel3D` now self-heals to `.structure` (`GIFReviewView.swift:70–102`). The view + Metal kernel remain in-tree for reuse but are off the default path. No wiring work is scheduled; reinstating it as a peer would be a new decision. **(STALE as of 2026-06-06: the render-mode UI/UX vision revives VoxelCubeView as the 3D iso GIF render mode — it is PRESERVE+REWIRE, not shelved. See docs/STATUS.md and the cell-field demolition plan §3b.)**
3. **Lock the integer-floor ↔ NN seams.** Pin `SIGMA_PAIR_*` / `DECODER_OUT_DIM = 384` into the Rust/Swift generated contracts; purge the stale "768-DOF" wording (incl. CLAUDE.md); add an MLX↔torch `allclose` arm to `check_golden.py`. Cheap, removes drift before any full-colour training.
4. **Promote the trainer from grayscale nucleus to full colour + populate data.** `train_look_net_mlx.py` already trains the AxisNet *L*-head against the Sinkhorn-OT renderer (`global_palette.py`); extend it to the a/b (chromatic) channels and the full σ-pair decoder, port the remaining `Spec.Loss` terms (Bures fidelity + coverage + Ou-Luo beauty), and fill the empty `trainer/data/{captured_frames,reference_gifs}` (Zig synthetic-GIF engine or real captures). Only then does the L/a/b core stop being a contract.
5. **Hand-write the on-device forward pass.** `loadLookNet` (`:82`) is load-only; once colour weights exist, add the Swift/Accelerate (or Metal) forward pass calling Zig `s4_haar_reconstruct` to expand coefficients → 256-leaf palette, gated vs golden.
6. **Color+frame navigation truth-fixes (parallel, low-risk).** Treemap axis/threshold labels (do first, `PaletteTreeView.swift:72`), grid fixed-range binning + per-cell a11y, then the shared `PaletteFilter` air-mask + multi-index brush; later spatial tree drill-down + breadcrumb.
7. **Deferred:** `PaletteSearch` MCTS (the GIFA→GIFB "art" layer) — spec-complete (`Spec/PaletteSearch.hs`, 234 lines), no iOS consumer; wire only after steps 1–5 give it a real collapsed palette to search over.