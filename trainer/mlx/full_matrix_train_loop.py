"""The full-matrix training LOOP — train a held-out detail predictor across the corpus, MEASURE the margin.

This is the first run that turns contractAboveFloorMarginMeasured from a () marker into an actual NUMBER.

THE HELD-OUT SCALE TASK (Spec.HeldOutTarget scale axis): input = the octant COARSE (DC), target = the
real (L,a,b) detail. The target is NOT a function of the input (lawScaleTargetNotAFunctionOfInput: many
octants share a coarse but differ in detail), so no predictor can be exact -- it can only learn the
CONDITIONAL-MEAN detail given (coarse, position). That mean beats the deterministic floor (zero detail)
IFF the corpus's detail is position-correlated. So FLOORED is a possible, honest outcome; we report it.

The predictor is a shared linear map (coarse + position -> per-voxel residual), trained on a TRAIN split
of octants and measured on a HELD-OUT split (no leakage). The measurement is the byte-exact integer cell
margin vs the coarse floor + the surviving-commit fraction + the dashboard verdict.
"""
from __future__ import annotations

import os
import sys

import numpy as np

# Import MLX BEFORE touching sys.path: adding the parent trainer/ dir below would let the local
# trainer/mlx/ DIRECTORY shadow the installed `mlx` package (import mlx.core would then fail).
try:
    import mlx.core as mx
    _HAVE_MLX = True
except Exception:
    _HAVE_MLX = False

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))

from jepa_data import unlift_oct                                          # noqa: E402
from jepa_synth_octants import octant_records                            # noqa: E402
from cell_loss import cell_loss, cell_aggregate                          # noqa: E402
from full_matrix_loss import floor_cell_baseline                        # noqa: E402
from above_floor_margin import cell_margin, dashboard_verdict, surviving_fraction  # noqa: E402

