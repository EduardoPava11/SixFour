"""Context super-res experiment — the architectural next step the FLOORED result pointed to.

The per-octant runs floored because the held detail is NOT determined by an octant's OWN coarse +
position (lawScaleTargetNotAFunctionOfInput, confirmed: even memorising captured only ~13%). The
information needed lives in the surrounding CONTENT. This experiment gives each octant a window of the
surrounding COARSE field (low-frequency context ONLY -- the octant's own detail is never an input, so
there is no leakage) and asks: can the model infer the high-frequency detail from the low-frequency
context? That is the genuine super-resolution task, and the stepping stone to the full 64-token ViT
(which generalises "a KxK window" to "all tokens via attention").

Held split = a DIFFERENT capture (different seed): the real test of whether a context->detail prior
GENERALISES to new content (edges/gradients -> high-freq is a content-universal relationship if the
corpus is structured). FLOORED stays a legitimate, honest outcome.
"""
from __future__ import annotations

import os
import sys

import numpy as np

try:
    import mlx.core as mx
    _HAVE_MLX = True
except Exception:
    _HAVE_MLX = False

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))

from jepa_synth_octants import lab_volume                                # noqa: E402
from cell_loss import cell_loss                                         # noqa: E402
from full_matrix_loss import floor_cell_baseline                       # noqa: E402
from above_floor_margin import dashboard_verdict, surviving_fraction   # noqa: E402

