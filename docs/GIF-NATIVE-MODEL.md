# GIF-NATIVE MODEL: can a GIF89a be a transformer, and how hard is the CPU-GPU recursive loop

> Status: DESIGN OF RECORD · 2026-07-02 · Owner: SixFour
> Companions: `docs/DEVICE-MODEL-MAP.md`, `docs/GENE-COMPUTE-ECONOMY.md`, `CLAUDE.md`.
> Spec wins on any disagreement. Anchors are `file:line` verified against the gather reports;
> PROPOSED laws are named as such and are not anchors. Start any spec browse at `SixFour.Spec.Map`.

---

## 1. THE QUESTION + VERDICT

Can a stored GIF89a be read back as a transformer / GPT, and how hard is the CPU-GPU recursive refinement loop that would run it on device?

**VERDICT.** GIF89a is a TOKENIZER either way, and the tokenizer half is already built and byte-exact. The fork is in the head that rides on top. The JEPA framing is **Medium**: it reuses everything below the attention head (frozen lift, rung ladder, seam door, halting, depth-1 linear golden) and closes one loop from a written GIF back into the frozen lift and up the A7 ladder, non-autoregressive, target = the held data band. The GPT framing is **Hard and a paradigm commitment**: it adds a multi-token attention forward and next-scale autoregression that do not exist on device in any form (contract + Mac MLX only), and it re-opens the collapse that the frozen-encoder / data-manufactured-target scaffold closes unless the anti-collapse laws are authored first. The bounded A7 recursion makes the CPU-GPU loop genuinely feasible: the depth is a call-time constant (4 rungs 16 to 256, ceiling `octreeDepth` = 8), so round-trips are O(1), not open recursion. **The hard part is not the recursion, it is byte-exact determinism at the sandwich seam**: the single float-to-int door `reenterQ16` re-establishes byte-exactness within one reduction order, but it does NOT erase cross-device float reduction-order drift, so any claim of cross-device byte-equality must pin a canonical reduction order rather than launder nondeterminism through round-half-to-even.

The one missing link that unblocks either path is the same: **a Swift caller for `s4_gif_decode` (`kernels.zig:2122`), which today has zero Swift hits.** On device the GIF is write-only.

---

## 2. GIF89a AS TOKENIZER

The pinned mapping, tagged against real code. iGPT (Chen 2020) is the literal precedent: its k-means color-cluster vocabulary (k=512) is exactly a handed color table, and the GIF index stream is its token sequence, except the palette is provided by the codec, not learned. VQGAN's lesson imports directly: tokens must be context-rich, so the model's real token is the octant leaf, not the raw palette index.

| # | Claimed correspondence | Anchor | Status |
|---|---|---|---|
| 1 | palette = 256-vocab | `kernels.zig:66` (K=256), LCT `:107`, `:1919-1932` | PARTIAL: palette BUILT as a per-frame quantizer codebook; a shared embedding table does NOT exist |
| 2 | LZW index stream = tokens | encode `kernels.zig:1794`; decode `:2122` (`gifLzwDecode :2058`) | BUILT as bytes; UNBUILT as a consumed token stream device-side (no Swift caller) |
| 3 | frame axis = sequence | `CaptureSession.swift:195` (fps 20, count 64), burst `s4_gif_encode_burst kernels.zig:173` | BUILT (64-frame burst); consumed-as-context is spec-only (`ConstructionEncoder`, `JepaTarget`) |
| 4 | GCE 5cs delay = positions | GCE `kernels.zig:1911-1917`; `GIFEncoder.swift:237-244`; const `DeterministicRenderer.swift:253,466` | BUILT as a constant byte; UNBUILT as a variable/learned position (the real position is P6 `RelationalMemory.hs:131`) |
| 5 | frozen lift = the tokenizer | `EncoderFrozen.hs:1-40`; `liftVec`/`unliftVec RefinementSystem.hs:139-145`; `s4_octant_lift kernels.zig:857` | BUILT (spec laws green + Zig floor kernel), param-free, byte-exact |

