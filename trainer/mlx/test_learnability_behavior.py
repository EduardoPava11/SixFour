"""test_learnability_behavior.py -- test the LEARNABILITY THEOREM's falsifiable predictions on the
ACTUAL trainer code (not the golden constants; the real cell_term/value_term train_loop descends and
a real short training run). This is the operational "is it working as designed?" test.

The theorem (Spec.LearnabilityTheorem.lawValueHeadIdentifiesComplement, verified in Haskell) predicts,
about the REAL objective the optimizer minimizes:
  P1 BLIND : cell_term (the rank-3 cross-moment, the primary objective) is EXACTLY invariant under a
             checkerboard-parity palette perturbation cb (cb ⊥ span(S)) -- it cannot see 15 of 24 DOF.
  P2 SEES  : value_term sees that SAME perturbation (Σ cb² > 0) -- the value head identifies the complement.
  P3 NON-VACUOUS: cell_term DOES see a span(S) (rank-3) perturbation -- it is a sufficient statistic for
             the 9-DOF projection, not blind to everything.
  P4 SIDE-CONDITION (operational): a real short training run with w_value>0 DRIVES the value/reconstruction
             loss DOWN (the complement is being identified); with w_value=0 it does NOT (unconstrained).
If P1/P2/P3 fail, the theorem is wrong about the real code. If P4 fails, the improvement (w_value=1) is inert.

Run from trainer/mlx: ../.venv/bin/python test_learnability_behavior.py
"""
import numpy as np
import mlx.core as mx

import train_loop as T
from jepa_synth_octants import build_corpus

KINDS = ["high-lab", "high-detail", "smooth-grey"]


def _checkerboard():
    """The 8-voxel parity vector cb[v] = (-1)^popcount(v); cb ⊥ span(SPACE_MX) (verified Sᵀcb=0)."""
    return np.array([(-1.0) ** bin(v).count("1") for v in range(T.N_PAL)], dtype=np.float32)


def _pred_target_pair():
    """A random target palette + a prediction differing ONLY by a checkerboard on one colour channel."""
    rng = np.random.default_rng(0)
    tgt = rng.standard_normal((4, T.N_PAL, T.PAL_CH)).astype(np.float32)
    cb = _checkerboard()
    pred_cb = tgt.copy()
    pred_cb[:, :, 0] += cb                       # perturb channel 0 by the complement direction
    return mx.array(tgt), mx.array(pred_cb), cb


def main():
    fails = 0
    tgt, pred_cb, cb = _pred_target_pair()

    # P1 + P2: the REAL cell_term/value_term the trainer descends, on the checkerboard perturbation.
    cell_blind = float(T.cell_term(pred_cb, tgt))
    value_sees = float(T.value_term(pred_cb, tgt))
    if cell_blind > 1e-9:
        print(f"[FAIL] P1: cell_term should be BLIND to the checkerboard (==0), got {cell_blind:.3e}"); fails += 1
    else:
        print(f"[ ok ] P1 BLIND: cell_term unchanged by the complement perturbation ({cell_blind:.2e})")
    if not (value_sees > 1e-6):
        print(f"[FAIL] P2: value_term must SEE the complement (>0), got {value_sees:.3e}"); fails += 1
    else:
        print(f"[ ok ] P2 SEES : value_term registers the complement ({value_sees:.4f}); Σcb²/voxels={np.mean(cb**2):.3f}")

    # P3 NON-VACUOUS: a span(S) (rank-3) perturbation IS seen by cell_term (it identifies that subspace).
    S = np.array(__import__("cell_loss").octant_space_matrix(), dtype=np.float32)   # (8,3)
    s_dir = S[:, 0]                                              # a vector IN span(S)
    pred_s = np.array(tgt).copy(); pred_s[:, :, 0] += s_dir
    cell_sees = float(T.cell_term(mx.array(pred_s), tgt))
    if not (cell_sees > 1e-6):
        print(f"[FAIL] P3: cell_term must SEE a span(S) perturbation (>0), got {cell_sees:.3e}"); fails += 1
    else:
        print(f"[ ok ] P3 NON-VACUOUS: cell_term sees the rank-3 (span S) perturbation ({cell_sees:.4f})")

    # P4 SIDE-CONDITION (operational, short real training): w_value>0 drives value loss down; w_value=0 does not.
    d6 = mx.array(T.octant_lattice_d6(T.N_TOKENS), dtype=mx.float32); mx.eval(d6)
    ex, _ = build_corpus([(i * 7 + 1, k) for i, k in enumerate(KINDS)], frame_step=8, space_step=16)
    ex = ex[:64]
    batch = T._build_batch(ex, d6)
    h_tb, h_masks, h_tg, h_pl = batch
    tgt_pal = h_pl.reshape(h_pl.shape[0], T.N_PAL, T.PAL_CH)

    def value_after(w_value, steps=60):
        mx.random.seed(0); np.random.seed(0)
        _mx, vit, _d, _p = T.large_head._build_vit()
        head = T.JepaHead(vit)
        head.readout.weight = head.readout.weight * 0.3
        head.readout.bias = head.readout.bias + 0.4
        mx.eval(head.parameters())
        opt = T.optim.SGD(learning_rate=1e-3, weight_decay=T.DEFAULT_WEIGHT_DECAY)
        grad = T._make_grad_batched(head, batch, d6, w_value, 0.0)
        for _ in range(steps):
            l, g = grad(head); opt.update(head, g); mx.eval(head.parameters(), l)
        _l, _r, palette, _i = T.batched_head(head, h_tb, d6); mx.eval(palette)
        return float(T.value_term(palette.reshape(palette.shape[0], T.N_PAL, T.PAL_CH), tgt_pal))

    v_on = value_after(1.0)
    v_off = value_after(0.0)
    print(f"  value-reconstruction loss after 60 steps: w_value=1 -> {v_on:.5f}   w_value=0 -> {v_off:.5f}")
    if not (v_on < v_off * 0.9):
        print(f"[FAIL] P4: w_value>0 must drive value loss BELOW the w_value=0 case (got {v_on:.5f} vs {v_off:.5f})"); fails += 1
    else:
        print(f"[ ok ] P4 SIDE-CONDITION: w_value=1 identifies the complement ({v_on:.5f} << {v_off:.5f} = w_value=0 inert)")

    print("=== learnability behavior: all green (the real trainer behaves as the theorem predicts) ==="
          if fails == 0 else f"=== learnability behavior: {fails} FAILED ===")
    return 1 if fails else 0


if __name__ == "__main__":
    raise SystemExit(main())
