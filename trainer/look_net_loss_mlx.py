"""look_net_loss_mlx — the MLX port of SixFour.Spec.Loss (the look-NN training target).

HAND-WRITTEN trainer tooling (NOT generated): mirrors spec/src/SixFour/Spec/Loss.hs
term-for-term so the loss the M1 MLX trainer minimises is the one the Haskell spec
pins. Verified against the loss reference cases in look_net_golden.json by
check_golden.py (within meta.tolerance, 1e-6).

The look-NN output is the 384 SigmaPairTree coefficients; reconstruct_sigma_pair
(in look_net_mlx.py) expands them into the 256-leaf σ-pair palette. The loss is the
weighted sum of three spec terms computed on those leaves:

  fidelity  — Bures-Wasserstein squared distance between the input capture GMM
              (moment-matched to one Gaussian) and the leaves' point-mass mixture
              (also moment-matched). Mirrors Spec.Loss.fidelityLossLeaves +
              Spec.Bures.buresDistanceSq (50-step scaled Denman-Beavers matrix sqrt).
  coverage  — 1 - (occupied 16³ OKLab voxels / 4096). DISCRETE (non-differentiable):
              a monitored metric, not a gradient driver. Mirrors Spec.Coverage.
  beauty    — negated sum of Ou-Luo per-pair beauty over the 128 adjacent σ-pairs
              (chromatic similarity + lightness asymmetry + lightness sum).
              Mirrors Spec.Loss.beautyLossLeaves.

Bit-for-bit fidelity to the spec is the contract; cross-language summation order
diverges at the ULP level, so the gate is a 1e-6 tolerance (same as the forward).
"""
from __future__ import annotations

import mlx.core as mx
import numpy as np

# ── Pinned grid (mirror Spec.Coverage / Spec.Color) ────────────────────────
COVERAGE_BINS_PER_AXIS = 16  # 16³ = 4096 voxels (Spec.Coverage.coverageBinsPerAxis)
SIGMA = mx.array([1.0, -1.0, -1.0])  # σ(L,a,b) = (L,-a,-b)


# ===========================================================================
# Moment matching (mirror Spec.GMM.mixtureMean / mixtureCovariance, law of
# total covariance), then the leaf mixture is point-mass (zero within-cov).
# ===========================================================================

def leaves_moments(leaves):
    """(256,3) leaves -> (mean(3), cov upper-tri(6)) of the uniform point-mass GMM.

    Point masses ⇒ within-component covariance is 0, so cov is the pure between
    term Σ pᵢ (μᵢ-μ)(μᵢ-μ)ᵀ with uniform pᵢ = 1/n (Spec.GMM.mixtureCovariance)."""
    n = leaves.shape[0]
    mean = mx.mean(leaves, axis=0)              # (3,)
    d = leaves - mean                           # (n,3)
    p = 1.0 / n
    sLL = mx.sum(d[:, 0] * d[:, 0]) * p
    sLa = mx.sum(d[:, 0] * d[:, 1]) * p
    sLb = mx.sum(d[:, 0] * d[:, 2]) * p
    saa = mx.sum(d[:, 1] * d[:, 1]) * p
    sab = mx.sum(d[:, 1] * d[:, 2]) * p
    sbb = mx.sum(d[:, 2] * d[:, 2]) * p
    cov = mx.stack([sLL, sLa, sLb, saa, sab, sbb])
    return mean, cov


def _cov_to_mat3(cov):
    """6 upper-tri (sLL,sLa,sLb,saa,sab,sbb) -> symmetric 3×3 (Spec.Bures.fromCov3)."""
    sLL, sLa, sLb, saa, sab, sbb = [cov[i] for i in range(6)]
    return mx.stack([
        mx.stack([sLL, sLa, sLb]),
        mx.stack([sLa, saa, sab]),
        mx.stack([sLb, sab, sbb]),
    ])


def _det3(m):
    return (m[0, 0] * (m[1, 1] * m[2, 2] - m[1, 2] * m[2, 1])
            - m[0, 1] * (m[1, 0] * m[2, 2] - m[1, 2] * m[2, 0])
            + m[0, 2] * (m[1, 0] * m[2, 1] - m[1, 1] * m[2, 0]))


