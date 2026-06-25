"""Learning test: feed the centered-cube volume's octants to the masked-band predictor and show
the division of labour between COMPRESSION (the reversible lift) and PREDICTION (the learned head):

  * The lift already compresses every CONSTANT octant (cube interior + background) to ZERO detail,
    so the floor (zero-param theta_B) predicts those masked bands EXACTLY -- the loss there is 0.
  * All the signal lives at the cube's SURFACE (mixed octants with nonzero detail). That sparse set
    is the only thing the predictor has to learn, and a trained theta_B beats the floor on held-out
    surface octants -- it learns the boundary structure, not the (already-compressed) flat regions.

This ties the compression result (test_centered_cube.py) to the learned head: smooth -> compressed ->
floor nails it; surface -> real signal -> theta_B learns it. Uses Q16-scale L values (0..65535) so the
predictor operates in its native regime, and an OFF-grid cube so the surface octants are genuinely
mixed (a grid-aligned cube has zero detail everywhere and nothing to learn).
"""
from __future__ import annotations

import os
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
from jepa_data import lift_oct  # noqa: E402

from theta_b import zero_params_b
from jepa_loss import masked_band_loss, masked_band_loss_sum
from masked_band_trainer import train_band_joint_stable

BG, FG = 58000, 2000   # Q16-scale L: high-L background, low-L cube (both clear of the v~->0.9 regime)


def offset_cube_volume(side: int = 64, cube: int = 18, start: int = 23) -> np.ndarray:
    """A side^3 Q16-L volume with a cube placed OFF the 2-voxel grid (odd start), so the boundary
    2x2x2 blocks straddle the cube faces and carry real detail."""
    v = np.full((side, side, side), BG, dtype=np.int64)
    v[start:start+cube, start:start+cube, start:start+cube] = FG
    return v


def octant_records(vol: np.ndarray, mask: int = 0):
    """Every finest-level 2x2x2 octant as a MaskedBandExample (coarse, detail7, mask)."""
    s = vol.shape[0]
    recs = []
    for F in range(s // 2):
        for X in range(s // 2):
            for Y in range(s // 2):
                blk = [int(vol[2*F, 2*X, 2*Y]),   int(vol[2*F, 2*X+1, 2*Y]),
                       int(vol[2*F, 2*X, 2*Y+1]), int(vol[2*F, 2*X+1, 2*Y+1]),
                       int(vol[2*F+1, 2*X, 2*Y]),   int(vol[2*F+1, 2*X+1, 2*Y]),
                       int(vol[2*F+1, 2*X, 2*Y+1]), int(vol[2*F+1, 2*X+1, 2*Y+1])]
                c, d = lift_oct(blk)
                recs.append((c, tuple(d), mask))
    return recs


if __name__ == "__main__":
    fails = 0
    vol = offset_cube_volume()
    recs = octant_records(vol, mask=0)

    # split by whether the MASKED target (band 0) is zero: smooth (floor nails it) vs surface (signal)
    smooth = [r for r in recs if r[1][r[2]] == 0]
    surface = [r for r in recs if r[1][r[2]] != 0]
    print(f"--- 64^3 cube ({len(recs)} octants), masked band 0 ---")
    print(f"  smooth octants (masked target == 0): {len(smooth)}  ({100*len(smooth)/len(recs):.1f}%)")
    print(f"  surface octants (masked target != 0): {len(surface)}")

    # the floor predicts the smooth octants EXACTLY (compression already did the work)
    floor = zero_params_b()
    floor_smooth = masked_band_loss_sum(floor, smooth)
    print(f"  floor loss on smooth octants: {floor_smooth:.3g}  "
          f"{'(ZERO -> the lift already compressed them; nothing to predict)' if floor_smooth == 0 else '(NONZERO?!)'}")
    if floor_smooth != 0:
        print("FAIL: floor does not predict the compressed-flat octants exactly"); fails += 1

    # the predictor LEARNS the surface: trained theta_B beats the floor on held-out surface octants
    np.random.seed(0)
    idx = np.random.permutation(len(surface))
    surf = [surface[i] for i in idx]
    split = int(len(surf) * 0.8)
    train, test = surf[:split], surf[split:]
    floor_test = masked_band_loss_sum(floor, test) / max(1, len(test))
    theta = train_band_joint_stable(1500, train)
    train_after = masked_band_loss_sum(theta, train) / max(1, len(train))
    test_after = masked_band_loss_sum(theta, test) / max(1, len(test))
    print(f"  surface prediction: floor test loss {floor_test:.4g} -> trained {test_after:.4g} "
          f"(train {train_after:.4g}); held-out is {test_after/floor_test:.1%} of floor")
    if not (test_after < floor_test):
        print("FAIL: trained theta_B did not beat the floor on held-out surface octants"); fails += 1
    else:
        print(f"  -> theta_B LEARNS the boundary: held-out surface loss cut to "
              f"{test_after/floor_test:.0%} of the floor (it predicts the masked edge band from context)")

    print("\ntest_cube_learning: PASS" if fails == 0 else f"\ntest_cube_learning: {fails} FAIL")
    raise SystemExit(1 if fails else 0)
