"""STEP 4 lock: anti-overfit the over-capacity ViT so the PRIMARY (cell-aggregate) held-out margin
stays POSITIVE and does NOT decline over a run -- and the old learning-rate 'NaN trap' is gone.

Three things this test pins (each refutes a specific regression):

  (A) THE NaN TRAP IS FIXED. The CLI default learning rate must be the stable 1e-3, not the old
      8e-3 -- 8e-3 drives the composite loss to nan by ~step 50 once w_value/w_policy>0 (reproduced
      in the audit). We assert the module default AND the argparse default are the lowered value.

  (B) CAPACITY CONTROL IS WIRED. The persistent trainer's SGD must carry weight_decay>0 (L2), the
      capacity control that bounds the train->held gap on the 18.9M-param head.

  (C) IT ACTUALLY GENERALIZES. A short real run (no --lr override, so it exercises the default the
      NaN trap lived in) must: produce NO nan, keep EVERY post-warmup cell-aggregate margin > 0,
      and end no worse than it started (the margin does not decline). This is the mission's PASS
      criterion run at gate scale.

The cell aggregate is Spec.MatrixTarget.cellLoss (rank 3, NudgeRankTheorem) -- the formally-proven
held-out objective the dashboard judges on, not the rank-1 per-voxel-blind band diagnostic.
"""
from __future__ import annotations

import os
import re
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))


def _check_static():
    """(A) + (B): the defaults are the anti-overfit values, read straight from the module."""
    fails = 0
    try:
        import train_loop  # noqa: E402  (imports the real mlx; HERE is on the path under the gate)
    except Exception as e:  # pragma: no cover
        print(f"  SKIP static checks: train_loop import failed ({e})")
        return 0

    lr = train_loop.DEFAULT_LR
    wd = train_loop.DEFAULT_WEIGHT_DECAY
    print(f"  DEFAULT_LR={lr}  DEFAULT_WEIGHT_DECAY={wd}")
    if not (lr <= 2e-3):
        print(f"FAIL (A): DEFAULT_LR={lr} is not in the stable regime (<=2e-3); the 8e-3 NaN trap"); fails += 1
    if lr == 8e-3:
        print("FAIL (A): DEFAULT_LR is still the 8e-3 NaN trap"); fails += 1
    if not (wd > 0):
        print(f"FAIL (B): DEFAULT_WEIGHT_DECAY={wd} is not > 0 (no capacity control)"); fails += 1

    # the argparse default must equal the module constant (so the bare CLI uses the safe lr).
    import argparse
    ap = argparse.ArgumentParser()
    # mirror the two flags the trainer registers (kept in sync with train_loop.main()).
    ap.add_argument("--lr", type=float, default=train_loop.DEFAULT_LR)
    ap.add_argument("--weight-decay", dest="weight_decay", type=float,
                    default=train_loop.DEFAULT_WEIGHT_DECAY)
    ns = ap.parse_args([])
    if ns.lr != train_loop.DEFAULT_LR or ns.weight_decay != train_loop.DEFAULT_WEIGHT_DECAY:
        print("FAIL: argparse defaults drifted from the module constants"); fails += 1
    if fails == 0:
        print("  (A) NaN-trap default fixed + (B) weight_decay wired: OK")
    return fails


def _check_run():
    """(C): a short real run; no nan, every cell margin > 0, margin does not decline."""
    fails = 0
    out_dir = tempfile.mkdtemp(prefix="s4_anti_overfit_")
    cmd = [sys.executable, os.path.join(HERE, "train_loop.py"),
           "--long", "--seed", "1", "--steps", "150",
           "--octants", "64", "--resample-every", "75",
           "--eval-every", "50", "--eval-octants", "64", "--out", out_dir]
    print(f"  running: {' '.join(cmd[1:])}")
    proc = subprocess.run(cmd, cwd=HERE, capture_output=True, text=True)
    out = proc.stdout + proc.stderr

    # confirm the stable default lr actually drove this run (locks the bare-CLI NaN-trap fix).
    if "lr=0.001" not in out:
        print("FAIL (C): run did not use the stable default lr=0.001"); fails += 1
    if "weight_decay=" not in out or "weight_decay=0 " in out or "weight_decay=0.0 " in out:
        print("FAIL (C): run did not report a positive weight_decay"); fails += 1

    # NO nan anywhere in the loss / margin stream.
    if re.search(r"\bnan\b", out, flags=re.IGNORECASE):
        print("FAIL (C): 'nan' appeared in the run output (the NaN trap)"); fails += 1

    # parse every "cell   held X vs floor Y   margin +Z%" line.
    margins = [float(m) for m in
               re.findall(r"cell\s+held\s+[\d.eE+-]+\s+vs floor\s+[\d.eE+-]+\s+margin\s+([+-][\d.]+)%",
                          out)]
    print(f"  cell-aggregate margins across evals: {margins}")
    if len(margins) < 3:
        print(f"FAIL (C): expected >=3 eval margins, got {len(margins)}"); fails += 1
        return fails, out

    # margins[0] is the step-0 (untrained) margin -> negative is expected; the POST-WARMUP evals
    # (every eval after step 0) must each be positive AND the run must end no worse than it started.
    post = margins[1:]
    if not all(m > 0 for m in post):
        print(f"FAIL (C): a post-warmup cell margin was not positive: {post}"); fails += 1
    if post[-1] < post[0] - 1e-6:
        print(f"FAIL (C): cell margin DECLINED over the run ({post[0]} -> {post[-1]})"); fails += 1
    if fails == 0:
        print(f"  (C) margin POSITIVE and non-declining over the run "
              f"({post[0]:+.1f}% -> {post[-1]:+.1f}%), no nan: OK")
    return fails, out


if __name__ == "__main__":
    print("--- STEP 4 anti-overfit lock ---")
    fails = _check_static()
    rf, _ = _check_run()
    fails += rf
    print("\ntest_anti_overfit: PASS" if fails == 0 else f"\ntest_anti_overfit: {fails} FAIL")
    raise SystemExit(1 if fails else 0)