def _inv3(m):
    dt = _det3(m)
    cA = (m[1, 1] * m[2, 2] - m[1, 2] * m[2, 1])
    cB = -(m[1, 0] * m[2, 2] - m[1, 2] * m[2, 0])
    cC = (m[1, 0] * m[2, 1] - m[1, 1] * m[2, 0])
    cD = -(m[0, 1] * m[2, 2] - m[0, 2] * m[2, 1])
    cE = (m[0, 0] * m[2, 2] - m[0, 2] * m[2, 0])
    cF = -(m[0, 0] * m[2, 1] - m[0, 1] * m[2, 0])
    cG = (m[0, 1] * m[1, 2] - m[0, 2] * m[1, 1])
    cH = -(m[0, 0] * m[1, 2] - m[0, 2] * m[1, 0])
    cI = (m[0, 0] * m[1, 1] - m[0, 1] * m[1, 0])
    adj_t = mx.stack([
        mx.stack([cA, cD, cG]),
        mx.stack([cB, cE, cH]),
        mx.stack([cC, cF, cI]),
    ])
    return adj_t * (1.0 / dt)


def sqrt_psd(a0):
    """Symmetric-PSD 3×3 matrix square root via 50-step scaled Denman-Beavers.
    Byte-faithful port of Spec.Bures.sqrtPSD (ridge 1e-9, γ = |detY·detZ|^(-1/6))."""
    ridge = 1e-9
    a = a0 + mx.eye(3, dtype=a0.dtype) * ridge
    y = a
    z = mx.eye(3, dtype=a0.dtype)
    for _ in range(50):
        dy = _det3(y)
        dz = _det3(z)
        gamma = mx.maximum(mx.abs(dy * dz), 1e-300) ** (-1.0 / 6.0)
        iy = _inv3(y)
        iz = _inv3(z)
        y = 0.5 * (gamma * y + (1.0 / gamma) * iz)
        z = 0.5 * (gamma * z + (1.0 / gamma) * iy)
    return y


def bures_distance_sq(mean1, cov1, mean2, cov2):
    """Squared Bures-Wasserstein (Gaussian W₂) distance (Spec.Bures.buresDistanceSq).
    dμ = ‖μ₁-μ₂‖²; covariance term = tr(Σ₁+Σ₂ - 2(Σ₁^½ Σ₂ Σ₁^½)^½), floored at 0."""
    dmu = mx.sum((mean1 - mean2) ** 2)
    c1 = _cov_to_mat3(cov1)
    c2 = _cov_to_mat3(cov2)
    s1 = sqrt_psd(c1)
    inner = sqrt_psd(s1 @ c2 @ s1)
    cross = inner[0, 0] + inner[1, 1] + inner[2, 2]
    tr1 = c1[0, 0] + c1[1, 1] + c1[2, 2]
    tr2 = c2[0, 0] + c2[1, 1] + c2[2, 2]
    t = tr1 + tr2 - 2.0 * cross
    return dmu + mx.maximum(t, 0.0)


# ===========================================================================
# Component losses (mirror Spec.Loss leaf cores)
# ===========================================================================

def fidelity_loss(leaves, input_mean, input_cov):
    """Bures-W² between the (moment-matched) input GMM and the leaves' mixture."""
    out_mean, out_cov = leaves_moments(leaves)
    return bures_distance_sq(input_mean, input_cov, out_mean, out_cov)


def coverage_loss_np(leaves_np):
    """1 - gamut coverage on the 16³ OKLab voxel grid (Spec.Coverage). DISCRETE.
    leaves_np: (256,3) numpy. L over [0,1]; a,b over [-0.5,0.5] (the +0.5 shift),
    floor + clamp to [0, n). Non-differentiable — a monitored metric only."""
    n = COVERAGE_BINS_PER_AXIS
    L = np.clip(np.floor(leaves_np[:, 0] * n).astype(np.int64), 0, n - 1)
    A = np.clip(np.floor((leaves_np[:, 1] + 0.5) * n).astype(np.int64), 0, n - 1)
    B = np.clip(np.floor((leaves_np[:, 2] + 0.5) * n).astype(np.int64), 0, n - 1)
    occupied = len({(int(l), int(a), int(b)) for l, a, b in zip(L, A, B)})
    return 1.0 - occupied / (n ** 3)


def beauty_loss(leaves):
    """Negated sum of Ou-Luo per-pair beauty over the 128 adjacent σ-pairs
    (leaves[2i], leaves[2i+1]). Mirrors Spec.Loss.beautyLossLeaves + pairBeauty:
      chromatic similarity = exp(-‖Δa,Δb‖)
      lightness asymmetry  = |ΔL|
      lightness sum        = (L₁+L₂)/2  """
    left = leaves[0::2]   # (128,3)
    right = leaves[1::2]  # (128,3)
    da = left[:, 1] - right[:, 1]
    db = left[:, 2] - right[:, 2]
    chrom = mx.exp(-mx.sqrt(da * da + db * db))
    asym = mx.abs(left[:, 0] - right[:, 0])
    lsum = (left[:, 0] + right[:, 0]) / 2.0
    per_pair = chrom + asym + lsum
    return -mx.sum(per_pair)


