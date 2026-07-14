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
   Swift kernel core** (`SixFour/Kernels/`, the 2026-07-06 port of the retired
   Zig core — same `s4_*` names, same C signatures, same golden vectors). It runs
   the same fixed-point (Q16) fold on every device, so the GIF is **bit-identical
   across phones** — no float drift, no "looks different on my device." This is
   the default path (`useDeterministicCore = true`); the GPU-float Swift renderer
   exists only as a throw-fallback.

A learned "look-network" that would emit a single *learned* global palette is
designed and golden-verified in Haskell, and partially trained on the Mac — but
it is **not shipped on device**. **MVP1 emits PER-FRAME palettes only.** The global
(GIFB) deterministic Zig **pooled-maximin collapse** is implemented and golden-gated
but **deferred to V2** behind `Feature.globalPaletteV2 = false` (unreachable in MVP1).

## Layout

| Path | Tier | Shipped? | Purpose |
|---|---|---|---|
| `spec/` | 0 — Haskell spec | No (Mac-side) | Formally-verified source of truth: shapes, laws, Q16 algorithms; emits contracts + golden vectors for every other tier. GHC-boot-only deps. |
| `SixFour/Kernels/` | 2 — Swift kernel core | **Yes** | The default render engine: integer-exact `s4_*` kernels (`@_cdecl`, C signatures preserved from the retired Zig core; ABI at `sixfour_kernels_abi.h`). |
| `SixFour/` | 2 — iOS 26 app | **Yes (core product)** | Hand-written Swift + Metal, zero third-party deps. Capture, cell-grid UI, the renderer driving the kernel core, GIF export, swipe-to-LOOK, the per-capture θ_up trainer (`Train/RungDispatch.swift`). |
| `SixFourTests/` | 2 | — | Swift unit tests (ports verified against Haskell golden vectors). |
| `trainer/mlx/` | 1 — Python trainer | No (Mac-side) | The hand-written H-JEPA trainer, gated byte-exact against spec-emitted goldens. `torch`/`coremltools` only for the dormant CoreML fallback. |
| `studio/` | — Rust analysis | No (Mac-side) | Analysis/baseline-research workspace (`analysis-core`, `look-nn-baseline` pure-Rust forward net, ES baseline, Bures covariance oracle). Not a runtime tier. |
| `scripts/` | — | — | Gate runner (`s4.sh`), codegen/build/lint/doc gates. |

## Architecture — the four real layers

```
  Haskell spec (spec/, Tier 0)          ── source of truth, Mac-side, NOT shipped
        │  emits contracts + golden vectors (Swift / Python / Rust)
        ▼
  ┌───────────────────────────────────────────────────────────────────┐
  │  Swift kernel core (SixFour/Kernels/)  ── DEFAULT engine, shipped │
  │  s4_* @_cdecl kernels, integer-exact, byte-identical per device   │
  └───────────────────────────────────────────────────────────────────┘
        │  called by
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

### 2. Swift kernel core — the default render engine (`SixFour/Kernels/`, shipped)
(**PIVOT 2026-07-06:** the former Zig core `Native/` was hand-ported to pure
Swift — identical `s4_*` names, C signatures via `@_cdecl`, and golden vectors;
`Native/` is deleted, git history is the record.) The integer-exact pipeline
that actually makes the GIF, identical on every device:

```
widen → linear → OKLab → quantize (maximin = Gonzalez farthest-first + Lloyd)
      → dither → significance-fill → palette → LZW / GIF89a assemble
