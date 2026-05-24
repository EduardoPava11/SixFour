"""Train a 9-parameter PSD OKLab distance metric.

Parameterize M = L Lᵀ with L lower-triangular (Cholesky) — guarantees
positive semidefinite. Loss: triplet margin where (anchor, positive) are
adjacent pixels in a smooth gradient sampled from `data/reference_gifs/`,
and (anchor, negative) are random pixel pairs from the same frames.

The resulting metric file is a tiny JSON dropped into the gene library.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
import pathlib
import time
from dataclasses import dataclass

import mlx.core as mx
import mlx.nn as nn
import mlx.optimizers as optim
import numpy as np
from PIL import Image, ImageSequence
from tqdm import tqdm


# ---------- OKLab conversion (matches Swift ColorScience exactly) ----------

def srgb_to_linear(c: np.ndarray) -> np.ndarray:
    c = np.clip(c, 0.0, 1.0)
    return np.where(c <= 0.04045, c / 12.92, ((c + 0.055) / 1.055) ** 2.4)


def linear_srgb_to_oklab(rgb: np.ndarray) -> np.ndarray:
    # rgb: (..., 3) in linear sRGB
    r = rgb[..., 0]; g = rgb[..., 1]; b = rgb[..., 2]
    l = 0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b
    m = 0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b
    s = 0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b
    l_, m_, s_ = np.cbrt(l), np.cbrt(m), np.cbrt(s)
    L = 0.2104542553 * l_ + 0.7936177850 * m_ - 0.0040720468 * s_
    A = 1.9779984951 * l_ - 2.4285922050 * m_ + 0.4505937099 * s_
    B = 0.0259040371 * l_ + 0.7827717662 * m_ - 0.8086757660 * s_
    return np.stack([L, A, B], axis=-1)


def gif_frames_to_oklab(gif_path: pathlib.Path) -> np.ndarray:
    """Return (frames, H, W, 3) OKLab tensor."""
    img = Image.open(gif_path)
    frames = []
    for frame in ImageSequence.Iterator(img):
        rgb = np.asarray(frame.convert("RGB"), dtype=np.float32) / 255.0
        linear = srgb_to_linear(rgb)
        frames.append(linear_srgb_to_oklab(linear))
    return np.stack(frames, axis=0)


# ---------- Triplet sampler ----------

@dataclass
class Triplets:
    anchor: np.ndarray   # (N, 3)
    positive: np.ndarray # (N, 3)
    negative: np.ndarray # (N, 3)


def sample_triplets(lab: np.ndarray, n: int, rng: np.random.Generator) -> Triplets:
    """Anchor: random pixel. Positive: 4-neighbor. Negative: random pixel from same frame."""
    F, H, W, _ = lab.shape
    fi = rng.integers(0, F, size=n)
    yi = rng.integers(1, H - 1, size=n)
    xi = rng.integers(1, W - 1, size=n)
    anchor = lab[fi, yi, xi]
    direction = rng.integers(0, 4, size=n)  # 0=up, 1=down, 2=left, 3=right
    dy = np.where(direction == 0, -1, np.where(direction == 1, 1, 0))
    dx = np.where(direction == 2, -1, np.where(direction == 3, 1, 0))
    positive = lab[fi, yi + dy, xi + dx]
    yn = rng.integers(0, H, size=n)
    xn = rng.integers(0, W, size=n)
    negative = lab[fi, yn, xn]
    return Triplets(anchor=anchor, positive=positive, negative=negative)


# ---------- Model: PSD metric via Cholesky ----------

class CholeskyPSD(nn.Module):
    """L is 3x3 lower triangular (6 params), M = L Lᵀ guaranteed PSD."""
    def __init__(self):
        super().__init__()
        # Initialize as identity Cholesky → identity M.
        self.l00 = mx.array(1.0)
        self.l10 = mx.array(0.0)
        self.l11 = mx.array(1.0)
        self.l20 = mx.array(0.0)
        self.l21 = mx.array(0.0)
        self.l22 = mx.array(1.0)

    def L(self) -> mx.array:
        # Returns 3x3 lower-triangular as a stacked matrix.
        row0 = mx.stack([self.l00, mx.array(0.0), mx.array(0.0)])
        row1 = mx.stack([self.l10, self.l11, mx.array(0.0)])
        row2 = mx.stack([self.l20, self.l21, self.l22])
        return mx.stack([row0, row1, row2], axis=0)

    def M(self) -> mx.array:
        L = self.L()
        return L @ L.T

    def __call__(self, a: mx.array, b: mx.array) -> mx.array:
        # Squared metric distance: (a-b)ᵀ M (a-b), per row.
        d = a - b
        Md = d @ self.M()
        return mx.sum(d * Md, axis=-1)


def triplet_loss(model: CholeskyPSD, t: Triplets, margin: float) -> mx.array:
    a = mx.array(t.anchor)
    p = mx.array(t.positive)
    n = mx.array(t.negative)
    d_ap = model(a, p)
    d_an = model(a, n)
    return mx.mean(mx.maximum(d_ap - d_an + margin, 0.0))


# ---------- Train ----------

def train(args):
    rng = np.random.default_rng(args.seed)
    data_dir = pathlib.Path(args.data_dir)
    gif_paths = sorted(data_dir.glob("*.gif"))
    if not gif_paths:
        raise SystemExit(f"No GIFs in {data_dir}. Drop reference GIFs there and retry.")

    print(f"Loading {len(gif_paths)} reference GIFs...")
    labs = [gif_frames_to_oklab(p) for p in gif_paths]
    print(f"Loaded; {sum(l.shape[0] for l in labs)} frames total.")

    model = CholeskyPSD()
    optimizer = optim.Adam(learning_rate=args.lr)

    loss_and_grad = nn.value_and_grad(model, lambda m, t: triplet_loss(m, t, args.margin))

    for step in tqdm(range(args.steps), desc="train"):
        which = rng.integers(0, len(labs))
        t = sample_triplets(labs[which], args.batch, rng)
        loss, grads = loss_and_grad(model, t)
        optimizer.update(model, grads)
        mx.eval(model.parameters(), optimizer.state)
        if step % 200 == 0:
            print(f"step {step:>5d}  loss = {float(loss):.5f}")

    M = np.asarray(model.M())
    print("Learned M:\n", M)

    upper_triangle = [float(M[0, 0]), float(M[0, 1]), float(M[0, 2]),
                      float(M[1, 1]), float(M[1, 2]),
                      float(M[2, 2])]

    payload = {"m": upper_triangle}
    out = pathlib.Path(args.out)
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(json.dumps(payload, indent=2))
    h = hashlib.sha256(out.read_bytes()).hexdigest()[:16]
    print(f"Wrote {out} (hash={h})")


def main():
    p = argparse.ArgumentParser()
    p.add_argument("--data-dir", default="data/reference_gifs")
    p.add_argument("--out", default="out/metric.json")
    p.add_argument("--steps", type=int, default=2000)
    p.add_argument("--batch", type=int, default=512)
    p.add_argument("--lr", type=float, default=1e-3)
    p.add_argument("--margin", type=float, default=0.01)
    p.add_argument("--seed", type=int, default=0)
    args = p.parse_args()
    train(args)


if __name__ == "__main__":
    main()
