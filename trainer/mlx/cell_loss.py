"""Byte-exact twin of Spec.MatrixTarget.cellLoss + Spec.NudgeRankTheorem.cellAggregate.

THE HELD-OUT OBJECTIVE the trainer trains AND judges on. The spec proves
(NudgeRankTheorem.lawHeldOutLossIsCellAggregateNotPerVoxel, delegated by
MatrixTarget.lawCellLossIsAggregateNotPerVoxel) that the honest held-out loss is the
squared error on the CELL-AGGREGATE comparison matrix

    A = Σ_v  colorVec(v) ⊗ spaceVec(v) = C · Sᵀ      (NudgeRankTheorem.cellAggregate)
    cellLoss predCell tgtCell = aggSqLoss (A pred) (A tgt)   (MatrixTarget.cellLoss)

NOT a per-voxel sum (rank-1, per-voxel-blind) and NOT the L-row band loss (chroma-blind).
The aggregate is rank ≤ 3 and REACHES rank 3, so the off-diagonal chroma×space cells are
independently addressable AT THE CELL -- the value-head reconstruction AND the chroma
coupling both live in it, so it is simultaneously learnable and generalizable.

A P6 voxel is (L, a, b, x, y, t) (the Haskell `P6 pL pA pB pX pY pT`, DualCube.hs:44):

    colorVec p = [a, b, L]   -- Chroma = A | B | L      (ChannelProduct.hs:57, colorVal order)
    spaceVec p = [x, y, t]   -- Axis   = X | Y | T      (ChannelProduct.hs:61, spaceVal order)

This module is INTEGER (the spec is Integer/P6). The MLX trainer keeps the gradient in float
and only the COMMITTED colours re-enter Q16 (q16.quantize_q16), the same float-train /
byte-commit split the band path uses -- an MLX float never decides a committed byte.

THE SPEC GOLDEN is gated here byte-exact: the concrete integer witnesses pinned inside the
QuickCheck'd spec laws (lawSingleVoxelRank1, lawCellAggregateReachesRank3,
lawHeldOutLossIsCellAggregateNotPerVoxel, lawMatrixLossSeesOffDiagonal) are reproduced
exactly by this port. If the port drifts from the spec by one integer, the self-check fails.

Run `python3 trainer/mlx/cell_loss.py` to self-check.
"""
from __future__ import annotations

# A voxel is a 6-tuple (L, a, b, x, y, t) -- the positional P6 fields.


def color_vec(p) -> list:
    """The colour vector (a, b, L) in Chroma minBound..maxBound order (ChannelProduct.colorVec)."""
    L, a, b, _x, _y, _t = p
    return [a, b, L]


def space_vec(p) -> list:
    """The space vector (x, y, t) in Axis minBound..maxBound order (ChannelProduct.spaceVec)."""
    _L, _a, _b, x, y, t = p
    return [x, y, t]


def outer_i(cs: list, ss: list) -> list:
    """The integer outer product c ⊗ s (one voxel's rank-1 comparison matrix), NudgeRankTheorem.outerI."""
    return [[c * s for s in ss] for c in cs]


def mat_add(a: list, b: list) -> list:
    """Entrywise matrix addition (NudgeRankTheorem.matAddI)."""
    return [[x + y for x, y in zip(ra, rb)] for ra, rb in zip(a, b)]


def cell_aggregate(cell: list) -> list:
    """The cell aggregate A = Σ_v colorVec(v) ⊗ spaceVec(v) (NudgeRankTheorem.cellAggregate)."""
    acc = [[0, 0, 0], [0, 0, 0], [0, 0, 0]]
    for v in cell:
        acc = mat_add(outer_i(color_vec(v), space_vec(v)), acc)
    return acc


def agg_sq_loss(a: list, b: list) -> int:
    """Summed squared error over all 9 aggregate cells (NudgeRankTheorem.aggSqLoss)."""
    return sum((x - y) * (x - y) for ra, rb in zip(a, b) for x, y in zip(ra, rb))


def cell_loss(pred_cell: list, tgt_cell: list) -> int:
    """The honest held-out loss: aggSqLoss on the cell aggregates (MatrixTarget.cellLoss)."""
    return agg_sq_loss(cell_aggregate(pred_cell), cell_aggregate(tgt_cell))


def compare_matrix(p) -> list:
    """The full 3x3 comparison matrix of one voxel = colorVec ⊗ spaceVec (ChannelProduct.compareMatrix)."""
    return outer_i(color_vec(p), space_vec(p))


def matrix_sq_loss(pred_p, tgt_p) -> int:
    """Summed squared error over all 9 cells of a SINGLE voxel matrix (MatrixTarget.matrixSqLoss)."""
    return agg_sq_loss(compare_matrix(pred_p), compare_matrix(tgt_p))


def l_row_loss(pred_p, tgt_p) -> int:
    """The L-anchored loss: squared error on only the L row of comparisons (MatrixTarget.lRowLoss).
    Blind to chroma differences -- the contrast that makes the matrix/cell loss necessary."""
    # The L row is row index 2 of compare_matrix (Chroma order A,B,L -> L is last).
    pr = compare_matrix(pred_p)[2]
    tr = compare_matrix(tgt_p)[2]
    return sum((x - y) * (x - y) for x, y in zip(pr, tr))