```

plus `s4_global_collapse` (per-frame → one global palette), the `s4_haar_*`
projections, the `s4_*_q16` look/LUT kernels, and `s4_load_look_net`. The ABI
contract lives at `SixFour/Kernels/sixfour_kernels_abi.h`; the former Zig test
batteries run as `SixFourTests/ZigPort*Tests.swift`. The Mac trainer loads the
SAME Swift sources as a dylib (`scripts/build-kernels-dylib.sh`) — no
train/deploy skew.

The **maximin** step (Gonzalez 1985 farthest-first, then Lloyd) is the canonical
collapse in `Spec.QuantFixed` / `Spec.Collapse`, and the kernel core matches it
byte-for-byte. It is the canon, not a bug.

### 3. iOS 26 app — the shipped product (`SixFour/`, Tier 2)
Swift 6.2 (strict concurrency), hand-written Swift + Metal, **zero third-party
dependencies** (Apple frameworks + `simd` only):
- the capture pipeline (64-frame burst at 20 fps),
- the **cell-grid UI** — one 4 pt cell atom, the whole screen is a cell field
  (no glass / no SF-Symbol chrome on the HUD),
- `DeterministicRenderer` driving the Swift kernel core,
- GIF export: the per-frame **GIFA** path, the global-palette **GIFB** ladder,
  and Save,
- **swipe-to-LOOK** (the `.cube` LUT export is deprecated, gated off behind
  `Feature.lutExport = false`),
- the per-capture **θ_up** trainer (`Train/RungDispatch.swift`, plain Metal;
  the earlier Color Atlas MPSGraph trainer was retired — its device-training
  proof stands in git history).

Every port is verified bit-for-bit against the Haskell golden vectors.

### 4. Trainer — the H-JEPA trainer (`trainer/mlx/`, Tier 1, not shipped)
**MLX/numpy on the M1**, hand-written, each module a byte-exact twin of a `spec/SixFour/Spec/*`
module and gated by spec-emitted goldens (`trainer/generated/*.json`). The composite objective
(masked-band I-JEPA + VICReg collapse guard + cross-encoder floors), both delta heads, the
18.9M-param ViT, and an end-to-end optimizer loop are realized; `torch` + `coremltools` exist
only for the dormant CoreML fallback. Run `python3 trainer/mlx/gate_trainer.py`; see
[`trainer/TRAINING.md`](trainer/TRAINING.md). Training data is synthetic-only (`trainer/data/` absent).

### Train → verify → deploy spine
- **Train (base net):** MLX on the M1.
- **Train (per-user, on device):** `SixFour/Train/` — `RungDispatch.swift`
  (plain Metal fused kernel, runs in the simulator too) is the LIVE per-capture
  θ_up trainer; `DeviceTrainer.swift` (MPSGraph, an Apple system framework —
  inside the Tier-2 zero-dependency contract) is the golden-parity harness.
  On-device MPSGraph training was proven on real hardware by the retired Color
  Atlas trainer (bit-identical loss trajectory Mac ↔ iPhone; git history is the
  record). MPSGraph does not run in the simulator (gated via
  `targetEnvironment(simulator)`).
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
cabal test                 # the full law + golden suite; one leg of the gate (spec/scripts/gate.sh is the full gate)
cabal run spec-codegen     # regenerate the per-tier contracts
```

`spec-codegen` writes generated files to `SixFour/Generated/` (Swift contracts),
`trainer/generated/` (Python), and `studio/look-nn-baseline/src/generated/`
(Rust constants). Never hand-edit generated files; change `spec/src/SixFour/Codegen/`
and regenerate.

### Trainer (Python)
```bash
cd trainer/mlx
python3 gate_trainer.py    # the H-JEPA trainer gate (byte-exact core + head + spec goldens)
python3 train_loop.py --smoke   # the end-to-end MLX optimizer over the corpus
```

### Full gate
```bash
scripts/s4.sh all          # codegen → doc → verify → native → lint → gen → build
scripts/s4.sh doc          # verify CLAUDE.md / Spec.Map load-bearing facts (grep/test/find only)
```

`s4 all` runs the verbs in the order recorded in `scripts/gate-order.txt`. The
`doc` gate (`verify-doc-claims.sh`) is wired in right after `codegen`, so the
canonical facts (CLAUDE.md + `SixFour.Spec.Map`) are re-asserted on every full **local** run.
CI (`.github/workflows/`) runs the checkout-safe gates — the spec-codegen drift
check + Haskell tests, and the GRID lint — on every push/PR. The `doc`, `native`,
and `build` gates stay **local-only**: `doc` and `native` assert local
generated/trained artifacts (e.g. the gitignored `trainer/out/` fixtures), and
`build` needs Xcode 26.2 / iOS 26, none of which exist on hosted CI runners.

## Status

Status-of-record lives on exactly three surfaces (see `CLAUDE.md`
§"Status-of-record"): **`CLAUDE.md`** (the contract), the arc ledger
**`docs/REBUILD-2026-07-10-PLAN.md`**, and the spec→app promotion ledger
**`docs/SPEC-APP-LINK-LEDGER.md`**; `scripts/verify-doc-claims.sh` gates the
canon's load-bearing facts. (`docs/STATUS.md` was deleted; do not recreate it.)
Current state:

- **The full Haskell spec suite passes** (`cabal test`; the count grows with the spec —
  run it, don't quote it).
- The **deterministic Swift kernel core is built and is the default path**
  (`useDeterministicCore = true`); the GPU-float Swift `GIFRenderer` is the
  throw-fallback only.
- **GIFA → GIFB global collapse is wired in production**:
  `CaptureViewModel.renderDeterministic` → `renderDeterministicGlobal` →
  `DeterministicRenderer.renderGlobalPalette` → `SixFourNative.globalCollapse` →
  `s4_global_collapse`. The shipped global palette is the deterministic
  pooled-maximin collapse, **not** a learned NN genome.
- **Swipe-to-LOOK is built**
  (`Spec.{ZoneProfile,LookTransfer,RedFrontEnd}`;
  `s4_zone_profile_q16` / `s4_look_transfer_q16`; iOS build succeeds —
  on-device verification is the user's step). The R3D `.cube` LUT export is
  **deprecated** (2026-07-08), gated off behind `Feature.lutExport = false`.
- The **look-NN forward path is proven in Haskell** (`LookNetE/R/D`, a 384-DOF
  `SigmaPairTree` decoder) but **nothing runs it on device**: `loadLookNet` has
  zero production callers (open debt: `looknet-load-unused`). The learned global
  palette / NN-genome path is **design-only and unreached**.
- The decoder genome is **384-DOF** (3 × 128 σ-pair generators, `SIGMA_PAIR_DOF`);
  it reconstructs into the **768-real** flat leaf space (256 × 3). The 384
  emitted and the 768 leaf space are not the same thing.
- **The Mac trainer is the H-JEPA trainer** (`trainer/mlx/`, hand-written MLX/numpy): the only
  learned object is the 63-param `theta_B` masked-band predictor, which ships as a hand-written
  Swift forward pass (`MaskedBandForward.swift`, golden-gated). The composite objective
  (masked-band + VICReg + cross-encoder), both delta heads, the 18.9M-param ViT, and an
  end-to-end optimizer loop are realized and gated, each a byte-exact twin of its Haskell spec.
  Training data is synthetic-only (`trainer/data/` absent).
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
farthest-first / Lloyd-Max) (`farthestPointCollapse` in `Spec.Collapse` /
`globalCollapseQ16` in `Spec.GlobalCollapseQ16`), gamut-closed and golden-pinned. `Spec.Bures` now supplies
only a Gaussian-*summary* backbone — `buresDistanceSq` as a fidelity term and
`buresBarycenterCov` as a covariance fixed point that the Rust analysis oracle
cross-checks — i.e. a moment-matched spread prior, **not** the collapse.

## Where to read next

| Document | What it covers |
|---|---|
| [`CLAUDE.md`](CLAUDE.md) | The canon: dependency + train/deploy contract (three tiers, zero-dep rule), status-of-record rules. **Start here.** |
| [`docs/REBUILD-2026-07-10-PLAN.md`](docs/REBUILD-2026-07-10-PLAN.md) | The active-arc ledger: rebuild stages, device-gate results, reconciliations. |
| [`docs/SPEC-APP-LINK-LEDGER.md`](docs/SPEC-APP-LINK-LEDGER.md) | The spec→app adoption/promotion ledger (updated per promotion commit). |
| [`spec/src/SixFour/Spec/Map.hs`](spec/src/SixFour/Spec/Map.hs) | Spec index — browse the Haskell source of truth (NN design is the ★ core category). |
| [`trainer/TRAINING.md`](trainer/TRAINING.md) | The H-JEPA trainer runbook (`trainer/mlx/`): how to run the gate and the end-to-end loop. |
| [`spec/README.md`](spec/README.md) | How the spec is built, what `spec-codegen` emits, and how the trainer is gated against it. |
| [`NOTES.md`](NOTES.md) | Chronological session log, closed 2026-07-05 (history; later sessions live in `docs/SESSION-*.md`). |

## License

Proprietary. The shipped iOS app and its deterministic Swift kernel core have **zero
third-party dependencies**. The Mac-side Rust analysis workspace is gated by
`cargo deny check licenses` (permissive-only); the Haskell spec uses only GHC
boot libraries.

---

Built with the discipline of *form follows function*: the cube is the only
state, every surface is an honest projection of it, the math is proved once in
Haskell, and the shipped engine is integer-exact so the same burst produces the
same GIF on every device.
