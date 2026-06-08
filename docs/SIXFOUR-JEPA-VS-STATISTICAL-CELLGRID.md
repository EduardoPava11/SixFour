# SixFour NN Core: JEPA vs Statistical Design over the Cell Grid

> Deep web-research synthesis (2026-06-08). 18-agent workflow: 6 research dimensions ×
> adversarial verification + completeness gap-fill + cited synthesis. ~820k tokens, 46 sources.
> Question: should SixFour's learned core be JEPA-style embedding-prediction or explicitly
> statistical (OT barycenter + RQ-VAE/VAR + deterministic residual), and how does each consume
> the (x,y,t) 1-byte-index cell grid on-device?

## 1. TL;DR recommendation

**Stay explicitly statistical, with a thin, gated learned residual — not a JEPA core.** For SixFour's exact target (a 64→256 (x,y,t) voxel grid where each cell holds a 1-byte index into a per-burst 256-leaf OKLab codebook, produced by a ~115k-param mlx-swift GPU model with dynamic halting), JEPA is the wrong primitive: it has no decoder, never emits indices, throws away the pixel-exact detail SixFour's byte-faithful GIF contract requires, and has zero published evidence below ~15M params [2301.08243; 2506.14373]. The statistical/OT spine (sliced-W₂ barycenter collapse + RQ-VAE/VAR residual capacity + deterministic Haar/OT residual) maps natively onto the index grid, has no collapse failure mode, and is cheap on-device (256-point Sinkhorn ≪20 ms) [1507.07218; 2203.01941; 2605.00837]. The single best-supported hybrid is a **continuous-OKLab-predict-then-snap-to-leaf residual head** that owns only the provable gaps (disocclusion, color detail subbands), gated so it provably cannot degrade the deterministic base [2506.14373; 2602.20650; 1812.02224]. Borrow JEPA *mechanisms* (variance-only anti-collapse, energy-as-latent-distance), never the JEPA *architecture*.

## 2. What JEPA actually offers — and its hard limits here

JEPA's genuine, primary-source-verified strengths: it predicts the **embedding** of a masked target (not pixels), prevents collapse with an EMA target encoder + stop-gradient, is framed as an energy-based model, and is compute-efficient *relative to* generative SSL like MAE — its I-JEPA headline trains a 632M-param ViT-H/14 on 16 A100s in <72 h and wins low-shot ImageNet [2301.08243; Meta blog]. Its defining virtue is **discarding inherently-unpredictable pixel detail** by predicting in abstract space [Meta blog]. V-JEPA 2 scales this to a 1.2B-param video world model that plans via energy = L1 distance to a goal embedding [2506.09985].

Every one of those strengths is either irrelevant or actively hostile to SixFour:

- **No decoder, no indices.** JEPA emits latents, never a 1-byte palette index. To touch the grid you must bolt on a separate decoder mapping embeddings → 256-way logits → argmin. The attentive-vs-linear-probe gap (V-JEPA ViT-L: 56.7% linear vs 80.8% attentive on K400) proves that decoder must be **heavy and nonlinear** — blowing the 115k budget and violating "don't learn what you can compute," since the deterministic argmin already does codebook assignment exactly [2404.08471; 2301.08243].
- **Pixel-discarding conflicts with the byte-exact contract.** SixFour *must* reproduce exact indices and color subbands; JEPA's whole point is to throw that away [Meta blog]. Latent MIM is documented to give "low-resolution (blurred)" reconstructions [2407.15837] — the opposite of what a pixel-art GIF tolerates.
- **Collapse is real and EMA is not provably enough.** C-JEPA shows EMA "can be insufficient," needing VICReg variance/covariance terms (63.7→69.5% linear probe) [2410.19560]. This imports a training instability the statistical path lacks entirely.
- **Scale.** There is *no* published JEPA below ~15M params; the smallest demonstrations (Mini-JEPA ~22M, LeWM ~15M) are still ~130× SixFour's 115k. The 632M headline runs on A100 clusters [2301.08243]. A 115k JEPA core is unsupported extrapolation, and collapse-fragility *worsens* at small scale and small batch [2603.15263].
- **Drift.** V-JEPA 2-AC autoregressive latent rollouts "accumulate error" over horizon and need manual camera positioning; LeCun's own framing is that V-JEPA predicts "gaps in short videos," not across time [2506.09985]. SixFour's 64→256 temporal super-res needs stable long-horizon interpolation — JEPA's documented drift is the wrong tool.

