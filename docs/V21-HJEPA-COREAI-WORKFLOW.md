# V2.1 to H-JEPA to Core AI: train on probability functions, deploy with on-device LoRA

> **SUPERSEDED (banner added 2026-07-13).** The Core AI display side was retired 2026-06 and the
> full-matrix H-JEPA working plan was replaced by [`REBUILD-2026-07-10-PLAN.md`](REBUILD-2026-07-10-PLAN.md) §1.1.
> Zig paths herein read as `SixFour/Kernels/` (CLAUDE.md pivot note). Historical record.


The workflow for the direction the owner named: feed the model the PROBABILITY FUNCTIONS (not the
collapsed GIF), let the encoder collapse them the way the user's eye does, train the H-JEPA large head
on energy and entropy, export it to Core AI, and improve it per-user on the iPhone with a LoRA adapter.
This doc is the ordered, gated plan. Each phase names its gate and its HONEST baseline, so "it works"
is always a number, never a vibe.

Read `spec/exploration/V2.1-STATE-AND-NEXT.md` and `V2.1-ENCODER-INPUT.md` first for the field itself;
this doc is the layer above them (field to model to device).

## The thesis, in one paragraph

Per 64x64 bin, a colour channel is a PROBABILITY CURVE, stored energy-first as an integer vector over
256 value levels. The whole capture is a dense rank-5 tensor `[T, Y, X, 3, 256]`, a fibre bundle: the
base lattice is `(Z cap [0,63])^3` over `(x, y, t)`, and the fibre is three energy curves. The GIF the
user sees is the COLLAPSE, `collapseQ16` = per-voxel argmin energy = the mode. Collapse is an
OBSERVATION: picking where and how to observe (which voxels, over which time window, weighted by which
axis) collapses the same field differently. The model trains on the pre-collapse curves; the encoder
learns the map that the observation performs. This is `SixFour.Spec.V21Field`, already gated and ported
byte-exact across Haskell, Zig, Swift, and Metal.

## Where collapse-as-observation already lives in code

- `collapseQ16 :: Curve -> Level` (spec) and `s4_v21_collapse` (Zig): the observation, argmin energy,
  lowest-index tie-break. `lawCollapseIsArgmin` proves the byte survives ANY monotone recode of the
  energy, so the observation is stable to how the field is scaled.
- `centeredEnergy` / `modeRelative` / `anchorAt`: the observation presented MODE-RELATIVE. The field
  input pins its own argmin to relative-0 and WITHHOLDS the absolute mode; the GIF supplies the mode
  back through a FiLM conditioning. `lawModeIsNotAFunctionOfField` proves field and GIF are
  complementary, not redundant, so "the GIF the user sees" and "the field the model sees" are two
  genuinely different observations of one object.
- `axisWeight pd T = pd` and now `paletteDelta` (Phase 0, below): WHERE-IN-TIME to observe. A static
  palette makes a temporal step free; a changing palette charges the time axis, so the observation
  stretches or compresses along `t` by how much the scene's colour distribution actually moved.
- `Spec.V21FieldUI` (`budgetCells`, `allocateWidgets`): WHERE-IN-SPACE to observe. The cell budget is a
  Morton quadtree apportionment that aims observation cells at the uncertain regions; the widget
  opposition law forces two readouts (Mode, Uncertainty) onto distinct cell counts.

## Current state (verified against live code, 2026-06-30)

Built and gated:
- The probability field end to end: `Spec.V21Field` (1299 spec tests), five `s4_v21_*` Zig kernels
  (77 fixture tests), the live `v21AccumulateHistKernel` in Metal, the AirDrop bundle (`.npy` field +
  contested sidecar + manifest), and `trainer/v21_ingest.py` to load it back on the Mac.
- The encoder-input presentation (`modeRelative` + GIF anchor via FiLM) is byte-exact ported Haskell to
  Zig to Swift, but consumed by NOTHING yet: no MLX module imports it.
- The large head candidate: `trainer/mlx/large_head.py` and `Spec.LargeJepaHead`, an 18.9M-param ViT
  with an integer-`d6` ALiBi position bias whose depth-1 limit provably reduces to the 77-param
  `theta_B` floor (`lawDepth1ReducesToFeaturesBPos`). This is the object we grow and ship to Core AI.
- The masked-band H-JEPA objective (`trainer/mlx/jepa_loss.py`), VICReg collapse guard
  (`trainer/mlx/vicreg.py`), and the paradigm-soundness proof chain (nine teachings under
  `Spec.ParadigmSoundness`).