def det3(m: list) -> int:
    """The 3x3 determinant (rank-3 witness), NudgeRankTheorem.det3."""
    (a, b, c), (d, e, f), (g, h, i) = m[0], m[1], m[2]
    return a * (e * i - f * h) - b * (d * i - f * g) + c * (d * h - e * g)


def octant_space_matrix(side: int = 2) -> list:
    """The data-fixed (x, y, t) space vectors for the N_VOX = side^3 octant voxels: voxel v sits at
    the 2x2x2 octant-child corner (x = v&1, y = (v>>1)&1, t = (v>>2)&1). These ARE the octant axes
    the spec collapses (NudgeRankTheorem H2 lawOctantAxesAreSpaceTime: liftOct factors as xy-Haar +
    t-Haar). The matrix spans rank 3, so the cell aggregate C·Sᵀ can reach full rank 3."""
    n = side ** 3
    return [[v & 1, (v >> 1) & 1, (v >> 2) & 1] for v in range(n)]


# ===========================================================================
# Self-check: reproduce the QuickCheck'd spec law witnesses byte-exact (the spec golden).
# ===========================================================================
def self_check() -> int:
    fails = 0

    # lawSingleVoxelRank1: compareMatrix (P6 5 1 2 3 4 6) == [[3,4,6],[6,8,12],[15,20,30]] (rank 1).
    v = (5, 1, 2, 3, 4, 6)   # L=5,a=1,b=2,x=3,y=4,t=6
    cm = compare_matrix(v)
    if cm != [[3, 4, 6], [6, 8, 12], [15, 20, 30]]:
        print(f"FAIL: compare_matrix witness drifted: {cm}"); fails += 1
    # rank <= 1: a single voxel matrix is its own outer product (det 0).
    if det3(cm) != 0:
        print(f"FAIL: single-voxel matrix is not rank<=1 (det {det3(cm)})"); fails += 1

    # lawCellAggregateReachesRank3: aggregate of 3 phi6-diagonal voxels == I, det == 1.
    tgt = [(0, 1, 0, 1, 0, 0), (0, 0, 1, 0, 1, 0), (1, 0, 0, 0, 0, 1)]
    aT = cell_aggregate(tgt)
    if aT != [[1, 0, 0], [0, 1, 0], [0, 0, 1]] or det3(aT) != 1:
        print(f"FAIL: cell aggregate != I (got {aT}, det {det3(aT)})"); fails += 1

    # lawHeldOutLossIsCellAggregateNotPerVoxel: a chroma<->space MISPAIRED prediction is invisible
    # per-voxel (each voxel still rank-1) but the AGGREGATE loss sees it == 4.
    pred = [(0, 1, 0, 0, 1, 0), (0, 0, 1, 1, 0, 0), (1, 0, 0, 0, 0, 1)]
    aP = cell_aggregate(pred)
    if aP != [[0, 1, 0], [1, 0, 0], [0, 0, 1]] or det3(aP) != -1:
        print(f"FAIL: mispaired aggregate witness drifted (got {aP}, det {det3(aP)})"); fails += 1
    if cell_loss(pred, tgt) != 4:
        print(f"FAIL: cellLoss(mispaired, target) != 4 (got {cell_loss(pred, tgt)})"); fails += 1
    # every predicted voxel is itself a valid rank-1 matrix (per-voxel view is blind):
    if any(det3(compare_matrix(p)) != 0 for p in pred):
        print("FAIL: a predicted voxel is not rank-1 (per-voxel blindness witness broken)"); fails += 1
    # cellLoss zero at match (lawCellLossZeroAtMatch):
    if cell_loss(tgt, tgt) != 0:
        print("FAIL: cellLoss(tgt, tgt) != 0"); fails += 1

    # lawMatrixLossSeesOffDiagonal: chroma-only difference is invisible to the L row, visible to the matrix.
    t_p = (5, 1, 2, 3, 4, 6)
    p_p = (5, 9, 8, 3, 4, 6)   # same L,x,y,t; chroma a,b differ
    if l_row_loss(p_p, t_p) != 0:
        print(f"FAIL: lRowLoss should be 0 on a chroma-only diff (got {l_row_loss(p_p, t_p)})"); fails += 1
    # The exact value the Haskell spec computes (verified in `cabal repl sixfour-spec`): 6100.
    if matrix_sq_loss(p_p, t_p) != 6100:
        print(f"FAIL: matrixSqLoss should be 6100 (got {matrix_sq_loss(p_p, t_p)})"); fails += 1

    # octant space matrix spans rank 3 (so C·Sᵀ can reach full rank).
    S = octant_space_matrix(2)
    if len(S) != 8:
        print(f"FAIL: octant space matrix has {len(S)} rows, expected 8"); fails += 1
    # rows (1,0,0),(0,1,0),(0,0,1) are all present -> rank 3.
    if not all(e in S for e in ([1, 0, 0], [0, 1, 0], [0, 0, 1])):
        print("FAIL: octant space matrix does not span rank 3"); fails += 1

    return fails


if __name__ == "__main__":
    n = self_check()
    if n == 0:
        print("  cell_loss: cellAggregate/aggSqLoss/matrixSqLoss reproduce the spec law witnesses byte-exact")
        print("cell_loss: PASS")
        raise SystemExit(0)
    print(f"cell_loss: {n} FAIL")
    raise SystemExit(1)