The **only** transferable pieces are mechanisms: (1) energy-as-latent-distance maps cleanly onto SixFour's W₂/Bures barycenter, which is *already* an energy in measure space and is collapse-free without EMA; (2) a variance-only anti-collapse term could stabilize a tiny masked-residual head. Apple's 2025 "Rethinking JEPA" even argues frozen teachers beat canonical EMA-JEPA on compute/stability, further weakening the case for the EMA machinery [machinelearning.apple.com].

## 3. What the statistical / OT + RQ-VAE design offers

This is the better-grounded default for SixFour's objects, with citable caveats.

- **Barycenter collapse is theoretically licensed.** A Wasserstein barycenter of discrete measures is itself discrete, provably sparse, with a *non-mass-splitting* OT to each marginal [1507.07218] — exactly the property needed so the global palette stays a 256-leaf measure and each frame maps to it via clean argmin.
- **But the elegant Bures/Gaussian fixed-point is NOT licensed for discrete palettes.** The closed-form recursion is proven only for absolutely-continuous measures and explicitly "excludes discrete distributions" [1511.05355]. SixFour's per-frame palettes are discrete empirical measures, so a Bures/σ-pair approximation is a Gaussian-moment model, faithful only if palettes are near-unimodal. Worse, **computing the exact discrete barycenter is NP-hard** even in 2D with 3 measures [VERIFICATION; 1910.07568]. **The defensible base is sliced-Wasserstein in 3D OKLab** — O(n log n) via 1D sorting, cheap precisely because color is only 3D, with an established color-grading template minimizing a sliced barycenter loss over palettes as empirical measures [Bonneel JMIV; 2102.09297]. Credit the low dimensionality, not a generic SW superpower.
- **RQ-VAE/VAR supplies capacity without growing K.** A fixed codebook of size K yields K^D capacity by recursive residual quantization, avoiding the codebook-collapse that forces plain VQ-VAE to grow K [2203.01941]; VAR's coarse-to-fine next-scale residual prediction over one shared codebook is structurally isomorphic to SixFour's reversible-Haar residual subbands [2404.02905]. **Caveat:** collapse is *not* eliminated in deeper residual stages — RQ-VAE only mitigates via EMA + dead-code reinit, so budget collapse mitigation explicitly. And VAR's *prior* is a 10⁸-param transformer; SixFour can borrow only the residual **structure**, keeping the prior deterministic (Haar).
- **The Lloyd-Max ceiling validates "don't learn what you can compute."** Lloyd-Max (= k-means) is the optimal fixed-rate quantizer; Zador-Gersho theory pins distortion at ~K^(−2/d), within a small constant of the Shannon bound [1801.03742]. For OKLab palette MSE, deterministic median-cut + k-means is near-optimal, so a 115k net **cannot meaningfully beat the base quantization** — confirming the ~90%-deterministic / ~10%-learned split. (Watch the documented OKLab lightness-bias at small K, which can starve the temporal/chroma quaternary bands [ubitux].)
- **Where it leaves gaps:** McCann displacement interpolation is the *unique* constant-speed Wasserstein geodesic and gives deterministic, drift-free temporal interpolation for transported mass — but disocclusion holes have **no source** and cannot be filled by transport [2003.05534]. That irreducible residual (hole-fill + chroma detail subbands) is exactly what the learned net should own.

## 4. Head-to-head on SixFour's exact constraints

| Axis | JEPA core | Statistical / OT + RQ-VAE |
|---|---|---|
| **Data-hunger / sample efficiency** | SSL loses to supervised below ~30k samples (self-pretrain crossover); SixFour trains on synthetic GIF bursts ≪30k [PMC12405560]. Small ViTs "benefit little" from SSL; only distillation rescues them [2302.14771; 2301.01296]. | No representation pretraining needed — barycenter/argmin are closed-form. Strong, abundant supervised target = the deterministic base itself. |
| **On-device fit (params/latency)** | No JEPA <~15M params exists (~130× over budget); needs heavy nonlinear decoder + EMA twin encoder. Small-batch collapse-fragility on phone GPU [2301.08243; 2603.15263]. | Sliced-OT/Sinkhorn: 256-point measures ≪ n=2048 → sub-20 ms; INT8/fixed-point matches the Zig integer core [2605.00837]. ANE-agnostic; no twin encoder. |
| **Consumes the (x,y,t) grid** | Must de-ref index→OKLab (raw indices are arbitrary labels, meaningless to feed), patchify into tubelets, run ViT — costs ≫115k. Writes latents, never indices. | Reads indices as 64 per-frame OKLab **measures**; writes indices back via deterministic argmin. Native round-trip. |
| **Determinism / bit-exactness** | Latent regression + argmin decoder re-introduces float nondeterminism; collapse-prevention adds fragility. | Argmin index map is deterministic; matches the cross-device byte-exact GIF contract by construction. |
| **What it CANNOT do** | Cannot emit indices or colors; cannot guarantee bit-exactness; cannot run at 115k; drifts over long temporal rollouts. | Cannot beat Lloyd-Max base MSE (by design); cannot fill disocclusion holes via transport; exact discrete barycenter is NP-hard (must approximate). |

