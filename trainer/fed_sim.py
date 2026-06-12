"""fed_sim.py — federated-learning cohort-size simulation for the Color Atlas
Bradley–Terry preference model (ON-DEVICE-TRAINING.md open item 4).

Question: for K = 4…512 users with m local Compare decisions each, when does
federated aggregation beat purely-local training, and when does clustered
federation (FedBiscuit pattern, arXiv 2407.03038) beat one global model?

World model
-----------
  • C latent taste clusters; cluster centers θ_c are random unit vectors in
    R^770 (in 770-D random directions are near-orthogonal, so clusters are
    well-separated by construction).
  • user k:  θ*_k = normalize(θ_c(k) + σ_user · u_k),  u_k random unit vector.
    σ_user is the within-cluster heterogeneity knob; the per-user angle off the
    cluster center is ≈ atan(σ_user), so even a PERFECT cluster model has a
    ranking-accuracy ceiling of 1 − atan(σ_user)/π for that user.
  • Compare pair: feature difference d = x_a − x_b ~ N(0, I_770) (isotropic,
    matching nothing about real genome embeddings except dimension — this is
    the simulation's main limitation).  Winner label y = sign⟨θ*_k, d⟩,
    flipped with probability 0.10 (label noise).
  • Model: linear Bradley–Terry θ ∈ R^770 (COLOR-ATLAS.md §4: the day-one
    on-device model).  Loss = logistic BT loss + λ‖θ‖², λ = 1e-3.

Metric
------
Held-out per-user pairwise ranking accuracy.  Because eval features are
isotropic Gaussian, the EXPECTED held-out accuracy of any linear model θ̂
against noiseless ground truth is exactly

    acc(θ̂, θ*) = 1 − angle(θ̂, θ*)/π

so we report that analytic value (zero eval-sampling noise; chance = 0.5,
ceiling = 1.0).  A Monte-Carlo cross-check against sampled held-out pairs is
run once at startup (assert |analytic − empirical| < 0.02).

Models compared (per user, averaged over users then over 3 seeds)
-----------------------------------------------------------------
  local        — each user trains alone on its m pairs (full-batch GD).
  fedavg       — R rounds of E local steps + weight averaging across all K.
  fed_blend    — design-doc rule: blend FedAvg global with local θ at
                 β = n/(n+50), n = m.  Both directions are unit-normalized
                 before blending (equivalent to blending scale-matched
                 scores; raw-weight blending would be dominated by whichever
                 θ has the larger norm).
  clust_self   — FedBiscuit pattern: C_fit = C cluster models, users
                 self-assign by minimum BT loss on their own m pairs,
                 per-cluster FedAvg, alternated.
  clust_oracle — same but with ground-truth cluster assignment (upper bound).
  clust_blend  — self-assigned cluster model blended with local θ at β.

Deterministic seeds throughout.  Full sweep ≈ 3–6 min on an M3 Max.

Run:  cd trainer && uv run python fed_sim.py
Out:  trainer/out/fed_sim_results.csv  (+ printed summary table)
"""
from __future__ import annotations

import csv
import time
from pathlib import Path

import numpy as np

# ── Pinned constants ────────────────────────────────────────────────────────
DIM = 770                 # COLOR-ATLAS.md §4.2: BT θ is [770] linear
LAMBDA = 1e-3             # §4.1 update rule weight decay
FLIP_P = 0.10             # Compare label noise
BETA_N0 = 50.0            # β = n/(n+50) blend ramp (§4.1)

K_GRID = [4, 8, 16, 32, 64, 128, 256, 512]
M_GRID = [8, 32, 128]
C_GRID = [1, 3, 8]
SIGMA_GRID = [0.25, 0.75]   # within-cluster heterogeneity (angle ≈ atan σ)
N_SEEDS = 3

MASTER_SEED = 64

OUT_DIR = Path(__file__).resolve().parent / "out"
CSV_PATH = OUT_DIR / "fed_sim_results.csv"

F32 = np.float32


def sigmoid(z: np.ndarray) -> np.ndarray:
    return 1.0 / (1.0 + np.exp(-z))


def softplus(z: np.ndarray) -> np.ndarray:
    return np.logaddexp(0.0, z)