**Palette (#1).** The palette is a real per-frame 256-entry Local Color Table (no GCT), quantized by maximin (Gonzalez farthest-first) seeding plus optional Lloyd, byte-exact vs `Spec.QuantFixed`: `s4_quantize_frame kernels.zig:343` (seeding `:369-427`, Lloyd `:431-452`), OKLab-Q16 centroids written to sRGB8 by `s4_palette_oklab_to_srgb8 kernels.zig:1685`, Swift caller `SixFourNative.swift:171`, trainer soft-assignment twin `trainer/mlx/frame_palette.py:69-80`. There is NO `nn.Embedding`, no learned index-to-vector matrix anywhere. The palette is a per-sequence codebook, not a fixed learned token-embedding. The model's actual embedding is the frozen feature map `featuresB` applied to lifted octants, not a palette lookup.

**LZW (#2), stated plainly.** LZW is a greedy open-addressed dictionary code (`LZW_SLOTS=8192 kernels.zig:1724`, LSB-first `BitSink :1757`, clear/reset `:1844`), byte-faithful to `GIFEncoder.swift`. **LZW is NOT attention.** It carries no query-key comparison, no learned mixing, no positional bias. It is a lossless byte serializer of the index map. Decode exists in Zig (`s4_gif_decode kernels.zig:2122`, `gifLzwDecode :2058`, header `sixfour_native.h:291,296`, round-trip test `synth.zig:393`) but has **zero Swift callers** (grep confirmed), so on device the index stream is written and never read back as tokens.

**The token the head actually consumes is the octant leaf via `liftOct . featuresB` (`EncoderFrozen.hs`), NOT the LZW palette index.** These are two different token notions and the metaphor conflates them. Decoding a GIF yields (index map, LCT); mapping those back through `s4_srgb8_to_oklab kernels.zig:1947` into the octant lift is the UNBUILT device-side bridge (map:tokenizer #2). The frozen lift itself is BUILT: prefix-difference scheme `liftVec`/`unliftVec RefinementSystem.hs:139-145`, class `ReversibleLift :120`, octant override `RefinementCarriers.hs:111-112`, floor kernels `s4_octant_lift`/`s4_octant_unlift kernels.zig:857/887`, laws `lawEmbeddingFeatureMapIsParameterFree`, `lawPredictorIsTheOnlyLearnedObject`, `lawEmbeddingNeverBypassesQ16`.

---

## 3. THE CPU-GPU RECURSIVE LOOP

The per-rung fold, framing-agnostic:

```
rung k (side s -> 2s):
  [CPU-int]  I-expand : bands <- s4_octant_unlift(coarse_k, detail_k)   byte-exact, refuse-not-wrap
  [handoff]  commit integers only cross the seam
  [GPU-flt]  S-invent : detail_k^theta <- theta_forward(phi(v))          fp32, theta_up=21p / theta_B=63p
  [seam]     reenterQ16 : committed <- rint(raw * 65536)  round-half-even  float->int door
  [CPU-int]  scatter -> cube_{k+1} (side 2s)  via s4_cube_expand_rung
  halt?      budgetToMask(painted)>0 AND k<ceiling -> recurse ; else floor-terminate
```

- CPU-int floor = the `I` stage, param-free: `s4_octant_lift`/`s4_octant_unlift kernels.zig:857/887`, `s4_cube_expand_rung :924` (the `details == null` fork at `:945` is the deterministic zero-detail floor), oracle-matched to `SelfSimilarReconstruct.expandRungVolume:238`.
- GPU-float invent = the `S` stage, the only weighted object: `deviceTrainFusedKernel DeviceTrainShaders.metal:191` (int lift `:202`, fp32 GD `:218-233`, Q16 commit `:238`), `theta_up` = `bands(7) x featureCount(3)` = 21p (`DeviceTrainer.swift:48`), features `phi(v)=[1,v,v^2]` `:52`; or depth-1 `theta_B` 63p linear forward `MaskedBandForward.swift:22`.
- Seam door = `reenterQ16 ByteCarrier.hs:92`, three matched twins Haskell / Swift (`DeviceTrainer.swift:72`) / Metal (`rint(raw*kQ16) metal:238`), type-enforced sole `Latent -> Int` (`lawByteOnlyFromQ16 :109`).

**Bounded round-trip count.** The depth is a call-time constant: `CurateBuilder.expandLadder swift:46` runs `for _ in 0..<rungs`, `rungs` a fixed Int (2 preview, 4 full), filtration explicitly finite (`ScaleFiltration.hs:11-13`), Ponder only shortens (`budgetToMask PonderBudget.hs:58`, `haltDist PonderHaltDistribution.hs:36`, floor always terminates `AnytimeDecode lawDecodeIsAnytime`). The full 16 to 256 ladder is exactly **4** `s4_cube_expand_rung` applications (`levelsPerStep = 2`, `SelfSimilarReconstruct.hs:159`). Inference = **1 CPU-to-GPU handoff per rung, integers only** (`CurateBuilder.swift:12,37-39`, `RungDispatch.swift:82`), so 4 crossings for a full expand. Training = **0 memory round-trips per rung** (fused, `metal:174`).

> DEPTH NOTE (critique-corrected). The "7" in A7 is bands-per-octant (branching 8 minus 1, `ScaleFiltration lawOctantBranchingIs8`), NOT a recursion depth. The recursion ceiling is `octreeDepth` = 8 for 256^3 = 2^8, and the shipped ladder from the 16^3 substrate is 4 rungs. State the bound as `rungs <= octreeDepth`, never as "recurse <= 7".

**The sandwich seam contract.** Only integers cross to the GPU; each rung re-enters Q16 so float error never accumulates across rungs (the integer floor re-establishes byte-exactness before the next `s4_octant_lift`). Float trajectories legitimately differ pre-commit (`DeviceTrainer.swift:18-21`); only post-commit bytes must match. **This holds within one binary / one reduction order. It does NOT hold across GPU families**: if MFA / MPSGraph reduction order differs, `raw` can land on opposite sides of a Q16 half-integer near a tie, and round-half-to-even commits to different integers. Round-half-to-even is the discontinuity, not an absorber. A single tie-flip at a coarse rung changes the integer input to the next `s4_octant_unlift` and cascades. So the seam is reproducible, not a cross-device theorem.

**Training shares the forward.** The same operator chain runs whether training `theta_up` per burst or expanding for preview; only the middle GPU stage differs. The learned object is only the `S` predictor, so backward touches only `S` params (`I`/`K` are param-free). Today this is 1-of-6 channels real: `CaptureGene.ThetaUp.train` trains channel 0 (L) only (`CaptureGene.swift:18-26`), and the MPSGraph backward returns nil when it cannot execute (`DeviceTrainer.swift:155`). The training identity is therefore aspirational and must be gated behind the backward realizer existing.

**Proposed seam laws and whether constructible.**

| Law (PROPOSED) | Tier | Constructible? |
|---|---|---|
| `lawRungSeamByteExact`: post-commit bytes identical across the three `quantizeQ16` twins for fixed committed input, **under one pinned reduction order** | Tier-0 | YES, but ONLY as same-reduction-order reproducibility; NOT a cross-device theorem. Pin a canonical fp32 accumulation order for the `S`-invent, not MFA/MPSGraph. |
| `lawRoundTripCountBounded`: seam crossings = `rungs`, a call-time constant `<= octreeDepth` | Tier-0 | YES, structural induction over `expandLadder` + `ScaleFiltration.hs:11-13`. |
| `lawRecursionWellFounded`: rung index strictly increases, bounded, `budgetToMask=0 => floor` always terminates | Tier-0 | YES, from `PonderBudget lawEmptyBudgetIsFloor` + `AnytimeDecode lawDecodeIsAnytime`. |
| `lawBackwardTouchesOnlySParams`: autodiff gradient is zero on `I`/`K`, non-zero only on `theta` | Tier-1 | NO yet: needs the backward realizer (`DeviceTrainer.swift:155` returns nil). |
| ~~`lawInterRungFloatErrorErased`~~ | DROPPED | NOT a corollary: a tie-flip cascades. Re-derivable only under the pinned-order premise, and then it is redundant with `lawRungSeamByteExact`. |

**S must regress the held data band only.** The anti-collapse lock lives entirely in "target = data-manufactured held detail band, theta-fixed" (`JepaTarget`). The loop must forbid self-produced targets: if `S` is trained against its own re-committed output, that is `RolledForwardSelf` collapse (`JepaTarget.hs:91` marks it inadmissible).

---

## 4. TWO FRAMINGS

### 4.1 JEPA (Medium, reuses everything)

**Shape.** Non-autoregressive latent refinement: read a stored GIF, decode to (index, LCT), bridge `sRGB8 -> OKLab -> octant` to recover the held bands, run the depth-1 linear forward (`MaskedBandForward.swift:22`) on the float side, energy = d6 to the HELD target (not self-produced), `reenterQ16`, expand one rung, recurse to the ceiling. Same operator chain for train and inference.

**Reused (built today):** frozen tokenizer (`EncoderFrozen.hs`, `s4_octant_lift kernels.zig:857`), rung operator (`s4_cube_expand_rung :924`, oracle `SelfSimilarReconstruct:238`), inference ladder (`CurateBuilder.expandLadder swift:46`), depth-1 golden (`MaskedBandForward.swift`, `lawDepth1ReducesToFeaturesBPos LargeJepaHead.hs:116`), `theta_up` learner (`CaptureGene.swift:62`), target/energy (`JepaTarget.hs`, `RelationalMemory` d6), seam (`reenterQ16 ByteCarrier.hs:92`), halting (`PonderBudget.hs:58`).

**Missing links:** (1) the `s4_gif_decode` Swift caller (`kernels.zig:2122`, zero hits), THE one missing link; (2) the `sRGB8 -> OKLab -> octant` device adapter; (3) the chained-theta invent tail 64 to 256, i.e. the device `upscale256` port (`ModelFloor.swift:13`, UNBUILT). Attention is out of scope here: depth-1 reduces to `MaskedBandForward`, which is the shipped forward.

**Cost / critic verdict.** SOUND-WITH-FIXES. Bounded recursion holds; O(n^2) never appears because n is the 16^3 decision surface. The real hole is that the GIF is a **lossy** front-end the model was never trained through: the LCT is a per-frame 256-color maximin quantizer (`kernels.zig:343`) storing nothing to invert quantization, so `decode -> octant` re-enters at quantized voxels, not the original OKLab.

**Fix (adopted).** Split the law, do not redefine it. (1) A Tier-0 equality only over already-quantized voxels: `lawGifDecodeInvertsAssemble` = `decode . assemble = id` on (index, LCT), which IS the existing `synth.zig:393` round-trip, byte-exact and gateable today. (2) Demote the original-capture equality to a Tier-1 MEASURED bounded-delta budget (`lawDecodedVoxelsReenterOctantFloor` as a quantization-Delta measurement, non-gating). (3) Force the field decision explicitly (Section 7 Q1): either commit to "palette IS the vocab" and formally retire `camera_box` as a training source, or keep the complementary `camera_box` field (not derivable from the GIF, different marginal, mass 123904) as the training source and scope GIF-decode to a cross-check. Do not ship the original-capture-equality as a green Tier-0 gate.

### 4.2 GPT (Hard, a paradigm commitment)

**Shape, least-bad variant: VAR next-scale prediction.** Not raster next-token (iGPT's O(n^2)-over-flattened trap). Predict the next-finer detail-band map conditioned on all coarser COMMITTED bands, up the octant ladder. The rung ladder 16 to 256 IS coarse-to-fine AR; "1 coarse + 7 detail" IS VAR's residual multi-scale VQ. Per rung: `s4_octant_lift` gives `[coarse | 7 detail]` (coarse = causal context, 7 detail = label), multi-token attention `logit = (q.k)/sqrt(d) + b_h(d6_ij)` with d6 as relative-position bias (`LargeJepaHead.hs`), softmax to predicted detail map, `reenterQ16`, `s4_cube_expand_rung`.

**Reused:** the same floor / ladder / seam / depth-1 golden as JEPA, plus the d6-bias contract (`Spec.LargeJepaHead`, single-token proofs `lawSingleTokenAttnIsUnit :107`, `lawBiasMonotoneInD6 :124`), the outer-product logit algebra (`Spec.ChannelProduct lawComparisonIsOuterProduct :95`), and Mac-side MLX qkv+softmax (`train_loop.py:355-361`).

**Missing (unbuilt from zero):** (1) multi-token attention forward: `HeadBias` carries only `(scale, offset) LargeJepaHead.hs:70`, `softmaxW :84` is a scalar helper, no QKV weights exist; (2) an O(n^2) Metal softmax/matmul kernel (grep `softmax|attn|qkv` over `*.metal` = zero); (3) a next-scale loss; (4) cross-rung AR context binding routed around `RolledForwardSelf` (inadmissible, `JepaTarget.hs:91`); (5) the same `s4_gif_decode` Swift caller for re-ingest.

**Cost / critic verdict.** SOUND-WITH-FIXES, with two coupled holes. First, **round-half-to-even does NOT erase softmax reduction drift**: a softmax accumulation over n terms carries ~n*eps error, so near a Q16 tie two reduction orders commit to different integers and the ladder desyncs. Second, **"small n per rung" is asserted, not shown**: octant-leaf tokens are per-voxel, so n is the rung's voxel count, up to 262144 at 64^3, where O(n^2) ~ 7e10 (iGPT's trap is NOT dissolved) and the float error blows up. VAR itself is cheap because its coarse scales are genuinely small (~680 tokens total); SixFour's rungs are orders larger. Honesty flag: held rungs 16 to 64 replay stored bit-exact detail, so the head does real synthesis only on 64 to 256; "4 next-scale predictions" is ~1 genuine synthesis step, and the VAR framing oversells the ladder.

**Fix.** Do not launder nondeterminism through `rint`. Either (i) accumulate the softmax in fixed-point integer arithmetic (integer add is associative, order-independent-exact) so the commit is a re-expression not a rounding gamble; or (ii) drop FlashAttention (its cross-family tiling is the drift source), window attention to a small per-rung n, and pin a canonical serial reduction order. Prove `lawBoundedScaleContextIsBoundedAttention` with a concrete windowed n-bound FIRST, before the kernel, because both determinism and O(n^2) affordability hang on that single bound. Author the anti-collapse laws first so the GPT keeps the collapse-proof: `lawNextScaleTargetIsHeldDetailBand` (label = held detail band, θ-free, the rescue), `lawNextScaleContextIsCoarserCommittedBands` (causal-in-scale, never self-rollout), `lawAttnCommitsThroughQ16Only`, `lawAttnDepth1IsMaskedBandForward`.

**Why VAR is the least-bad GPT.** Bounded scales (finite filtration `ScaleFiltration.hs:11-13`) mean bounded context, and it lands exactly on the A7 ladder: attend WITHIN a rung (small n, FlashAttention-tileable, exact) and condition across the <=4 coarser committed rungs. Raster iGPT's O(n^2) over flattened 64^2 x 64 is the trap VAR structurally dissolves, **but only if the windowed per-rung n is actually bounded** (see the fix above); on unbounded per-voxel leaves the trap returns.

---

## 5. DECISION

**Build the JEPA recursive loop first.** It reuses the entire built stack, is buildable to step 4 on landed primitives, keeps the collapse-proof by construction, and its only genuinely new engineering is the device `upscale256` ladder that both framings need anyway. Treat GPT / attention as a **separate scoped decision**, not a default. Before any Metal attention kernel, **prototype attention in the Mac MLX ViT** (`train_loop.py:355-361` already trains qkv+softmax): verify a real loss drop / power-law on held detail-band targets, and measure the actual per-rung token count, so the O(n^2) and determinism bounds are known BEFORE committing a hand-written commit-robust Metal softmax (the single least-built piece in the stack).

**Trigger conditions that would flip the recommendation toward GPT:**
- The Mac MLX next-scale head shows a decisive quality win over the depth-1 linear floor on the invented 64 to 256 rung (the only rung with real synthesis), large enough to justify the attention paradigm cost.
- A concrete windowed per-rung n-bound is proven (`lawBoundedScaleContextIsBoundedAttention`) that makes attention both affordable and near-deterministic without degenerating back to `MaskedBandForward`.
- A fixed-point or pinned-order softmax is demonstrated to commit bit-identically across Apple GPU families, so `lawRungSeamByteExact` survives attention on the seam.

Until all three land, the JEPA linear-floor forward is the shipped forward and attention stays deferred (`LargeJepaHead` contract-only).

---

## 6. BUILD PLAN

Dependency-ordered. UNBUILT dependencies flagged. Spec laws to author first are the Tier-0 seam laws that gate before any port ships.

1. **Spec Tier-0 (author first).** `lawGifDecodeInvertsAssemble` (lift the existing `synth.zig:393` round-trip into a spec law over `QuantFixed`/`kernels`, byte-exact), `lawTokenIsOctantLeafNotPaletteIndex` (pin token = `liftOct . featuresB`, closing map:tokenizer #2), `lawRoundTripCountBounded` + `lawRecursionWellFounded` (cheap structural inductions over `expandLadder` + `PonderBudget`). All constructible today.
2. **Swift caller for `s4_gif_decode`** (`kernels.zig:2122`), **THE one missing link**. Returns (index map, per-frame LCT) into memory; golden vs Zig `synth.zig:393`. GIF is write-only on device until this lands. Unblocks everything downstream in both framings.
3. **`sRGB8 -> OKLab -> octant` adapter in Swift** (reuse `s4_srgb8_to_oklab kernels.zig:1947` + `s4_octant_lift`). Gate the Tier-1 MEASURED quantization-delta budget (`lawDecodedVoxelsReenterOctantFloor` as a bounded-delta measurement, non-gating), and MAKE the field decision (Section 7 Q1). Accept the lossy decode seam explicitly.
4. **Chain decode -> `MaskedBandForward` (theta_B) at depth-1** (already the golden). Energy = d6 to the held band. No new kernel. Buildable-today path ends here (steps 1 to 4 all against landed primitives).
5. **Chain the invent tail through `expandLadder`**: land the **device `upscale256` port** (UNBUILT, `ModelFloor.swift:13`). This is the real remaining engineering. Gate `lawDecodeThenExpandIsAnytime` (extends `AnytimeDecode lawDecodeIsAnytime`).
6. **Point `theta_up` training** (`CaptureGene.swift:62`) at the SAME decoded-octant forward; gate `lawRecursiveForwardSharedTrainInfer` (both already call the same Zig kernel). Requires the **MPSGraph backward realizer** (UNBUILT, `DeviceTrainer.swift:155` returns nil) and generalizing `theta_up` past channel 0 before the training-shares-the-forward claim is more than 1-of-6 channels.
7. **Per-rung packet counters** (UNBUILT, `DEVICE-MODEL-MAP.md:391-415` proposal, `Feature.signpostPackets` + `MTL4CounterHeap`), needed to measure the S-schedule the budget economy assumes, and to detect a seam desync at a rung boundary.

**Deferred (GPT-only, separate scoped decision):** device attention forward (UNBUILT from zero), the hand-written commit-robust Metal softmax/matmul, and the Tier-0 anti-collapse next-scale laws (`lawNextScaleTargetIsHeldDetailBand` first). Prototype in Mac MLX before any Metal kernel.

**UNBUILT-dependency flags, consolidated:** `s4_gif_decode` Swift caller (step 2); device `upscale256` ladder (`ModelFloor.swift:13`, step 5); MPSGraph backward (`DeviceTrainer.swift:155`, step 6); per-rung packet counters (step 7); device attention forward (GPT deferred).

---

## 7. OPEN DECISIONS FOR THE OWNER

1. **Training source: decoded-quantized GIF voxels vs the complementary `camera_box` field.** The GIF decode re-enters at palette-quantized voxels, strictly lossier than the capture. RECOMMENDED DEFAULT: commit to "palette IS the vocab" (iGPT/VQGAN handed-codebook), scope the JEPA forward to quantized voxels, and formally retire `camera_box` as a training source (write it down). Keep the field only as a cross-check, not the training reference. Flip only if a measured target-bias from quantization proves too large.

2. **Seam determinism: pin a canonical reduction order vs rely on round-half-to-even.** Round-half-to-even reproduces bytes within one reduction order but not across GPU families near a tie. RECOMMENDED DEFAULT: pin one canonical fp32 accumulation order for the `S`-invent (a fixed-order deterministic kernel, NOT MFA/MPSGraph), demote `lawRungSeamByteExact` to same-reduction-order reproducibility, and never claim cross-device byte-equality without it.

3. **Head paradigm: ship the JEPA depth-1 linear floor vs invest in GPT attention.** RECOMMENDED DEFAULT: JEPA linear-floor forward is the shipped forward; attention stays deferred and contract-only (`LargeJepaHead`) until the three Section-5 triggers all land. Prototype any attention in Mac MLX first.

4. **Attention token granularity (if GPT is ever pursued): per-voxel octant leaves vs a windowed block.** Per-voxel leaves make n up to 262144 (O(n^2) trap returns, float error blows up); windowing to a 2x2x2 block (n=8) is affordable and near-deterministic but degenerates toward `MaskedBandForward`. RECOMMENDED DEFAULT: prove `lawBoundedScaleContextIsBoundedAttention` with a concrete windowed n-bound BEFORE writing any kernel; do not assert "small n" without the bound.

5. **Backward scope: 1-channel (L) vs all six.** Training currently touches channel 0 only (`CaptureGene.swift:18-26`). RECOMMENDED DEFAULT: keep the "training shares the forward" claim gated behind the backward realizer existing (`DeviceTrainer.swift:155`), and do not sequence multi-channel training as if the shared forward guarantees it; state it as 1-of-6 real today.
