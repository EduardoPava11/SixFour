"""The super-res head: the up-rung that invents 256^3 detail, the twin of
spec/SixFour/Spec/DetailPredictor.hs reused per RungPivot (Down=Held / Up=Invented).

The learned object is f_theta : coarse -> detail (NOT the encoder, which is frozen). f is
21 params (7 bands x [1, v~, v~^2]), trained on the SUPERVISED down-rung where real detail
exists, then REUSED on the unsupervised up-rung to INVENT 256^3 detail the 64^3 capture lacks
(lawReusesOnBothRungs / lawDownIsHeldUpIsInvented).

  zeroParams == the floor (predict_detail returns 0 for every coarse -> the upsample we show today).
  trained theta -> nonzero invented detail.

Honest caveat measured below: coarse-only f learns E[detail | coarse] (the conditional mean).
For zero-mean high-frequency detail that mean is ~0, so f invents detail only where the coarse
value genuinely predicts it (edges / structure), and correctly stays near the floor on smooth
regions. Re-downsample consistency is STRUCTURAL: octantSynthesize is the exact inverse of the
distill, so distilling the invented 256^3 back recovers the 64^3 input EXACTLY -- invention adds
high-freq detail without disturbing the coarse.

The forward/synthesize are vectorized in numpy (the lift is linear integer arithmetic); the scalar
predict_detail is kept as the spec twin for the zeroParams==floor law.
"""
from __future__ import annotations

import os
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
from jepa_data import lift_oct  # noqa: E402

from encoder_frozen import NUM_BANDS
from q16 import to_q16, quantize_q16

FEATURE_COUNT_D = 3                            # phi(v) = [1, v~, v~^2]  (DetailPredictor.hs:26)
PARAM_COUNT_D = NUM_BANDS * FEATURE_COUNT_D    # 7 * 3 = 21
Q = 65536


# --- scalar forward (the spec twin, for the law) ---
def predict_detail(theta, coarse: int):
    """f_theta(coarse) -> 7 detail bands (each raw readout re-entered to Q16). zeroParams -> floor."""
    vq = to_q16(coarse)
    phi = (1.0, vq, vq * vq)
    return [quantize_q16(sum(theta[j*FEATURE_COUNT_D + k] * phi[k] for k in range(FEATURE_COUNT_D)))
            for j in range(NUM_BANDS)]


# --- vectorized forward / training / synthesize ---
def _phi_vol(v: np.ndarray) -> np.ndarray:
    vq = v.astype(np.float64) / Q
    return np.stack([np.ones_like(vq), vq, vq * vq], axis=-1)   # (..., 3)


def predict_detail_vol(theta: np.ndarray, v: np.ndarray) -> np.ndarray:
    """f_theta over a whole coarse volume -> (..., 7) integer detail (half-to-even Q16, matches scalar)."""
    raw = _phi_vol(v) @ theta.reshape(NUM_BANDS, FEATURE_COUNT_D).T   # (..., 7) float
    return np.rint(raw * Q).astype(np.int64)


def train_detail(coarse: np.ndarray, detail: np.ndarray, steps: int = 600, eta: float = 0.2) -> np.ndarray:
    """Fit f_theta on (coarse, detail) down-rung pairs (mean-gradient GD, vectorized). Returns (21,)."""
    phi = _phi_vol(coarse)                       # (N, 3)
    t = detail.astype(np.float64) / Q            # (N, 7) Q16-normalised targets
    theta = np.zeros((NUM_BANDS, FEATURE_COUNT_D))
    n = max(1, len(coarse))
    for _ in range(steps):
        err = phi @ theta.T - t                  # (N, 7)
        theta -= eta * (err.T @ phi) / n         # (7, 3)
    return theta.reshape(-1)


def _s_unlift(lo, hi):
    # floor division (toward -inf) matches Python `//` and Haskell `div` for negative detail.
    y = lo - np.floor_divide(hi, 2)
    return y + hi, y


def _unlift_quad(r, g, b, t):
    la, lc = _s_unlift(r, g)
    ha, hc = _s_unlift(b, t)
    a, bb = _s_unlift(la, ha)
    c, d = _s_unlift(lc, hc)
    return a, bb, c, d


