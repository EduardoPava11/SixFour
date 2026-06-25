"""The masked-band (I-JEPA) objective: loss, exact gradient, SGD step. Twin of the
loss/gradient block in spec/SixFour/Spec/MaskedBandPrediction.hs:235-261.

The loss is half the squared error of the RAW readout against the Q16-normalised
masked target (raw, so the gradient is smooth; the device prediction re-enters Q16
separately):

    L(theta) = 0.5 * (raw_m - t~)^2        where t~ = toQ16(target)

The gradient is exact and sparse: only the masked band's row is nonzero,

    dL/dtheta_{m,k} = (raw_m - t~) * phi_B_k       (every other row is zero)

This analytic gradient is the thing autograd_check.py confirms against MLX's
autodiff (lawMaskedGradientFiniteDiff), proving the hand-derived backprop is correct
before it is trusted at scale.
"""
from __future__ import annotations

from encoder_frozen import NUM_BANDS, FEATURE_COUNT_B, features_b
from theta_b import (
    PARAM_COUNT_B, mbe_coarse, mbe_masked, siblings_of, masked_target_band,
    raw_masked_band,
)
from q16 import to_q16


def masked_band_loss(ps: list[float], ex) -> float:
    """0.5 * (raw - t~)^2 on the Mac-side raw readout."""
    r = raw_masked_band(ps, ex)
    t = to_q16(masked_target_band(ex))
    return 0.5 * (r - t) * (r - t)


def masked_band_loss_sum(ps: list[float], exs) -> float:
    """Summed loss over a batch (used by the keystone law and the joint trainer)."""
    return sum(masked_band_loss(ps, ex) for ex in exs)


def masked_band_gradient(ps: list[float], ex) -> list[float]:
    """Exact gradient of masked_band_loss over all 63 params. Only the masked row is nonzero."""
    m = mbe_masked(ex)
    phi = features_b(mbe_coarse(ex), siblings_of(ex))
    err = raw_masked_band(ps, ex) - to_q16(masked_target_band(ex))
    grad: list[float] = []
    for j in range(NUM_BANDS):
        if j == m:
            grad.extend(err * p for p in phi)
        else:
            grad.extend([0.0] * FEATURE_COUNT_B)
    return grad


def masked_band_update(eta: float, ps: list[float], ex) -> list[float]:
    """One SGD step on a single example: theta <- theta - eta * dL/dtheta."""
    g = masked_band_gradient(ps, ex)
    return [p - eta * gi for p, gi in zip(ps, g)]


def _central_fd(ps: list[float], ex, i: int, hh: float = 1e-6) -> float:
    """Central finite difference of the loss w.r.t. param i (for the gradient gate)."""
    up = ps[:]; up[i] += hh
    dn = ps[:]; dn[i] -= hh
    return (masked_band_loss(up, ex) - masked_band_loss(dn, ex)) / (2 * hh)


if __name__ == "__main__":
    fails = 0
    # a non-floor witness theta so the gradient is non-trivial, and a generic example
    ps = [0.01 * ((i * 7) % 5 - 2) for i in range(PARAM_COUNT_B)]
    ex = (12345, (3000, 1500, 0, 800, 0, 0, 4000), 2)   # mask band 2

    # lawMaskedGradientFiniteDiff: analytic == central finite difference, componentwise.
    g = masked_band_gradient(ps, ex)
    if len(g) != PARAM_COUNT_B:
        print(f"FAIL: gradient width {len(g)} != {PARAM_COUNT_B}"); fails += 1
    for i, gi in enumerate(g):
        fd = _central_fd(ps, ex, i)
        if abs(gi - fd) > 1e-5:
            print(f"FAIL: grad[{i}] {gi} != fd {fd}"); fails += 1
            break

    # sparsity: only the masked band's row (band 2 => params 18..26) may be nonzero.
    m = 2
    for i, gi in enumerate(g):
        in_row = (m * FEATURE_COUNT_B) <= i < ((m + 1) * FEATURE_COUNT_B)
        if not in_row and gi != 0.0:
            print(f"FAIL: nonzero gradient outside masked row at {i}"); fails += 1
            break

    # a step toward an OFF-FLOOR masked target strictly decreases the loss. The masked
    # band must be nonzero or the floor already fits it (loss 0) and the test is vacuous.
    floor = [0.0] * PARAM_COUNT_B
    ex_off = (12345, (5000, 0, 0, 0, 0, 0, 0), 0)   # masked band 0 target = 5000, off floor
    l0 = masked_band_loss(floor, ex_off)
    l1 = masked_band_loss(masked_band_update(0.25, floor, ex_off), ex_off)
    if not (l0 > 1e-6 and l1 < l0):
        print(f"FAIL: one SGD step did not decrease loss ({l0} -> {l1})"); fails += 1

    print("jepa_loss: PASS" if fails == 0 else f"jepa_loss: {fails} FAIL")
    raise SystemExit(1 if fails else 0)
