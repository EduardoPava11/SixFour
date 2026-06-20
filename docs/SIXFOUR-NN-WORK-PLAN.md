# SixFour NN Work Organization Plan

> **Status:** work-breakdown + sequencing plan. **Not** new design, **not** an implementation.
> **Companion to** [`docs/SIXFOUR-NN-STACK-RESEARCH.md`](SIXFOUR-NN-STACK-RESEARCH.md) (§1.5 locked design) and
> [`docs/SIXFOUR-NN-SPEC-COVERAGE.md`](SIXFOUR-NN-SPEC-COVERAGE.md) (coverage map).
> **This document organizes the work.** The substrate choices in §4 and §8 are **RECOMMENDED but
> returned to the user for sign-off** — per the standing rule that web-research-driven decisions need
> alignment before they become commitments.

---

## 1. Purpose

This document **organizes the neural-network work** for SixFour into a dependency-ordered
work-breakdown with milestones, grounded in three already-existing assets:

1. **The tensor spec** — `spec/src/SixFour/Spec/Tensor.hs` (Naperian `Tensor1/2/3`, SoA channel-axis
   via `HasChannelAxis`/`channelView`, σ-actions `sigma64`/`sigma64Mask` 22/21/21) and the net spec
   modules (`LookNetE/R/D`, `LookNetCompose`, `SigmaPairHead` 384-DOF, `PaletteOracle`,
   `PreferenceUpdate`, `GumbelSearch`, `GenomePair`, `Collapse`, `ExportFamily`).
2. **The verified coverage map** — `docs/SIXFOUR-NN-SPEC-COVERAGE.md`, which classifies each NN law as
   `covered` / `partial` / `hollow` and is the basis for the work items in §5.
3. **The SIMT/MPS substrate research** — synthesized in §3, with the locked NN design living in
   `docs/SIXFOUR-NN-STACK-RESEARCH.md` §1.5.

It is **a work-breakdown + sequencing plan, NOT new design and NOT an implementation.** Every work
item follows the CLAUDE.md spec-first discipline (Spec → `cabal test` → codegen golden →
Zig/Swift/Metal/MPS port). The substrate recommendations in §4 and the open choices in §8 are
**RECOMMENDED, pending the user's sign-off** — substrate-by-determinism is a web-research-driven
decision and the user requires alignment before it is committed.

**One line:** this plan organizes the work; the substrate decisions are pending sign-off.

## 2. Compute stack & the determinism tension

### 2.1 How a SixFour tensor lowers across the stack

The pipeline is **Haskell spec (source of truth) → codegen goldens → execution substrates**, with six
layers:

| Layer | Owns | Determinism |
|---|---|---|
| **Spec (Haskell, Tier 0, Mac-only)** | ALL math semantics + laws. `Tensor.hs` (Naperian, SoA channel-axis = last axis, σ baked as fixed diagonal involutions); the value/proposer/SR/genome/collapse math modules. | Bit-exact by construction (the reference) |
| **Codegen (Haskell → goldens)** | Emits golden vectors + contract constants into `SixFour/Generated/` (`NetContract.swift` pins `lookSigmaPairDOF=384`, `MODEL_DIM=64`, `CORE_DEPTH=8`) and `trainer/generated/net_shape.py`. `cabal test` is the cross-tier gate. | Gate of record |
| **Zig integer Q16 core (Tier 2 shipped)** | The deterministic integer pipeline: `s4_quantize_frame`, `s4_dither_frame`, `s4_significance_fill`, `s4_palette_oklab_to_srgb8`, `s4_gif_*`, reversible Haar/RGBT lifts, `s4_board_mass_q16`, `s4_leaf_override`, `s4_build_cube_q16`, and the look-NN blob parser `s4_load_look_net` (31 exports, all tested). | **Cross-device BIT-EXACT** |
| **Swift CPU (Tier 2 shipped)** | Orchestration + the live value path: `DeterministicRenderer.render`, `PersonalTaste` (CPU linear 770-D Bradley-Terry θ, the LIVE value head), `PaletteValue` (golden-gated but UNWIRED), `GenomePair`/`ABCandidates` proposer seed, `ABExportFamily`, `NetSynth256` (SR scaffold, returns floor). | float, per-device (not cross-device-exact) |
| **Metal GPU (Tier 2 shipped)** | Camera-side k-means palette EXTRACTION (the NN input) + the live cell-field UI (`field.metal`). NOT used for any NN forward/backward pass. | float, non-deterministic reduction order |
| **MPSGraph (Apple framework, Tier 2 allowed)** | On-device autodiff training spine. `AtlasTrainer.swift` builds a Bradley-Terry VALUE graph (board+genome → V), `gradients(of:with:)` + SGD + `assign`. **PROVEN on iPhone 17 Pro (12.4 ms/step, bit-identical loss Mac↔iPhone)** but a value-only spike. | float, on-device training |

### 2.2 The two disconnected tensor representations

There are **two tensor representations today, and the signed-off nets lower through neither cleanly yet**:

1. **`Spec/Tensor.hs`** is the verified algebra (Naperian over `U.Vector Double`, channel axis = last
   axis, σ baked as `sigma64`/`gmmTokenSigma`). It lowers **byte-exactly** to the Zig
   `S4LookNetWeights` blob (`phi(64,10)`, `w1/w2(64,64)`, `halt`, 8 heads {3,3,6,12,24,48,96,192}=384) —
   but that whole path is the **SUPERSEDED supervised look-NN**: `s4_load_look_net` only *parses* the
   blob, no forward pass consumes it.