def synth_level(coarse: np.ndarray, detail: np.ndarray) -> np.ndarray:
    """Vectorized octree synthesize: coarse (h,h,h) + detail (h,h,h,7) -> (2h,2h,2h) (exact unlift_oct)."""
    g0, b0, t0, g1, b1, t1, dz = (detail[..., k] for k in range(7))
    r0, r1 = _s_unlift(coarse, dz)
    a, b, c, d = _unlift_quad(r0, g0, b0, t0)
    e, f, g, hh = _unlift_quad(r1, g1, b1, t1)
    h = coarse.shape[0]
    fine = np.zeros((2*h, 2*h, 2*h), dtype=np.int64)
    fine[0::2, 0::2, 0::2], fine[0::2, 1::2, 0::2] = a, b
    fine[0::2, 0::2, 1::2], fine[0::2, 1::2, 1::2] = c, d
    fine[1::2, 0::2, 0::2], fine[1::2, 1::2, 0::2] = e, f
    fine[1::2, 0::2, 1::2], fine[1::2, 1::2, 1::2] = g, hh
    return fine


def invent_one_level(coarse_vol: np.ndarray, theta: np.ndarray) -> np.ndarray:
    """Up-rung: predict each voxel's detail with f_theta, synthesize -> 2x finer. theta=0 -> upsample."""
    return synth_level(coarse_vol, predict_detail_vol(theta, coarse_vol))


def upscale_256(vol64: np.ndarray, theta: np.ndarray) -> np.ndarray:
    """64^3 -> 128^3 -> 256^3, inventing detail at each up-rung with the reused f_theta."""
    return invent_one_level(invent_one_level(vol64, theta), theta)


def invented_detail_energy(vol64: np.ndarray, theta: np.ndarray) -> float:
    """Total |invented detail| over the two up-rungs (0 at the floor)."""
    e = 0.0
    v = vol64
    for _ in range(2):
        e += float(np.abs(predict_detail_vol(theta, v)).sum())
        v = invent_one_level(v, theta)
    return e


def octant_pairs(vol: np.ndarray):
    """(coarse (N,), detail (N,7)) for every finest 2x2x2 octant — the down-rung supervised labels."""
    s = vol.shape[0]
    coarse, detail = [], []
    for F in range(s // 2):
        for X in range(s // 2):
            for Y in range(s // 2):
                blk = [int(vol[2*F+df, 2*X+dx, 2*Y+dy])
                       for df in (0, 1) for dx in (0, 1) for dy in (0, 1)]
                c, d = lift_oct(blk)
                coarse.append(c); detail.append(d)
    return np.array(coarse), np.array(detail)


if __name__ == "__main__":
    from test_centered_cube import make_volume, distill
    from jepa_synth_octants import l_volume

    fails = 0
    floor = np.zeros(PARAM_COUNT_D)

    if any(b != 0 for b in predict_detail(floor.tolist(), 40000)):
        print("FAIL: floor predictor invented nonzero detail"); fails += 1
    # vectorized == scalar forward
    if predict_detail_vol(floor, np.array([40000]))[0].tolist() != predict_detail(floor.tolist(), 40000):
        print("FAIL: vectorized forward != scalar"); fails += 1

    for label, vol in [("cube(edges)", make_volume(64, 16)),
                       ("capture(smooth)", l_volume(7, "high-lab"))]:
        c, d = octant_pairs(vol)
        theta = train_detail(c, d)
        floor_e = invented_detail_energy(vol, floor)
        inv_e = invented_detail_energy(vol, theta)
        sr = upscale_256(vol, theta)
        c1, _ = distill(sr); c2, _ = distill(c1)
        consistent = bool(np.array_equal(c2, vol))
        print(f"--- {label}: floor invented-detail={floor_e:.0f}  trained={inv_e:.0f}  "
              f"({'INVENTS detail' if inv_e > floor_e else 'stays at floor'})")
        print(f"    256^3 re-downsamples to the exact 64^3: {consistent}  (consistency is structural)")
        if not consistent:
            print(f"FAIL: super-res broke re-downsample consistency on {label}"); fails += 1

    print("\nsuperres: PASS" if fails == 0 else f"\nsuperres: {fails} FAIL")
    raise SystemExit(1 if fails else 0)
