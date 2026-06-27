"""temporal_rung.py -- the TimeRung: predict frame f+1 from frame f, and BEAT PERSISTENCE.

Spec.ScaleSpineRungs TimeRung (the HELD axis) + Spec.TemporalData value delta (ColourDelta =
next - cur). The honest baseline is PERSISTENCE: predict next := cur (zero colour-delta), which
Spec.MotionFloorCorpus says is optimal on a static clip. The rung LEARNS iff a model predicting
the next frame's colours from the current frame beats persistence on HELD-OUT (disjoint-seed)
octants -- i.e. the inter-frame motion is structured, not noise.

Each training octant is a frame-major 2x2x2 (jepa_synth_octants._cube_at): voxels [0:4] = frame f,
[4:8] = frame f+1 at the SAME four 2x2 spatial positions, so persistence is well-defined per voxel.
The (L,a,b) value-delta target is data-manufactured from the REAL next frame (temporal_data
semantics) -- never self-produced, no rollout, so the time-axis collapse guard holds by construction.

float32 MLX (the byte commit is unaffected -- this is a float training head). Run from trainer/mlx:
    ../.venv/bin/python temporal_rung.py
"""
import mlx.core as mx
import mlx.nn as nn
import mlx.optimizers as optim

from jepa_synth_octants import build_corpus
from jepa_data import unlift_oct
from q16 import to_q16

KINDS = ["high-lab", "high-detail", "smooth-grey"]
# The rung must beat persistence by at least this held-out margin to count as LEARNING motion.
LEARN_MARGIN_PCT = 5.0


def octant_pairs(specs):
    """(cur, next) per octant: frame-f voxels [0:4] and frame-(f+1) voxels [4:8], (L,a,b) in Q16
    units (to_q16, ~[0,1]). Shapes (N, 12) = 4 voxels x 3 channels, voxel-aligned so next[i] is the
    SAME spatial cell as cur[i] one frame later (persistence = predict next:=cur)."""
    examples, _ = build_corpus(specs, frame_step=8, space_step=8)
    cur, nxt = [], []
    for (coarse, detail, _m, chroma) in examples:
        L = unlift_oct(coarse, list(detail))
        (cA, dA), (cB, dB) = chroma
        A = unlift_oct(cA, list(dA))
        B = unlift_oct(cB, list(dB))
        c, n = [], []
        for v in range(4):
            c += [to_q16(L[v]), to_q16(A[v]), to_q16(B[v])]
            n += [to_q16(L[v + 4]), to_q16(A[v + 4]), to_q16(B[v + 4])]
        cur.append(c)
        nxt.append(n)
    return mx.array(cur, dtype=mx.float32), mx.array(nxt, dtype=mx.float32)


class TimeHead(nn.Module):
    """Predicts the value DELTA (next - cur) from the current frame's colours; next_pred = cur +
    delta. Predicting zero delta == persistence, so any nonzero learned delta that lowers held-out
    error is real motion prediction."""
    def __init__(self, d=64):
        super().__init__()
        self.l1 = nn.Linear(12, d)
        self.l2 = nn.Linear(d, d)
        self.l3 = nn.Linear(d, 12)

    def __call__(self, cur):
        h = nn.relu(self.l1(cur))
        h = nn.relu(self.l2(h))
        return self.l3(h)                       # the predicted ColourDelta


def _loss(m, cur, nxt):
    return mx.mean((cur + m(cur) - nxt) ** 2)   # MSE of reconstructed next frame


def persistence_loss(cur, nxt):
    return float(mx.mean((cur - nxt) ** 2))     # the zero-delta baseline


def train_time_rung(steps=800, seed=0, d=64, lr=1e-3):
    mx.random.seed(seed)
    train_cur, train_nxt = octant_pairs([(i * 7 + 1, k) for i, k in enumerate(KINDS)])
    held_cur, held_nxt = octant_pairs([(500003 + i, k) for i, k in enumerate(KINDS)])  # disjoint seeds
    m = TimeHead(d)
    mx.eval(m.parameters())
    opt = optim.Adam(learning_rate=lr)
    lg = nn.value_and_grad(m, lambda mm: _loss(mm, train_cur, train_nxt))
    for _ in range(steps):
        l, g = lg(m)
        opt.update(m, g)
        mx.eval(m.parameters(), l)
    pers = persistence_loss(held_cur, held_nxt)
    model = float(_loss(m, held_cur, held_nxt))
    margin = (pers - model) / pers * 100 if pers > 0 else 0.0
    return pers, model, margin, train_cur.shape[0], held_cur.shape[0]


def main():
    print("=== TimeRung: predict frame f+1 from frame f, beat PERSISTENCE (Spec.ScaleSpineRungs) ===")
    pers, model, margin, n_tr, n_he = train_time_rung()
    print(f"  train octants={n_tr}  held-out octants={n_he} (disjoint seeds)")
    print(f"  persistence (predict next:=cur) held-out MSE : {pers:.6f}   (THE baseline to beat)")
    print(f"  TimeRung model                  held-out MSE : {model:.6f}")
    print(f"  margin vs persistence: {margin:+.1f}%   (>{LEARN_MARGIN_PCT}% = learns motion, not a copy)")
    ok = margin > LEARN_MARGIN_PCT
    print("PASS: the TimeRung LEARNS inter-frame motion (beats persistence on held-out)" if ok else
          "FAIL: cannot beat persistence -- motion not predictable from cur alone (needs richer context)")
    return 0 if ok else 1


if __name__ == "__main__":
    raise SystemExit(main())