2. **The new signed-off nets bypass `Tensor.hs` entirely.** `AtlasTrainer.swift` hand-builds MPSGraph
   tensors from raw `[Float]` (`board[B,4096,6]`, `genome[B,384]`) with no reference to `Tensor.hs`,
   `HasChannelAxis`, or the σ-masks. The genome's **384 DOF do trace to the spec** (`SigmaPairHead` →
   `NetContract.lookSigmaPairDOF=384` → `AtlasTrainer.genomeDim`), so the *interface* lowers cleanly;
   the **network internals** (value MLP, proposer tree, SR body) have **no `Tensor.hs` lowering at all**.

### 2.3 What runs where today

- **Zig (integer Q16, cross-device bit-exact):** the entire shipped per-frame GIF pipeline, the
  reversible Haar/RGBT lifts, `s4_global_collapse` (gated off in V2), `s4_board_mass_q16` (the
  deterministic board the trainer eats), `s4_leaf_override`, and the look-NN blob *parse only*.
- **Swift CPU (float, per-device):** orchestration + the **live value head** = `PersonalTaste` 770-D
  linear θ; the A/B proposer **seed** (`GenomePair.sampleOrthogonalPair`); `PaletteValue` (UNWIRED);
  `NetSynth256` SR (scaffold, returns the floor).
- **Metal GPU (float, non-deterministic reductions):** camera-side k-means palette **extraction** (the
  NN input) + the live cell-field UI.
- **MPSGraph (float, on-device training):** `AtlasTrainer` Bradley-Terry **value** graph — proven 12.4
  ms/step, but a value-only spike (no σ-masks, policy heads stubbed).
- **Nothing runs the proposer MCTS, the real value MLP, or the SR net anywhere yet.**

### 2.4 THE tension, and the rule this plan uses

**The tension.** The app's hard guarantee is **integer Q16 cross-device bit-exact** (Zig). Every new
net — value head, proposer scoring, SR residual — is **float** (MPSGraph / Swift / Metal). GPU float
reductions are **non-associative and order-dependent** (vary with tile shape, scheduling, batch), so
they are **not bit-identical to the integer Q16 reference**, and Apple publishes **no cross-device
bit-exact guarantee**. The only designed bridge — `GumbelSearch.q16Key` (quantize a float value to an
integer bucket so a float wobble cannot flip a tie) — is specified but **unimplemented on either side**.

**The assignment rule this plan uses** (derived from §3, finalized in §4):

> A workload runs on the **integer Zig Q16 core if and only if its OUTPUT must be cross-device
> bit-exact** (it crosses the bit-exact contract boundary — the GIF bytes, the integer-index path, the
> `zero-genome == floor` gate). Otherwise it runs on a **float substrate** (MPSGraph for training,
> hand-Metal or Swift for scoring/inference) and its result re-enters the integer path through a
> **quantization boundary** (`q16Key` for decisions, structural zero-bypass + Q16 add for the SR
> residual). Workloads that only **rank/propose/add-detail** tolerate float; workloads that **define the
> bytes** do not.

## 3. SIMT + MPS research findings (cited)

Concise, organized by sub-theme. Adversarial-verify verdicts are folded in where they bound a claim.

### 3.1 The Apple GPU SIMT model

