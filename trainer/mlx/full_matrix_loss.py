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


def cell_from_output(out, f0: int, side_out: int, y0: int, x0: int):
    """Extract a 2x2x2 P6 cell (8 voxels = (L,a,b,x,y,t)) from a ModelOutput (or buildFloor output).

    Two consecutive frames x a 2x2 spatial block: (L,a,b) = palette[index] at each voxel; (x,y,t) the
    octant coords. This is what pipes upscale256 output -> floor_cell -> floor_cell_baseline / held loss,
    so the cell loss is computed on REAL deterministic-floor pixels, not a hand-built cell.
    """
    voxels = []
    for t in (0, 1):
        f = f0 + t
        pal, plane = out["palettes"][f], out["cube"][f]
        for dy in (0, 1):
            for dx in (0, 1):
                px = (y0 + dy) * side_out + (x0 + dx)
                L, a, b = pal[plane[px]]
                voxels.append((L, a, b, dx, dy, t))
    return voxels


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

    # END-TO-END on the REAL deterministic floor: pipe upscale256 -> cell_from_output -> floor baseline,
    # so the baseline is the actual buildFloor, not a hand-built cell (addresses the review's P0 gap).
    from model_io import ModelInput, build_floor, capture_to_upscale_input
    from cell_budget import neutral_nudge, N_CELLS
    pal = [[(0, 0, 0), (40000, 5000, -3000), (65000, 0, 0)],
           [(4096, 0, 0), (38000, 4000, -2000), (60000, 1000, 500)]]
    idx = [[0, 1, 2, 1], [1, 2, 0, 2]]
    mi = ModelInput(mi_capture=capture_to_upscale_input(pal, idx, side=2),
                    mi_nudge=neutral_nudge(N_CELLS), mi_gauge=False)
    floor_out = build_floor(mi)
    side_out = 4 * 2
    real_floor_cell = cell_from_output(floor_out, f0=0, side_out=side_out, y0=0, x0=0)
    # a target that carries detail the flat-ish floor lacks: perturb each voxel's chroma off the floor.
    real_target = [(L, a + 3000, b - 3000, x, y, t) for (L, a, b, x, y, t) in real_floor_cell]
    real_base = floor_cell_baseline(real_floor_cell, real_target)
    assert real_base > 0, "the REAL deterministic floor must incur positive loss against a detailed target"
    assert held_cell_loss(real_target, real_target) == 0 and held_cell_loss(real_target, real_target) < real_base

    print(f"full_matrix_loss: floor-aligned cell loss OK (float==byte aggregate; hand floor baseline={base}; "
          f"REAL buildFloor cell baseline={real_base} piped from upscale256; perfect-head beats both)")


if __name__ == "__main__":
    _self_test()
