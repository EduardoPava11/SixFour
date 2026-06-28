"""The full-matrix training LOOP — train a held-out detail predictor, MEASURE the margin.

This turns contractAboveFloorMarginMeasured from a () marker into an actual NUMBER, and is where we
IMPROVE the model and re-measure.

THE HELD-OUT SCALE TASK (Spec.HeldOutTarget scale axis): input = the octant COARSE (DC) + WHERE the
octant sits (its block position = spatial context); target = the real (L,a,b) detail. The target is NOT a
function of the coarse alone (lawScaleTargetNotAFunctionOfInput), so the predictor learns the
CONDITIONAL-MEAN detail given (coarse, position, spatial-context). It beats the deterministic floor (zero
detail) IFF that mean carries generalisable signal.

THE IMPROVEMENT over the first (linear) run, which FLOORED:
  * richer FEATURES: add the octant's block position (xblk, yblk) -> the predictor knows WHERE it is, not
    just the intra-octant voxel coords. A linear map on (coarse, intra-pos) alone had no spatial context.
  * a NONLINEAR predictor (MLP) instead of a single linear layer.
We report the honest A/B (linear vs MLP) on a held-out split. FLOORED stays a legitimate outcome.
"""
from __future__ import annotations

import os
import sys

import numpy as np

try:
    import mlx.core as mx          # before sys.path edits, else local trainer/mlx shadows the mlx package
    _HAVE_MLX = True
except Exception:
    _HAVE_MLX = False

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))

from jepa_data import unlift_oct                                          # noqa: E402
from jepa_synth_octants import octant_records                            # noqa: E402
from cell_loss import cell_loss                                          # noqa: E402
from full_matrix_loss import floor_cell_baseline                        # noqa: E402
from above_floor_margin import dashboard_verdict, surviving_fraction    # noqa: E402

