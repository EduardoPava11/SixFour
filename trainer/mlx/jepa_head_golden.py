"""Force the MLX head trainer to match the spec, byte-exact, against jepa_head_golden.json.

The spec (SixFour.Codegen.JepaHead) emits the head golden: the theta_B training-trajectory
endpoints and single-active-term forward witnesses of the 77-param position head. This loader
is the gate that makes the spec the DESIGN AUTHORITY for the trainer (the same discipline
trainer/jepa_data.py applies to the corpus): if the MLX forward or the trainer drifts from the
spec by one byte, this fails.

Run `python3 trainer/mlx/jepa_head_golden.py` to self-check. Regenerate the golden with
`cd spec && cabal run spec-codegen` after any change to the head spec.
"""
from __future__ import annotations

import json
import os

from theta_b import (
    PARAM_COUNT_B, PARAM_COUNT_B_POS, predict_masked_band_pos, predict_masked_band,
)
from masked_band_trainer import train_band_joint

GOLDEN = os.path.join(os.path.dirname(__file__), "..", "generated", "jepa_head_golden.json")


def load_golden(path: str = GOLDEN):
    with open(path) as fh:
        return json.load(fh)


def _one_hot(n: int, index: int, weight: float) -> list[float]:
    """The single-active-term parameter vector the spec witness uses (no summation order)."""
    ps = [0.0] * n
    ps[index] = weight
    return ps


def self_check(path: str = GOLDEN) -> int:
    g = load_golden(path)

    # shape constants agree with the spec
    assert g["paramCountB"] == PARAM_COUNT_B, f"paramCountB {g['paramCountB']} != {PARAM_COUNT_B}"
    assert g["paramCountBPos"] == PARAM_COUNT_B_POS, \
        f"paramCountBPos {g['paramCountBPos']} != {PARAM_COUNT_B_POS}"

    # forward witnesses: every single-active-term prediction reproduces byte-exact
    n = g["paramCountBPos"]
    for w in g["posForward"]:
        ps = _one_hot(n, w["index"], w["weight"])
        ex = (w["coarse"], tuple(w["detail"]), w["mask"], (w["x"], w["y"]))
        got = predict_masked_band_pos(ps, ex)
        assert got == w["predicted"], \
            f"forward drift [{w['label']}]: {got} != {w['predicted']}"

    # trajectory endpoints: the floor predicts goldenFloorBand; trained predicts goldenTrainedBand
    t = g["trainer"]
    ex = (t["coarse"], tuple(t["detail"]), t["mask"])
    floor_pred = predict_masked_band([0.0] * PARAM_COUNT_B, ex)
    assert floor_pred == t["goldenFloorBand"], \
        f"floor band {floor_pred} != goldenFloorBand {t['goldenFloorBand']}"
    trained = train_band_joint(t["steps"], [ex])
    trained_pred = predict_masked_band(trained, ex)
    assert trained_pred == t["goldenTrainedBand"], \
        f"trained band {trained_pred} != goldenTrainedBand {t['goldenTrainedBand']}"

    return len(g["posForward"])


if __name__ == "__main__":
    try:
        n = self_check()
        print(f"  head golden: {n} forward witnesses + trajectory endpoints reproduce byte-exact")
        print("jepa_head_golden: PASS")
        raise SystemExit(0)
    except AssertionError as e:
        print(f"FAIL: {e}")
        print("jepa_head_golden: FAIL")
        raise SystemExit(1)
