# SixFour

**SixFour is an iOS 26 camera app that turns a 64-frame burst into a
64 × 64 × 256-colour animated GIF.** You hold the shutter, it captures 64 frames
at 20 fps, and it renders them into a tiny looping GIF: a 64 × 64 pixel grid,
64 frames long, drawn from a single shared 256-colour palette.

The interesting part is *how* it is built, and *why*.

## The idea

A burst of photos is a **64³ index cube**: 64 × 64 pixels × 64 frames, each
voxel an index into a colour palette. SixFour treats that cube as the *only*
state in the app. Everything you see is an honest projection of it:

- the **2D GIF** you export is the cube animated over time,
- the **16 × 16 palette grid** is the cube's colours laid flat,
- the **shutter** itself is a coarse Haar projection of the same cube.

"One cube, projected honestly" is the design law. There is no hidden second
representation that can drift out of sync with what you see.

The defining engineering principle is **Haskell-verified, dependency-free,
hand-written**:

1. **Haskell-verified.** A Haskell algebraic spec (`spec/`) is the single source
   of truth for every shape, law, and fixed-point algorithm. It generates the
   contracts for every other language and pins them bit-for-bit with golden
   vectors, so no implementation can drift from the math.

2. **Dependency-free.** The shipped iOS app has **zero third-party
   dependencies** — only Apple system frameworks and `simd`. All compute is
   hand-written Swift + Metal.

3. **Integer-exact.** The real render engine is a **deterministic, integer-exact
   Zig core** (`Native/`). It runs the same fixed-point (Q16) fold on every
   device, so the GIF is **bit-identical across phones** — no float drift, no
   "looks different on my device." This is the default path
   (`useDeterministicCore = true`); the GPU-float Swift renderer exists only as a
   throw-fallback.

A learned "look-network" that would emit a single *learned* global palette is
designed and golden-verified in Haskell, and partially trained on the Mac — but
it is **not shipped on device**. The global palette the app emits today is the
deterministic Zig **pooled-maximin collapse**, not a learned genome.

## Layout

| Path | Tier | Shipped? | Purpose |
|---|---|---|---|
| `spec/` | 0 — Haskell spec | No (Mac-side) | Formally-verified source of truth: shapes, laws, Q16 algorithms; emits Swift/Python/Rust/Zig contracts + golden vectors. GHC-boot-only deps. |
| `Native/` | — Zig core | **Yes** | The default render engine: integer-exact `s4_*` C-ABI kernels (the deterministic GIF pipeline). |
| `SixFour/` | 2 — iOS 26 app | **Yes (core product)** | Hand-written Swift + Metal, zero third-party deps. Capture, cell-grid UI, the renderer driving the Zig core, GIF export, swipe-to-LOOK + `.cube` LUT, the on-device Color Atlas trainer. |
| `SixFourTests/` | 2 | — | Swift unit tests (ports verified against Haskell golden vectors). |
| `trainer/` | 1 — Python trainer | No (Mac-side) | MLX base-net trainer; consumes generated Python contracts. `torch`/`coremltools` only for the dormant CoreML/ANE fallback. |
| `studio/` | — Rust analysis | No (Mac-side) | Analysis/baseline-research workspace (`analysis-core`, `look-nn-baseline` pure-Rust forward net, ES baseline, Bures covariance oracle). Not a runtime tier. |
| `scripts/` | — | — | Gate runner (`s4.sh`), codegen/build/lint/doc gates. |

## Architecture — the four real layers

```
  Haskell spec (spec/, Tier 0)          ── source of truth, Mac-side, NOT shipped
        │  emits contracts + golden vectors (Swift / Python / Rust / Zig)
        ▼
  ┌─────────────────────────────────────────────────────────────┐
  │  Zig deterministic core (Native/)   ── DEFAULT engine, shipped │
  │  s4_* C-ABI kernels, integer-exact, byte-identical per device  │
  └─────────────────────────────────────────────────────────────┘
        │  loaded by
        ▼
  iOS 26 app (SixFour/, Tier 2)         ── the SHIPPED CORE PRODUCT, zero deps
        ▲
        │  weights trained by (NOT shipped)
  Trainer (trainer/, Tier 1)            ── MLX on the M1, Mac-side
```

### 1. Haskell spec — the source of truth (`spec/`, Tier 0, not shipped)
Every dimension, law, and Q16 fixed-point algorithm is defined here first. The
`sixfour-spec` library is GHC-boot-only (`base`, `vector`, `containers`, `text`,
`transformers`). It emits Swift, Python, Rust, and Zig contracts and pins them
with **golden vectors** so no tier drifts. The gate is `cabal test`. Browse it
starting from module **`SixFour.Spec.Map`** — the categorised index.

### 2. Zig deterministic core — the default render engine (`Native/`, shipped)
The integer-exact pipeline that actually makes the GIF, identical on every
device:

```
widen → linear → OKLab → quantize (maximin = Gonzalez farthest-first + Lloyd)
      → dither → significance-fill → palette → LZW / GIF89a assemble
```

