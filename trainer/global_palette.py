"""global_palette.py — the OT substrate the look-NN GAN composes on (Milestone L).

The look-NN's job: 64 per-frame palettes → ONE global palette → re-index all frames
to it → a single global-palette 64³ GIF. This module builds the pieces that BOTH the
GAN training signal and the visible MVP output need, and that don't exist yet:

  1. wasserstein_l_barycenter — the non-NN BASELINE global L-palette (1D-Wasserstein
     barycenter of the per-frame L-distributions = average of their quantile functions,
     Bonneel-style). The palette the GAN must BEAT.
  2. sinkhorn_assign — the DIFFERENTIABLE renderer: entropic-OT soft assignment of pixels
     to palette entries. Same primitive the Wasserstein-GAN discriminator uses (DOT/W2GAN),
     so the renderer + discriminator + Bures anchor are one composable object. A uniform
     palette marginal makes Sinkhorn enforce full-palette usage = the significance contract.
  3. global_reindex / render_global_gif — hard argmin re-index + a single global-palette GIF
     (via zig_native.s4_gif_assemble with the SAME palette table on every frame).

Numpy here (baseline + validation); every op is MLX-portable for train_look_net_mlx.py.
"""
from __future__ import annotations

import numpy as np

import zig_native as zn

Q16 = zn.Q16
K = zn.K


# ── 1D-Wasserstein barycenter of the per-frame L-distributions (BASELINE) ──────
def wasserstein_l_barycenter(burst: zn.Burst, k: int = K) -> np.ndarray:
    """Global L-palette (k,) as the 1D-Wasserstein barycenter of the 64 per-frame
    L-distributions. In 1D the W₂ barycenter is the average of the inverse-CDFs
    (quantile functions), so we average each frame's weighted L-quantile function on
    a common k-point grid. Returns k sorted L levels in float OKLab [0,1]."""
    pal = burst.palettes_oklab()            # (F, k, 3) float OKLab
    counts = np.array([np.bincount(burst.indices[f].astype(np.int64), minlength=pal.shape[1])
                       for f in range(pal.shape[0])], dtype=np.float64)  # (F, k)
    u = (np.arange(k) + 0.5) / k            # k quantile probe points in (0,1)
    q_sum = np.zeros(k, dtype=np.float64)
    for f in range(pal.shape[0]):
        L = pal[f, :, 0]
        w = counts[f]
        order = np.argsort(L, kind="stable")
        Ls, ws = L[order], w[order]
        cdf = np.cumsum(ws)
        if cdf[-1] <= 0:
            continue
        cdf = (cdf - 0.5 * ws) / cdf[-1]    # midpoint CDF for stable quantiles
        q_sum += np.interp(u, cdf, Ls)      # frame f's quantile function at u
    return np.sort(q_sum / pal.shape[0])    # averaged quantile fn = barycenter, sorted


def l_palette_to_oklab(global_L: np.ndarray) -> np.ndarray:
    """(k,) L levels → (k,3) OKLab with a=b=0 (the grayscale global palette)."""
    pal = np.zeros((global_L.shape[0], 3), dtype=np.float64)
    pal[:, 0] = global_L
    return pal


