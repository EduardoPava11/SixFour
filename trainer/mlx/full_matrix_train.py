"""Gap 1+3+4 — the nudge-conditioned invention + the end-to-end train step.

THE GAP this closes: until now mi_nudge (the 16^3 x 9 CellBudget paint) and mi_gauge were carried by the
boundary but READ BY NOBODY, so the paint surface was decoration and no loss connected to the margin.

THE MECHANISM (paint conditions invention, in the rank-3 cell-aggregate directions): the nine paint
channels ARE the nine ChannelProduct (colour x space) pairs = the nine entries of the cell aggregate
A = sum_v colour(v) (x) space(v). A painted budget b[i] on channel i = (colour k, space s) adds, to each
voxel v, an invented colour residual on channel k proportional to b[i] * theta[i] * v[s]. So:
  * NEUTRAL nudge (all zero) => zero residual => the output is EXACTLY build_floor (lawNeutralNudgeIsAllFloor).
  * paint in a channel => invented detail along that colour x space direction, magnitude scaled by the budget.
  * mi_gauge selects the pairing (colour-by-space vs the phi6 dual), so it genuinely changes the invention.
theta (9 learnable weights) is trained by SGD on the cell loss vs the held target; the residual is LINEAR
in theta so the loss is convex (no spurious minima), matching LearnabilityTheorem's convergence teaching.

THE END-TO-END PROOF (gap 4): on a held target carrying detail the floor lacks, training drives the cell
loss BELOW the deterministic floor baseline -- i.e. the nudge-conditioned up-rung genuinely BEATS the floor
when trained. This is the mechanism working on a controlled synthetic case; the REAL-corpus number stays the
empirical unknown (contractAboveFloorMarginMeasured). Gap 3: it consumes heldout_corpus examples.
"""
from __future__ import annotations

import os
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

try:
    import mlx.core as mx
    _HAVE_MLX = True
except Exception:
    _HAVE_MLX = False

from cell_loss import cell_aggregate, cell_loss                          # noqa: E402
from full_matrix_loss import floor_cell_baseline                          # noqa: E402
from above_floor_margin import cell_margin, dashboard_verdict, surviving_fraction  # noqa: E402

# The nine ChannelProduct pairs (Spec.CellNudge / Spec.ChannelProduct): (colour, space).
PAIRS = [('L', 't'), ('L', 'x'), ('L', 'y'),
         ('a', 'x'), ('a', 'y'), ('a', 't'),
         ('b', 'x'), ('b', 'y'), ('b', 't')]
# The phi6 dual pairing (a<->x, b<->y, L<->t): mi_gauge=True rotates which space each colour pairs with.
PAIRS_DUAL = [('L', 'x'), ('L', 'y'), ('L', 't'),
              ('a', 'y'), ('a', 't'), ('a', 'x'),
              ('b', 't'), ('b', 'x'), ('b', 'y')]
_COL = {'L': 0, 'a': 1, 'b': 2}        # voxel colour index in (L,a,b)
_SPC = {'x': 3, 'y': 4, 't': 5}        # voxel coord index in (L,a,b,x,y,t)


def _basis(cell, budget9, gauge):
    """Per-voxel linear map M_v (3x9): residual_colour(v) = M_v @ theta, where M_v[k,i] = b[i]*v[space_i]
    if colour_i == k else 0. So the residual is paint-gated (b=0 => 0) and lands in the painted channel's
    colour x space direction. Returns a list of (3,9) numpy matrices, one per voxel."""
    pairs = PAIRS_DUAL if gauge else PAIRS
    mats = []
    for v in cell:
        M = np.zeros((3, 9), dtype=np.float64)
        for i, (col, sp) in enumerate(pairs):
            M[_COL[col], i] = budget9[i] * v[_SPC[sp]]
        mats.append(M)
    return mats


def condition_cell(floor_cell, budget9, theta9, gauge=False):
    """The nudge-conditioned cell: floor + paint-gated invented residual. theta9 may be a list/np/mx.
    NEUTRAL budget (all zero) => residual 0 => returns floor_cell unchanged (lawNeutralNudgeIsAllFloor)."""
    theta = np.array(theta9, dtype=np.float64)
    mats = _basis(floor_cell, budget9, gauge)
    out = []
    for v, M in zip(floor_cell, mats):
        d = M @ theta                      # (dL, da, db)
        out.append((int(round(v[0] + d[0])), int(round(v[1] + d[1])), int(round(v[2] + d[2])),
                    v[3], v[4], v[5]))
    return out


