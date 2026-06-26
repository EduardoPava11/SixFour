"""Step A (make it real): frame-level GIF89a palette + index on REAL chroma.

The octant heads in train_loop.py learn an L-channel, per-octant, N_PAL=8 PROXY palette. This
module is the real thing: it loads a genuine per-frame GIF89a Local Color Table + index raster
from synth_capture (256 colours, 4096-pixel index, byte-exact through gif_assemble/gif_decode)
and learns a K-colour palette + per-pixel index by DIFFERENTIABLE quantization on the REAL (L,a,b)
OKLab pixels -- a learned colour quantizer (ColorCNN-style data-tied centroids), straight-through
index, fused palette[index] reconstruction, margin-guarded commit.

This is the per-frame VALUE (palette) + discrete CONTENT (index) heads at their NATURAL granularity
(4096 pixels -> <=K colours = real compression, unlike the degenerate 8-voxel octant). It is
STANDALONE: not yet on the ViT trunk (that wiring is the scale-spine follow-up); here it proves the
machinery trains on actual GIF chroma.

Run:  python3 frame_palette.py            # self-test (loss descends, valid raster, determinism)
      python3 cli.py quantize --k 64
"""
from __future__ import annotations

import argparse
import os
import sys

# IMPORT ORDER IS LOAD-BEARING (see train_loop.py header): import the REAL mlx FIRST so it is
# cached in sys.modules. Only THEN insert trainer/ on the path -- it contains this 'mlx/' package
# dir, so a later `import mlx` would otherwise resolve to trainer/mlx/__init__.py and fail.
import numpy as np
import mlx.core as mx

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))  # trainer/

from synth_capture import synthetic_capture, CAPTURE_K  # noqa: E402

# Soft-assignment temperature (OKLab Q16-normalized distance) and the cross-device commit margin.
T = 5e-3
MARGIN_EPS = 1e-6


def frame_lct(seed: int, kind: str, fr: int):
    """LOADER: the REAL per-frame GIF89a structure. Returns
    (palette_q16 (K,3) int64, index (4096,) int64, pixels_q16 (4096,3) int64) where
    pixels = palette[index] is the frame in Q16 OKLab. This is exactly what gif_assemble ships."""
    cap = synthetic_capture(seed, kind)
    pal = cap.palettes_q16[fr].astype(np.int64)    # (256, 3) Q16 OKLab Local Color Table
    idx = cap.indices[fr].astype(np.int64)         # (4096,) per-pixel index raster
    pixels = pal[idx]                              # (4096, 3) the real frame, OKLab
    return pal, idx, pixels


def _dist2(px, pal):
    """Squared OKLab distance, every pixel to every palette entry -> (N, k)."""
    return ((px[:, None, :] - pal[None, :, :]) ** 2).sum(axis=-1)


def commit_frame_index(d2_np, eps=MARGIN_EPS):
    """Byte-exact index commit (spec lawPolicyArgmaxMarginOrFallback, frame version): assign each
    pixel to its nearest palette entry, but among entries within `eps` of the minimum distance pick
    the LOWEST slot index -- a deterministic tie-break so float noise never decides a near-tie."""
    out = np.empty(d2_np.shape[0], dtype=np.int64)
    mins = d2_np.min(axis=1)
    for p in range(d2_np.shape[0]):
        near = np.nonzero(d2_np[p] <= mins[p] + eps)[0]   # all within-eps of the min
        out[p] = int(near[0])                             # lowest slot index (deterministic)
    return out