plus `s4_global_collapse` (per-frame → one global palette), the `s4_haar_*`
projections, the `s4_*_q16` look/LUT kernels, and `s4_load_look_net`. The header
(`Native/include/sixfour_native.h`) declares all **24** exports, and a gate
asserts the header symbol set equals the Zig export set.

The **maximin** step (Gonzalez 1985 farthest-first, then Lloyd) is the canonical
collapse in `Spec.QuantFixed` / `Spec.Collapse`, and the Zig matches it
byte-for-byte. It is the canon, not a bug.

### 3. iOS 26 app — the shipped product (`SixFour/`, Tier 2)
Swift 6.2 (strict concurrency), hand-written Swift + Metal, **zero third-party
dependencies** (Apple frameworks + `simd` only):
- the capture pipeline (64-frame burst at 20 fps),
- the **cell-grid UI** — one 4 pt cell atom, the whole screen is a cell field
  (no glass / no SF-Symbol chrome on the HUD),
- `DeterministicRenderer` driving the Zig core,
- GIF export: the per-frame **GIFA** path, the global-palette **GIFB** ladder,
  and Save,
- **swipe-to-LOOK** + R3D `.cube` LUT export,
- the on-device **Color Atlas** MPSGraph trainer.

Every port is verified bit-for-bit against the Haskell golden vectors.

### 4. Trainer — base-net training (`trainer/`, Tier 1, not shipped)
**MLX on the M1** is the primary base-net trainer. `torch` + `coremltools` exist
only for the dormant CoreML/ANE distillation fallback. It consumes the generated
Python contracts (`generated/stages.py`, `generated/net_shape.py`). Today the
trainer is **grayscale-L-only**, and there is no committed training data
(`trainer/data/` is absent / gitignored).

### Train → verify → deploy spine
- **Train (base net):** MLX on the M1.
- **Train (per-user, on device):** **MPSGraph** — an Apple system framework, so
  it stays inside the Tier-2 zero-dependency contract. Proven on real hardware
  (Color Atlas: `SixFour/Atlas/AtlasTrainer.swift`, MPSGraph SGD, Bradley–Terry
  value net, bit-identical loss trajectory Mac ↔ iPhone). MPSGraph does not run
  in the simulator (gated via `targetEnvironment(simulator)`).
- **Verify:** Haskell golden vectors gate every backend.
- **Deploy:** hand-written Swift + Metal on device (zero deps).
- **Fallback:** PyTorch → CoreML → ANE, kept dormant, **never shipped**. Never
  `mlx-swift`, never a CoreML black box.

## Build