## 5. How each would concretely use the cell grid

**JEPA (poor fit).** READ: de-reference each 1-byte index through the codebook into an (x,y,t,3) OKLab volume (JEPA needs continuous metric input), patchify into spatiotemporal tubelets, run a ViT context encoder. PREDICT: mask tubelets (3D block masking, à la V-JEPA), regress masked **embeddings** from context with EMA target + stop-gradient (+ likely a variance term against collapse) [2404.08471; 2506.09985]. WRITE (the fatal gap): a separate, heavy nonlinear decoder maps predicted embedding → 256-way logits → argmin. Closest published systems: **I-JEPA / V-JEPA 2** (analysis/planning, never index emission) and **Discrete-JEPA**, which adds VQ to the *latent* but still trains with three L2 embedding objectives + VQ commitment and "sacrifices fine-grained spatial information" — it never predicts indices as a classification target in its pretraining loss [2506.14373]. This round-trip (index→embed→predict→argmin→index) adds a decoder, an EMA encoder, and collapse machinery to reproduce what one argmax over 256 logits does in one step.

**Statistical (native fit).** CONSUME: per frame t, de-reference indices to an empirical OKLab measure (≤256 weighted points). COLLAPSE: global palette = **sliced-W₂ barycenter** of the 64 measures (project onto ~16–32 random 3D directions, 1D-sort = closed-form OT, average quantiles) — no learned net for the base [Bonneel; 2102.09297]. Re-quantize each frame by deterministic argmin → rewrite the index field. CAPACITY: treat the reversible integer Haar pyramid as the depth-D RQ residual stack over the *one* 256 codebook (coarse leaf + finer subband indices = K^D colors without growing K) [2203.01941; 2404.02905]. TEMPORAL: Brenier/OT displacement v_t between consecutive measures, McCann-geodesic interpolate, softmax-splat — but **in OKLab color space, then re-quantize once at the end**, never warping indices directly. The cut level (2⁸/4⁴/16²) is the motion-bandwidth lever = which residual bands you keep.

**Decisive external evidence.** Orbis — the one controlled, same-backbone/same-tokenizer generative bake-off on real video — finds **continuous latent prediction beats discrete masked-token prediction on FVD "by a large margin" and is far more robust** to tokenizer design [2507.13162]. Under matched FLOPs, MaskGIT-style masked-token *underperforms* next-token and diffusion on FID [2405.13218]. Conversely, Discrete-JEPA shows discretization's value is **anti-drift stability** over long horizons (perfect 200-step color, 6× LPIPS at 1000 steps vs I-JEPA), not fidelity [2506.14373]. This maps onto SixFour exactly: **continuous OT/barycenter for fidelity, discrete index codebook for drift-free stability.** Critically, the field SOTA on motion-over-discrete-grids (VCT, TVC) **deletes optical flow and warping entirely**, predicting token distributions with a transformer instead — independently corroborating that **warping indices is ill-posed** (code-collapse, re-quant noise, GOP drift) [2206.07307; 2504.16953; 2312.00853]. NGLR/LBRC is the structural precedent: deterministic base dominates (30–60% gain), neural residual is "purely an entropy reducer" adding only 10–40%, provably unable to break the base guarantee [2606.05389].

## 6. The hybrid that probably wins

**Deterministic statistical base owns structure; a thin learned residual owns only provable gaps.** Concretely:

