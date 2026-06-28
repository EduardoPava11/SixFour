"""Phase 4 — the loss measured against the DETERMINISTIC floor, not a zero baseline.

The cell-aggregate objective (cell_loss.py = Spec.MatrixTarget.cellLoss) is already correct and primary.
The two alignments here are surgical:

  * floor_cell_baseline: the "above-floor" reference is the cell-aggregate loss of the DETERMINISTIC
    buildFloor (upscale256), NOT 0.5*mean(target^2). So a learned head that merely reproduces the floor
    scores margin = 0, and only genuinely-invented detail scores margin > 0.
  * float<->byte cross-check: the float (MLX-trainable) cell aggregate must agree with the byte-exact
    integer cell_loss.cell_aggregate on integer cells, so the trained loss and the byte-exact JUDGE never
    diverge (lawHeldOutLossIsCellAggregateNotPerVoxel stays the thing optimized).

Reuses cell_loss.py (gated vs Spec.MatrixTarget). The L_band demotion (--w-band 0.0) lives in the new
trainer's composite (Phase 3); this module supplies the floor-aligned numbers it reports.
"""
from __future__ import annotations

import os
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from cell_loss import cell_aggregate, cell_loss, color_vec, space_vec  # noqa: E402


def float_cell_aggregate(cell):
    """The cell aggregate A = sum_v colorVec(v) (x) spaceVec(v) in float (the trainable twin)."""
    acc = np.zeros((3, 3), dtype=np.float64)
    for p in cell:
        c = np.array(color_vec(p), dtype=np.float64)
        s = np.array(space_vec(p), dtype=np.float64)
        acc += np.outer(c, s)
    return acc


def held_cell_loss(pred_cell, target_cell) -> int:
    """The held-out objective: byte-exact cell-aggregate squared error (Spec.MatrixTarget.cellLoss)."""
    return cell_loss(pred_cell, target_cell)


def floor_cell_baseline(floor_cell, target_cell) -> int:
    """The REAL floor reference: the cell-aggregate loss of the deterministic buildFloor vs the target.

    A learned head must beat THIS, not a zero baseline. floor_cell is the cell extracted from
    build_floor (upscale256); target_cell is the data-manufactured held target.
    """
    return cell_loss(floor_cell, target_cell)


def _self_test():
    # A small synthetic cell: 3 voxels (L,a,b,x,y,t). (matches test_cell_loss-style fixtures.)
    target = [(0, 2, 0, 1, 0, 0), (0, 0, 1, 0, 1, 0), (1, 0, 0, 0, 0, 1)]
    floor = [(0, 0, 0, 1, 0, 0), (0, 0, 0, 0, 1, 0), (0, 0, 0, 0, 0, 1)]   # a flat (zero-detail) floor
    good = [(0, 2, 0, 1, 0, 0), (0, 0, 1, 0, 1, 0), (1, 0, 0, 0, 0, 1)]    # exactly the target

    # CROSS-CHECK: the float aggregate agrees with the byte-exact integer aggregate on integer cells.
    for cell in (target, floor, good):
        fi = np.array(cell_aggregate(cell), dtype=np.float64)
        ff = float_cell_aggregate(cell)
        assert np.array_equal(fi, ff), f"float<->byte cell-aggregate drift on {cell}"

    # FLOOR BASELINE is the real floor, not zero: a flat floor incurs positive loss against a real target.
    base = floor_cell_baseline(floor, target)
    assert base > 0, "the deterministic floor must incur positive loss against a non-floor target"

    # A head reproducing the target beats the floor (margin > 0); reproducing the floor does not.
    assert held_cell_loss(good, target) == 0, "a perfect head has zero held loss"
    assert held_cell_loss(floor, target) == base, "reproducing the floor scores exactly the floor baseline"
    assert held_cell_loss(good, target) < base, "an inventing head beats the floor (margin > 0)"

    print(f"full_matrix_loss: floor-aligned cell loss OK (float==byte aggregate; floor baseline={base}, "
          f"reproduced-floor margin=0, perfect-head margin={base})")


if __name__ == "__main__":
    _self_test()