# ── World generation ────────────────────────────────────────────────────────
def make_users(rng: np.random.Generator, K: int, C: int, sigma_user: float):
    """Return (theta_star [K,DIM] unit rows, cluster_ids [K])."""
    centers = rng.standard_normal((C, DIM))
    centers /= np.linalg.norm(centers, axis=1, keepdims=True)
    cluster_ids = np.arange(K) % C          # balanced round-robin
    u = rng.standard_normal((K, DIM))
    u /= np.linalg.norm(u, axis=1, keepdims=True)
    theta = centers[cluster_ids] + sigma_user * u
    theta /= np.linalg.norm(theta, axis=1, keepdims=True)
    return theta.astype(F32), cluster_ids, centers.astype(F32)


def gen_pairs(rng: np.random.Generator, theta_star: np.ndarray, m: int):
    """Generate m Compare pairs per user.

    Returns yd [K,m,DIM] = label·feature-difference (the only form the BT
    gradient and loss ever need).
    """
    K = theta_star.shape[0]
    d = rng.standard_normal((K, m, DIM), dtype=F32)
    z = np.matmul(d, theta_star[..., None])[..., 0]        # [K,m]
    y = np.where(z > 0, 1.0, -1.0).astype(F32)
    flips = rng.random((K, m)) < FLIP_P
    y = np.where(flips, -y, y)
    return d * y[..., None]                                # yd


# ── Linear BT training (vectorized over users; batched GEMMs) ──────────────
def bt_step(yd: np.ndarray, theta: np.ndarray, lr: float) -> np.ndarray:
    """One full-batch GD step per user. yd [K,m,D], theta [K,D] (in-place)."""
    z = np.matmul(yd, theta[..., None])[..., 0]            # [K,m]
    s = sigmoid(-z)                                        # [K,m]
    m = yd.shape[1]
    grad = np.matmul(yd.transpose(0, 2, 1), s[..., None])[..., 0] / m
    theta += lr * (grad - LAMBDA * theta)
    return theta


def lr_for(m: int) -> float:
    """Stable full-batch step size: logistic Hessian λmax ≈ (770+m)/(4m)."""
    return 2.0 * m / (m + DIM)


def train_local(yd: np.ndarray, steps: int = 400) -> np.ndarray:
    K, m, _ = yd.shape
    theta = np.zeros((K, DIM), dtype=F32)
    lr = lr_for(m)
    for _ in range(steps):
        bt_step(yd, theta, lr)
    return theta


def fedavg(yd: np.ndarray, theta0: np.ndarray, rounds: int, local_steps: int = 4) -> np.ndarray:
    """FedAvg over the users in yd, starting from theta0 [DIM]."""
    K, m, _ = yd.shape
    lr = lr_for(m)
    theta_g = theta0.astype(F32).copy()
    for _ in range(rounds):
        th = np.broadcast_to(theta_g, (K, DIM)).copy()
        for _ in range(local_steps):
            bt_step(yd, th, lr)
        theta_g = th.mean(axis=0)
    return theta_g


def bt_loss(yd: np.ndarray, thetas: np.ndarray) -> np.ndarray:
    """Mean BT loss of each cluster model on each user's pairs → [K, C]."""
    z = np.matmul(yd, thetas.T.astype(F32))                # [K,m,C]
    return softplus(-z).mean(axis=1)


def train_clustered(yd: np.ndarray, c_fit: int, rng: np.random.Generator,
                    th_local: np.ndarray, outer: int = 8, inner_rounds: int = 2):
    """FedBiscuit pattern: alternate (self-assign by min loss on own pairs,
    per-cluster FedAvg).  Symmetry breaking: initial grouping via spherical
    k-means on the users' LOCAL model directions (server-side clustering of
    uploaded updates) — a random partition gives every init model the same
    cluster mixture and the loss-based assignment never escapes it."""
    K = yd.shape[0]
    c_fit = min(c_fit, K)
    X = th_local / np.maximum(np.linalg.norm(th_local, axis=1, keepdims=True), 1e-12)
    cent = X[rng.choice(K, size=c_fit, replace=False)].copy()
    for _ in range(10):
        km = (X @ cent.T).argmax(axis=1)
        for c in range(c_fit):
            idx = km == c
            if idx.any():
                v = X[idx].sum(axis=0)
                n = np.linalg.norm(v)
                if n > 1e-12:
                    cent[c] = v / n
    thetas = np.stack([
        fedavg(yd[km == c], np.zeros(DIM, dtype=F32), rounds=4)
        if (km == c).any() else np.zeros(DIM, dtype=F32)
        for c in range(c_fit)
    ])
    assign = np.zeros(K, dtype=np.int64)
    for _ in range(outer):
        assign = bt_loss(yd, thetas).argmin(axis=1)
        for c in range(c_fit):
            idx = np.flatnonzero(assign == c)
            if idx.size == 0:
                continue                                   # keep stale model
            thetas[c] = fedavg(yd[idx], thetas[c], rounds=inner_rounds)
    assign = bt_loss(yd, thetas).argmin(axis=1)
    return thetas, assign