- **32-wide lockstep SIMD-groups, execution-mask divergence.** The Apple GPU executes 32-thread
  SIMD-groups in lockstep sharing one PC; control-flow divergence is a 32-bit execution **mask**, not
  separate paths — so a branch costs roughly the sum of both sides unless a whole SIMD-group takes one
  side. Up to 1024 threads/threadgroup = up to 32 SIMD-groups, programmer-controlled, with explicit
  threadgroup memory + barriers. (Apple G13 reference, dougallj: https://dougallj.github.io/applegpu/docs.html ;
  Metal Feature Set Tables: https://developer.apple.com/metal/Metal-Feature-Set-Tables.pdf )
- **`simdgroup_matrix` (8×8 tiles) is the matmul intrinsic — NOT a separate tensor core (pre-M5).**
  It reuses the FP32 ALU pipeline; the 8×8 tile aligns with the 128-registers-per-thread budget and the
  SoA pad-to-8 contract. (metal-benchmarks: https://github.com/philipturner/metal-benchmarks ;
  Rigel M4 reverse-engineering, arXiv:2606.12765: https://arxiv.org/html/2606.12765v1 )
- **Tiny MLPs map onto the "fully-fused" pattern:** weights/activations in registers + threadgroup
  memory, global memory only for I/O; ~16-neuron groups per SIMD-group. SixFour's ~50–100K-param value
  head and per-frame SR body are squarely in this single-fused-kernel-per-frame regime. On Apple,
  registers/occupancy bind (128 regs/thread; D=128 attention "nosedives") — so the nets staying tiny is
  exactly what keeps them GPU-cheap. (Fully-fused MLPs, arXiv:2403.17607: https://arxiv.org/pdf/2403.17607 ;
  tiny-cuda-nn: https://github.com/NVlabs/tiny-cuda-nn/blob/master/src/fully_fused_mlp.cu )
- **SIMD-group reductions (`simd_sum`/`simd_shuffle`/`quad_*`)** keep small reductions in registers, but
  their accumulation order is the hardware's — a hardware `simd_sum` tree reduction is **not** the
  left-to-right order of a scalar Zig sum. (Apple forums: https://developer.apple.com/forums/thread/687495 )
- **Bandwidth/occupancy-bound for tiny nets:** on M-series, "shared memory isn't as crucial," ALUs stay
  register-resident; the GPU win over CPU/Accelerate is dominated by launch overhead, so the substrate
  choice must be **benchmarked per-workload**, not assumed. (ThunderMittens/Hazy Research:
  https://hazyresearch.stanford.edu/blog/2024-11-28-tk-mlx )
- **Metal 4 / iOS 26 adds an MSL `tensor` type, cooperative tensors, and 4/8-bit quantized matmul** that
  auto-use on-GPU Neural Accelerators on A19/M5 — but it is OS-/silicon-version-gated, the **iPhone 17
  Pro target predates M5 Neural Accelerators**, and the quantized reductions have unestablished
  cross-device bit-exactness. **"Reason-about-later" option, not a determinism guarantee.** (WWDC26-330:
  https://developer.apple.com/videos/play/wwdc2026/330/ )

### 3.2 MPSGraph / MPSGraph NN + training primitives

- **Complete on-device training loop with reverse-mode autodiff:** `placeholder` →
  `variable` (persistent weights) → forward (`matrixMultiplication`/`convolution2D`/`reLU`/`softMax`) →
  loss (`softMaxCrossEntropy`) → `gradients(of:with:)` → `stochasticGradientDescent` → `assign`, run by
  targeting the assign ops. **This is exactly the AtlasTrainer spine** and covers the value MLP
  end-to-end. (Training guide:
  https://developer.apple.com/documentation/metalperformanceshadersgraph/training-a-neural-network-using-mps-graph ;
  WWDC20-10677: https://developer.apple.com/videos/play/wwdc2020/10677/ )
- **The SR pixel-shuffle is a first-class op:** `depth(toSpace2DTensor:…blockSize:usePixelShuffleOrder:)`
  gives true sub-pixel (ESPCN-style) ordering; `convolutionTranspose2D` + its `*DataGradient` provide the
  trainable alternative; **FiLM = `multiplication` + `addition` broadcast** (or `normalization` γ/β from
  a genome projection). (depthToSpace:
  https://developer.apple.com/documentation/metalperformanceshadersgraph/mpsgraph/3750709-depth )
- **WWDC23 added `sort`/`argSort`, cumulative, grid-sample, Int8 `quantize`/`dequantize`, bf16.** Data
  flows via `MPSGraphTensorData` wrapping `MTLBuffer`/`MPSNDArray`/`MTLTexture` — the Zig-core genome can
  be fed as an `MTLBuffer`-backed tensor **without a custom bridge**. (WWDC23-10050:
  https://developer.apple.com/videos/play/wwdc2023/10050/ )
- **Compile-once-per-shape, executable cached;** `MPSGraphPackage` can prebuild/serialize for cold-start.
  For ~50–100K-param nets the cost is **per-dispatch launch overhead, not FLOPs** → run the value head as
  **ONE batched dispatch over all K candidates per MCTS layer**, and keep K + SR tile shape **fixed/
  bucketed** so no recompile per shutter press. (WWDC23-10050, as above.)
- **Adversarial-verify verdict — SUPPORTED:** every primitive (matmul, conv, transposed-conv,
  pixel-shuffle, softmax, FiLM-as-mul+add, autodiff, in-graph SGD) maps to a **real documented MPSGraph
  method**, zero third-party deps. Caveats: **Adam is composed** (not turnkey); SR-**training** latency is
  **unproven** (12.4 ms/step is the value head, not a conv+pixel-shuffle SR body); MCTS tree control flow
  is **host-side**, not an MPSGraph op (static-graph model is hostile to data-dependent branching).

### 3.3 Tensor lowering

- **`MPSNDArray` is the lowering target for the row-major SoA tensor:** it exports to/from a plain
  `MTLBuffer` by `rowStrides` (innermost-to-outermost) — exactly `Tensor.hs`'s `v[i*m+j]` row-major,
  channel = last axis. `channelView`'s per-channel parallel arrays are the **strided view of the same
  buffer**, not a separate allocation. (MPSNDArray:
  https://developer.apple.com/documentation/metalperformanceshaders/mpsndarray )
- **macOS 15 / iOS 18 `arrayView(input, shape:, strides:)`** aliases input memory copy-free — so the
  padded-to-8 SoA can feed MPSGraph as a non-contiguous view, **one `MTLBuffer` backing both the
  hand-Metal path and the trainer** (gated; older OS materializes a contiguous copy). (WWDC24-10218:
  https://developer.apple.com/videos/play/wwdc2024/10218/ )
- **Dual-backend-from-one-source is the ONNX-MLIR "reference lowering" pattern** realized SixFour-style:
  the Haskell spec + `LookNetEval` oracle is the IR-and-reference, `Codegen.*` emit per-backend ports,
  and **one set of golden vectors gates BOTH** an MPSGraph-builder emitter and a hand-Metal emitter — a
  shared compiled IR would breach the Tier-2 zero-dep rule, so golden conformance substitutes. (onnx-mlir:
  https://github.com/onnx/onnx-mlir )
- **fp32, not fp16, is the pragmatic default** on Apple for these tiny nets (fp32 often faster, fp16 can
  NaN); this also means the dormant CoreML/ANE FLOAT16 fallback would **change numerics** vs the
  fp32 MPSGraph/Zig path. (PyTorch hardware 2025: https://tunguz.github.io/PyTorch_Hardware_2025/ )
- **Adversarial-verify verdict — PARTIALLY-SUPPORTED.** The math foundation (Naperian/representable,
  Gibbons 2017: https://www.cs.ox.ac.uk/people/jeremy.gibbons/publications/aplicative.pdf ) and the
  MPSGraph↔hand-Metal shared-`MTLBuffer` interop are real, **but the single-source lowering does NOT
  exist today** — there is **no `Codegen.MPSGraph` and no `Codegen.Metal`**; the one real MPSGraph net
  (AtlasTrainer, 29,249 params) is **hand-written Swift, not lowered from `Tensor.hs`**, and is not
  spec-pinned. And **"golden-gated like the rest of the stack" is weaker than it sounds**: the Zig core
  is gated byte-exact; float GPU/MPSGraph nets can be gated only **ordinally** via `q16Key`, never
  bit-exact.

### 3.4 Determinism

- **The primary cause is changing reduction ORDER, not concurrency itself.** IEEE-754 non-associativity
  is necessary but not sufficient; "batch invariance" violations (a kernel picking a different
  tile/strategy per shape) are the real culprit. A tiny forward pass at fixed shapes with fixed reduction
  order is **run-to-run deterministic on a given device** — the hard problem is **cross-device**
  (different Apple GPU family = different kernel). (Thinking Machines:
  https://thinkingmachines.ai/blog/defeating-nondeterminism-in-llm-inference/ )
- **Float atomics are a stronger, completion-order-dependent hazard.** The mitigation: **disable float
  atomics**, use ordered register/tree reductions. (arXiv:2408.05148:
  https://arxiv.org/pdf/2408.05148 ; Deterministic Atomic Buffering, MICRO-53:
  https://microarch.org/micro53/papers/738300a981.pdf )
- **Integer/fixed-point accumulation is ASSOCIATIVE → order-independent → bit-exact regardless of
  schedule.** This is the canonical reconciliation with the Q16 contract (Jacob et al. CVPR 2018,
  int8 operands → int32 accumulator → requantize:
  https://openaccess.thecvf.com/content_cvpr_2018/papers/Jacob_Quantization_and_Training_CVPR_2018_paper.pdf ).
  **Output-only quantization (float on GPU → cast to Q16) only fixes determinism if the float result is
  identical across devices to within < 0.5 Q16-ULP at every boundary** — otherwise two devices round to
  different integers; **safer to do the bit-exact-critical accumulation in integer.** (arXiv:2301.13376
  overflow bounds: https://arxiv.org/pdf/2301.13376 )
- **Float deviation is tiny AND structured, so argmax/decision outputs are far more stable than raw
  bits:** ~1e-3 relative perturbation, **zero prediction flips in 10,000 trials** (single NVIDIA GPU,
  does NOT establish Apple cross-family stability). → a value head used only to **rank** is
  decision-stable; what truly needs Q16 is the **SR residual feeding the integer-index path**.
  (arXiv:2511.00025: https://arxiv.org/pdf/2511.00025 )
- **Metal gives explicit knobs but no cross-family guarantee:** fast-math allows reassociation + FMA
  contraction; disabling it + a fixed tree reduction + no float atomics gives **same-device**
  reproducibility; Apple MPS "fine-tunes kernels per GPU family" → **no contractual cross-device
  bit-exactness.** (MSL spec: https://developer.apple.com/metal/Metal-Shading-Language-Specification.pdf )
- **Two defensible philosophies, pick per-workload:** (A) **ENFORCE** (fixed order + integer accumulate —
  what the Zig core does, required for the SR floor-gate); (B) **TOLERATE** with error bounds — fine for
  rank/propose (NAO, arXiv:2510.16028: https://arxiv.org/html/2510.16028v1 ).
- **Adversarial-verify verdict — SUPPORTED** (cross-device bit-exactness not guaranteed for learned
  compute; HARD MUST #2 requires fixing reduction order OR quantizing through Zig). Caveat: the real
  requirement near the integer boundary is **stable quantization decisions (integer-stable argmin/
  rounding), not full float bit-exactness** — float noise below the quantization step is harmless; noise
  that flips an index near a rounding boundary is the failure mode.

### 3.5 Tiny-net perf + on-device training

- **MPSGraph is the only dep-clean on-device trainer.** Core ML `MLUpdateTask` is an opaque black-box
  updater → **OFF-CONTRACT**; MPSGraph keeps the graph hand-owned. (MLUpdateTask:
  https://developer.apple.com/documentation/coreml/mlupdatetask )
- **`simdgroup_matrix` at SixFour's 8×8 sizes only roughly matches scalar code (~17–18 cycles/8×8
  matmul) — no free lunch;** small-matmul timing is itself variable (clock-state bimodality). It
  accumulates in ≥FP32. **M5 adds dedicated Neural Accelerators (FP16 matmul), widening the determinism
  gap** between newest and older silicon SixFour must still support. (metal-benchmarks; Rigel
  arXiv:2606.12765, as above.)
- **Thermal throttling is the dominant latency risk for SUSTAINED loops, not peak FLOPs:** older iPhone
  GPUs shed **~40–60%** under continuous load; a one-shot 12.4 ms value step + a short MCTS burst live in
  the safe peak regime, but **a long SR-training run or deep search hits the Hot plateau** → budget the
  **sustained** number. iPhone 17 Pro / A19 Pro reports up to 3× A18 peak GPU + a new cooling system, but
  **the floor device cannot be assumed to behave like the ceiling device.** (LLM-at-the-edge,
  arXiv:2603.23640: https://arxiv.org/html/2603.23640v2 ; Argmax:
  https://www.argmaxinc.com/blog/iphone-17-on-device-inference-benchmarks )
- **On-device training of small nets is established prior art** (per-user "personalization" via tiny
  adapter modules, batching is the main lever); SixFour's frozen-floor + tiny-residual-on-top design is
  structurally identical. The open variable is **step COUNT per A/B pick under thermal limits**, not
  whether it can train. → keep training **event-driven (per pick), not a sustained loop.**
  (arXiv:2206.04688: https://arxiv.org/pdf/2206.04688 ; Apple foundation models:
  https://machinelearning.apple.com/research/introducing-apple-foundation-models )

## 4. Substrate assignment (RECOMMENDATION, pending sign-off)

The rule from §2.4: **integer Zig Q16 iff the output must be cross-device bit-exact; otherwise float,
re-quantized at the boundary.** Applying it per workload:

| Workload | Recommended substrate | Needs determinism? | Why |
|---|---|---|---|
| **Value-head TRAIN** (BT MLP ~50–100K params) | **MPSGraph (float fp32)** | No (training-loss minimization converges to the same decision) | The documented `gradients→SGD→assign` loop is the proven AtlasTrainer spine (12.4 ms/step). On-device autodiff is the load-bearing capability and MPSGraph is the only dep-clean trainer. **Add a Q16/fixed-order training-trajectory golden (`nn-10`)** to *gate* it, not to make it bit-exact. |
| **Value-head INFER / scoring** | **MPSGraph (float fp32), batched over K candidates** | No — **ordinal only** | The value head only **ranks**; float noise is ~1e-3 and structured (zero flips empirically), and `q16Key` quantizes the score to an integer bucket **before any argmax** so a float wobble cannot flip a cross-tier tie. Hand-Metal is a fallback if the per-dispatch overhead at ~30K params beats MPSGraph (benchmark). |
| **Proposer SEARCH (shallow MCTS depth 2–3, Sequential Halving)** | **Swift CPU control flow** orchestrating **batched MPSGraph value evals** | Tie-break only, via `q16Key` | Dynamic tree control flow is **hostile to MPSGraph's static compile-once-per-shape model** (the "ANE-hostile = MPSGraph-hostile" reasoning one level up). Host-side tree + batched GPU scoring. Determinism enters only at the integer `q16Key` decision bucket so a float value can't flip a CPU tie. |
| **SR residual TRAIN** (FiLM + conv + pixel-shuffle) | **MPSGraph (float fp32)** | No (learning the residual) | All ops are first-class MPSGraph (`convolution2D`, `convolutionTranspose2DDataGradient`, `depthToSpace`, FiLM = mul+add). **Training latency/thermal is UNPROVEN** (risk R1); keep it **event-driven, not a sustained loop**. |
| **SR residual INFER + zero-gate + final 256-cube** | **Zig integer Q16** for the floor + index path + zero-bypass; **GPU float** for the thin learned residual only | **YES — cross-device bit-exact (HARD MUST #2)** | The `zero-genome == floor` law must be **structural** (genome==0 ⇒ short-circuit to the Zig integer floor before any float touches the output), **not** numerical vanishing of a float residual. Pixel-shuffle is a deterministic integer permutation → stays on Zig; the FiLM/conv reductions are the only non-deterministic part, so the **GPU→integer handoff is drawn at the residual's argmin/index-assignment**, which runs on the integer core. |
| **Deterministic floor** (`Upscale256`, Haar/RGBT lift, collapse, OKLab, `s4_quantize`) | **Zig integer Q16** | **YES — bit-exact** | Already shipped here; this is the determinism substrate and the reference the goldens gate against. |
| **Genome ops** (orthogonal A/B seed, `leafOverride` tint, 384-DOF interface) | **Zig integer Q16** (`s4_leaf_override`) + **Swift** seed (`GenomePair`/`ABCandidates`) | Interface is bit-exact; seed is float-tolerant | The 384-DOF genome **interface already lowers cleanly** (`SigmaPairHead`→`NetContract`→`AtlasTrainer.genomeDim`); the tint is integer in Zig; the sampling seed is CPU float (only seeds candidates, then re-enters the integer path). |

### The determinism-driven split, explicit

- **Floor + final quantize + index path + zero-gate live on integer Zig** for cross-device
  bit-exactness. The SR `zero-genome == floor` contract is satisfied by a **structural zero-bypass**, not
  by hoping GPU float equals the floor.
- **Learned float detail (value scores, policy logits, SR residual deltas) lives on GPU/MPSGraph**, then
  is **integer-quantized through the Zig path** before it can affect a bit-exact output — its FP noise is
  absorbed by the quantization step (decisions via `q16Key`, SR residual via Q16 add after the integer
  argmin).
- **Nothing decided here is committed** — these are §8 sign-off items. In particular **MPSGraph-vs-
  hand-Metal for the value-head forward pass is left to an on-device benchmark** (CLAUDE.md's
  "chosen after benchmarking" clause), and the **Metal 4 quantized-TensorOps path stays a forward-looking
  option** (iPhone 17 Pro predates M5 Neural Accelerators).

**Dep rule holds throughout:** MPSGraph + `MPSNDArray` + hand-written MSL (incl. `simdgroup_matrix` and
the Metal 4 `tensor` type) are the team's own code over Apple **system** frameworks — distinct from the
forbidden mlx-swift / CoreML-blackbox / opaque-ANE.

## 5. Work-breakdown DAG

The 11 consolidated work items, dependency-ordered, grouped into milestones (cheapest-enabling-first).
Every item is **spec-first** per CLAUDE.md: **Spec → `cabal test` → codegen golden → Zig/Swift/Metal/
MPS port.**

| id | component | layers | size | depends-on | coverage |
|---|---|---|---|---|---|
| **nn-1** | coldstart-prior | Spec | small | — | partial |
| **nn-2** | hard-constraint-laws | Spec, codegen | small | — | partial |
| **nn-3** | proposer-search (depth bound) | Spec, codegen | small | — | partial |
| **nn-4** | genome-pair-generator (n-way) | Spec, codegen, Swift | small | — | covered |
| **nn-5** | proposer-search (`Spec.Proposer` assembly) | Spec, codegen, Swift | medium | nn-3, nn-4 | partial |
| **nn-6** | value-head BT-MLP (training law) | Spec, codegen, MPSGraph, Swift | medium | nn-1 | partial |
| **nn-7** | value-head BT-MLP (live path port) | Swift, MPSGraph | medium | nn-6 | partial |
| **nn-8** | sr-residual-floor-gate (`ExportFamily` spec) | Spec, codegen | large | nn-2 | **hollow** |
| **nn-9** | sr-residual-floor-gate (compute) | Zig, Metal, MPSGraph, Swift | large | nn-8 | **hollow** |
| **nn-10** | training-loss-gradient-determinism (golden) | Spec, codegen, Swift, MPSGraph | medium | nn-6 | partial |
| **nn-11** | coldstart `Spec.MetaPrior` (optional) | Spec, codegen, Swift, MPSGraph | medium | nn-1, nn-6 | partial |

### What each item is (one line, grounded)

- **nn-1** — Register the 14 already-written cold-start laws (`Properties.PersonalGenome` /
  `Properties.GenomeBlend`) in `test/Spec.hs`; both files exist but are not imported. **Zero new design.**
- **nn-2** — Add the per-frame-only / no-global-collapse invariant (HARD MUST #1) as a law beside
  `Collapse.globalCollapseQ16` (today only Swift-feature-guarded). Also de-risks the proposer substrate.
- **nn-3** — Thread a `depthBudget` through `mctsStep`, add a `depth>=3` terminal clause + `lawDepthBounded`.
- **nn-4** — Generalize `GenomePair` from exactly-2 to n-way disjoint-band partition (only needed if the
  proposer expands >2 seeded children). Already `covered`.
- **nn-5** — Create `Spec.Proposer` composing the three never-assembled real pieces (seed from
  `GenomePair`, run `GumbelSearch.sequentialHalving`, rank by the value head) + one composed golden.
  **Headline architecture; wiring not rewrite.**
- **nn-6** — Add the BT-MLP value training LAW (backprop through the MLP forward, not `linearUtility`).
  **The compute already exists on-device** (AtlasTrainer MPSGraph, 12.4 ms/step) — this is the missing
  spec law to *gate* it.
- **nn-7** — Port the live value path from CPU-linear θ to the MPSGraph MLP; persist trained weights;
  verify forward against the `nn-6` goldens. Sim-gated off (no MPSGraph device in simulator).
- **nn-8** — Fill `ExportFamily` / `NetSynth256` — **the only 100%-`error "TODO"` module in `spec/`**.
  Real zero-init-gated residual body (`floor (+) s*tanh(residual)`), FiLM, pixel-shuffle; prove
  `lawZeroGenomeIsFloor` bit-exact vs `Upscale256`. **Closes the hollow + content-half of MUST #2.**
- **nn-9** — Implement the SR residual COMPUTE: the **determinism-split assignment** — floor+index on Zig
  integer Q16, learned residual on GPU float, zero-gated bit-exact, verified vs `nn-8` goldens.
  **Compile-check only (no camera in sim).** Carries risk R1.
- **nn-10** — Add a cross-device bit-exact BT training-trajectory golden (Q16 / fixed-order twin of
  `btUpdate`) so the MPSGraph trainer is *gated*; hardens the already-claimed "bit-identical loss
  trajectory."
- **nn-11** — Optional `Spec.MetaPrior` (frozen Reptile/federated init blended via `personalBeta =
  50/(n+50)`, applied to value/policy+genome but NOT the SR head). **Lowest priority (explicitly optional).**

### Critical path

```
nn-2 ──▶ nn-8 ──▶ nn-9          (SR / HARD MUST #2 — the longest chain, two large items)
nn-1 ──▶ nn-6 ──▶ nn-7          (value head: spec law → trained MLP live)
                  └──▶ nn-10    (training determinism golden, gates the trainer)
nn-3, nn-4 ──▶ nn-5             (proposer assembly)
nn-1, nn-6 ──▶ nn-11           (optional meta-prior, off the critical path)
```

The **binding critical path is `nn-2 → nn-8 → nn-9`** (the only `hollow` coverage, two `large` items,
and the sole unmet HARD MUST). Everything else is `small`/`medium` and mostly **wiring of already-real
spec bodies**.

## 6. Milestones

Sequenced cheapest-enabling-first. The exit criterion for every milestone is **`cabal test` green** (the
cross-tier gate) plus, where a port exists, **BUILD SUCCEEDED** (camera apps are compile-check only).

### M1 — Cheap spec wiring (`nn-1`, `nn-2`, `nn-3`, `nn-4`)

Register laws that already have real bodies but are not yet run, and add the two missing invariants
(per-frame-only, depth-bound). All `small`, no new design, mostly `Spec` (+ trivial codegen).
**Exit:** the 14 cold-start laws + `lawDepthBounded` + the no-global-collapse invariant + the n-way
`GenomePair` laws all run and are green; codegen drift = 0. This is the **cheapest milestone and unblocks
nn-5, nn-6, nn-8.**

### M2 — Proposer assembly (`nn-5`)

Create `Spec.Proposer` composing the three real-but-unassembled pieces (genome seed → Sequential
Halving → value-head rank) with one composed golden, plus the Swift host-side tree caller.
**Exit:** `Spec.Proposer` golden green; a Swift MCTS-depth-2–3 loop exists that calls batched scoring;
`q16Key` tie-break is enforced at the decision boundary. **The headline architecture lands as wiring.**

### M3 — Value head: spec law + live port (`nn-6`, `nn-7`, `nn-10`)

Add the BT-MLP training law (gating the already-proven AtlasTrainer compute), port the live value path
from CPU-linear θ to the MPSGraph MLP, and add the cross-device training-trajectory golden.
**Exit:** `nn-6` forward matches goldens; the MPSGraph MLP is the ranking value used by the proposer
(sim-gated off); `nn-10` Q16 training-trajectory golden green so the trainer is gated.

### M4 — SR residual + HARD MUST #2 (`nn-8`, `nn-9`) — the critical path

Fill the hollow `ExportFamily` spec (real zero-gated FiLM/pixel-shuffle residual, `lawZeroGenomeIsFloor`
bit-exact vs `Upscale256`), then implement the compute under the determinism split (floor+index on Zig
integer Q16, learned residual on GPU float, structural zero-bypass).
**Exit:** `ExportFamily` is in `spec.cabal`, `Properties.ExportFamily` + FNV golden green,
`lawZeroGenomeIsFloor` proves bit-exact equality; the Swift/Zig/Metal port BUILDs and verifies against
the goldens. **This closes the only `hollow` coverage and the only unmet HARD MUST.** Gated on the R1
feasibility spike.

### M5 — Optional meta-prior (`nn-11`)

Add `Spec.MetaPrior` (frozen Reptile/federated init faded via `personalBeta`), applied to value/policy +
genome but not the SR head.
**Exit:** `nn-11` law ties prior weight `50/(n+50)` to fade-out and is green. **Explicitly optional; ships
only if the cold-start spike justifies it.**

## 7. Risk register

| id | risk | grounding | mitigation |
|---|---|---|---|
| **R1** | **On-device SR TRAINING is unproven + thermally bounded.** The 12.4 ms/step figure is the tiny BT value head, NOT a conv+pixel-shuffle SR body; no citation establishes interactive-latency SR training. Older iPhone GPUs shed **~40–60%** under sustained load. | adversarial-verify "LATENCY UNPROVEN for SR"; arXiv:2603.23640 thermal; AtlasTrainer is value-only. | **Spike SR training feasibility separately** (gate `nn-9` on it). Keep training **event-driven (per A/B pick), not a sustained loop**; budget the **Hot-plateau** number, not peak. SR nets are 3–4 orders smaller than the ResNet-34 ceiling that throttles, so the envelope is plausible — but **measure on the floor device, not the ceiling device.** |
| **R2** | **GPU determinism: no cross-device float bit-exactness.** GPU reductions are non-associative/order-dependent; Apple MPS "fine-tunes kernels per GPU family"; no contractual guarantee. M5 Neural Accelerators (FP16 matmul) diverge from the M1–M4 FP32-ALU path SixFour must still support. | §3.4; arXiv:2408.05148 / 2511.00025; MSL fast-math reassociation. | **Never put a bit-exact output on raw GPU float.** Floor+index+zero-gate stay on **integer Zig**; learned float is **quantized through `q16Key`/Q16-add** before it affects bytes. Test **integer-stable quantization decisions at boundary cases** (the real requirement, slightly stronger than "run it through Zig"). |
| **R3** | **Cold-start: untrained nets at n=0.** Value/policy heads have no data on first runs; SR cold-starts on the floor. | §1.5; `nn-1`/`nn-11`. | **SR cold-starts on the deterministic floor by construction** (zero-genome == floor). Value/policy fade in a frozen prior via `personalBeta = 50/(n+50)` (`nn-11`), so early behavior is the prior, not noise. `nn-1` makes the floor-is-default ramp a gated law. |
| **R4** | **Static-graph rigidity:** MPSGraph compiles once **per shape**; dynamic control flow (variable MCTS depth, halting) is hostile and recompiles per shutter press are a latency cliff. | §3.2; adversarial-verify "MCTS is host-side." | **Keep MCTS tree control flow host-side in Swift**, orchestrating **batched** MPSGraph value evals. Keep **K (candidate count) and SR tile shapes fixed/bucketed** so no per-press recompile. Static-unroll the shared block (×8), matching the spec's existing choice. |
| **R5** | **Single-source lowering does not exist yet.** No `Codegen.MPSGraph`, no `Codegen.Metal`; the one MPSGraph net is hand-written Swift, not spec-pinned. "Golden-gated like the rest of the stack" is **ordinal-only** for the float tiers, not byte-exact. | adversarial-verify CLAIM 3 (PARTIALLY-SUPPORTED). | **Gate float tiers ordinally** via `q16Key` goldens (a strictly weaker but honest gate); reserve byte-exact gates for the Zig integer path. If a hand-Metal forward pass is chosen, add a **golden-vector conformance check against `LookNetEval`** rather than a shared compiled IR (which would breach the zero-dep rule). |

> **Honest read:** R1 is the genuine open risk and gates the critical-path M4. R2/R4/R5 are **bounded by
> the substrate split**, not eliminated — the plan's value is that it assigns each workload so the
> bit-exact contract never touches a non-deterministic substrate.

## 8. DECISIONS FOR SIGN-OFF

These are substrate + determinism choices the research **frames but does not pick** — they come back to
the user before becoming commitments.

1. **Value-head forward substrate: MPSGraph vs hand-Metal SIMT.** Training is settled on MPSGraph (only
   dep-clean autodiff, proven). The **inference/scoring** forward pass at ~30K params is launch-overhead-
   bound, where hand-Metal (sharing the render command queue, avoiding MPSGraph's hidden intermediates)
   *might* beat MPSGraph — **CLAUDE.md says "chosen after benchmarking."** Decision: **default MPSGraph,
   benchmark hand-Metal on iPhone 17 Pro before committing?** (Recommend: yes, default MPSGraph.)

2. **Determinism strategy for learned detail.** Confirm the rule: **bit-exact outputs (floor, index path,
   zero-gate) stay on integer Zig Q16; learned float (value/policy/SR residual) lives on GPU and
   re-enters via `q16Key` / Q16-add.** Equivalently: float tiers are **gated ordinally**, never byte-exact.
   (Recommend: adopt.)

3. **SR residual: GPU float train + integer-quantized output?** Confirm the SR residual **trains on GPU
   float (MPSGraph)** but its **output re-enters the integer-index Zig path**, with the
   `zero-genome == floor` gate enforced as a **STRUCTURAL zero-bypass** (genome==0 ⇒ skip the float
   residual op graph entirely, emit the Zig floor) — **not** numerical vanishing of a float residual.
   This makes `lawZeroGenomeIsFloor` an **exact-equality** law and dictates where the gate lives.
   (Recommend: structural zero-bypass.)

4. **GPU→integer handoff point for SR (per frame).** The pixel-shuffle is a deterministic integer
   permutation (safe on Zig); the FiLM/conv reductions are the non-deterministic part. Confirm the
   handoff is drawn at the **residual's argmin/index-assignment**, which runs on the integer core, so the
   float residual feeds Zig **before** any byte-defining decision. (Recommend: argmin on integer core.)

5. **Training cadence.** Confirm per-user training is **event-driven (one short burst per A/B pick), not a
   sustained loop**, to stay clear of the Hot-plateau thermal envelope (R1). (Recommend: event-driven.)

6. **Optimizer.** MPSGraph ships `stochasticGradientDescent` turnkey; **Adam/momentum must be composed**
   from `mul`/`add`/`assign` on extra variables. Decision: **SGD-only for v1, or hand-build Adam?**
   (Recommend: SGD-only for v1; the proven spike uses SGD.)

7. **Precision: lock fp32 for the float tiers?** fp32 is faster + more stable than fp16 on M1–M4 for these
   tiny nets, and it is what gave the AtlasTrainer bit-identical Mac↔iPhone trajectory; the dormant
   CoreML/ANE FLOAT16 fallback would diverge. Decision: **pin fp32?** (Recommend: yes.)

8. **Metal 4 / M5 quantized-TensorOps path: defer?** It is OS-/silicon-gated and the **iPhone 17 Pro
   target predates M5 Neural Accelerators**, with unestablished cross-device bit-exactness. Decision:
   **keep it a forward-looking option, out of scope for v1?** (Recommend: defer.)

9. **`s4_load_look_net` blob path: repurpose or retire?** The Zig parser + `S4LookNetWeights` struct exist
   and are tested but consume the **abandoned supervised look-NN** with no forward pass. Decision:
   **repurpose the blob path for the new value/SR weights, or retire it?** (Recommend: retire; persist the
   new MLP weights via a fresh plain binary blob per `nn-7`.)

10. **Scope of `nn-11` (meta-prior).** It is **explicitly optional** in §1.5. Decision: **in or out of the
    committed plan** (ships only if the cold-start spike justifies it)? (Recommend: build the spec law,
    defer the trained-prior production until cold-start data warrants it.)
