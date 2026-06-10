# On-Device & Federated Training — Research Report

*Deep-research pass, 2026-06-10. Claims below survived 3-vote adversarial verification
(confidence noted per claim). Companion to COLOR-ATLAS.md §5 (curriculum/training plan);
this document decides WHERE training runs.*

## Question

Can the ~63K-param Atlas policy/value network train on iPhone with first-party (zero
third-party dependency) tooling, and how do we bootstrap it across many users whose
color taste is deliberately non-IID?

## Answer 1 — Yes. Train on-device with MPSGraph. (HIGH confidence)

| API | Backward pass? | First-party? | Verdict |
|---|---|---|---|
| **MPSGraph** | Yes — `gradients(of:with:)` reverse-mode autodiff + `stochasticGradientDescent` update op | Yes, OS framework since iOS 14, `deprecated: false` through current SDKs; Metal 4 (WWDC25) adds ML APIs *without* deprecating it | **Use this.** Official Apple sample trains a digit classifier end-to-end on device. matmul/conv/activations/reductions, fp16+fp32 — covers the 10→64→64→384 MLP + heads trivially. |
| Core ML `MLUpdateTask` | Yes, but only legacy `.mlmodel` "updatable neuralnetwork" format (not ML Program/mlpackage) | Yes, iOS 13+, not formally deprecated | **Avoid.** No meaningful updates since iOS 13; absent from WWDC 2025 framework guidance. Functional but abandoned-in-guidance. |
| MLX (Swift) | Yes — MNISTTrainer example trains a LeNet on physical iPhone (no Simulator; Metal required) | **No** — SPM package from GitHub, not in the OS SDK | Violates the zero-third-party rule unless we vendor an Apple-authored OSS package. Apple's own positioning of MLX training is Mac-centric ("train… directly on your Mac", WWDC25 315/360). Keep MLX on the Mac. |
| BNNS/BNNSGraph training, CreateML on-device | — | — | **No surviving verified claims either way.** Unevidenced; do not plan around them without a spike. |

Practical notes: fp32 weights (fp16 activations optional). Schedule training in
charging/idle windows via `BGProcessingTask` — *this scheduling recommendation is
general platform knowledge; no verified sources covered BGProcessingTask budgets or
thermal throttling. Needs an on-device spike before relying on overnight training.*

Sources: Apple "Training a neural network using MPSGraph" sample;
WWDC20 10677; WWDC25 315 & 360; `developer.apple.com/documentation/coreml/mlupdatetask`;
`github.com/ml-explore/mlx-swift-examples` (MNISTTrainer).

## Answer 2 — Federated bootstrap architecture (HIGH/MEDIUM confidence)

**Communication is a non-issue.** One full weight update = 63K × 4B ≈ **252 KB fp32
(~126 KB fp16)** — smaller than one photo. Bandwidth never constrains the design;
privacy mechanism and non-IID aggregation do.

**Apple's published reference design** (Talwar et al., CCS 2024, "Samplable Anonymous
Aggregation", HIGH): split-trust Prio-style secure aggregation — each client additively
secret-shares its DP-noised contribution to ≥2 non-colluding servers and sends a
**single message** (no multi-round protocol, no dropout handling). Privacy amplification
by sampling improves ε≈100 → ε≈1 in their worked example. The single-message client
keeps the iOS side a thin one-shot upload — fully compatible with first-party-only.

**Reality check on scale** (MEDIUM): Apple's shipped deployment (Photos iconic scenes,
iOS 16/17) runs at ε=1, δ=1.5e-7 with **150,000-device cohorts per round** — and that
is federated *statistics* (DP histograms), not federated SGD. A small-to-medium user
base cannot reach Apple-grade distributed-DP guarantees. Therefore: plan for
**central DP at the aggregator (per-update clipping + noise) plus secure aggregation
if two non-colluding operators are feasible** — not pure local DP.

**Non-IID taste** (HIGH): users' color preferences differing is the *point* of Color
Atlas, which breaks naive FedAvg. The most applicable published pattern is
**FedBiscuit** (arXiv 2407.03038): cluster clients with similar preferences into
disjoint groups, train one Bradley–Terry selector per cluster, clients self-assign by
minimum validation loss with cap-and-reassign balancing. Caveat: their experiments are
LLM-scale and simulated — adopt the *pattern* (cluster-of-selectors, or global core +
personal head split, consistent with the β = n/(n+50) blend in COLOR-ATLAS.md §4),
not the empirical numbers. The broader "federated RLHF is validated" claim was
REFUTED 1-2 in verification.

**Server tooling**: Apple's `pfl-research` (v0.5.1, Mar 2026, actively maintained) is
a *simulation* framework — explicitly "not intended for third-party FL deployments."
Use it offline to validate aggregation rules, DP budgets, and non-IID behavior before
building a thin production aggregator. Flower/FedML were not covered by surviving
claims — unevaluated.

## Answer 3 — The stack split

```
iPhone (first-party only)
  MPSGraph training graph, ~63K params
  loss = Bradley–Terry logistic on local Compare pairs
       + cross-entropy behavior cloning on curation replay logs (DecisionLog)
  fp32 weights; BGProcessingTask charging/idle windows (needs spike)
  emits ONE message per round: clipped weight delta, ~126–252 KB

Coordination server (thin)
  FedAvg-style aggregation + per-update clipping + central DP noise
  Prio split-trust secure aggregation IF two non-colluding operators exist
  FedBiscuit-style preference clustering (or global-core/personal-head)
  design validated offline in pfl-research simulation

Mac (MLX, authoritative)
  AlphaGo expert-iteration loop (T1/T2 curricula per COLOR-ATLAS.md §5)
  periodically retrains from aggregated signals
  redistributes the global checkpoint (.s4ln v2)
```

This composition is the analyst's recommendation; each component is individually
verified but the assembly is not an externally validated deployment.

## Open items (no verified evidence — spike before relying on them)

1. BGProcessingTask wall-clock/energy budgets and thermal throttling under MPSGraph training.
2. BNNS/BNNSGraph training capability.
3. Flower/FedML as server-side aggregators (client stays first-party regardless).
4. Minimum viable cohort size for useful (non-DP) FedAvg on a 63K model — literature
   gives no direct number for this regime; pfl-research simulation should answer it.
