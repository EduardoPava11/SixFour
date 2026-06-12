# Federated Cohort-Size Simulation — Findings

*Run 2026-06-12 via `uv run python fed_sim.py` (deterministic seeds, 3 seeds/config).
Raw grid: `out/fed_sim_results.csv` (150 rows: 144 linear770 + 6 mlp16; 6 MLP rows
have no clustering columns by design). Subject model: the 770-D linear Bradley–Terry
θ from COLOR-ATLAS.md §4 (day-one on-device value model). Metric: held-out per-user
pairwise ranking accuracy. Sweep: C ∈ {1,3,8} latent taste clusters, per-user noise
σ ∈ {0.25, 0.75}, m ∈ {8,32,128} Compare decisions/user, K ∈ {4…512} users, 10%
label noise. Methods: local-only, global FedAvg, β=n/(n+50) blend, FedBiscuit-style
self-assigned clustering (+ oracle-cluster upper bound), clustered blend.*

## Headline thresholds — smallest K where FedAvg beats local (+1 pt)

| Taste structure | m=8 | m=32 | m=128 |
|---|---|---|---|
| C=1 (shared taste), σ=0.25 | **K≥4** | K≥4 | K≥4 |
| C=1, σ=0.75 | K≥4 | K≥4 | K≥4 |
| C=3 (moderate non-IID), σ=0.25 | K≥64 | **K≥16** | K≥32 |
| C=3, σ=0.75 | K≥64 | K≥64 | K≥64 |
| C=8 (strong non-IID), σ=0.25 | K≥256 | K≥128 | K≥512 |
| C=8, σ=0.75 | K≥512 | K≥512 | **never** |

Reading: if users' tastes share structure, federation pays **immediately** (4 users:
0.52 → 0.71–0.91). At moderate heterogeneity it pays from **~16–64 users**. At strong
heterogeneity a single global model is useless or harmful — exactly the FedAvg
failure mode the literature predicts for non-IID data.

## Which method wins (mean accuracy, K≥16)

| Regime | local | FedAvg | β-blend | clust(self) | clust(oracle) |
|---|---|---|---|---|---|
| C=1, σ=0.25 | 0.548 | **0.769** | 0.691 | 0.768 | 0.769 |
| C=3, σ=0.25 | 0.547 | 0.604 | 0.597 | 0.623 | **0.704** |
| C=3, σ=0.75 | 0.548 | 0.578 | 0.580 | 0.578 | **0.643** |
| C=8, σ=0.25 | 0.548 | 0.548 | 0.562 | 0.561 | **0.649** |
| C=8, σ=0.75 | 0.548 | 0.536 | **0.554** | 0.537 | 0.607 |

Two structural facts:

1. **The oracle-vs-self clustering gap is the whole game at high heterogeneity**
   (0.704 vs 0.623 at C=3; 0.649 vs 0.561 at C=8). FedBiscuit-style min-validation-loss
   self-assignment recovers only a fraction of what perfect cluster assignment would
   give. Better assignment (more local validation data, assignment stickiness,
   genome-space features) is the highest-leverage research item — not more rounds,
   not bigger cohorts.
2. **The β = n/(n+50) blend is the best cold-start policy.** At m=8 it wins more
   configs than any other method (22/48 vs FedAvg 10, local 10), and at C=8 it is
   the only practical method that never drops below local. With data-rich users
   (m=128) self-assigned clustering takes over (24/48 wins).

MLP sanity sweep (mlp16, C=3, σ=0.75) agrees directionally: FedAvg overtakes local
between K=8 and K=64, blend cushions the small-K regime.

## Recommendation

**With ~16–64 active users at ~32 decisions each, ship the FedAvg global core behind
the β = n/(n+50) personal blend** (already the COLOR-ATLAS.md §4 design — this
simulation validates it as the dominant cold-start policy). Do NOT gate launch on
clustering: enable FedBiscuit-style clusters only once median decisions/user reaches
~32–128, and treat cluster-assignment quality as the research investment, since the
oracle bound shows 8–9 points of unrealized accuracy sitting there.

## Limits (honest)

Synthetic features and a linear taste teacher; real curation features are correlated
and taste is likely lower-rank than the C=8 worst case. 10% label noise is a guess.
No DP noise in this sweep — central-DP clipping/noise (per docs/ON-DEVICE-TRAINING.md)
will shave the FedAvg numbers and raise the K thresholds somewhat. Accuracy ceilings
(~0.9 at C=1) reflect label noise, not model capacity.