### iOS app
The project is generated by [xcodegen](https://github.com/yonaskolb/XcodeGen):

```bash
xcodegen generate
xcodebuild -scheme SixFour \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build
```

Xcode 26.2, iOS 26, Swift 6.2. For device builds, set the team in `project.yml`.
(Camera apps are compile-checked only; the simulator has no camera, so on-device
behaviour is the user's verification step.)

### Spec + codegen (Haskell)
```bash
cd spec
cabal build
cabal test                 # 595 tests; the gate
cabal run spec-codegen     # regenerate the per-tier contracts
```

`spec-codegen` writes generated files to `SixFour/Generated/` (Swift contracts),
`trainer/generated/` (Python), and `studio/look-nn-baseline/src/generated/`
(Rust constants). Never hand-edit generated files; change `spec/src/SixFour/Codegen/`
and regenerate.

### Trainer (Python)
```bash
cd trainer
uv sync
python train_metric.py     # reads generated/stages.py + net_shape.py
```

### Full gate
```bash
scripts/s4.sh all          # codegen → doc → verify → native → lint → gen → build
scripts/s4.sh doc          # verify docs/STATUS.md claims (grep/test/find only)
```

`s4 all` runs the verbs in the order recorded in `scripts/gate-order.txt`. The
`doc` gate (`verify-doc-claims.sh`) is wired in right after `codegen`, so the
canonical `docs/STATUS.md` facts are re-asserted on every full **local** run.
CI (`.github/workflows/`) runs the checkout-safe gates — the spec-codegen drift
check + Haskell tests, and the GRID lint — on every push/PR. The `doc`, `native`,
and `build` gates stay **local-only**: `doc` and `native` assert local
generated/trained artifacts (e.g. the gitignored `trainer/out/` fixtures), and
`build` needs Xcode 26.2 / iOS 26, none of which exist on hosted CI runners.

## Status

`docs/STATUS.md` is the **single canonical status ledger** (gated by
`scripts/verify-doc-claims.sh`). Current state:

- **Spec suite: 595 Haskell tests pass** (`cabal test`).
- The **deterministic Zig render core is built and is the default path**
  (`useDeterministicCore = true`); the GPU-float Swift `GIFRenderer` is the
  throw-fallback only.
- **GIFA → GIFB global collapse is wired in production**:
  `CaptureViewModel.renderDeterministic` → `renderDeterministicGlobal` →
  `DeterministicRenderer.renderGlobalPalette` → `SixFourNative.globalCollapse` →
  Zig `s4_global_collapse`. The shipped global palette is the deterministic
  pooled-maximin collapse, **not** a learned NN genome.
- **Swipe-to-LOOK + R3D `.cube` LUT export is built**
  (`Spec.{ZoneProfile,LookTransfer,RedFrontEnd,CubeLut}`; Zig
  `s4_zone_profile_q16` / `s4_look_transfer_q16` / `s4_build_cube_q16`; 28 Zig
  tests; iOS build succeeds — on-device verification is the user's step).
- The **look-NN forward path is proven in Haskell** (`LookNetE/R/D`, a 384-DOF
  `SigmaPairTree` decoder) but **nothing runs it on device**: `loadLookNet` has
  zero production callers (open debt: `looknet-load-unused`). The learned global
  palette / NN-genome path is **design-only and unreached**.
- The decoder genome is **384-DOF** (3 × 128 σ-pair generators, `SIGMA_PAIR_DOF`);
  it reconstructs into the **768-real** flat leaf space (256 × 3). The 384
  emitted and the 768 leaf space are not the same thing.
- **On-device per-user training is proven on hardware** (Color Atlas:
  `SixFour/Atlas/AtlasTrainer.swift`, MPSGraph SGD, Bradley–Terry value net
  ≈29,249 params, ≈12.4 ms/step, loss trajectory bit-identical Mac ↔ iPhone).
- **Missing:** a full-colour trained NN with an on-device forward pass. The Mac
  trainer is grayscale-L-only and there is no committed training data.
- **North-star** is on-device personalized look-learning. A first spec footprint
  exists (`Spec.Atlas*` + `Spec.LookCategory`, 74 properties green). Open spec
  gaps: the look-category taxonomy and golden-gating of the on-device
  trainer/gradient spec.

## A note on the substrate (ADR-014)

An earlier framing claimed the palette substrate was a **Wasserstein-2 (Bures)
barycenter on Gaussians**. That framing was **retired**. The Gaussian Bures
barycenter is invalid for *discrete* palettes — arXiv:1511.05355 explicitly
excludes discrete measures, and the exact discrete W₂ barycenter is NP-hard — so
`buresBarycenter` was deleted.

The honest substrate is **OKLab + the deterministic maximin floor** (Gonzalez
farthest-first / Lloyd-Max) in `Spec.Collapse` (`farthestPointCollapse` /
`globalCollapseQ16`), gamut-closed and golden-pinned. `Spec.Bures` now supplies
only a Gaussian-*summary* backbone — `buresDistanceSq` as a fidelity term and
`buresBarycenterCov` as a covariance fixed point that the Rust analysis oracle
cross-checks — i.e. a moment-matched spread prior, **not** the collapse. See
[`docs/SIXFOUR-BURES-DISCRETE-CORRECTION.md`](docs/SIXFOUR-BURES-DISCRETE-CORRECTION.md).

## Where to read next

| Document | What it covers |
|---|---|
| [`docs/STATUS.md`](docs/STATUS.md) | **Canonical status ledger** — built / design-only / missing, open debt. Start here for current state. |
| [`docs/SIXFOUR-VISION.md`](docs/SIXFOUR-VISION.md) | Project narrative: "one cube, projected honestly." |
| [`CLAUDE.md`](CLAUDE.md) | The dependency + train/deploy contract (three tiers, zero-dep rule). |
| [`spec/src/SixFour/Spec/Map.hs`](spec/src/SixFour/Spec/Map.hs) | Spec index — start here to browse the Haskell source of truth. |
| [`docs/SIXFOUR-BURES-DISCRETE-CORRECTION.md`](docs/SIXFOUR-BURES-DISCRETE-CORRECTION.md) | ADR-014: why the discrete substrate is maximin, not a Gaussian Bures barycenter. |
| [`docs/COLOR-ATLAS.md`](docs/COLOR-ATLAS.md) | On-device personalization / north-star design (Color Atlas). |
| [`docs/ON-DEVICE-TRAINING.md`](docs/ON-DEVICE-TRAINING.md) | On-device training research (MPSGraph, verified + cited). |
| [`docs/SIXFOUR-WIDGETS.md`](docs/SIXFOUR-WIDGETS.md) | Consolidated widget authority (16² SEE / 4⁴ CONTROL / 2⁸ LEARN). |
| [`docs/L-NN-MASTER-DESIGN.md`](docs/L-NN-MASTER-DESIGN.md) | Look-NN master design. |
| [`docs/archive/SIXFOUR-ARCHITECTURE-MAP.md`](docs/archive/SIXFOUR-ARCHITECTURE-MAP.md) | Archived prior orientation map (historical only — superseded by `STATUS.md`). |

## License

Proprietary. The shipped iOS app and the deterministic Zig core have **zero
third-party dependencies**. The Mac-side Rust analysis workspace is gated by
`cargo deny check licenses` (permissive-only); the Haskell spec uses only GHC
boot libraries.

---

Built with the discipline of *form follows function*: the cube is the only
state, every surface is an honest projection of it, the math is proved once in
Haskell, and the shipped engine is integer-exact so the same burst produces the
same GIF on every device.