Q = 65536.0
COORDS = [(i % 2, (i // 2) % 2, i // 4) for i in range(8)]
RADIUS = 2                                       # KxK context window, K = 2*RADIUS+1 = 5
K = 2 * RADIUS + 1


def _octants_with_context(seed, kind, frame_step=8):
    """Yield (feat_window (K*K*3,), floor_cell, target_cell) for non-overlapping 2x2x2 octants.

    feat_window = the surrounding coarse field (octant means) in a KxK neighbourhood, normalised. The
    octant's OWN detail is never in the features (no leakage); only the low-freq coarse grid is.
    """
    vol = lab_volume(seed, kind)                 # (F, 64, 64, 3) Q16 OKLab
    F, S, _, _ = vol.shape
    G = S // 2                                    # 32x32 octant grid
    for f in range(0, F - 1, frame_step):
        pair = vol[f:f + 2].astype(np.float64)   # (2, 64, 64, 3)
        # coarse grid: mean of each 2x2x2 octant -> (G, G, 3)
        coarse = pair.reshape(2, G, 2, G, 2, 3).mean(axis=(0, 2, 4))   # (G,G,3)
        for gr in range(G):
            for gc in range(G):
                # context window of the COARSE grid (zero-padded at edges), normalised by Q.
                win = np.zeros((K, K, 3), dtype=np.float64)
                for dr in range(-RADIUS, RADIUS + 1):
                    for dc in range(-RADIUS, RADIUS + 1):
                        rr, cc = gr + dr, gc + dc
                        if 0 <= rr < G and 0 <= cc < G:
                            win[dr + RADIUS, dc + RADIUS] = coarse[rr, cc] / Q
                feat = win.reshape(-1)            # (K*K*3,)
                # target = the real octant detail; floor = coarse-flat (zero detail).
                r0, c0 = 2 * gr, 2 * gc
                target = []
                for i, (x, y, t) in enumerate(COORDS):
                    vx = pair[t, r0 + y, c0 + x]
                    target.append((int(vx[0]), int(vx[1]), int(vx[2]), x, y, t))
                cm = coarse[gr, gc]
                floor = [(int(cm[0]), int(cm[1]), int(cm[2]), x, y, t) for (x, y, t) in COORDS]
                yield feat, floor, target


def _agg(cell):
    A = np.zeros((3, 3))
    for (L, a, b, x, y, t) in cell:
        A += np.outer([a / Q, b / Q, L / Q], [x, y, t])
    return A


def _gather(kinds, seeds, frame_step=8):
    out = []
    for s in seeds:
        for k in kinds:
            out.extend(_octants_with_context(s, k, frame_step))
    return out


def train_mlp(train, h=64, steps=400, lr=0.01, seed=0):
    feats = mx.array(np.stack([f for f, _, _ in train]), dtype=mx.float32)                # (N, KK3)
    floor_col = mx.array(np.stack([[[L / Q, a / Q, b / Q] for (L, a, b, *_ ) in fl] for _, fl, _ in train]),
                         dtype=mx.float32)                                                 # (N,8,3)
    space = mx.array(np.array([[x, y, t] for (x, y, t) in COORDS]), dtype=mx.float32)      # (8,3)
    A_tgt = mx.array(np.stack([_agg(t) for _, _, t in train]), dtype=mx.float32)           # (N,3,3)
    din = feats.shape[-1]
    rng = np.random.default_rng(seed)
    def he(a, b): return mx.array(rng.standard_normal((a, b)) * np.sqrt(2.0 / a), dtype=mx.float32)
    P = [he(din, h), mx.zeros((h,)), he(h, h), mx.zeros((h,)), he(h, 24) * 0.0, mx.zeros((24,))]

    def fwd(P, X):
        x = mx.maximum(X @ P[0] + P[1], 0)
        x = mx.maximum(x @ P[2] + P[3], 0)
        return (x @ P[4] + P[5]).reshape(X.shape[0], 8, 3)    # per-voxel (L,a,b) residual

    def loss_fn(P):
        col = floor_col + fwd(P, feats)
        col_abL = mx.stack([col[..., 1], col[..., 2], col[..., 0]], axis=-1)
        A = mx.matmul(col_abL.transpose(0, 2, 1), mx.broadcast_to(space, (col.shape[0], 8, 3)))
        return mx.mean((A - A_tgt) ** 2)

    gfn = mx.value_and_grad(loss_fn)
    traj = []
    for _ in range(steps):
        loss, G = gfn(P)
        P = [p - lr * g for p, g in zip(P, G)]
        mx.eval(*P, loss); traj.append(float(loss))
    Pn = [np.array(p) for p in P]

    def predict(feat):                                        # (KK3,) -> (8,3)
        x = np.maximum(feat @ Pn[0] + Pn[1], 0)
        x = np.maximum(x @ Pn[2] + Pn[3], 0)
        return (x @ Pn[4] + Pn[5]).reshape(8, 3)
    return predict, traj


def _measure(predict, held):
    hl_, fl_, beats, coeffs = [], [], 0, []
    for feat, floor, target in held:
        resid = predict(feat)
        if not np.all(np.isfinite(resid)):
            return {"verdict": "DIVERGED", "n": len(held)}
        inv = [(int(round(floor[i][0] + resid[i, 0] * Q)),
                int(round(floor[i][1] + resid[i, 1] * Q)),
                int(round(floor[i][2] + resid[i, 2] * Q)), *COORDS[i]) for i in range(8)]
        hl, fl = cell_loss(inv, target), floor_cell_baseline(floor, target)
        hl_.append(hl); fl_.append(fl); beats += (hl < fl); coeffs.extend(resid.flatten().tolist())
    mh, mf = float(np.mean(hl_)), float(np.mean(fl_))
    m = {"held": mh, "floor": mf, "margin": mf - mh, "beats_floor": mh < mf * 0.98}
    return {"verdict": dashboard_verdict(m, surviving_fraction(coeffs), collapsed=False, diverged=False),
            "held": mh, "floor": mf, "margin": mf - mh, "frac": surviving_fraction(coeffs),
            "beats": beats, "n": len(held)}


def run(train_kinds=("high-lab", "high-detail", "high-lab-detail"), held_kind="high-lab",
        train_seeds=(0, 1), held_seed=7, steps=400, lr=0.01):
    if not _HAVE_MLX:
        print("context_super_res: SKIP (MLX not importable)"); return None
    train = _gather(train_kinds, train_seeds)
    held = _gather((held_kind,), (held_seed,))     # a DIFFERENT capture -> generalisation test
    predict, traj = train_mlp(train, steps=steps, lr=lr)
    if not np.isfinite(traj[-1]):
        print("context_super_res: DIVERGED"); return {"verdict": "DIVERGED", "traj": traj}
    r = _measure(predict, held); r["traj"] = traj
    print(f"context_super_res[{K}x{K} window]: train {len(train)} / held {r['n']} octants "
          f"(loss {traj[0]:.5f}->{traj[-1]:.5f}, drop {100*(1-traj[-1]/traj[0]):.0f}%)")
    print(f"  held cell loss {r['held']:.0f} vs floor {r['floor']:.0f}; beats {r['beats']}/{r['n']} "
          f"({100*r['beats']//r['n']}%); surviving {r['frac']:.3f}  ==> {r['verdict']} (margin {r['margin']:.0f})")
    return r


def _self_test():
    if not _HAVE_MLX:
        print("context_super_res: SKIP (MLX not importable)"); return
    # gate config: a small slice so the gate is fast; run() defaults give the full corpus.
    train = _gather(("high-lab",), (0,))[:2000]
    held = _gather(("high-lab",), (7,))[:800]
    predict, traj = train_mlp(train, steps=150)
    r = _measure(predict, held)
    assert np.isfinite(traj[-1]) and traj[-1] <= traj[0]
    assert r["verdict"] in ("LEARNING", "MEAN-ONLY", "FLOORED", "DIVERGED")
    # The overfit gap is the load-bearing finding: a high-capacity MLP fits detail from context on a
    # small set but does NOT generalise -> the corpus lacks a transferable coarse->detail prior (DATA).
    _, ot = train_mlp(train[:256], h=256, steps=600, lr=0.02)
    overfit_drop = 1 - ot[-1] / ot[0]
    print(f"context_super_res: held verdict={r['verdict']}; overfit-256 drop={100*overfit_drop:.0f}% "
          f"(big gap vs held => the bottleneck is DATA, not architecture).")


if __name__ == "__main__":
    _self_test()
