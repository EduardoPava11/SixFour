"""STEP 3 lock test: the trained AND judged objective IS Spec.MatrixTarget.cellLoss.

Three locks:
  (1) GOLDEN  -- cell_loss.py reproduces the QuickCheck'd spec law witnesses byte-exact
      (delegates cell_loss.self_check; also gated standalone in gate_trainer.py).
  (2) BRIDGE  -- the MLX trainer's cell term formula (0.5 * mean((palᵀ·S - tgtᵀ·S)^2), the body
      of _composite_terms / _composite_terms_batched) EQUALS Spec.MatrixTarget.cellLoss on integer
      colours, up to the 1/18 averaging the optimizer is invariant to (0.5 * sum/9 = sum/18). This
      proves the float term the optimizer descends is the spec held-out loss, not a look-alike. The
      colour columns are (L,a,b) in the trainer vs (a,b,L) in the spec -- a row permutation of the
      3x3 aggregate, which leaves the summed squared error unchanged, so the values match exactly.
  (3) VERDICT -- dashboard_verdict keys on the CELL margin when the eval supplies it: a cell-beating
      head reads LEARNING, a cell-worse head reads FLOORED, COLLAPSE still wins, and with no 'cell'
      key it falls back to the value margin (legacy, keeps test_dashboard_verdict valid).

Pure NumPy + Python (no MLX needed): the bridge checks the SAME arithmetic the mx.matmul path runs.
"""
from __future__ import annotations

import os
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import cell_loss  # noqa: E402
from cell_loss import cell_loss as spec_cell_loss, octant_space_matrix  # noqa: E402
from train_loop import dashboard_verdict, VIC_GAMMA, VIC_NEURON_SLICE  # noqa: E402

MAX_VIC = VIC_GAMMA * VIC_NEURON_SLICE
OK_VIC = 0.1 * MAX_VIC


def _trainer_cell_term(pal_lab: np.ndarray, tgt_lab: np.ndarray, S: np.ndarray) -> float:
    """The exact body of train_loop._composite_terms' cell term, in NumPy (== the mx.matmul path).
    pal_lab/tgt_lab: (N_VOX, 3) colours in (L,a,b) order; S: (N_VOX, 3) space (x,y,t)."""
    a_pred = pal_lab.T @ S            # (3, 3) cell aggregate (pred)
    a_tgt = tgt_lab.T @ S             # (3, 3) cell aggregate (target)
    cd = a_pred - a_tgt
    return 0.5 * float(np.mean(cd * cd))


def main() -> int:
    fails = 0

    # (1) GOLDEN: the spec law witnesses reproduce byte-exact.
    if cell_loss.self_check() != 0:
        print("[FAIL] cell_loss.self_check (spec golden) did not pass"); fails += 1
    else:
        print("[ ok ] (1) GOLDEN -- cell_loss reproduces Spec.MatrixTarget.cellLoss witnesses byte-exact")

    # (2) BRIDGE: the MLX trainer cell term == Spec.MatrixTarget.cellLoss (up to the 1/18 averaging).
    S_int = octant_space_matrix(2)                 # the 8 octant (x,y,t) rows
    S = np.asarray(S_int, dtype=np.float64)
    rng = np.random.default_rng(64)
    bridge_ok = True
    for _ in range(200):
        pal_lab = rng.integers(-50, 50, size=(8, 3)).astype(np.float64)   # (L,a,b) per voxel, pred
        tgt_lab = rng.integers(-50, 50, size=(8, 3)).astype(np.float64)   # (L,a,b) per voxel, target
        # Spec side: build P6 voxels (L,a,b,x,y,t) with the SAME colours + octant space lattice.
        pred_cell = [(int(L), int(a), int(b), int(x), int(y), int(t))
                     for (L, a, b), (x, y, t) in zip(pal_lab, S_int)]
        tgt_cell = [(int(L), int(a), int(b), int(x), int(y), int(t))
                    for (L, a, b), (x, y, t) in zip(tgt_lab, S_int)]
        spec = spec_cell_loss(pred_cell, tgt_cell)                        # exact integer
        term = _trainer_cell_term(pal_lab, tgt_lab, S)                    # the trained float term
        # 0.5 * mean over 9 cells = 0.5 * sum/9 = sum/18; sum == spec (row-permutation invariant).
        if abs(term * 18.0 - spec) > 1e-6:
            print(f"[FAIL] trainer cell term {term} *18 != spec cellLoss {spec}"); fails += 1
            bridge_ok = False
            break
    if bridge_ok:
        print("[ ok ] (2) BRIDGE -- MLX cell term == Spec.MatrixTarget.cellLoss (200 random octants, *1/18)")

    # (3) VERDICT: the dashboard keys on the cell margin when present.
    floor = {"value": 0.04, "band": 0.0004, "cell": 0.020}
    # cell beats floor (held 0.001 << 0.020) -> LEARNING, even though band is below its floor.
    learn = {"pal": 0.003, "band": 0.0005, "idx": 0.0, "vic": OK_VIC, "cell": 0.001}
    v, _vm, bm, _coll, _ = dashboard_verdict(learn, floor)
    if v != "LEARNING":
        print(f"[FAIL] cell-beating head should read LEARNING, got {v!r}"); fails += 1
    elif bm >= 0.0:
        print(f"[FAIL] band margin should be negative (the blind metric), got {bm:+.1f}%"); fails += 1
    else:
        print(f"[ ok ] (3a) LEARNING via cell margin while band margin {bm:+.1f}% (blind)")

    # cell worse than floor -> FLOORED (no goalpost-moving).
    floored = {"pal": 0.003, "band": 0.0005, "idx": 0.0, "vic": OK_VIC, "cell": 0.030}
    vf, *_ = dashboard_verdict(floored, floor)
    if vf != "FLOORED (worse than predicting zero)":
        print(f"[FAIL] cell-worse head should read FLOORED, got {vf!r}"); fails += 1
    else:
        print("[ ok ] (3b) cell worse than floor reads FLOORED")

    # collapse wins over a good cell margin.
    coll = {"pal": 0.003, "band": 0.0005, "idx": 0.0, "vic": 0.9 * MAX_VIC, "cell": 0.001}
    vc, _, _, c, _ = dashboard_verdict(coll, floor)
    if vc != "COLLAPSE (variance floor tripped)" or not c:
        print(f"[FAIL] collapse must win over cell margin, got {vc!r}"); fails += 1
    else:
        print("[ ok ] (3c) COLLAPSE guard fires first regardless of cell margin")

    # legacy fallback: no 'cell' key -> verdict from the value margin (keeps test_dashboard_verdict valid).
    legacy_floor = {"value": 0.04, "band": 0.0004}
    legacy_held = {"pal": 0.003, "band": 0.0005, "idx": 0.0, "vic": OK_VIC}
    vl, *_ = dashboard_verdict(legacy_held, legacy_floor)
    if vl != "LEARNING":
        print(f"[FAIL] legacy (no cell key) should fall back to value margin LEARNING, got {vl!r}"); fails += 1
    else:
        print("[ ok ] (3d) no cell key -> falls back to value-margin verdict (legacy preserved)")

    print("test_cell_loss: PASS" if fails == 0 else f"test_cell_loss: {fails} FAIL")
    return 1 if fails else 0


if __name__ == "__main__":
    raise SystemExit(main())
