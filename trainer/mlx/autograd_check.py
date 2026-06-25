"""MLX autograd cross-check: prove the hand-derived `masked_band_gradient` equals MLX's
automatic differentiation on the exact same forward pass.

This is the bridge the regimen needs before trusting autodiff at scale: the small
theta_B gradient is hand-written (and finite-difference checked in jepa_loss.py), but
the LARGE position-conditioned I-JEPA head will be trained with mx.value_and_grad. This
module confirms MLX's autodiff reproduces the analytic gradient on theta_B, so the same
mechanism is trustworthy when the head grows. Realizes the spirit of
lawMaskedGradientFiniteDiff with autodiff instead of finite differences.

MLX runs in float64 here to match the Haskell Double / numpy twin tightly. The byte-exact
COMMIT still happens in q16.py (Python round); MLX is used only for the gradient, which
has a tolerance, so no byte ever depends on MLX's float summation.
"""
from __future__ import annotations

import mlx.core as mx
import numpy as np

# float64 is required to match the Haskell Double / numpy twin tightly, and MLX supports
# float64 only on the CPU (the Apple-Silicon Metal GPU is float32-only). Pin the CPU device.
mx.set_default_device(mx.cpu)

from encoder_frozen import NUM_BANDS, FEATURE_COUNT_B, features_b
from theta_b import (
    PARAM_COUNT_B, mbe_coarse, mbe_masked, siblings_of, masked_target_band,
)
from jepa_loss import masked_band_gradient
from q16 import to_q16


def _mlx_loss(ps_mx: mx.array, phi_mx: mx.array, m: int, t: float) -> mx.array:
    """0.5 * (theta_row[m] . phi - t)^2, built in MLX so mx.grad can differentiate it."""
    rows = ps_mx.reshape(NUM_BANDS, FEATURE_COUNT_B)
    raw = mx.sum(rows[m] * phi_mx)
    d = raw - t
    return 0.5 * d * d


def mlx_gradient(ps: list[float], ex) -> list[float]:
    """The gradient of the masked-band loss via MLX autodiff, returned as a flat list."""
    phi = features_b(mbe_coarse(ex), siblings_of(ex))
    m = mbe_masked(ex)
    t = to_q16(masked_target_band(ex))
    ps_mx = mx.array(ps, dtype=mx.float64)
    phi_mx = mx.array(phi, dtype=mx.float64)
    grad_fn = mx.grad(lambda p: _mlx_loss(p, phi_mx, m, t))
    g = grad_fn(ps_mx)
    mx.eval(g)
    # MLX 0.30 .tolist() does not support float64 extraction; round-trip through numpy
    # (full float64 precision preserved) for the 1e-9 comparison against the analytic grad.
    return [float(x) for x in np.array(g)]


if __name__ == "__main__":
    fails = 0
    cases = [
        ([0.01 * ((i * 7) % 5 - 2) for i in range(PARAM_COUNT_B)],
         (12345, (3000, 1500, 0, 800, 0, 0, 4000), 2)),
        ([0.0] * PARAM_COUNT_B, (20000, (3000, 0, 0, 0, 0, 0, 0), 0)),
        ([0.005 * (i % 9) for i in range(PARAM_COUNT_B)],
         (40000, (0, 0, 7000, 0, 1234, 0, 0), 4)),
    ]
    for ps, ex in cases:
        analytic = masked_band_gradient(ps, ex)
        auto = mlx_gradient(ps, ex)
        worst = max(abs(a - b) for a, b in zip(analytic, auto))
        if worst > 1e-9:
            print(f"FAIL: MLX autodiff != analytic gradient (worst {worst:.2e}) on {ex}"); fails += 1
        else:
            print(f"  autodiff == analytic (worst delta {worst:.2e}) on mask {ex[2]}")

    print("autograd_check: PASS" if fails == 0 else f"autograd_check: {fails} FAIL")
    raise SystemExit(1 if fails else 0)
