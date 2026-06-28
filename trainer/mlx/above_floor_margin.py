"""Phase 5 — the ACCEPTANCE NUMBER that discharges the contract markers.

Spec.AboveFloorMargin proves IN PRINCIPLE that a 1-Q16-LSB invention survives the commit and moves the
output off the floor (lawAboveFloorMarginReachable, marginCoeffQ16=1, marginCoeffLatent=1/65536). This
module is the EMPIRICAL measurement the spec law lawAboveFloorMarginMeasured (ContractOnly) points at:
it turns the two `()` markers (contractDescentOnRealDataUnproven / contractEmpiricalSoundnessUnproven)
into measured numbers.

Two numbers, BOTH required for a pass:
  1. surviving_fraction: the fraction of the model's emitted latent detail coefficients that survive the
     Q16 commit (|quantize_q16(x)| >= marginCoeffQ16 = 1). If ~0, invented detail is snapped back to the
     floor and the up-rung learned nothing visible -- the real empirical risk.
  2. cell margin vs the DETERMINISTIC buildFloor (full_matrix_loss.floor_cell_baseline). The cell
     aggregate is MEAN-DOMINATED, so a positive cell margin alone can hide a FLOORED super-res detail;
     requiring (1) as well is the guard against declaring victory on the mean.

The verdict cannot pass while COLLAPSE or DIVERGED. NO training is run here; this is the harness the
trainer reports through.
"""
from __future__ import annotations

import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from q16 import quantize_q16, to_q16                 # noqa: E402
from full_matrix_loss import held_cell_loss, floor_cell_baseline  # noqa: E402

MARGIN_COEFF_Q16 = 1                                 # Spec.AboveFloorMargin.marginCoeffQ16
MARGIN_COEFF_LATENT = to_q16(1)                      # = 1/65536, the latent threshold a coeff must exceed


def survives_commit(x: float) -> bool:
    """A latent detail coefficient survives the Q16 commit iff it quantizes to a non-zero integer
    (|x| >= 1/2 LSB rounds to >= marginCoeffQ16). A half-LSB floors to 0 (absorbed)."""
    return quantize_q16(x) != 0


def surviving_fraction(coeffs) -> float:
    """Fraction of emitted detail coefficients that survive the commit (above the floor margin)."""
    coeffs = list(coeffs)
    if not coeffs:
        return 0.0
    return sum(1 for x in coeffs if survives_commit(x)) / len(coeffs)


def cell_margin(pred_cell, target_cell, floor_cell):
    """The held cell-aggregate margin ABOVE the deterministic floor. Returns a dict of measured numbers."""
    held = held_cell_loss(pred_cell, target_cell)
    floor = floor_cell_baseline(floor_cell, target_cell)
    return {"held": held, "floor": floor, "margin": floor - held,
            "beats_floor": held < floor * 0.98}      # 2% below the floor = genuine LEARNING


def dashboard_verdict(margin, frac, *, collapsed: bool, diverged: bool):
    """The acceptance verdict. PASS requires BOTH numbers AND the guards held.

    - DIVERGED / COLLAPSE block a pass outright (no margin can be trusted).
    - beats_floor (cell margin > 0 vs the REAL floor) is necessary but NOT sufficient (mean-dominated).
    - surviving_fraction > 0 is REQUIRED: invented detail must actually survive the Q16 snap.
    """
    if diverged:
        return "DIVERGED"
    if collapsed:
        return "COLLAPSE"
    if not margin["beats_floor"]:
        return "FLOORED"            # learned head did not beat the deterministic floor
    if frac <= 0.0:
        return "MEAN-ONLY"          # beat the floor on the mean but no detail survived the commit
    return "LEARNING"               # beats the floor AND invented detail survives the commit


def _self_test():
    # survives_commit: a half-LSB floors to 0; one LSB survives.
    assert not survives_commit(MARGIN_COEFF_LATENT / 2), "half-LSB must be absorbed by the commit"
    assert survives_commit(MARGIN_COEFF_LATENT), "one LSB must survive the commit"
    assert survives_commit(-MARGIN_COEFF_LATENT), "negative one LSB must survive (magnitude)"

    # surviving_fraction over a mix: 2 of 4 survive.
    frac = surviving_fraction([MARGIN_COEFF_LATENT, MARGIN_COEFF_LATENT / 4, 0.0, -MARGIN_COEFF_LATENT])
    assert abs(frac - 0.5) < 1e-12, f"surviving fraction must be 0.5, got {frac}"

    target = [(0, 2, 0, 1, 0, 0), (0, 0, 1, 0, 1, 0), (1, 0, 0, 0, 0, 1)]
    floor = [(0, 0, 0, 1, 0, 0), (0, 0, 0, 0, 1, 0), (0, 0, 0, 0, 0, 1)]

    # A perfect head that beats the floor AND emits surviving detail -> LEARNING.
    m_good = cell_margin(target, target, floor)
    assert dashboard_verdict(m_good, 0.5, collapsed=False, diverged=False) == "LEARNING"

    # Beat the floor on the mean but NO detail survives -> MEAN-ONLY (the mean-dominance guard fires).
    assert dashboard_verdict(m_good, 0.0, collapsed=False, diverged=False) == "MEAN-ONLY"

    # Reproducing the floor -> FLOORED.
    m_floor = cell_margin(floor, target, floor)
    assert dashboard_verdict(m_floor, 0.9, collapsed=False, diverged=False) == "FLOORED"

    # Guards block a pass regardless of margin.
    assert dashboard_verdict(m_good, 0.9, collapsed=True, diverged=False) == "COLLAPSE"
    assert dashboard_verdict(m_good, 0.9, collapsed=False, diverged=True) == "DIVERGED"

    print(f"above_floor_margin: acceptance harness OK (marginCoeffLatent={MARGIN_COEFF_LATENT}; "
          f"survives/fraction/cell-margin + mean-dominance guard + collapse/diverge blocks). "
          f"CONTRACT-ONLY: the real number is produced by a TRAINED model, which does not yet exist.")


if __name__ == "__main__":
    _self_test()