# ── 2. entropic-OT soft assignment (the differentiable renderer + GAN primitive) ─
def sinkhorn_assign(pixels_L: np.ndarray, palette_L: np.ndarray, eps: float = 1e-3,
                    n_iters: int = 50, palette_marginal: np.ndarray | None = None):
    """Entropic-OT coupling P (p,k) between pixels and palette on the L-axis.
    Cost C[i,j] = (Lᵢ−Lⱼ)². ε is the entropic regularizer (the dynamic-range / diversity
    knob). `palette_marginal=None` → row-softmax (soft nearest-palette, no usage
    constraint); a uniform marginal makes Sinkhorn spread mass over ALL entries (the
    differentiable significance/coverage objective). Returns row-normalised P.

    Pure-numpy log-domain Sinkhorn; the identical recurrence ports to mlx.core."""
    p, k = pixels_L.shape[0], palette_L.shape[0]
    logK = -((pixels_L[:, None] - palette_L[None, :]) ** 2) / eps   # log Gibbs kernel (p,k)
    if palette_marginal is None:
        # One-sided: each pixel is a distribution over palette entries (soft argmin).
        return _softmax_rows(logK)
    # Stabilised log-domain Sinkhorn. Potentials u=f/ε (p,), v=g/ε (k,);
    # logP = u[:,None] + logK + v[None,:], with row-sums→a, col-sums→b.
    a = np.full(p, 1.0 / p)                                    # uniform over pixels
    b = palette_marginal / palette_marginal.sum()             # target palette usage
    log_a, log_b = np.log(a), np.log(b)
    u = np.zeros(p); v = np.zeros(k)
    for _ in range(n_iters):
        u = log_a - _logsumexp(logK + v[None, :], axis=1)
        v = log_b - _logsumexp(logK + u[:, None], axis=0)
    P = np.exp(u[:, None] + logK + v[None, :])
    return P / P.sum(axis=1, keepdims=True)


def _logsumexp(x, axis):
    m = np.max(x, axis=axis, keepdims=True)
    return (m + np.log(np.sum(np.exp(x - m), axis=axis, keepdims=True))).squeeze(axis)


def _softmax_rows(logits):
    m = np.max(logits, axis=1, keepdims=True)
    e = np.exp(logits - m)
    return e / e.sum(axis=1, keepdims=True)


def soft_render_L(pixels_L: np.ndarray, palette_L: np.ndarray, eps: float = 1e-3) -> np.ndarray:
    """Differentiable grayscale render: each pixel → Σⱼ Pᵢⱼ·Lⱼ (soft palette lookup)."""
    P = sinkhorn_assign(pixels_L, palette_L, eps)
    return P @ palette_L


# ── 3. hard global re-index + single-global-palette GIF (the MVP output path) ───
def global_reindex(burst: zn.Burst, palette_L: np.ndarray) -> np.ndarray:
    """(F, p) uint8 indices: every frame's pixels assigned (nearest L) to the ONE
    global palette. This is L7 globalIndexTensor for the grayscale axis."""
    F, p, _ = burst.oklab_q16.shape
    out = np.empty((F, p), dtype=np.uint8)
    for f in range(F):
        L = burst.oklab_q16[f, :, 0].astype(np.float64) / Q16
        out[f] = np.argmin((L[:, None] - palette_L[None, :]) ** 2, axis=1).astype(np.uint8)
    return out


def render_global_gif(burst: zn.Burst, palette_oklab: np.ndarray, side: int = zn.SIDE,
                      k: int = K) -> bytes:
    """Assemble a single GLOBAL-palette GIF: re-index all frames to `palette_oklab`
    and give every frame the SAME colour table (vs the per-frame-local-palette GIF)."""
    pal_q16 = np.ascontiguousarray((palette_oklab * Q16).round().astype(np.int32))
    pal_rgb = zn.palette_to_srgb8(pal_q16)                    # (k,3) uint8
    indices = global_reindex(burst, palette_oklab[:, 0])
    palettes_rgb = np.broadcast_to(pal_rgb, (burst.indices.shape[0], k, 3)).copy()
    return zn.gif_assemble(indices, palettes_rgb, side, k)


def render_perframe_grayscale_gif(burst: zn.Burst, side: int = zn.SIDE, k: int = K,
                                  lloyd_iters: int = 3):
    """The QUALITY FLOOR / discriminator 'real': each frame's LIGHTNESS quantised to
    its OWN best 256 grey levels (per-frame grayscale palette). Returns (gif_bytes,
    perframe_L_mse). The L-NN must make ONE global grey palette reach this quality."""
    F, p, _ = burst.oklab_q16.shape
    indices = np.empty((F, p), dtype=np.uint8)
    palettes_rgb = np.empty((F, k, 3), dtype=np.uint8)
    se = 0.0
    n = 0
    for f in range(F):
        gray = burst.oklab_q16[f].copy()
        gray[:, 1:] = 0                                   # project to the L-axis (a=b=0)
        cen, idx = zn.quantize_frame(gray, k, lloyd_iters)
        palettes_rgb[f] = zn.palette_to_srgb8(cen)
        indices[f] = idx
        L = gray[:, 0].astype(np.float64) / Q16
        se += float(np.sum((L - cen[idx, 0].astype(np.float64) / Q16) ** 2))
        n += p
    gif = zn.gif_assemble(indices, palettes_rgb, side, k)
    return gif, se / n


