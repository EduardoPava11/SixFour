# SixFour Research Papers Index

Reference catalogue of the research assets backing the SixFour A/B-loop pivot.
Source PDFs live in `~/CubeGIF/Research/Papers/`. This index maps each paper to the
**one technique** SixFour uses it for and **which pivot risk** (R1–R5) it serves, then
catalogues `~/CubeGIF` itself as the working float/NEAT **prior art** that the pivot
re-implements in deterministic Q16.

> Reading note on the risk frame: the verified prior art and these papers do **not**
> add a generator or a second orthogonality basis. The 384-DOF σ-pair is the decided
> generator (R1) and band-disjoint 384-D Haar support is the exact-0 orthogonality (R2);
> both are settled design decisions, not open gaps. The papers' real, contract-safe value
> is closing the **training** (R3) and **temporal** (R5) risks. See the Risk Legend.

## Risk Legend

| Risk | Pivot gap |
|------|-----------|
| **R1** | Proposer gap — θ only RANKS; what GENERATES the two candidates (σ-pair = decided generator; live sub-gap = cold-start `sampleOrthogonalPair`) |
| **R2** | Orthogonality — two 16³ candidates genuinely distinct AND both valid (band-disjoint Haar = exact-0; spatial/temporal demoted to a band-PARTITION heuristic) |
| **R3** | On-device training — cold-start + verified per-pick preference update + learn/regenerate cadence |
| **R4** | 256³ synthesis / continuous space-time floor (`synthBeyond` cascade floor is canonical; INR/LVE deferred) |
| **R5** | Cube ladder {16,64,256} multi-scale + 64-frame GIF-loop temporal coherence |

## The 9 Papers

