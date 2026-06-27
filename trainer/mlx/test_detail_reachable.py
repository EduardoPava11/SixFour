"""test_detail_reachable.py -- the ScaleRung within-octant DETAIL is LEARNABLE (not masking-blocked).

The mean-dominated cell loss hides whether the model learns within-octant DETAIL (the centered
aggregate, flat-mean blind spot). Before chasing a positive detail margin by training, this proves
the bar is REACHABLE: one detail band is MASKED from the head's input (I-JEPA masking), so the
honest question is whether the 6 VISIBLE bands carry enough to beat the flat-mean floor.

Oracle = reconstruct the octant with the masked band ZEROED (the best a head could do from visible
context). If the oracle's centered-detail error is BELOW the flat-mean floor, a positive detail
margin is reachable and the negative margin a short run shows is an OPTIMIZATION gap (more training),
NOT a structural wall. MEASURED: oracle ~0.00002 vs flat-mean floor ~0.00018 => +~90% reachable.
Byte-exact, no MLX; uses the SAME held-out corpus + centered aggregate the dashboard reports.
"""
import numpy as np

from jepa_synth_octants import build_corpus
from jepa_data import unlift_oct
from cell_loss import octant_space_matrix
from q16 import to_q16

KINDS = ["high-lab", "high-detail", "smooth-grey"]
_SP = np.asarray(octant_space_matrix(2), dtype=np.float64)
_SC = _SP - _SP.mean(axis=0, keepdims=True)            # centered space => detail-only aggregate


def _centered_loss(pred, tgt):
    a = np.einsum('bvc,vs->bcs', pred, _SC)
    at = np.einsum('bvc,vs->bcs', tgt, _SC)
    return 0.5 * float(np.mean((a - at) ** 2))


def _held(n=128):
    specs = [(500003 + i, k) for i, k in enumerate(KINDS)]
    ex, _ = build_corpus(specs, frame_step=8, space_step=8)
    if len(ex) > n:
        ex = ex[:: max(1, len(ex) // n)][:n]
    tgt, oracle = [], []
    for (coarse, detail, mask, chroma) in ex:
        (cA, dA), (cB, dB) = chroma
        L = unlift_oct(coarse, list(detail)); A = unlift_oct(cA, list(dA)); B = unlift_oct(cB, list(dB))
        dz = list(detail); dz[mask] = 0                # masked band zeroed = visible-only reconstruction
        Lm = unlift_oct(coarse, dz)
        tgt.append([[to_q16(L[v]), to_q16(A[v]), to_q16(B[v])] for v in range(8)])
        oracle.append([[to_q16(Lm[v]), to_q16(A[v]), to_q16(B[v])] for v in range(8)])
    return np.array(tgt), np.array(oracle)


def main():
    print("=== ScaleRung DETAIL reachability: is a positive centered-detail margin attainable? ===")
    tgt, oracle = _held()
    floor = _centered_loss(tgt.mean(axis=1, keepdims=True).repeat(8, axis=1), tgt)   # flat-mean
    orc = _centered_loss(oracle, tgt)                                                # visible-only best
    margin = (floor - orc) / floor * 100 if floor > 0 else 0.0
    print(f"  flat-mean detail floor    : {floor:.6f}   (the bar a flat prediction scores)")
    print(f"  masked-band oracle detail : {orc:.6f}   (BEST reachable from the 6 visible bands)")
    print(f"  reachable margin vs floor : {margin:+.1f}%   (>0 => detail IS learnable, gap is optimization)")
    ok = orc < floor
    print("PASS: positive detail margin is REACHABLE (masking does not block the ScaleRung)" if ok else
          "FAIL: oracle worse than flat-mean -- detail is structurally blocked by masking")
    return 0 if ok else 1


if __name__ == "__main__":
    raise SystemExit(main())