1. **Base (no net):** sliced-W₂ barycenter → shared 256-leaf SplitTree; deterministic argmin index map; reversible integer Haar carries LH/HL/HH (spatial) and DC/LF/MF/HF (temporal) subbands; OT/McCann advection for 64→256, warping in OKLab and **re-quantizing once at the terminal step** (bounds drift vs recursive index warping).
2. **Residual head (the seam):** the ~115k look-NN (384-DOF σ-pair genome) predicts a **continuous OKLab residual** on the leaf colors, then **snaps to the nearest of 256 leaves at write time**. This is the "predict-in-OKLab, snap-to-leaf" hybrid: it gets JEPA's permutation-invariance to the per-burst palette (never sees raw indices) **and** Discrete-JEPA's anti-drift snapping [2506.14373; 2602.20650]. It is OT/RQ-flavored regress-then-quantize — *not* collapse-prone energy-based JEPA.
3. **Restrict to gaps only:** disocclusion holes (no OT source), occlusion-mask selection between backward-warped candidates, and HF/MF temporal-band color detail — never the ~90% the base reconstructs.
4. **Optional JEPA-borrowed regularizer, gated:** if a masked-subband pretext is added, use a **variance-only** anti-collapse term (skip full covariance — singular when batch < D on-device [emergentmind VICReg]) and a **gradient-cosine gate**: zero the pretext gradient whenever its cosine with the supervised-residual gradient is negative, *guaranteeing convergence to the main task's critical points* [1812.02224]. This makes the auxiliary provably unable to harm the deterministic write. Because SixFour's supervised target (the base) is abundant and cheap, the overfitting-prevention payoff of SSL is muted — keep it tiny, gated, and gap-only. Better still, the **deterministic base can act as the "large teacher"** that distillation (not raw SSL) requires for tiny models [2302.14771; 2101.04731], possibly replacing the JEPA pretext entirely.

## 7. Open questions & what to prototype first (ranked)