The gaps this workflow closes:
1. The MLX trainer trains on old masked-band octant targets, NOT on the V2.1 energy field. The central
   missing wire.
2. `s4_v21_palette_delta` did not exist (the temporal-axis blocker). CLOSED in Phase 0 below.
3. The Core AI export seam was deleted in the 2026-06-26 cleanup; rebuild from scratch on Apple's
   `apple/coreai-models` recipes.
4. On-device LoRA is not started, and Core AI cannot train (hard contract constraint).
5. The GPU render/bleed compositor and the Metal 4 tensor path are unexplored.

## The contract constraints that shape every phase

- ZERO third-party deps in the shipped app (Tier 2). Trainer (Tier 1) may use MLX / torch / coremltools.
- The learned object deploys as a HAND-WRITTEN forward OR through Core AI (an Apple system framework),
  never a CoreML black box, never `mlx-swift`, never an opaque ANE runtime.
- Core AI float is not cross-device bit-exact, so every deployed inference must RE-ENTER the Zig Q16
  floor before it reaches GIF bytes. `collapseQ16` is argmin (order-only), so the collapse is exact
  under the float encoder as long as the argmin is preserved: this is why energy, not mass or
  surprisal, is the learnable quantity.
- Core AI CANNOT train. On-device training is MPSGraph (proven: Atlas Bradley-Terry, 12.4 ms/step,
  bit-identical Mac to iPhone 17 Pro). iOS 27 adds on-device LoRA, but see Phase 4 for the exact catch.

---

## Phase 0: close the observation loop (the temporal axis + the GPU compositor)

Goal: make "where and how you observe collapses differently" complete and visible.

### 0a. The palette-delta metric. DONE (this session).

`s4_v21_palette_delta` is the temporal metric weight `axisWeight T = pd`. It was the single headline
blocker for the Delta / temporal widget and the time-stretch of movement-follow.

- METRIC CHOSEN (open Q3 resolved for the cheap tier): the L1 / total variation between the two frames'
  per-channel value histograms, `sum_{ch,v} |hist1(ch,v) - hist2(ch,v)|`. It is byte-exact integer and
  PERMUTATION-INVARIANT: reordering a palette's slots (the palette index gauge) does not change it, so
  the temporal axis is charged only for a genuine change in the colour DISTRIBUTION, never for a
  re-indexing of the same colours. This directly answers the project's long-standing "compare in fused
  space, not slot-by-slot" gauge concern. A joint-3D / earth-mover refinement is deferred.
- LANDED: `paletteDelta` + `paletteChannelHist` in `Spec.V21Field` with four laws
  (`lawPaletteDeltaZeroOnEqual`, `lawPaletteDeltaSymmetric`, `lawPaletteDeltaGaugeInvariant`,
  `lawPaletteDeltaStaticTimeFree`); the `s4_v21_palette_delta` Zig kernel (signed one-pass difference
  histogram, fixed 3x256 stack buffer, `RC_OUT_OF_RANGE` on `n_levels > 256` or an out-of-range value);
  the Haskell-emitted golden `v21_palette_delta_golden.json`; and the cross-language fixture test
  (delta bit-exact + symmetry + gauge invariance at the kernel level).
- GATE: `cabal test` 1299/1299, warning-clean; `zig build test -Drequire_fixtures=true` green,
  non-vacuously (a tampered golden fails `expected X, found 6`).

### 0b. Swift wrapper + the Delta widget. NEXT.

Port the kernel the way the other five were: a `paletteDeltaV21` wrapper in
`SixFour/Native/SixFourNative.swift` (+ C decl in `Native/include/sixfour_native.h`), a Swift golden
test, then feed `pd` into the third widget in `V21WidgetSurface.swift` (Delta: `labDeltaAt` tint,
t-bleed scaled by `pd`). Gate: the app iOS-sim build + the Swift golden test.

### 0c. The Metal render/bleed compositor (the Metal-toolchain entry point).

Move the widget bleed from the CPU `Canvas` to a Metal compute/render pass, per
`V2.1-UIUX-FUNCTIONS.md`. This is the natural place to explore the new Metal toolchain: the bleed is a
scatter-splat whose radius grows with the region's spread, a good fit for a tile-based compute kernel.
Gate: a Metal-vs-CPU golden on one field (structure, since the CPU path is the reference).

Metal 4 note: the same toolchain exposes `MTLTensor` and tensor ops. Keep the render compositor and any
tensor-op experiment SEPARATE. The shipped inference path is still governed by "hand-written or Core
AI"; a Metal tensor op is a legitimate hand-written forward primitive, an opaque runtime is not.

