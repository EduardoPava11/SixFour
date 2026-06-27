"""Lock the dashboard VERDICT onto the VALUE (reconstruction) margin, not the band margin.

The model already beats its zero-prediction floor by about +91% on held-out via the
value/reconstruction head, while sitting at/below the band floor (the band target is
rank-1/per-voxel-blind -- Spec.NudgeRankTheorem.cellAggregate +
Spec.MatrixTarget.lawMatrixLossSeesOffDiagonal -- so a band-only metric is provably unbeatable
and mis-reads a genuinely-learning head as FLOORED). This test pins the corrected behaviour:

  1. A head that beats the value floor but is below the band floor reads LEARNING (the exact
     state that was mis-reported FLOORED before the fix).
  2. The COLLAPSE guard still wins over any margin (checked first).
  3. A head that does NOT beat the value floor reads FLOORED/AT FLOOR (no goalpost-moving:
     the verdict still requires real value-head generalization).

These are pure-logic assertions on dashboard_verdict (no MLX, no training run needed).
"""
from __future__ import annotations

import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from train_loop import dashboard_verdict, VIC_GAMMA, VIC_NEURON_SLICE  # noqa: E402

# A modest, uncollapsed VICReg value (well under the 0.5*max collapse threshold).
MAX_VIC = VIC_GAMMA * VIC_NEURON_SLICE
OK_VIC = 0.1 * MAX_VIC


def _held(pal, band, vic=OK_VIC, idx=0.0):
    return {"pal": pal, "band": band, "vic": vic, "idx": idx, "composite": 0.0}


def main() -> int:
    fails = 0
    # The REAL observed numbers from the smoke run (step 200): value floor 0.036769,
    # value held 0.003171 (=> +91.4%); band floor 0.000417, band held 0.000486 (=> -16.6%).
    floor = {"value": 0.036769, "band": 0.000417}
    held = _held(pal=0.003171, band=0.000486)

    verdict, vmargin, bmargin, collapsed, _mv = dashboard_verdict(held, floor)

    # (1) The fix: a value-beating, band-floored head reads LEARNING off the VALUE margin.
    if verdict != "LEARNING":
        print(f"[FAIL] expected LEARNING (value beats floor), got {verdict!r}"); fails += 1
    else:
        print(f"[ ok ] LEARNING via value margin {vmargin:+.1f}% (band margin {bmargin:+.1f}% is diagnostic only)")
    if not (vmargin > 50.0):
        print(f"[FAIL] value margin should be strongly positive, got {vmargin:+.1f}%"); fails += 1
    else:
        print(f"[ ok ] value margin strongly positive ({vmargin:+.1f}%)")
    if not (bmargin < 0.0):
        print(f"[FAIL] band margin should be negative (the blind metric), got {bmargin:+.1f}%"); fails += 1
    else:
        print(f"[ ok ] band margin negative ({bmargin:+.1f}%) -- proves band-only would mis-report FLOORED")

    # (2) COLLAPSE wins over any margin (guard checked first).
    coll_verdict, _, _, coll, _ = dashboard_verdict(_held(pal=0.003171, band=0.000486, vic=0.9 * MAX_VIC), floor)
    if coll_verdict != "COLLAPSE (variance floor tripped)" or not coll:
        print(f"[FAIL] collapse must win over margin, got {coll_verdict!r}"); fails += 1
    else:
        print(f"[ ok ] COLLAPSE guard still fires first regardless of value margin")

    # (3) No goalpost-moving: a head that does NOT beat the value floor is NOT LEARNING.
    fl_verdict, fl_v, _, _, _ = dashboard_verdict(_held(pal=0.05, band=0.000486), floor)
    if fl_verdict == "LEARNING":
        print(f"[FAIL] a head worse than the value floor must not read LEARNING, got {fl_verdict!r}"); fails += 1
    else:
        print(f"[ ok ] value-floor not beaten ({fl_v:+.1f}%) reads {fl_verdict!r}, not LEARNING")

    # (4) DIVERGED guard: a NaN primary (lr/weight too hot) must NOT silently read AT FLOOR/ok.
    # nan>floor*1.02 and nan>collapse-threshold are both False, so without the isfinite guard the
    # dashboard would lie green while the model has blown up (the reproduced w_detail=20 NaN trap).
    nan_verdict, _, _, _, _ = dashboard_verdict(_held(pal=float("nan"), band=float("nan")), floor)
    if not nan_verdict.startswith("DIVERGED"):
        print(f"[FAIL] a NaN primary must read DIVERGED, got {nan_verdict!r}"); fails += 1
    else:
        print(f"[ ok ] NaN primary reads {nan_verdict!r} (does not silently pass as AT FLOOR)")
    # ...and a NaN in the VICReg term alone also diverges (collapse read would be misleading).
    nan_vic, _, _, _, _ = dashboard_verdict(_held(pal=0.003171, band=0.000486, vic=float("nan")), floor)
    if not nan_vic.startswith("DIVERGED"):
        print(f"[FAIL] a NaN vic must read DIVERGED, got {nan_vic!r}"); fails += 1
    else:
        print(f"[ ok ] NaN vic reads {nan_vic!r}")

    print("=== dashboard verdict: all green ===" if fails == 0 else f"=== dashboard verdict: {fails} FAILED ===")
    return 1 if fails else 0


if __name__ == "__main__":
    raise SystemExit(main())