def train_clustered_oracle(yd: np.ndarray, cluster_ids: np.ndarray, C: int) -> np.ndarray:
    """Per-true-cluster FedAvg → per-user model [K,DIM]."""
    K = yd.shape[0]
    out = np.zeros((K, DIM), dtype=F32)
    for c in range(C):
        idx = np.flatnonzero(cluster_ids == c)
        if idx.size == 0:
            continue
        out[idx] = fedavg(yd[idx], np.zeros(DIM, dtype=F32), rounds=30)
    return out


# ── Evaluation ──────────────────────────────────────────────────────────────
def ranking_acc(theta_hat: np.ndarray, theta_star: np.ndarray) -> float:
    """Mean over users of analytic held-out pairwise ranking accuracy
    1 − angle/π (exact for isotropic Gaussian features, noiseless labels)."""
    th = np.atleast_2d(theta_hat).astype(np.float64)
    ts = theta_star.astype(np.float64)
    if th.shape[0] == 1:
        th = np.broadcast_to(th, ts.shape)
    nh = np.linalg.norm(th, axis=1)
    cos = np.einsum("kd,kd->k", th, ts) / np.maximum(nh * np.linalg.norm(ts, axis=1), 1e-30)
    acc = np.where(nh < 1e-12, 0.5, 1.0 - np.arccos(np.clip(cos, -1.0, 1.0)) / np.pi)
    return float(acc.mean())


def blend(theta_local: np.ndarray, theta_core: np.ndarray, m: int) -> np.ndarray:
    """β = n/(n+50) blend of unit-normalized local + core directions."""
    beta = m / (m + BETA_N0)
    tl = theta_local / np.maximum(np.linalg.norm(theta_local, axis=-1, keepdims=True), 1e-12)
    core = np.atleast_2d(theta_core)
    tc = core / np.maximum(np.linalg.norm(core, axis=-1, keepdims=True), 1e-12)
    return (beta * tl + (1.0 - beta) * tc).astype(F32)


def monte_carlo_check(rng: np.random.Generator) -> None:
    """Verify the analytic accuracy formula against sampled held-out pairs."""
    theta_star, _, _ = make_users(rng, K=4, C=1, sigma_user=0.5)
    yd = gen_pairs(rng, theta_star, m=64)
    theta_hat = train_local(yd, steps=200)
    analytic = ranking_acc(theta_hat, theta_star)
    d = rng.standard_normal((4, 4000, DIM), dtype=F32)
    truth = np.matmul(d, theta_star[..., None])[..., 0] > 0
    pred = np.matmul(d, theta_hat[..., None])[..., 0] > 0
    empirical = float((truth == pred).mean())
    assert abs(analytic - empirical) < 0.02, (analytic, empirical)
    print(f"[check] analytic acc {analytic:.4f} vs Monte-Carlo {empirical:.4f} — OK")


# ── One configuration ───────────────────────────────────────────────────────
def run_config(K: int, m: int, C: int, sigma: float, seed: int) -> dict[str, float]:
    rng = np.random.default_rng(np.random.SeedSequence([MASTER_SEED, K, m, C,
                                                        int(sigma * 100), seed]))
    theta_star, cluster_ids, _ = make_users(rng, K, C, sigma)
    yd = gen_pairs(rng, theta_star, m)

    th_local = train_local(yd)
    th_global = fedavg(yd, np.zeros(DIM, dtype=F32), rounds=30)
    th_clust, assign = train_clustered(yd, c_fit=C, rng=rng, th_local=th_local)
    th_oracle = train_clustered_oracle(yd, cluster_ids, C)

    return {
        "local": ranking_acc(th_local, theta_star),
        "fedavg": ranking_acc(th_global, theta_star),
        "fed_blend": ranking_acc(blend(th_local, th_global, m), theta_star),
        "clust_self": ranking_acc(th_clust[assign], theta_star),
        "clust_oracle": ranking_acc(th_oracle, theta_star),
        "clust_blend": ranking_acc(blend(th_local, th_clust[assign], m), theta_star),
    }