---

## Phase 1: wire the probability field into the MLX trainer

Goal: the model trains on the energy CURVES plus the GIF anchor, not on the collapsed byte. This is the
heart of the owner's request.

1. CORPUS. Build `trainer/mlx/v21_corpus.py`: capture real bursts on device, AirDrop the bundles, load
   them with `v21_ingest.load_bundle`, and yield training examples. Each example is
   `(mode_relative_field, gif_anchor)` decimated from `64^3` to the locked `4^3` octant waist (box
   decimate factor 16), cast to float32. The int-to-float cast is the ONE seam; its left inverse is
   `round`, and deploy re-enters integer by argmin.
2. THE TRANSFORM. Port `centeredEnergy` to `modeRelative` to the `64^3` to `4^3` decimation into MLX
   (float32), gated against the existing `v21_mode_relative_golden.json` and a new decimation golden
   vs `s4_v21_accumulate_hist`. The energy is `E = maxCount - count` (`countsToEnergy`), the ONLY
   learnable quantity: not counts (nuisance scale), not mass (divide-by-N dies at the floor), not
   surprisal (transcendental, breaks argmin).
3. THE OBJECTIVE (H-JEPA on energy and entropy). Reuse the masked-band I-JEPA loss (`jepa_loss.py`):
   context = coarse + 6 sibling bands with the target voxel excluded
   (`lawHeldTargetIsExcludedFromContext`), target = the held detail band of the LIFTED curves
   (`liftOctCurves` / `detailAt`, `lawTargetNotDeterminedByGifModes`). Add the VICReg variance floor
   (`vicreg.py`) as the collapse guard on the never-surfaced mid-latent. Entropy enters as the target's
   own dispersion: a confident (spike) bin has near-zero held-band energy, an uncertain bin carries
   real detail, so the loss is naturally entropy-weighted by construction.

GATE: the trainer gate (`cli.py gate`) stays green; the new corpus + transform modules ship with
self-tests and goldens; a smoke run (`cli.py train --smoke`) trains 4/4 props on the field corpus.
HONEST baseline: the field model must beat the mean-field predictor (predict every bin's curve as the
corpus-mean curve) on held-out disjoint captures, not merely beat predict-zero.

---

## Phase 2: train the large head on the field

Goal: grow `large_head.py` to consume the field and beat the honest baselines over a real run.

1. FiLM the ViT on the withheld mode: the mode-relative field is the token content, the GIF mode anchor
   conditions each block (FiLM gamma/beta from the anchor). This is exactly the non-redundancy the spec
   proved: the field cannot recover the absolute mode, so the anchor is real information.
2. Keep the keystone: `law_depth1_reduces_to_features_b_pos` must stay green, so the big net remains a
   controlled deviation above the proven `theta_B` floor and zero-genome still equals the floor.
3. Judge vs HONEST baselines, per axis: spatial detail vs the mean-field predictor; temporal vs
   PERSISTENCE (copy frame `t` to `t+1`), the baseline the `temporal_rung` already uses. Verdict
   dashboard: LEARNING / FLOORED / COLLAPSE / DIVERGED (`eval_checkpoint.py`, `dashboard_verdict`).

GATE: a multi-hour MLX run on the M1 with `--resample` (fresh data, so generalization not
memorization); held-out margin positive vs BOTH baselines; no VICReg collapse; resume bit-faithful.

---

## Phase 3: export to Core AI (rebuild the deleted seam)

Goal: the trained large head runs on device through Core AI, an Apple system framework, satisfying the
zero-third-party rule.

1. Rebuild `trainer/coreai_export/` on Apple's `apple/coreai-models` recipes (the `coreai-torch`
   successor): MLX weights to the Core AI export format, producing an `.aimodel`. WWDC26 session 326 is
   the reference.
2. PonderNet dynamic halting must be UNROLLED to a fixed read-depth for export (Core AI graphs are
   static); the halting distribution becomes a fixed-depth read, which the spine already bounds
   (`readDepth` is well-founded).
3. The float output re-enters the Zig Q16 floor at collapse: `collapseQ16` is argmin, exact under any
   monotone float transform, so the GIF byte is deterministic even though the ViT floats are not.
4. Guard everything `#if canImport(CoreAI)`; Core AI is absent from the simulator SDK and is
   developer-beta (GA around Sept 2026), so this is device-only and verified on the iPhone 17 Pro.

GATE: on-device, the Core-AI-collapsed GIF equals the Zig-floor GIF byte-for-byte on a fixture capture
(the determinism floor holds); latency and memory acceptable in a burst.