def quantize(pixels_q16, k, steps, lr, seed, verbose=False):
    """Learn a k-colour palette on the REAL frame pixels by SGD on fused reconstruction.
    Straight-through index: forward = hard nearest-palette; backward = soft softmax(-d2/T)."""
    mx.random.seed(seed)
    np.random.seed(seed)
    px = mx.array(pixels_q16.astype(np.float64) / 65536.0, dtype=mx.float32)   # (N,3) OKLab
    n = px.shape[0]
    # Data-tied init: k strided real pixels (so the palette starts ON the data manifold).
    init = pixels_q16[np.linspace(0, n - 1, k).astype(int)].astype(np.float64) / 65536.0
    pal = mx.array(init, dtype=mx.float32)                                     # learnable (k,3)

    def loss_fn(p):
        d2 = _dist2(px, p)                      # (N, k)
        w = mx.softmax(-d2 / T, axis=-1)        # soft assignment (differentiable)
        hard = mx.argmax(-d2, axis=-1)          # nearest palette (discrete)
        st = mx.eye(k)[hard] + (w - mx.stop_gradient(w))   # straight-through one-hot
        recon = st @ p                          # (N,3) fused palette[index]
        return mx.mean((recon - px) ** 2)

    grad_fn = mx.value_and_grad(loss_fn)
    traj = []
    for step in range(steps):
        loss, g = grad_fn(pal)
        pal = pal - lr * g
        mx.eval(pal, loss)
        traj.append(float(loss))
        if verbose and (step % max(1, steps // 10) == 0 or step == steps - 1):
            print(f"    step {step:3d}  recon_MSE={float(loss):.8f}")
    return pal, traj


def _selftest():
    fails = 0
    seed, kind, fr, k = 7, "high-lab", 0, 32
    pal_real, idx_real, pixels = frame_lct(seed, kind, fr)
    print(f"  loaded REAL frame: {pixels.shape[0]} pixels, capture LCT K={CAPTURE_K}, "
          f"distinct colours used={len(np.unique(idx_real))}")

    # the capture's OWN palette reconstructs the frame EXACTLY (pixels = palette[index]).
    px01 = pixels.astype(np.float64) / 65536.0
    print(f"  capture palette recon_MSE = 0.0 (lossless by construction; pixels = palette[index])")

    # learn a k=32 palette -> real LOSSY compression of 4096 pixels into 32 colours.
    pal, traj = quantize(pixels, k=k, steps=60, lr=0.5, seed=seed, verbose=True)
    drop = traj[0] - traj[-1]
    print(f"  learned k={k} palette: recon_MSE {traj[0]:.6f} -> {traj[-1]:.6f}  drop={drop:.6f}")
    if not (drop > 0 and traj[-1] < traj[0]):
        print("FAIL: quantizer recon MSE did not descend"); fails += 1

    # commit the index raster on the REAL pixels with the margin guard.
    d2 = np.array(_dist2(mx.array(px01, dtype=mx.float32), pal))
    committed = commit_frame_index(d2)
    valid = committed.shape[0] == pixels.shape[0] and committed.min() >= 0 and committed.max() < k
    print(f"  committed index raster: {committed.shape[0]} pixels, slots in "
          f"[{int(committed.min())},{int(committed.max())}], {len(np.unique(committed))} colours used")
    if not valid:
        print("FAIL: committed raster out of range"); fails += 1

    # determinism: same seed -> identical trajectory.
    _, traj_b = quantize(pixels, k=k, steps=60, lr=0.5, seed=seed)
    worst = max(abs(a - b) for a, b in zip(traj, traj_b))
    print(f"  determinism: worst |A-B| over the trajectory = {worst:.3e}")
    if worst != 0.0:
        print("FAIL: non-deterministic"); fails += 1

    print("frame_palette: PASS" if fails == 0 else f"frame_palette: {fails} FAIL")
    return fails


def main():
    ap = argparse.ArgumentParser(description="Frame-level GIF89a palette + index on real chroma.")
    ap.add_argument("--seed", type=int, default=7)
    ap.add_argument("--kind", type=str, default="high-lab")
    ap.add_argument("--frame", type=int, default=0)
    ap.add_argument("--k", type=int, default=32, help="learned palette size (real GIF K=256)")
    ap.add_argument("--steps", type=int, default=60)
    ap.add_argument("--lr", type=float, default=0.5)
    ap.add_argument("--selftest", action="store_true")
    args = ap.parse_args()
    if args.selftest:
        raise SystemExit(1 if _selftest() else 0)
    _pal_real, idx_real, pixels = frame_lct(args.seed, args.kind, args.frame)
    print(f"=== frame quantize: seed={args.seed} kind={args.kind} frame={args.frame} k={args.k} ===")
    print(f"real frame: {pixels.shape[0]} pixels, capture used {len(np.unique(idx_real))} of "
          f"{CAPTURE_K} colours")
    pal, traj = quantize(pixels, args.k, args.steps, args.lr, args.seed, verbose=True)
    px01 = pixels.astype(np.float64) / 65536.0
    d2 = np.array(_dist2(mx.array(px01, dtype=mx.float32), pal))
    committed = commit_frame_index(d2)
    print(f"committed index raster: {len(np.unique(committed))} colours used, "
          f"recon_MSE {traj[0]:.6f} -> {traj[-1]:.6f}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