MODELS = ["local", "fedavg", "fed_blend", "clust_self", "clust_oracle", "clust_blend"]


# ── MLP value-head secondary sweep (reduced grid) ───────────────────────────
MLP_H = 16
MLP_K_GRID = [8, 64, 512]
MLP_M_GRID = [32, 128]
MLP_C, MLP_SIGMA, MLP_SEEDS = 3, 0.75, 2


def mlp_init(rng: np.random.Generator, K: int):
    W1 = (rng.standard_normal((K, MLP_H, DIM)) / np.sqrt(DIM)).astype(F32)
    b1 = np.zeros((K, MLP_H), dtype=F32)
    w2 = (rng.standard_normal((K, MLP_H)) * 0.5 / np.sqrt(MLP_H)).astype(F32)
    return [W1, b1, w2]


def mlp_util(params, x):
    """x [K,m,D] → utility [K,m]; also returns hidden activations."""
    W1, b1, w2 = params
    h = np.tanh(np.matmul(x, W1.transpose(0, 2, 1)) + b1[:, None, :])  # [K,m,H]
    return np.einsum("kmh,kh->km", h, w2), h


def mlp_step(params, xa, xb, y, lr):
    W1, b1, w2 = params
    m = xa.shape[1]
    ua, ha = mlp_util(params, xa)
    ub, hb = mlp_util(params, xb)
    s = sigmoid(-y * (ua - ub))                       # [K,m]
    g = (-s * y / m)[..., None]                       # dL/dlogit  [K,m,1]
    dw2 = np.einsum("kmh,km->kh", ha - hb, g[..., 0])
    dha = g * w2[:, None, :]                          # [K,m,H]
    dpa = dha * (1.0 - ha * ha)
    dpb = -dha * (1.0 - hb * hb)
    dW1 = np.matmul(dpa.transpose(0, 2, 1), xa) + np.matmul(dpb.transpose(0, 2, 1), xb)
    db1 = dpa.sum(axis=1) + dpb.sum(axis=1)
    W1 -= lr * (dW1 + LAMBDA * W1)
    b1 -= lr * db1
    w2 -= lr * (dw2 + LAMBDA * w2)


def mlp_acc(params, theta_star, rng, n_eval=512):
    K = theta_star.shape[0]
    xa = rng.standard_normal((K, n_eval, DIM), dtype=F32)
    xb = rng.standard_normal((K, n_eval, DIM), dtype=F32)
    truth = np.matmul(xa - xb, theta_star[..., None])[..., 0] > 0
    ua, _ = mlp_util(params, xa)
    ub, _ = mlp_util(params, xb)
    return float(((ua - ub > 0) == truth).mean())


def run_mlp_config(K: int, m: int, seed: int) -> dict[str, float]:
    rng = np.random.default_rng(np.random.SeedSequence([MASTER_SEED, 7000 + K, m, seed]))
    theta_star, _, _ = make_users(rng, K, MLP_C, MLP_SIGMA)
    xa = rng.standard_normal((K, m, DIM), dtype=F32)
    xb = rng.standard_normal((K, m, DIM), dtype=F32)
    z = np.matmul(xa - xb, theta_star[..., None])[..., 0]
    y = np.where(z > 0, 1.0, -1.0).astype(F32)
    y = np.where(rng.random((K, m)) < FLIP_P, -y, y)
    lr = 8.0 * m / (m + DIM)

    init = mlp_init(rng, 1)                            # shared init
    # local
    loc = [np.repeat(p, K, axis=0).copy() for p in init]
    for _ in range(120):
        mlp_step(loc, xa, xb, y, lr)
    # fedavg
    glob = [p[0].copy() for p in init]
    for _ in range(25):
        th = [np.repeat(p[None], K, axis=0).copy() for p in glob]
        for _ in range(4):
            mlp_step(th, xa, xb, y, lr)
        glob = [p.mean(axis=0) for p in th]
    glob_k = [np.repeat(p[None], K, axis=0) for p in glob]
    # blend (weight-space, shared-init lineage)
    beta = m / (m + BETA_N0)
    bl = [(beta * pl + (1 - beta) * pg).astype(F32) for pl, pg in zip(loc, glob_k)]

    erng = np.random.default_rng(np.random.SeedSequence([MASTER_SEED, 9000 + K, m, seed]))
    accs = {}
    for name, params in (("local", loc), ("fedavg", glob_k), ("fed_blend", bl)):
        accs[name] = mlp_acc(params, theta_star, np.random.default_rng(erng.integers(2**32)))
    return accs


