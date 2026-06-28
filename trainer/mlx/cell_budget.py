"""The paint / conditioning input: Spec.CellNudge.CellBudget (the miNudge of Spec.ModelIO.ModelInput).

A per-cell NINE-channel budget over the 16^3 COARSE control grid (the surface the user paints, NOT the
256^3 they cannot see). One painted 16^3 cell governs its (256/16)^3 = 4096-leaf 256^3 subtree. The zero
field is the byte-exact floor (lawNeutralNudgeIsAllFloor); painting is local and clamped (paintCellPair).

Byte-exact twin of the DATA-STRUCTURE of spec/src/SixFour/Spec/CellNudge.hs. The self-test reproduces its
STRUCTURAL/dimensional laws (lawNineChannelsAtCell, lawZeroCellBudgetIsFloor, lawPaintOnePairIsLocal,
lawCellGovernsSuperResSubtree). It does NOT reproduce the three rank/honesty THEOREM-laws the spec module
delegates to NudgeRankTheorem (lawNineHonestAtCell, lawLossIsCellAggregate, lawGaugeExplicit) -- those are
proven Haskell-side and exercised by the trainer through cell_loss.py (the cell-aggregate objective).
"""
from __future__ import annotations

N_PAIRS = 9                              # the nine ChannelProduct pairs (L:t,L:x,L:y,a:x,a:y,a:t,b:x,b:y,b:t)
CONTROL_GRID_SIDE = 16                   # the coarse grid the user paints (64^3 analysed down two octant levels)
SUPER_RES_SIDE = 256                     # the invented output side (two twiceness rungs: 16 -> 64 -> 256)
CELL_SUBTREE_LEAVES = (SUPER_RES_SIDE // CONTROL_GRID_SIDE) ** 3   # (256/16)^3 = 4096
N_CELLS = CONTROL_GRID_SIDE ** 3         # 4096 cells in the 16^3 control grid


def empty_cell_budget(n_cells: int):
    """Spec.CellNudge.emptyCellBudget: every channel zero everywhere (the byte-exact floor)."""
    return [[0] * N_PAIRS for _ in range(n_cells)]


def neutral_nudge(n_cells: int):
    """Spec.ModelIO.neutralNudge = emptyCellBudget: the unpainted input that builds exactly buildFloor."""
    return empty_cell_budget(n_cells)


def paint_cell_pair(budget, c: int, p: int, v: int):
    """Spec.CellNudge.paintCellPair: set only (cell c, pair p) to max(0, v); everything else unchanged."""
    out = [list(row) for row in budget]
    if 0 <= c < len(out) and 0 <= p < N_PAIRS:
        out[c][p] = max(0, v)
    return out


def _self_test():
    # lawNineChannelsAtCell: a cell exposes exactly 9 paint channels.
    assert N_PAIRS == 9

    # lawCellGovernsSuperResSubtree (dimensional identity): (256/16)^3 = 4096 = twicenessSpan^2.
    assert CELL_SUBTREE_LEAVES == 4096
    assert CELL_SUBTREE_LEAVES == (SUPER_RES_SIDE // CONTROL_GRID_SIDE) ** 3
    assert CONTROL_GRID_SIDE * 16 == SUPER_RES_SIDE

    # lawZeroCellBudgetIsFloor: an empty budget paints no channel in any cell.
    for n in (0, 1, 4, 99):
        b = empty_cell_budget(n)
        assert all(all(v == 0 for v in row) for row in b)

    # lawPaintOnePairIsLocal: exactly one (cell, pair) entry changes.
    b = paint_cell_pair(empty_cell_budget(4), 1, 3, 7)
    assert b[1][3] == 7 and sum(sum(row) for row in b) == 7

    # clamp: negative paint clamps to 0.
    b2 = paint_cell_pair(empty_cell_budget(4), 0, 0, -5)
    assert b2[0][0] == 0

    print(f"cell_budget: CellNudge laws OK (9 channels, 16^3 grid, {CELL_SUBTREE_LEAVES}-leaf subtree, "
          f"local paint, zero=floor)")


if __name__ == "__main__":
    _self_test()