---

## Phase 4: on-device LoRA (per-user improvement on the iPhone)

Goal: the "LoRA on iPhone" the owner asked for. The owner chose to EXPLORE the iOS 27 Core AI adapter
path first, with MPSGraph as the contract-proven fallback.

The iOS 27 landscape (researched 2026-06-30, sources below):
- iOS 27 adds on-device fine-tuning: an app trains a LoRA adapter on local data that never leaves the
  device, the base weights stay frozen, the adapter persists in the app sandbox. Apple ships a Python
  training workflow and packaging utilities for this.
- THE CATCH: that documented adapter-training toolkit is for the FOUNDATION MODELS system LLM (Apple's
  model), not automatically for an arbitrary custom Core AI model. Core AI (the custom-model runtime)
  and Foundation Models (the system LLM with the PEFT toolkit) are different layers.
- THE THING TO VERIFY ON THE BETA: does Core AI expose on-device LoRA TRAINING for a CUSTOM model, or
  only inference plus adapter LOADING (with training done off-device)? Session 326 and the
  `apple/coreai-models` repo are where to confirm. This is a device-only, beta-only check; the owner
  has the beta and can run it.

Decision gate on the finding:
- IF Core AI supports custom-model on-device LoRA training: the ViT ships with frozen base weights and
  low-rank `A*B` adapters on the attention and FF projections; per-user data trains only the adapter.
  The adapter delta stays float and re-enters Q16 at collapse. This is the cleanest path (one system
  framework, no MPSGraph).
- ELSE (the safe fallback, already proven on this hardware): MPSGraph LoRA. Low-rank adapters trained
  on device via MPSGraph, exactly the mechanism the Atlas trainer already demonstrated bit-identical
  Mac to device. Core AI stays inference-only; MPSGraph owns the adapter training.

Either way the adapter is a low-rank delta on the SAME 18.9M ViT, so the base export (Phase 3) is
unchanged; Phase 4 only adds the adapter tensors and the training loop.

GATE: on device, an adapter trained on a handful of the user's captures improves the held-out field
loss on THAT user's later captures vs the frozen base, and the adapted collapse still re-enters the Q16
floor byte-exact.

---

## Metal toolchain thread (cross-cutting)

The new Metal toolchain shows up in three places, kept distinct so none of them touches the shipped
inference contract:
1. Phase 0c: the render/bleed compositor (a compute + render pass), the safe first experiment.
2. Phase 1/2: `v21AccumulateHistKernel` already proves Metal can build the field on-GPU; the same
   place is where a `MTLTensor` experiment for the decimation or the FiLM could live, as a hand-written
   forward primitive (allowed), never as an opaque runtime (forbidden).
3. Phase 4: if MPSGraph owns the adapter training, that is the Metal-adjacent training path already
   blessed by the contract.

## Decision forks still open

- Q3 refinement: is per-channel-histogram L1 enough for the temporal weight, or is a joint-3D /
  earth-mover distance worth the cost? Cheap tier is landed; measure before refining.
- The `64^3` to `4^3` decimation convention for the encoder input (box vs windowed) is an open question
  in `V2.1-ENCODER-INPUT.md`; Phase 1 step 2 must pin it with a golden.
- Core AI custom-model on-device LoRA training: the Phase 4 beta check decides the whole adaptation
  path. Until then, MPSGraph is the assumed fallback.

## Progress

- 2026-06-30: Phase 0a DONE. `s4_v21_palette_delta` (metric chosen, spec + laws + Zig kernel + golden +
  cross-language fixture), gates green (`cabal test` 1299, `zig build test -Drequire_fixtures=true`
  exit 0, non-vacuously verified). Workflow doc authored. NEXT: Phase 0b (Swift wrapper + Delta widget)
  or Phase 1 step 1 (the `v21_corpus.py` wire), owner's call.

## Sources (iOS 27 Core AI / LoRA research, 2026-06-30)

- Integrate on-device AI models into your app using Core AI, WWDC26 session 326:
  https://developer.apple.com/videos/play/wwdc2026/326/
- apple/coreai-models (export recipes, Python primitives, Swift runtime):
  https://github.com/apple/coreai-models
- Foundation Models adapter training (the LoRA PEFT toolkit, system-LLM):
  https://developer.apple.com/apple-intelligence/foundation-models-adapter/
- Apple newsroom, new intelligence frameworks and tools:
  https://www.apple.com/newsroom/2026/06/apple-aids-app-development-with-new-intelligence-frameworks-and-advanced-tools/