Q = 65536.0
# octant voxel order (frame-major then row then col): i -> (x,y,t).
COORDS = [(i % 2, (i // 2) % 2, i // 4) for i in range(8)]


def _cells(seed, kind, frame_step=8, space_step=6):
    """Yield (floor_cell, target_cell) per octant: floor = coarse-flat (zero detail), target = real detail."""
    for cube_l, coarse_l, _detail_l, _blk, chroma in octant_records(seed, kind, frame_step, space_step):
        (cA, dA), (cB, dB) = chroma
        cube_a = unlift_oct(cA, list(dA))
        cube_b = unlift_oct(cB, list(dB))
        target = [(int(cube_l[i]), int(cube_a[i]), int(cube_b[i]), x, y, t)
                  for i, (x, y, t) in enumerate(COORDS)]
        floor = [(int(coarse_l), int(cA), int(cB), x, y, t) for (x, y, t) in COORDS]
        yield floor, target


def _features(floor_cell):
    """Per-voxel feature row [coarseL, coarseA, coarseB, x, y, t, 1] (colour normalised by Q16)."""
    L, a, b = floor_cell[0][0] / Q, floor_cell[0][1] / Q, floor_cell[0][2] / Q
    return np.array([[L, a, b, x, y, t, 1.0] for (_, _, _, x, y, t) in floor_cell], dtype=np.float64)


def _agg_norm(cell):
    """Float cell aggregate (cell_loss colour order a,b,L) on Q16-normalised colours."""
    A = np.zeros((3, 3))
    for (L, a, b, x, y, t) in cell:
        A += np.outer([a / Q, b / Q, L / Q], [x, y, t])
    return A


def run(train_kinds=("high-lab", "high-lab-detail"), held_kind="high-lab", steps=300, lr=0.05, seed=0):
    if not _HAVE_MLX:
        print("full_matrix_train_loop: SKIP (MLX not importable)")
        return None

    train = [c for k in train_kinds for c in _cells(seed, k)]
    held = list(_cells(seed + 1, held_kind))            # different seed => no leakage
    assert train and held

    feats = mx.array(np.stack([_features(f) for f, _ in train]), dtype=mx.float32)       # (N,8,7)
    floor_col = mx.array(np.stack([[[L / Q, a / Q, b / Q] for (L, a, b, *_ ) in f] for f, _ in train]),
                         dtype=mx.float32)                                                # (N,8,3) L,a,b
    space = mx.array(np.array([[x, y, t] for (x, y, t) in COORDS]), dtype=mx.float32)     # (8,3)
    A_tgt = mx.array(np.stack([_agg_norm(t) for _, t in train]), dtype=mx.float32)        # (N,3,3)

    def loss_fn(W):
        resid = feats @ W                                       # (N,8,3) residual on (L,a,b)
        col = floor_col + resid
        col_abL = mx.stack([col[..., 1], col[..., 2], col[..., 0]], axis=-1)   # -> (a,b,L)
        A = mx.matmul(col_abL.transpose(0, 2, 1), mx.broadcast_to(space, (col.shape[0], 8, 3)))
        return mx.mean((A - A_tgt) ** 2)

    W = mx.zeros((7, 3))
    gfn = mx.value_and_grad(loss_fn)
    traj = []
    for _ in range(steps):
        loss, g = gfn(W)
        W = W - lr * g
        mx.eval(W, loss)
        traj.append(float(loss))
    Wn = np.array(W)

    # DIVERGED guard: a too-hot lr sends the loss to NaN/inf. Report DIVERGED, never crash on int(NaN).
    if not np.all(np.isfinite(Wn)) or not np.isfinite(traj[-1]):
        print(f"full_matrix_train_loop: trained {len(train)} octants -> DIVERGED "
              f"(non-finite at lr={lr}); the lr/loss-weight is too hot.")
        print("  ==> VERDICT: DIVERGED")
        return {"verdict": "DIVERGED", "held": float("nan"), "floor": float("nan"),
                "frac": float("nan"), "beats": 0, "n_held": len(held), "traj": traj}

    # MEASURE on the HELD split (byte-exact integer cell margin + surviving fraction).
    held_losses, floor_losses, fracs, beats = [], [], [], 0
    all_coeffs = []
    for floor, target in held:
        feat = _features(floor)
        resid = feat @ Wn                                       # (8,3) normalised residual
        invented = [(int(round(floor[i][0] + resid[i, 0] * Q)),
                     int(round(floor[i][1] + resid[i, 1] * Q)),
                     int(round(floor[i][2] + resid[i, 2] * Q)),
                     *COORDS[i]) for i in range(8)]
        hl = cell_loss(invented, target)
        fl = floor_cell_baseline(floor, target)
        held_losses.append(hl)
        floor_losses.append(fl)
        if hl < fl:
            beats += 1
        all_coeffs.extend(resid.flatten().tolist())

    mean_held = float(np.mean(held_losses))
    mean_floor = float(np.mean(floor_losses))
    frac = surviving_fraction(all_coeffs)
    m = {"held": mean_held, "floor": mean_floor, "margin": mean_floor - mean_held,
         "beats_floor": mean_held < mean_floor * 0.98}
    verdict = dashboard_verdict(m, frac, collapsed=False, diverged=False)

    print(f"full_matrix_train_loop: trained {len(train)} octants ({traj[0]:.4f}->{traj[-1]:.4f}), "
          f"measured {len(held)} HELD-OUT octants:")
    print(f"  mean held cell loss = {mean_held:.1f}   vs   mean floor baseline = {mean_floor:.1f}")
    print(f"  beats floor on {beats}/{len(held)} octants;  surviving-detail fraction = {frac:.3f}")
    print(f"  ==> VERDICT: {verdict}  (margin = {m['margin']:.1f})")
    return {"verdict": verdict, "held": mean_held, "floor": mean_floor, "frac": frac,
            "beats": beats, "n_held": len(held), "traj": traj}


def _self_test():
    r = run(steps=200)
    if r is None:
        return
    assert np.isfinite(r["traj"][-1]), "training loss must be finite"
    assert r["traj"][-1] < r["traj"][0], "training must descend on the TRAIN split"
    assert r["verdict"] in ("LEARNING", "MEAN-ONLY", "FLOORED", "DIVERGED"), f"unexpected verdict {r['verdict']}"
    print(f"full_matrix_train_loop: loop runs + measures a HELD-OUT verdict ({r['verdict']}) -- "
          f"the real above-floor number, not a () marker.")


if __name__ == "__main__":
    _self_test()