def oklab_mse(burst: zn.Burst, palette_L: np.ndarray) -> float:
    """Mean squared L-error of rendering every pixel with the global palette (hard).
    The product-relevant quality number: how much the ONE global palette degrades vs
    the per-frame palettes (whose own L-MSE is the floor)."""
    idx = global_reindex(burst, palette_L)
    F = burst.oklab_q16.shape[0]
    se = 0.0
    n = 0
    for f in range(F):
        L = burst.oklab_q16[f, :, 0].astype(np.float64) / Q16
        se += float(np.sum((L - palette_L[idx[f]]) ** 2))
        n += L.shape[0]
    return se / n


# ── validation / baseline artifact ──────────────────────────────────────────────
if __name__ == "__main__":
    from pathlib import Path

    out_dir = Path(__file__).resolve().parent / "out"
    out_dir.mkdir(parents=True, exist_ok=True)

    # The L-NN's real task: COLOR per-frame-palette 64³ GIF IN → global GRAYSCALE OUT.
    b = zn.synth_sample(seed=42, mode=zn.SYNTH_COLOR)
    (out_dir / "synth_color_input.gif").write_bytes(b.gif)   # the colour INPUT capture

    global_L = wasserstein_l_barycenter(b)                   # global grey palette from the L-marginal
    assert global_L.shape == (K,)
    assert np.all(np.diff(global_L) >= -1e-9), "barycenter L not sorted/monotone"
    assert global_L.min() >= -1e-6 and global_L.max() <= 1 + 1e-6, "L out of [0,1]"

    pal = l_palette_to_oklab(global_L)

    # Soft renderer sanity: tiny ε ⇒ soft render ≈ hard nearest-palette render.
    px = b.oklab_q16[0, :, 0].astype(np.float64) / Q16
    soft = soft_render_L(px, global_L, eps=1e-4)
    hard = global_L[np.argmin((px[:, None] - global_L[None, :]) ** 2, axis=1)]
    assert np.mean(np.abs(soft - hard)) < 1e-2, "soft render diverges from hard at small eps"

    # Sinkhorn with uniform palette marginal spreads mass over ALL entries (significance).
    P = sinkhorn_assign(px[:512], global_L, eps=1e-3, palette_marginal=np.ones(K))
    col_mass = P.sum(axis=0)
    assert np.all(col_mass > 0), "Sinkhorn left a palette entry unused (collapse)"

    # Baseline global-grayscale render + the per-frame-grayscale quality FLOOR.
    gif = render_global_gif(b, pal)
    (out_dir / "synth_global_grayscale.gif").write_bytes(gif)
    pf_gif, pf_mse = render_perframe_grayscale_gif(b)
    (out_dir / "synth_perframe_grayscale.gif").write_bytes(pf_gif)

    global_mse = oklab_mse(b, global_L)
    print(f"OK  L-NN task: colour 64³ capture → global grayscale {K}-level palette")
    print(f"    global grey L range [{global_L.min():.3f}, {global_L.max():.3f}]")
    print(f"    L-MSE  global-grey = {global_mse:.6e}   per-frame-grey FLOOR = {pf_mse:.6e}")
    print(f"    gap the L-NN must close (global − floor) = {global_mse - pf_mse:.6e}")
    print(f"    soft↔hard render Δ = {np.mean(np.abs(soft - hard)):.2e}; "
          f"Sinkhorn min col mass = {col_mass.min():.3e} (no collapse)")
    print(f"    artifacts: synth_color_input.gif (IN), synth_global_grayscale.gif (baseline OUT), "
          f"synth_perframe_grayscale.gif (floor)")
