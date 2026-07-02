"""Soft-histogram conditioning probe — does the 10-bit face help invent detail?

THE QUESTION (owner, 2026-07-02): we hold the 10-bit sensor data as the V2.1
soft-splat histogram (`accumulateHistSoft`: 6-bit level + 4-bit sub-LSB splat
mass, first-moment-exact). Should a net collapsing 2x2x2 -> 1 + LATENT colour
condition on it? The lift itself stays frozen (bijective; the supervision
manufacturer; the collapse-proof target) -- the open question is only whether
the histogram + coarse context CONDITION the up-rung inventor better than the
coarse value alone.

THE ARMS (same MLP harness, same held-capture split as context_super_res):
  V   value-only        phi(v) per channel               (6 feats)  == theta_up's world
  C   + coarse context  the 5x5 window                   (75)       == context_super_res
  H   + soft histogram  order-invariant moments of the    (15)
      octant's own samples, computed FROM a faithfully
      simulated 64-bin soft-splat histogram (w=16, the
      10-bit face) -- permutation-invariant, so it can
      carry detail MAGNITUDE but structurally CANNOT
      leak sign/arrangement (device-honest input).
  CH  context + histogram                                 (84)

EXPECTED SHAPE if the theory holds: H adds magnitude information C lacks and
vice versa (C orients, H sizes), so CH > C > H > V on held cell loss. FLOORED
on any arm stays a legitimate, honest outcome (the corpus lesson).

Held split = a DIFFERENT capture seed: a generalisation test, not a fit test.
"""
from __future__ import annotations

import os
import sys

import numpy as np

try:
    import mlx.core as mx  # noqa: F401
    _HAVE_MLX = True
except Exception:
    _HAVE_MLX = False

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))

from jepa_synth_octants import lab_volume                              # noqa: E402
from context_super_res import train_mlp, _measure, COORDS, Q, RADIUS, K  # noqa: E402

# The simulated device face: 64 levels x 16 sub-steps = 10 bits, splat mass w.
LEVELS = 64
W_SUB = 16


def _soft_hist(vals01):
    """The `accumulateHistSoft` face over one octant's samples of ONE channel.

    vals01 in [0,1] -> hi in 0..(LEVELS-1)*W_SUB (10-bit positions); each sample
    splats integer mass W_SUB across the two adjacent levels ((w - hi%w) at
    hi//w, hi%w at hi//w + 1) -- a partition of unity whose mass-weighted mean
    is EXACTLY hi (lawSoftSplatCentroidExact).
    """
    bins = np.zeros(LEVELS, dtype=np.int64)
    hi = np.clip(np.round(vals01 * (LEVELS - 1) * W_SUB), 0, (LEVELS - 1) * W_SUB).astype(np.int64)
    lev, sub = hi // W_SUB, hi % W_SUB
    for l, s in zip(lev, sub):
        bins[l] += W_SUB - s
        if s and l + 1 < LEVELS:
            bins[l + 1] += s
    return bins


def _hist_moments(bins):
    """Order-invariant moments a 64-bin soft histogram carries: (std, span, skew).

    All computed from bin masses only -- exactly what the device face holds; the
    sub-LSB splat is what makes them accurate beyond the 6-bit level grid.
    """
    mass = bins.sum()
    if mass == 0:
        return 0.0, 0.0, 0.0
    centers = np.arange(LEVELS, dtype=np.float64) / (LEVELS - 1)
    p = bins / mass
    mean = float(p @ centers)
    var = float(p @ (centers - mean) ** 2)
    std = np.sqrt(var)
    nz = np.nonzero(bins)[0]
    span = float(centers[nz[-1]] - centers[nz[0]]) if len(nz) else 0.0
    skew = float(p @ (centers - mean) ** 3) / (std ** 3 + 1e-12)
    return std, span, np.tanh(skew)   # tanh: bound the ratio's tail


# Fixed per-channel affine onto [0,1] (L unsigned, a/b signed) -- the probe's
# stand-in for the device's level mapping.
_CH_LO = np.array([0.0, -32768.0, -32768.0])
_CH_SPAN = np.array([65536.0, 65536.0, 65536.0])