# ── Sweep ───────────────────────────────────────────────────────────────────
def main() -> None:
    t0 = time.time()
    OUT_DIR.mkdir(exist_ok=True)
    monte_carlo_check(np.random.default_rng(MASTER_SEED))

    rows = []
    n_cfg = len(C_GRID) * len(SIGMA_GRID) * len(M_GRID) * len(K_GRID)
    i = 0
    for C in C_GRID:
        for sigma in SIGMA_GRID:
            for m in M_GRID:
                for K in K_GRID:
                    i += 1
                    per_seed = {mod: [] for mod in MODELS}
                    for seed in range(N_SEEDS):
                        res = run_config(K, m, C, sigma, seed)
                        for mod in MODELS:
                            per_seed[mod].append(res[mod])
                    row = {"family": "linear770", "C": C, "sigma_user": sigma,
                           "m": m, "K": K}
                    for mod in MODELS:
                        v = np.array(per_seed[mod])
                        row[mod] = round(float(v.mean()), 4)
                        row[mod + "_std"] = round(float(v.std()), 4)
                    rows.append(row)
                    print(f"[{i:3d}/{n_cfg}] C={C} σ={sigma} m={m:3d} K={K:3d}  "
                          + "  ".join(f"{mod}={row[mod]:.3f}" for mod in MODELS)
                          + f"  ({time.time()-t0:.0f}s)")

    # MLP secondary sweep
    mlp_rows = []
    for m in MLP_M_GRID:
        for K in MLP_K_GRID:
            per_seed = {mod: [] for mod in ("local", "fedavg", "fed_blend")}
            for seed in range(MLP_SEEDS):
                res = run_mlp_config(K, m, seed)
                for mod, v in res.items():
                    per_seed[mod].append(v)
            row = {"family": f"mlp{MLP_H}", "C": MLP_C, "sigma_user": MLP_SIGMA,
                   "m": m, "K": K}
            for mod, vs in per_seed.items():
                v = np.array(vs)
                row[mod] = round(float(v.mean()), 4)
                row[mod + "_std"] = round(float(v.std()), 4)
            for mod in ("clust_self", "clust_oracle", "clust_blend"):
                row[mod] = ""
                row[mod + "_std"] = ""
            mlp_rows.append(row)
            print(f"[mlp] C={MLP_C} σ={MLP_SIGMA} m={m:3d} K={K:3d}  "
                  + "  ".join(f"{mod}={row[mod]:.3f}"
                              for mod in ("local", "fedavg", "fed_blend"))
                  + f"  ({time.time()-t0:.0f}s)")

    fieldnames = (["family", "C", "sigma_user", "m", "K"]
                  + [c for mod in MODELS for c in (mod, mod + "_std")])
    with open(CSV_PATH, "w", newline="") as f:
        w = csv.DictWriter(f, fieldnames=fieldnames)
        w.writeheader()
        for row in rows + mlp_rows:
            w.writerow(row)
    print(f"\nwrote {CSV_PATH}  ({len(rows) + len(mlp_rows)} rows)")

    # ── Summary: smallest K where federation beats local by ≥1 pt ──────────
    print("\n=== smallest K where model beats LOCAL by ≥0.01 accuracy ===")
    print(f"{'C':>2} {'σ':>5} {'m':>4} | {'fedavg':>7} {'clust_self':>10} "
          f"{'clust_oracle':>12} {'fed_blend':>9} {'clust_blend':>11}")
    for C in C_GRID:
        for sigma in SIGMA_GRID:
            for m in M_GRID:
                sub = [r for r in rows if r["C"] == C and r["sigma_user"] == sigma
                       and r["m"] == m]
                sub.sort(key=lambda r: r["K"])
                cells = []
                for mod in ("fedavg", "clust_self", "clust_oracle",
                            "fed_blend", "clust_blend"):
                    k = next((r["K"] for r in sub if r[mod] >= r["local"] + 0.01),
                             None)
                    cells.append(str(k) if k else "never")
                print(f"{C:>2} {sigma:>5} {m:>4} | {cells[0]:>7} {cells[1]:>10} "
                      f"{cells[2]:>12} {cells[3]:>9} {cells[4]:>11}")

    print(f"\ntotal {time.time()-t0:.0f}s")


if __name__ == "__main__":
    main()