def train_cell(floor_cell, target_cell, budget9, gauge=False, steps=200, lr=1e-3, seed=0):
    """SGD on theta to minimise the (float) cell-aggregate loss of the nudge-conditioned cell vs target.
    Returns (theta, trajectory). Linear-in-theta => convex => descends to the unique minimum."""
    assert _HAVE_MLX, "train_cell needs MLX"
    mx.random.seed(seed)
    mats = mx.array(np.stack(_basis(floor_cell, budget9, gauge)), dtype=mx.float32)   # (8,3,9)
    floor_col = mx.array(np.array([[v[0], v[1], v[2]] for v in floor_cell]), dtype=mx.float32)  # (8,3)
    space = mx.array(np.array([[v[3], v[4], v[5]] for v in floor_cell]), dtype=mx.float32)      # (8,3)
    # target aggregate A_tgt = sum_v outer([a,b,L],[x,y,t]) -- cell_loss colour order is (a,b,L).
    A_tgt = mx.array(np.array(cell_aggregate(target_cell), dtype=np.float64), dtype=mx.float32)

    def loss_fn(theta):
        d = mats @ theta                                  # (8,3) residual (dL,da,db)
        col = floor_col + d                               # invented colour (L,a,b)
        cabL = mx.stack([col[:, 1], col[:, 2], col[:, 0]], axis=1)  # reorder to (a,b,L)
        A = mx.zeros((3, 3))
        for v in range(col.shape[0]):
            A = A + mx.outer(cabL[v], space[v])
        return mx.mean((A - A_tgt) ** 2)

    theta = mx.zeros((9,))
    gfn = mx.value_and_grad(loss_fn)
    traj = []
    for _ in range(steps):
        loss, g = gfn(theta)
        theta = theta - lr * g
        mx.eval(theta, loss)
        traj.append(float(loss))
    return np.array(theta), traj


def _self_test():
    if not _HAVE_MLX:
        print("full_matrix_train: SKIP (MLX not importable)")
        return

    # A floor cell (no detail) + a held target carrying chroma detail in the paint-expressible span.
    floor = [(20000, 0, 0, 0, 0, 0), (20000, 0, 0, 1, 0, 0), (20000, 0, 0, 0, 1, 0), (20000, 0, 0, 1, 1, 0),
             (20000, 0, 0, 0, 0, 1), (20000, 0, 0, 1, 0, 1), (20000, 0, 0, 0, 1, 1), (20000, 0, 0, 1, 1, 1)]
    # target: add an 'a' residual that grows with x (the (a,x) channel, index 3). True theta[3] ~ 3000.
    target = [(L, a + 3000 * x, b, x, y, t) for (L, a, b, x, y, t) in floor]
    budget = [0, 0, 0, 5, 0, 0, 0, 0, 0]        # paint ONLY the (a,x) channel

    # (1) lawNeutralNudgeIsAllFloor: a NEUTRAL nudge yields EXACTLY the floor, for any theta.
    neutral_out = condition_cell(floor, [0] * 9, [9.9] * 9, gauge=False)
    assert neutral_out == floor, "neutral nudge must reproduce the floor exactly"

    # (2) mi_nudge is READ: nonzero paint with nonzero theta moves the cell off the floor.
    painted = condition_cell(floor, budget, [0, 0, 0, 600, 0, 0, 0, 0, 0], gauge=False)
    assert painted != floor, "a painted nudge must condition the output (mi_nudge is read)"
    # (3) mi_gauge is READ: the dual pairing changes the conditioned output.
    painted_dual = condition_cell(floor, budget, [0, 0, 0, 600, 0, 0, 0, 0, 0], gauge=True)
    assert painted_dual != painted, "mi_gauge must change the invention (the phi6 dual pairing)"

    # (4) END-TO-END (gap 4): train theta -> the cell loss BEATS the deterministic floor baseline.
    base = floor_cell_baseline(floor, target)
    theta, traj = train_cell(floor, target, budget, gauge=False, steps=400, lr=2e-3)
    trained = condition_cell(floor, budget, theta, gauge=False)
    held = cell_loss(trained, target)
    assert traj[-1] < traj[0], f"training must descend ({traj[0]:.1f} -> {traj[-1]:.1f})"
    assert held < base, f"the trained nudge-conditioned head must BEAT the floor: held={held} vs floor={base}"

    # the trained invention survives the commit AND beats the floor -> honest LEARNING verdict.
    deltas = [(t[i] - f[i]) / 65536.0 for t, f in zip(trained, floor) for i in range(3)]
    m = cell_margin(trained, target, floor)
    verdict = dashboard_verdict(m, surviving_fraction(deltas), collapsed=False, diverged=False)
    assert verdict == "LEARNING", f"a TRAINED head that beats the floor + emits surviving detail = LEARNING (got {verdict})"

    # (5) gap 3: the held corpus is consumable -- convert a scale example to a cell the train step accepts.
    from heldout_corpus import scale_examples
    ex = next(iter(scale_examples(0, "high-lab")))
    cube = ex["cube"]                                   # 8 L-values of a 2x2x2 octant
    coords = [(x, y, t) for t in (0, 1) for y in (0, 1) for x in (0, 1)]
    corpus_floor = [(int(np.mean(cube)), 0, 0, x, y, t) for (x, y, t) in coords]   # coarse = the DC mean
    corpus_target = [(int(L), 0, 0, x, y, t) for L, (x, y, t) in zip(cube, coords)]  # held = the real detail
    _, ctraj = train_cell(corpus_floor, corpus_target, [3, 0, 0, 0, 0, 0, 0, 0, 0], steps=20, lr=1e-3)
    assert np.isfinite(ctraj[-1]), "the train step must accept a held-corpus-derived cell"

    print(f"full_matrix_train: nudge conditioning + end-to-end train OK -- neutral=floor, paint+gauge READ, "
          f"trained head BEATS floor (held={held} < floor={base}, verdict=LEARNING), held corpus consumed.")


if __name__ == "__main__":
    _self_test()