1. **The actual bake-off (highest value).** On SixFour's own spec-gen synthetic GIFs (Zig data engine), run the clean experiment the literature lacks: same tiny transformer, swap a continuous-OKLab-regression-then-snap head vs a masked-256-index head; report FVD + index-MSE + temporal drift. Orbis and Discrete-JEPA test opposite hypotheses on opposite domains — only an internal run settles it [2507.13162; 2506.14373].
2. **Inter-burst palette drift.** Measure W₂ distance between consecutive per-burst codebooks. If small (similar scenes), a frozen/shared 256 codebook (DCQ's fix [2602.20650]) makes plain metric-aware token prediction viable and may moot the JEPA question.
3. **Disocclusion budget.** What fraction of 64→256 new cells are holes with no OT source? This sizes the irreducible learned residual and tests whether it fits 115k params [2506.01061].
4. **Bures faithfulness.** Are per-frame OKLab palettes near-unimodal enough for the σ-pair Gaussian approximation, or do multimodal palettes demand the sliced/discrete barycenter? [1511.05355]
5. **Straight-through gradient for snap-to-leaf.** Does the terminal argmin hide quantization-error gradient from the σ-pair head? Needs a soft/Gumbel assignment to train end-to-end [2506.14373].
6. **Drift accumulation.** Does iterative re-quantization across 64→256 accumulate error? Bound it by Lloyd-Max cell radius per step; verify VCT's "no dependence on previous reconstructions" trick composes with the Haar temporal pyramid [1801.03742; 2206.07307].

**Evidence flags:** The 115k-param feasibility claim is unsupported for *both* camps — every cited system (JEPA ≥15M; MaskGIT/MAGVIT 87M–3B; RIFE 9.8M; Orbis 469M) is orders of magnitude larger; the mechanic transfers, the param budget does not [VERIFICATION, multiple dims]. The Bures-over-discrete and exact-discrete-barycenter claims are contested/NP-hard. No published system does SixFour's exact triple (deterministic base + learned residual + VQ-index grid + OT motion) — the OT-displacement-over-indices branch is the genuinely unexplored, and likely ill-posed, seam.

## 8. Sources

**JEPA camp**
1. I-JEPA — Self-Supervised Learning from a Joint-Embedding Predictive Architecture, CVPR 2023 — https://arxiv.org/abs/2301.08243
2. I-JEPA (Meta AI blog) — https://ai.meta.com/blog/yann-lecun-ai-model-i-jepa/
3. V-JEPA — Revisiting Feature Prediction for Learning Visual Representations from Video — https://arxiv.org/pdf/2404.08471
4. V-JEPA 2 — Self-Supervised Video Models Enable Understanding, Prediction and Planning — https://arxiv.org/abs/2506.09985
5. C-JEPA — Connecting JEPA with Contrastive SSL, NeurIPS 2024 — https://arxiv.org/html/2410.19560v1
6. Towards Latent Masked Image Modeling for SSL — https://arxiv.org/html/2407.15837v1
7. JEPA Deep Dive (Bandaru, blog) — https://rohitbandaru.github.io/blog/JEPA-Deep-Dive/
8. Rethinking JEPA: Frozen Teachers (Apple, 2025) — https://machinelearning.apple.com/research/rethinking-jepa
9. Discrete-JEPA — Learning Discrete Token Representations without Reconstruction — https://arxiv.org/html/2506.14373v1
10. VL-JEPA (rewire.it, secondary) — https://rewire.it/blog/vl-jepa-why-predicting-embeddings-beats-generating-tokens/

**Discrete-token / masked generative camp**
11. MaskGIT — Masked Generative Image Transformer, CVPR 2022 — https://masked-generative-image-transformer.github.io/
12. MAGVIT — Masked Generative Video Transformer, CVPR 2023 — https://ar5iv.labs.arxiv.org/html/2212.05199
13. MAGVIT-v2 — Tokenizer is Key to Visual Generation, ICLR 2024 — https://arxiv.org/html/2310.05737v2
14. Muse — Text-To-Image Generation via Masked Generative Transformers, ICML 2023 — https://arxiv.org/pdf/2301.00704
15. IAR — Cluster-Oriented Token Prediction — https://arxiv.org/abs/2501.00880
16. Computational Tradeoffs in Image Synthesis (diffusion/masked/next-token) — https://arxiv.org/html/2405.13218v1
17. Learn from your own latents: a sample-complexity theory — https://arxiv.org/html/2605.27734

**Statistical / OT / quantization camp**
18. Discrete Wasserstein Barycenters — https://arxiv.org/abs/1507.07218
19. A fixed-point approach to barycenters in Wasserstein space — https://ar5iv.labs.arxiv.org/html/1511.05355
20. Sliced L2 Distance for Colour Grading (Alghamdi & Dahyot) — https://arxiv.org/abs/2102.09297
21. RQ-VAE — Autoregressive Image Generation using Residual Quantization, CVPR 2022 — https://arxiv.org/abs/2203.01941
22. VAR — Visual Autoregressive Modeling (Next-Scale Prediction), NeurIPS 2024 — https://arxiv.org/abs/2404.02905
23. Lloyd-Max / Zador-Gersho high-resolution VQ theory — https://arxiv.org/pdf/1801.03742
24. Improving color quantization heuristics (ubitux) — http://blog.pkh.me/p/39-improving-color-quantization-heuristics.html
25. Softmax Splatting for Video Frame Interpolation, CVPR 2020 — https://arxiv.org/abs/2003.05534
26. DCQ — Dataset Color Quantization — https://arxiv.org/html/2602.20650
27. Beyond Stationarity: Rethinking Codebook Collapse in VQ — https://arxiv.org/pdf/2602.18896
28. Fast Log-Domain Sinkhorn OT with Warp-Level GPU Reductions — https://arxiv.org/html/2605.00837

**Deterministic-base + residual / codecs / on-device camp**
29. AceVFI — Survey of Video Frame Interpolation — https://arxiv.org/html/2506.01061
30. RIFE — Real-Time Intermediate Flow Estimation, ECCV 2022 — https://ar5iv.labs.arxiv.org/html/2011.06294
31. RAFT — Recurrent All-Pairs Field Transforms, ECCV 2020 — https://ar5iv.labs.arxiv.org/html/2003.12039
32. PhySR — Physics-informed Deep Super-resolution — https://arxiv.org/abs/2208.01462
33. Orbis — Long-Horizon Driving World Models (continuous vs discrete bake-off) — https://arxiv.org/abs/2507.13162
34. NGLR / LBRC — Residual Modeling for Learned Compression of Scientific Data — https://arxiv.org/html/2606.05389
35. VCT — A Video Compression Transformer, NeurIPS 2022 — https://ar5iv.labs.arxiv.org/html/2206.07307
36. TVC — Tokenized Video Compression at Ultra-Low Bit Rate — https://arxiv.org/html/2504.16953v4
37. Discrete-latent motion-compensation artifacts / drift — https://arxiv.org/pdf/2312.00853
38. G2SD — Generic-to-Specific Distillation of MAEs, CVPR 2023 — https://ar5iv.labs.arxiv.org/html/2302.14771
39. TinyMIM — Distilling MIM Pre-trained Models, CVPR 2023 — https://arxiv.org/abs/2301.01296
40. Supervised vs SSL with small/imbalanced datasets, Sci. Reports 2025 — https://pmc.ncbi.nlm.nih.gov/articles/PMC12405560/
41. IConE — Batch-Independent Collapse Prevention — https://arxiv.org/html/2603.15263v1
42. SEED — Self-supervised Distillation, ICLR 2021 — https://arxiv.org/pdf/2101.04731
43. Adapting Auxiliary Losses Using Gradient Similarity — https://arxiv.org/abs/1812.02224
44. Boosting Supervision with Self-Supervision for Few-shot Learning — https://arxiv.org/pdf/1906.07079
45. DIAMOND — Diffusion for World Modeling, NeurIPS 2024 — https://arxiv.org/pdf/2405.12399
46. RQ-VAE / S-HR-VQVAE topic page — https://www.emergentmind.com/topics/residual-quantized-variational-autoencoder-rq-vae