def _octants_all_arms(seed, kind, frame_step=8):
    """Yield (featV, featC, featH, featCH, floor_cell, target_cell) per octant."""
    vol = lab_volume(seed, kind)                  # (F, 64, 64, 3) Q16 OKLab
    F, S, _, _ = vol.shape
    G = S // 2
    for f in range(0, F - 1, frame_step):
        pair = vol[f:f + 2].astype(np.float64)
        coarse = pair.reshape(2, G, 2, G, 2, 3).mean(axis=(0, 2, 4))   # (G,G,3)
        for gr in range(G):
            for gc in range(G):
                win = np.zeros((K, K, 3), dtype=np.float64)
                for dr in range(-RADIUS, RADIUS + 1):
                    for dc in range(-RADIUS, RADIUS + 1):
                        rr, cc = gr + dr, gc + dc
                        if 0 <= rr < G and 0 <= cc < G:
                            win[dr + RADIUS, dc + RADIUS] = coarse[rr, cc] / Q
                featC = win.reshape(-1)                                 # (75,)

                cm = coarse[gr, gc]
                v = cm / Q
                featV = np.concatenate([v, v * v])                      # (6,)

                # The octant's 8 samples -> per-channel soft histogram -> moments.
                r0, c0 = 2 * gr, 2 * gc
                samples = pair[:, r0:r0 + 2, c0:c0 + 2, :].reshape(8, 3)
                hstats = []
                for ch in range(3):
                    x01 = (samples[:, ch] - _CH_LO[ch]) / _CH_SPAN[ch]
                    hstats.extend(_hist_moments(_soft_hist(np.clip(x01, 0, 1))))
                featH = np.concatenate([featV, np.array(hstats)])       # (15,)
                featCH = np.concatenate([featC, np.array(hstats)])      # (84,)

                target = []
                for i, (x, y, t) in enumerate(COORDS):
                    vx = pair[t, r0 + y, c0 + x]
                    target.append((int(vx[0]), int(vx[1]), int(vx[2]), x, y, t))
                floor = [(int(cm[0]), int(cm[1]), int(cm[2]), x, y, t) for (x, y, t) in COORDS]
                yield featV, featC, featH, featCH, floor, target


def _gather_arms(kinds, seeds, frame_step=8):
    rows = []
    for s in seeds:
        for k in kinds:
            rows.extend(_octants_all_arms(s, k, frame_step))
    return rows


def run(train_kinds=("high-lab", "high-detail", "high-lab-detail"), held_kind="high-lab",
        train_seeds=(0, 1), held_seed=7, steps=400, lr=0.01):
    if not _HAVE_MLX:
        print("soft_hist_probe: SKIP (MLX not importable)")
        return None
    rows_tr = _gather_arms(train_kinds, train_seeds)
    rows_he = _gather_arms((held_kind,), (held_seed,))
    arms = {"V": 0, "C": 1, "H": 2, "CH": 3}
    results = {}
    print(f"soft_hist_probe: train {len(rows_tr)} / held {len(rows_he)} octants; "
          f"held = seed {held_seed} (a different capture)")
    for name, ix in arms.items():
        train = [(r[ix], r[4], r[5]) for r in rows_tr]
        held = [(r[ix], r[4], r[5]) for r in rows_he]
        predict, traj = train_mlp(train, steps=steps, lr=lr)
        r = _measure(predict, held)
        r["dims"] = len(rows_tr[0][ix])
        r["drop"] = 100 * (1 - traj[-1] / traj[0]) if np.isfinite(traj[-1]) else float("nan")
        results[name] = r
        print(f"  arm {name:>2} ({r['dims']:>2} feats): train drop {r['drop']:.0f}%  "
              f"held {r['held']:.0f} vs floor {r['floor']:.0f}  margin {r['margin']:.0f}  "
              f"beats {r['beats']}/{r['n']} ({100 * r['beats'] // r['n']}%)  ==> {r['verdict']}")

    mV, mC, mH, mCH = (results[k]["margin"] for k in ("V", "C", "H", "CH"))
    print("\n  READ: margins  V={:.0f}  C={:.0f}  H={:.0f}  CH={:.0f}".format(mV, mC, mH, mCH))
    print(f"  histogram over value-only : {'+' if mH > mV else ''}{mH - mV:.0f}")
    print(f"  histogram over context    : {'+' if mCH > mC else ''}{mCH - mC:.0f}")
    verdict = ("CONDITION-ON-HIST" if (mH > mV and mCH > mC and results["CH"]["beats"] > results["C"]["beats"])
               else "HIST-HELPS-ALONE-ONLY" if mH > mV
               else "NO-GAIN")
    print(f"  ==> {verdict}")
    results["probe_verdict"] = verdict
    return results


if __name__ == "__main__":
    if "--scenes" in sys.argv:
        run(train_kinds=("scene-mixed", "scene-edge", "scene-blob"), held_kind="scene-mixed",
            train_seeds=(0, 1), held_seed=7,
            steps=int(os.environ.get("STEPS", "1200")), lr=float(os.environ.get("LR", "0.03")))
    else:
        run(steps=int(os.environ.get("STEPS", "400")), lr=float(os.environ.get("LR", "0.01")))