# ===========================================================================
# PonderNet halting loss (mirror Spec.Loss.haltingLoss)
# ===========================================================================

DEFAULT_HALT_LAMBDA_P = 0.5  # Spec.Loss.defaultHaltLambdaP


def halting_distribution(halts):
    """PonderNet halting distribution p_n = λ_n · ∏_{i<n}(1-λ_i) over the static
    unroll, with the LAST step forced to absorb the remaining mass so Σ p_n = 1.
    Mirrors Spec.Loss.haltingDistribution. `halts`: list of per-level λ floats."""
    halts = list(halts)
    if not halts:
        return []
    p = []
    remaining = 1.0
    for i, l in enumerate(halts):
        if i == len(halts) - 1:
            p.append(remaining)            # tail absorbs the rest
        else:
            p.append(remaining * l)
            remaining = remaining * (1.0 - l)
    return p


def geometric_prior(lambda_p, n):
    """Renormalised geometric prior g_n ∝ λ_p·(1-λ_p)^n over n=0..N-1.
    Mirrors Spec.Loss.geometricPrior."""
    raw = [lambda_p * (1.0 - lambda_p) ** k for k in range(n)]
    z = sum(raw)
    if z <= 0:
        return [1.0 / max(1, n)] * n
    return [r / z for r in raw]


def halting_loss(halts, lambda_p=DEFAULT_HALT_LAMBDA_P):
    """PonderNet halting regulariser KL(halting-dist ‖ geometric-prior). Trains
    the per-level halt λ's the static unroll otherwise leaves unsupervised.
    Mirrors Spec.Loss.haltingLoss (0·log0 = 0 convention)."""
    import math
    p = halting_distribution(halts)
    g = geometric_prior(lambda_p, len(halts))
    return sum(0.0 if pn <= 0 else pn * math.log(pn / gn) for pn, gn in zip(p, g))


# ===========================================================================
# Total (mirror Spec.Loss.lookNetLossLeaves)
# ===========================================================================

DEFAULT_WEIGHTS = {"fidelity": 1.0, "coverage": 1.0, "beauty": 1.0}


def look_net_loss(coeffs_384, input_mean, input_cov, weights=None, high_precision=False):
    """Total look-NN loss from the raw 384 SigmaPairTree coeffs.

    coeffs_384: (384,) or (1,384) mx.array (the LookNet forward output).
    input_mean: (3,) mx.array; input_cov: (6,) mx.array upper-tri (from the
    capture's pooled GMM, or look_net_golden.json's input_gmm_mean/cov).

    Returns (total, parts_dict). Coverage is included in the total but is
    DISCRETE (computed on a stop-gradient numpy view) — gradients flow only
    through fidelity + beauty, exactly as the spec's coverage metric is discrete.

    high_precision: run the whole reduction in float64 on the CPU stream. The
    beauty term sums 128 σ-pairs to magnitude ~127, whose float32 ULP (~7.6e-6)
    exceeds the 1e-6 spec contract; float64-CPU reproduces the Haskell Spec.Loss
    oracle to ~1e-14. Used by the golden gate. Training keeps the float32-GPU
    default — gradients don't need bit-exactness, and MLX rejects float64 on GPU."""
    import contextlib
    import look_net_mlx as m

    w = dict(DEFAULT_WEIGHTS if weights is None else weights)
    ctx = mx.stream(mx.cpu) if high_precision else contextlib.nullcontext()
    with ctx:
        c = coeffs_384.reshape(1, -1)
        if high_precision:
            c = c.astype(mx.float64)
            input_mean = input_mean.astype(mx.float64)
            input_cov = input_cov.astype(mx.float64)
        leaves = m.reconstruct_sigma_pair(c)[0]          # (256,3)
        if high_precision:
            leaves = leaves.astype(mx.float64)

        fid = fidelity_loss(leaves, input_mean, input_cov)
        bty = beauty_loss(leaves)
        cov = coverage_loss_np(np.array(leaves))         # discrete, stop-grad
        total = w["fidelity"] * fid + w["beauty"] * bty + w["coverage"] * cov
    return total, {
        "fidelity": fid,
        "coverage": mx.array(cov),
        "beauty": bty,
        "total": total,
    }