| # | Filename | Full Title | SixFour uses it for (one technique) | Serves |
|---|----------|------------|--------------------------------------|--------|
| 1 | `CPPN_Original_Stanley.pdf` | Evolving Neural Networks Through Augmenting Topologies (NEAT; Stanley & Miikkulainen 2002) | Speciation via compatibility distance (excess + disjoint + weighted mean weight-diff) as the *principled* way to keep two distinct-yet-valid candidates alive — integer counts ⇒ cleanest Q16 fit | R2 (also R3 cold-start complexification) |
| 2 | `CPPN2GAN_ArXiv.pdf` | CPPN2GAN: Combining CPPNs and GANs to Generate Diverse Content (Schrum, Volz & Risi 2020) | Latent-Variable-Evolution reframe — evolve a coordinate→latent map over a *frozen* generator (σ-pair as the analogue of their pre-trained GAN); headline result: indirect coordinate→latent beats evolving raw latents on diversity AND cohesion | R1 (REJECTED as architecture — risks resurrecting deleted buresBarycenter; lesson retained, reframe rejected) |
| 3 | `KataGo_Accelerating_SelfPlay.pdf` | Accelerating Self-Play Learning in Go (KataGo; Wu 2019) | Auxiliary-target decomposition (train-time-only sub-losses localize gradients from one sparse A/B bit) + gated promotion (promote θ only if it beats the current) + playout-cap two-clock cadence | R3 (highest-leverage, lowest-risk imports) |
| 4 | `CrossViT_MultiScale_Attention.pdf` | CrossViT: Cross-Attention Multi-Scale Vision Transformer for Image Classification (Chen, Fan & Panda 2021) | CLS-token-as-agent cross-scale fusion (one summary token per cube scale carries coarse→fine context in LINEAR time, not O(N²)) | R5 (cube-ladder cross-scale coupling) |
| 5 | `MERIT_Hierarchical_ViT.pdf` | MERIT: Multi-Scale Hierarchical Vision Transformer (cascaded multi-resolution backbones) | Cascade dataflow — solve 16³ first, ×4 integer-upsample, feed forward as a Q16 skip-residual into 64³ then 256³ (the ladder's dataflow over owned `s4_haar_*`) | R5 (also R4 256³ synthesis) |
| 6 | `VMC_Temporal_Attention_CVPR2024.pdf` | VMC: Video Motion Customization using Temporal Attention Adaptation (Jeong et al. 2024) | Motion-as-residual — the 64-frame loop is a low-frequency Q16 displacement residual (owned `s4_haar` low band) over a stable per-frame palette; aligns with SixFour's palette-is-motion prior | R5 (temporal coherence) |
| 7 | `StoryDiffusion_NeurIPS2024.pdf` | StoryDiffusion: Consistent Self-Attention for Long-Range Image and Video Generation (Zhou et al. 2024) | Shared-reference anchoring — every frame's palette is a child of ONE W₂-barycenter collapse (`s4_global_collapse`), making loop appearance-consistency a structural invariant, not on-device attention | R5 (loop appearance consistency) |
| 8 | `ActINR_Video_CVPR2025.pdf` | ActINR: Activation-Modulated Implicit Neural Representations for Video (CVPR 2025) | Bias-modulated INR (shared weights = basis shape, per-frame/time-conditioned biases = motion) as the continuous space-time floor — DEFERRED to a frozen Q16-LUT export asset only | R4 / R5 (deferred; float-native, high effort) |
| 9 | `ColorCNN_Few_Colors_CVPR2020.pdf` | Learning to Structure an Image with Few Colors (ColorCNN; Hou et al. CVPR 2020) | Softmax color-map proposer (argmax index + assigned-pixel-mean palette) + entropy regularizer as a single A/B knob (compact/low-entropy vs diverse/high-entropy); inference path is Q16-clean argmin + integer mean | R1 / R2 (proposer + orthogonal-but-valid; train-time entropy knob has zero Q16 cost) |

## `~/CubeGIF` as Prior Art

`~/CubeGIF` is the **working, verified predecessor** of the A/B loop: a 19-frame, **float**
(`Float.random`, float `sin`/`cos`, CoreML `computeUnits = .all`), **population-based**
NEAT/CPPN system. It proves the loop's control flow runs end-to-end — so R1/R2 are design
decisions the pivot must **not regress against**, not gaps the research "solves." Everything
float/population (CMA-ES, NEAT speciation/crossover, CPPN coordinate→latent) is rejected;
only deterministic, contract-safe shapes are ported to Q16.

### 4 key code files

| File | Path | What it proves |
|------|------|----------------|
| **GenePool** | `~/CubeGIF/CubeGIF/Neural/GenePool.swift` | The on-device A/B learning loop runs. `AttentionGene.recordSelection` (α=0.3 EMA, line ~301/308) = cheap O(1)-per-pick preference update; `recordABResult` (`totalSelections % 10 → evolveGeneration`, line ~719/730) = the **two-clock cadence** (learn-every-pick / regenerate-every-N); `ABStrategy` (line ~131) = the spatial-vs-temporal dominance axis that makes two candidates intrinsically distinct from ONE generator; `loadKataGoFoundersIfNeeded` = warm-prior cold-start + always-runs fallback. → ports to Q16 `Spec.PreferenceUpdate.btUpdate` over the 770-D θ + gated promotion. |
| **DualGIFService** | `~/CubeGIF/CubeGIF/Neural/DualGIFService.swift` | The A-vs-B emit loop works. `generateDualGIFs` (line ~135) runs ONE pipeline twice — `getBestGenes(.spatial)` for GIF-A, `(.temporal)` for GIF-B — producing two perceptually different yet both-valid candidates with no separate diversity objective; `recordSelection(winner:)` is the pick hook. → the spatial/temporal split is DEMOTED in SixFour to a band-PARTITION heuristic choosing which disjoint Haar levels seed S_A vs S_B (rides on top of exact-0 disjointness). |
| **NEATOperators** | `~/CubeGIF/CubeGIF/NeuralPipeline/NEATOperators.swift` | Speciation and breeding work. `NEATSpeciation.compatibilityDistance` (per-gene-group weighted: temporal 0.25, output 0.20…) defines what "distinct" means and protects niches via fitness sharing; `NEATCrossover.crossover` aligns variable-length genomes by `innovationId`; `NEATMutation.mutate` (σ=0.1, 90% perturb/10% reset) is the candidate-novelty source. → speciation/crossover REJECTED for the single-θ pivot (no population); innovation-number counter shelved as a deferred substrate. |
| **HierarchicalLambdaGenes** | `~/CubeGIF/CubeGIF/NeuralPipeline/HierarchicalLambdaGenes.swift` | A genome→(palette,indices) GENERATOR exists. Coarse/medium/fine (9/13/19) Lambda blocks fused by scalar gates with cross-scale bridges + separate 256×3 palette-head / 256-logit index-head — the multi-scale template for the {16,64,256} ladder; `PositionEncoding.cyclic` + `CyclicPEGene` amplitude/phase (line ~214/268) = loop-safe cyclic PE so frame N-1 abuts frame 0. → float Lambda core REPLACED by the Q16 σ-pair; cyclic PE re-derived as an EXACT period-64 Q16 cosine LUT in a NEW `Spec.TemporalLoop` (not the existing float `Spec.Cyclic`). |

## Papers to Fetch

| Paper | Why fetch | Priority |
|-------|-----------|----------|
| **HyperNEAT** (Stanley, D'Ambrosio & Gauci 2009) — A Hypercube-Based Indirect Encoding | The load-bearing citation behind the disputed CPPN-coordinate→latent reframe. CubeGIF's CPPN emits only 6 attention scalars (no latent/frozen-GAN), so the reframe is unsubstantiated; fetch to honestly judge whether a coordinate→substrate front-end could EVER reconcile with the Q16 σ-pair — likely confirms rejection. | High (settles R1/R2 ruling) |
| **ES-HyperNEAT** (Risi & Stanley 2012) — Enhanced Substrate (density/resolution evolution) | Substrate resolution evolution maps directly onto the {16,64,256} multi-resolution ladder question (R5/R4). Fetch to see if a resolution-agnostic substrate offers anything the deterministic MERIT cascade over `s4_haar` does not. | Medium |
| **SIREN** (Sitzmann et al. 2020) — Implicit Neural Representations with Periodic Activation Functions | Foundational periodic-activation INR underlying ActINR (R4); its exact-periodicity behaviour is directly relevant to the period-64 loop-closure decision and to judging whether a deferred Q16-LUT'd-INR export asset is worth it. | Low (only if continuous temporal super-res becomes committed; deferred per Q9) |
| **PonderNet / Mixture-of-Recursions** adaptive-compute (already in SixFour look-NN memory) | Re-fetch only if the slow-clock promotion cadence wants a *learned* halting signal rather than a fixed modulo. The deterministic integer cadence is the contract-safe default. | Optional / lowest |

## Open Rulings (carried from the pivot ledger)

- **R1/R2 premise** — confirm the adversarial reading: σ-pair = generator and band-disjoint Haar = exact orthogonality are SETTLED; the only live pieces are the still-stubbed `sampleOrthogonalPair` and its cold-start (n<8) ranking. Do NOT bolt a second float generator in front of the σ-pair.
- **Cold-start ranking source** — per-Haar-level coefficient variance of base genome g0 (recommended) vs a fixed founder band-partition preset (KataGo-founder style). Affects `lawColdStartRankingDeterministic`.
- **NetSynth256 vs ActINR** — is continuous temporal/spatial super-resolution a committed requirement? If NO, the INR cluster stays deferred and SIREN/ES-HyperNEAT are optional.
- **Aux-label corpus** — commit to generating a synthetic A/B corpus (Zig oracles over synthetic captures) for the off-device θ trainer, or defer aux losses until real pick-logs accumulate?
- **Temporal module boundary** — keep `Spec.Cyclic` (float analysis oracle) SEPARATE from the new `Spec.TemporalLoop` (shipped Q16 period-64 closure); do not merge.