Q = 65536.0
COORDS = [(i % 2, (i // 2) % 2, i // 4) for i in range(8)]    # octant voxel order -> (x,y,t)
_BLK = 64.0                                                   # block-position normaliser (capture side)


def _examples(seed, kind, frame_step=8, space_step=6):
    """Yield (floor_cell, target_cell, (xblk,yblk)) per octant. floor = coarse-flat; target = real detail."""
    for cube_l, coarse_l, _dl, (xblk, yblk), chroma in octant_records(seed, kind, frame_step, space_step):
        (cA, dA), (cB, dB) = chroma
        cube_a = unlift_oct(cA, list(dA))
        cube_b = unlift_oct(cB, list(dB))
        target = [(int(cube_l[i]), int(cube_a[i]), int(cube_b[i]), x, y, t) for i, (x, y, t) in enumerate(COORDS)]
        floor = [(int(coarse_l), int(cA), int(cB), x, y, t) for (x, y, t) in COORDS]
        yield floor, target, (xblk, yblk)


def _feat(floor, blk):
    """Per-voxel feature row: [coarseL, coarseA, coarseB, x, y, t, xblk, yblk] (colour & block normalised)."""
    cL, cA, cB = floor[0][0] / Q, floor[0][1] / Q, floor[0][2] / Q
    bx, by = blk[0] / _BLK, blk[1] / _BLK
    return np.array([[cL, cA, cB, x, y, t, bx, by] for (_, _, _, x, y, t) in floor], dtype=np.float64)


def _agg(cell):
    A = np.zeros((3, 3))
    for (L, a, b, x, y, t) in cell:
        A += np.outer([a / Q, b / Q, L / Q], [x, y, t])    # cell_loss colour order (a,b,L)
    return A


def _gather(kinds, seeds):
    ex = []
    for s in seeds:
        for k in kinds:
            ex.extend(_examples(s, k))
    return ex


def _measure(predict, held):
    """predict: (feat (8,Din)) -> residual (8,3) normalised. Returns the measured numbers + verdict."""
    held_l, floor_l, beats, coeffs = [], [], 0, []
    for floor, target, blk in held:
        resid = predict(_feat(floor, blk))
        if not np.all(np.isfinite(resid)):
            return {"verdict": "DIVERGED", "held": float("nan"), "floor": float("nan"),
                    "frac": float("nan"), "beats": 0, "n": len(held)}
        invented = [(int(round(floor[i][0] + resid[i, 0] * Q)),
                     int(round(floor[i][1] + resid[i, 1] * Q)),
                     int(round(floor[i][2] + resid[i, 2] * Q)), *COORDS[i]) for i in range(8)]
        hl, fl = cell_loss(invented, target), floor_cell_baseline(floor, target)
        held_l.append(hl); floor_l.append(fl); beats += (hl < fl)
        coeffs.extend(resid.flatten().tolist())
    mh, mf = float(np.mean(held_l)), float(np.mean(floor_l))
    frac = surviving_fraction(coeffs)
    m = {"held": mh, "floor": mf, "margin": mf - mh, "beats_floor": mh < mf * 0.98}
    return {"verdict": dashboard_verdict(m, frac, collapsed=False, diverged=False),
            "held": mh, "floor": mf, "margin": mf - mh, "frac": frac, "beats": beats, "n": len(held)}


def _batched(train):
    feats = mx.array(np.stack([_feat(f, b) for f, _, b in train]), dtype=mx.float32)      # (N,8,Din)
    floor_col = mx.array(np.stack([[[L / Q, a / Q, b / Q] for (L, a, b, *_ ) in f] for f, _, _ in train]),
                         dtype=mx.float32)                                                 # (N,8,3)
    space = mx.array(np.array([[x, y, t] for (x, y, t) in COORDS]), dtype=mx.float32)      # (8,3)
    A_tgt = mx.array(np.stack([_agg(t) for _, t, _ in train]), dtype=mx.float32)           # (N,3,3)
    return feats, floor_col, space, A_tgt


def _agg_loss(resid, floor_col, space, A_tgt):
    col = floor_col + resid
    col_abL = mx.stack([col[..., 1], col[..., 2], col[..., 0]], axis=-1)
    A = mx.matmul(col_abL.transpose(0, 2, 1), mx.broadcast_to(space, (col.shape[0], 8, 3)))
    return mx.mean((A - A_tgt) ** 2)


def train_linear(train, steps=300, lr=0.05):
    feats, floor_col, space, A_tgt = _batched(train)
    din = feats.shape[-1]
    W = mx.zeros((din, 3))
    gfn = mx.value_and_grad(lambda W: _agg_loss(feats @ W, floor_col, space, A_tgt))
    traj = []
    for _ in range(steps):
        loss, g = gfn(W); W = W - lr * g; mx.eval(W, loss); traj.append(float(loss))
    Wn = np.array(W)
    return (lambda feat: feat @ Wn), traj


def train_mlp(train, h=32, steps=500, lr=0.02, seed=0):
    feats, floor_col, space, A_tgt = _batched(train)
    din = feats.shape[-1]
    rng = np.random.default_rng(seed)
    def he(a, b): return mx.array(rng.standard_normal((a, b)) * np.sqrt(2.0 / a), dtype=mx.float32)
    P = [he(din, h), mx.zeros((h,)), he(h, h), mx.zeros((h,)), he(h, 3) * 0.0, mx.zeros((3,))]

    def fwd(P, X):                                  # X (N,8,Din) -> (N,8,3)
        x = mx.maximum(X @ P[0] + P[1], 0)
        x = mx.maximum(x @ P[2] + P[3], 0)
        return x @ P[4] + P[5]

    def loss_fn(P):
        return _agg_loss(fwd(P, feats), floor_col, space, A_tgt)

    gfn = mx.value_and_grad(loss_fn)
    traj = []
    for _ in range(steps):
        loss, G = gfn(P)
        P = [p - lr * g for p, g in zip(P, G)]
        mx.eval(*P, loss); traj.append(float(loss))
    Pn = [np.array(p) for p in P]

    def predict(feat):                              # feat (8,Din) -> (8,3)
        x = np.maximum(feat @ Pn[0] + Pn[1], 0)
        x = np.maximum(x @ Pn[2] + Pn[3], 0)
        return x @ Pn[4] + Pn[5]
    return predict, traj


def run(predictor="mlp", split="random", steps=None, lr=None, seed=0, kinds=None, seeds=None):
    if not _HAVE_MLX:
        print("full_matrix_train_loop: SKIP (MLX not importable)")
        return None
    kinds = kinds or ("high-lab", "high-lab-detail", "high-detail")
    seeds = seeds or (seed, seed + 1, seed + 2)
    ex = _gather(kinds, seeds=seeds)
    if split == "random":
        idx = np.random.default_rng(seed).permutation(len(ex))
        cut = int(0.8 * len(ex))
        train = [ex[i] for i in idx[:cut]]; held = [ex[i] for i in idx[cut:]]
    else:                                                   # seed split: held is a fresh capture (extrapolation)
        train = ex; held = _gather(("high-lab",), seeds=(seed + 99,))

    if predictor == "mlp":
        predict, traj = train_mlp(train, steps=steps or 500, lr=lr or 0.02)
    else:
        predict, traj = train_linear(train, steps=steps or 300, lr=lr or 0.05)

    if not np.isfinite(traj[-1]):
        print(f"full_matrix_train_loop[{predictor}/{split}]: DIVERGED (lr too hot)")
        return {"verdict": "DIVERGED", "traj": traj}
    r = _measure(predict, held)
    r["traj"] = traj
    print(f"full_matrix_train_loop[{predictor}/{split}]: train {len(train)} / held {r.get('n','?')} octants "
          f"(loss {traj[0]:.5f}->{traj[-1]:.5f})")
    if r["verdict"] != "DIVERGED":
        print(f"  held cell loss {r['held']:.0f} vs floor {r['floor']:.0f}; beats {r['beats']}/{r['n']} "
              f"({100*r['beats']//r['n']}%); surviving {r['frac']:.3f}  ==> {r['verdict']} (margin {r['margin']:.0f})")
    return r


def _self_test():
    if not _HAVE_MLX:
        print("full_matrix_train_loop: SKIP (MLX not importable)"); return
    # gate config: a small subset (1 seed, 2 kinds) so the gate is fast; run() defaults give the full corpus.
    sub = dict(kinds=("high-lab", "high-detail"), seeds=(0,))
    rl = run("linear", "random", steps=120, **sub)
    rm = run("mlp", "random", steps=150, **sub)
    for r in (rl, rm):
        assert np.isfinite(r["traj"][-1]) and r["traj"][-1] <= r["traj"][0]
        assert r["verdict"] in ("LEARNING", "MEAN-ONLY", "FLOORED", "DIVERGED")
    print(f"full_matrix_train_loop: A/B measured -- linear={rl['verdict']}, mlp+context={rm['verdict']} "
          f"(the real above-floor numbers, honest whichever way).")


if __name__ == "__main__":
    _self_test()
